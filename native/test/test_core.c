/* Host tests for the Jupiter ACE core. Run with `make core-test` (working directory native/test). */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ace_api.h"

static int failures;
static int checks;

#define CHECK(cond) do { checks++; if (!(cond)) { failures++; \
    fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); } } while (0)

static uint8_t *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", path);
        exit(2);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = malloc((size_t)size);
    if (fread(data, 1, (size_t)size, f) != (size_t)size)
        exit(2);
    fclose(f);
    *len = (size_t)size;
    return data;
}

static uint8_t *rom;
static size_t rom_len;

static ace_machine *boot(void)
{
    ace_machine *m = ace_create(rom, rom_len);
    for (int n = 0; n < 100; n++)
        ace_run_frame(m);
    return m;
}

/* The screen as text, one '\n'-terminated line per row, inverse bit stripped. */
static void screen_text(ace_machine *m, char *out)
{
    for (int y = 0; y < 24; y++) {
        for (int x = 0; x < 32; x++) {
            int ch = ace_peek(m, 0x2400 + y * 32 + x) & 0x7f;
            *out++ = (ch >= 32 && ch < 127) ? (char)ch : '.';
        }
        *out++ = '\n';
    }
    *out = '\0';
}

static int screen_contains(ace_machine *m, const char *text)
{
    char screen[24 * 33 + 1];
    screen_text(m, screen);
    return strstr(screen, text) != NULL;
}

static void dump_screen(ace_machine *m)
{
    char screen[24 * 33 + 1];
    screen_text(m, screen);
    fprintf(stderr, "%s", screen);
}

typedef struct {
    const uint8_t *tape;
    size_t tape_len;
    int load_requests;
    char requested[16];
    int requested_kind;
    uint8_t *saved;
    size_t saved_len;
    char saved_name[16];
    int saved_kind;
} tape_deck;

/* Types text and runs until the spooler is done and the machine has settled. */
static void type(ace_machine *m, const char *text, tape_deck *deck)
{
    ace_spool(m, text);
    for (int n = 0; n < 3000 && ace_spool_active(m); n++) {
        int flags = ace_run_frame(m);
        if (flags & ACE_FRAME_TAPE_LOAD) {
            CHECK(deck != NULL);
            if (!deck)
                return;
            deck->load_requests++;
            ace_tape_request(m, deck->requested, sizeof(deck->requested), &deck->requested_kind);
            ace_tape_supply(m, deck->tape, deck->tape_len);
        }
        if (flags & ACE_FRAME_TAPE_SAVED) {
            CHECK(deck != NULL);
            if (!deck)
                return;
            const uint8_t *data;
            deck->saved_len = ace_tape_saved(m, deck->saved_name, sizeof(deck->saved_name),
                                             &deck->saved_kind, &data);
            free(deck->saved);
            deck->saved = malloc(deck->saved_len);
            memcpy(deck->saved, data, deck->saved_len);
        }
    }
    CHECK(!ace_spool_active(m));
    for (int n = 0; n < 25; n++)
        ace_run_frame(m);
}

static void test_create_rejects_bad_rom(void)
{
    int failures_before = failures;
    (void)failures_before;
    CHECK(ace_create(NULL, 0) == NULL);
    CHECK(ace_create(rom, rom_len - 1) == NULL);
}

static void test_boot_and_arithmetic(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = boot();
    type(m, "2 2 + .\n", NULL);
    CHECK(screen_contains(m, "2 2 + . 4  OK"));
    if (failures != failures_before)
        dump_screen(m);
    ace_destroy(m);
}

static void test_framebuffer(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = ace_create(rom, rom_len);
    int dirty = 0;
    for (int n = 0; n < 100; n++)
        dirty |= ace_run_frame(m) & ACE_FRAME_SCREEN_DIRTY;
    CHECK(dirty);
    /* Idle machine: the screen does not change between frames. */
    CHECK(!(ace_run_frame(m) & ACE_FRAME_SCREEN_DIRTY));

    /* Put an inverse space in the top left cell: its 8x8 pixels turn white. */
    ace_poke(m, 0x2400, 0x80 | ' ');
    CHECK(ace_run_frame(m) & ACE_FRAME_SCREEN_DIRTY);
    const uint8_t *fb = ace_framebuffer(m);
    CHECK(fb[0] == 0xff && fb[1] == 0xff && fb[2] == 0xff && fb[3] == 0xff);
    const uint8_t *below = fb + (8 * ACE_SCREEN_WIDTH) * 4;
    CHECK(below[0] == 0x00 && below[1] == 0x00 && below[2] == 0x00 && below[3] == 0xff);
    ace_destroy(m);
}

static void test_memory_mirrors_and_rom(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = ace_create(rom, rom_len);
    uint8_t rom_byte = ace_peek(m, 0x0100);
    ace_poke(m, 0x0100, (uint8_t)~rom_byte);
    CHECK(ace_peek(m, 0x0100) == rom_byte);

    ace_poke(m, 0x2400, 0x41);
    CHECK(ace_peek(m, 0x2000) == 0x41);
    ace_poke(m, 0x2800, 0x42);
    CHECK(ace_peek(m, 0x2c00) == 0x42);
    ace_poke(m, 0x3c05, 0x43);
    CHECK(ace_peek(m, 0x3005) == 0x43 && ace_peek(m, 0x3405) == 0x43 && ace_peek(m, 0x3805) == 0x43);
    ace_destroy(m);
}

static void test_keyboard_matrix(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = ace_create(rom, rom_len);
    ace_key_char(m, 'A', 1); /* SHIFT (port 0 bit 0) + A (port 1 bit 0) */
    ace_key_char(m, 'A', 0);
    ace_key(m, 7, 0x01, 1);
    ace_key(m, 7, 0x01, 0);
    ace_key_char(m, 0x60, 1); /* pound: SYMBOL SHIFT + X, both on port 0 */
    ace_key_release_all(m);
    /* Every character the spooler knows can be typed and released without leaving keys down. */
    const char *text = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
                       "!@#$%&'()_<>[];\"~|\\{}^-+=:?/*,. ";
    ace_machine *typed = boot();
    type(typed, text, NULL); /* no Enter: the text stays in the input line */
    CHECK(screen_contains(typed, "abcdefghijklmnopqrstuvwxyzABCDE\n"
                                 "FGHIJKLMNOPQRSTUVWXYZ0123456789!\n"
                                 "@#$%&'()_<>[];\"~|\\{}^-+=:?/*,. "));
    ace_destroy(typed);
    ace_destroy(m);
}

static void test_spool_cancel(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = boot();
    ace_spool(m, "1 2 3 4 5 6 7 8 9\n");
    CHECK(ace_spool_active(m));
    ace_run_frame(m);
    ace_spool_cancel(m);
    CHECK(!ace_spool_active(m));
    ace_destroy(m);
}

static void test_snapshot_round_trip(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *a = boot();
    type(a, ": SQ DUP * ;\n", NULL);

    size_t size = ace_snapshot_size();
    uint8_t *snap = malloc(size);
    CHECK(ace_snapshot_save(a, snap, size - 1) == 0);
    CHECK(ace_snapshot_save(a, snap, size) == size);
    CHECK(memcmp(snap, "ACE2SNAP", 8) == 0);

    ace_machine *b = ace_create(rom, rom_len);
    CHECK(ace_snapshot_load(b, snap, size));

    /* Both machines behave identically from here on. */
    type(a, "7 SQ .\n", NULL);
    type(b, "7 SQ .\n", NULL);
    CHECK(screen_contains(b, "7 SQ . 49  OK"));
    for (unsigned addr = 0; addr < 0x10000; addr++) {
        if (ace_peek(a, (uint16_t)addr) != ace_peek(b, (uint16_t)addr)) {
            CHECK(!"memory differs after snapshot restore");
            break;
        }
    }

    free(snap);
    ace_destroy(a);
    ace_destroy(b);
}

static void test_snapshot_rejects_bad_input(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = boot();
    size_t size = ace_snapshot_size();
    uint8_t *snap = malloc(size);
    ace_snapshot_save(m, snap, size);
    uint8_t pc_lo = snap[8 + 2 + 2 + 21];

    CHECK(!ace_snapshot_load(m, snap, size - 1));
    snap[0] = 'X';
    CHECK(!ace_snapshot_load(m, snap, size));
    snap[0] = 'A';
    snap[8] = 99; /* unknown version */
    CHECK(!ace_snapshot_load(m, snap, size));
    snap[8] = 1;
    CHECK(!ace_snapshot_load(m, NULL, size));
    CHECK(ace_snapshot_load(m, snap, size));
    CHECK(snap[8 + 2 + 2 + 21] == pc_lo);

    free(snap);
    ace_destroy(m);
}

static void test_tape_save_and_load(void)
{
    int failures_before = failures;
    (void)failures_before;
    tape_deck deck = {0};
    ace_machine *m = boot();
    type(m, ": SQ DUP * ;\n", NULL);
    type(m, "SAVE squares\n", &deck);
    CHECK(deck.saved_len > 0);
    CHECK(strcmp(deck.saved_name, "squares") == 0);
    CHECK(deck.saved_kind == ACE_TAPE_DICT);
    /* Header block of 26 bytes (25 + checksum), then the data block. */
    CHECK(deck.saved_len > 28 && deck.saved[0] == 26 && deck.saved[1] == 0);
    ace_destroy(m);

    ace_machine *fresh = boot();
    deck.tape = deck.saved;
    deck.tape_len = deck.saved_len;
    type(fresh, "LOAD squares\n", &deck);
    CHECK(deck.load_requests == 1);
    CHECK(strcmp(deck.requested, "squares") == 0);
    CHECK(deck.requested_kind == ACE_TAPE_DICT);
    type(fresh, "5 SQ .\n", &deck);
    CHECK(screen_contains(fresh, "5 SQ . 25  OK"));
    if (failures != failures_before)
        dump_screen(fresh);
    ace_destroy(fresh);
    free(deck.saved);
}

static void test_tape_missing_loads_stub(void)
{
    int failures_before = failures;
    (void)failures_before;
    tape_deck deck = {0};
    ace_machine *m = boot();
    type(m, "LOAD nothing\n", &deck);
    CHECK(deck.load_requests == 1);
    CHECK(strcmp(deck.requested, "nothing") == 0);
    /* The stub dictionary is accepted and the machine is still usable. */
    type(m, "3 4 * .\n", &deck);
    CHECK(screen_contains(m, "3 4 * . 12  OK"));
    if (failures != failures_before)
        dump_screen(m);
    ace_destroy(m);
}

static void test_tape_malformed_is_treated_as_missing(void)
{
    int failures_before = failures;
    (void)failures_before;
    const uint8_t bad[] = {0x40, 0x00, 0x01};
    tape_deck deck = {.tape = bad, .tape_len = sizeof(bad)};
    ace_machine *m = boot();
    type(m, "LOAD broken\n", &deck);
    type(m, "1 1 + .\n", &deck);
    CHECK(screen_contains(m, "1 1 + . 2  OK"));
    ace_destroy(m);
}

/* Lines after a LOAD must wait until the ROM is back at the input line (iACE 1.x lost them). */
static void test_spool_waits_for_input_line(void)
{
    int failures_before = failures;
    size_t len;
    uint8_t *frogger = read_file("../../assets/tapes/frogger.dic", &len);
    tape_deck deck = {.tape = frogger, .tape_len = len};
    ace_machine *m = boot();
    type(m, "LOAD frogger\n1 2 + .\n", &deck);
    CHECK(screen_contains(m, "1 2 + . 3  OK"));
    if (failures != failures_before)
        dump_screen(m);
    ace_destroy(m);
    free(frogger);
}

static void test_frogger_tape_loads(void)
{
    int failures_before = failures;
    (void)failures_before;
    size_t len;
    uint8_t *frogger = read_file("../../assets/tapes/frogger.dic", &len);
    tape_deck deck = {.tape = frogger, .tape_len = len};
    ace_machine *m = boot();
    type(m, "LOAD frogger\n", &deck);
    CHECK(deck.load_requests == 1);
    CHECK(screen_contains(m, "Dict: frogger"));
    /* Frogger redefines VLIST to start the game. */
    type(m, "VLIST\n", &deck);
    CHECK(screen_contains(m, "P R E S E N T S"));
    if (failures != failures_before)
        dump_screen(m);
    ace_destroy(m);
    free(frogger);
}

static void test_beeper_events(void)
{
    int failures_before = failures;
    (void)failures_before;
    ace_machine *m = boot();
    ace_spool(m, "100 200 BEEP\n"); /* period 0.8 ms for 200 ms */
    size_t max_events = 0;
    for (int n = 0; n < 400; n++) {
        ace_run_frame(m);
        const uint32_t *events;
        size_t count = ace_beeper_events(m, &events);
        if (count > max_events)
            max_events = count;
    }
    CHECK(max_events > 20);
    ace_destroy(m);
}

/* Renders frames while spooling and collects every audio sample produced. */
static size_t collect_audio(ace_machine *m, int frames, float *out, size_t cap)
{
    size_t total = 0;
    for (int n = 0; n < frames; n++) {
        ace_run_frame(m);
        float buf[1024];
        size_t got = ace_audio_read(m, buf, 1024);
        for (size_t k = 0; k < got && total < cap; k++)
            out[total++] = buf[k];
    }
    return total;
}

static void test_audio_silent_when_idle(void)
{
    ace_machine *m = boot();
    static float samples[44100];
    size_t n = collect_audio(m, 50, samples, 44100);
    CHECK(n > 30000); /* about a second, minus the priming delay */
    float peak = 0;
    for (size_t k = 0; k < n; k++)
        peak = fabsf(samples[k]) > peak ? fabsf(samples[k]) : peak;
    CHECK(peak < 0.01f);
    ace_destroy(m);
}

static void test_audio_beep_pitch(void)
{
    ace_machine *m = boot();
    ace_spool(m, "200 1000 BEEP\n");
    static float samples[44100 * 3];
    size_t n = collect_audio(m, 150, samples, 44100 * 3);

    /* Count rising crossings with hysteresis over the whole capture: the 1 s tone dominates. */
    int crossings = 0, below = 1;
    float peak = 0;
    for (size_t k = 0; k < n; k++) {
        if (below && samples[k] > 0.05f) {
            crossings++;
            below = 0;
        } else if (!below && samples[k] < -0.05f) {
            below = 1;
        }
        peak = fabsf(samples[k]) > peak ? fabsf(samples[k]) : peak;
    }
    int hz = crossings; /* per second of tone */
    printf("test_core: 200 1000 BEEP measured %d Hz, peak %.2f\n", hz, peak);
    /* ACE manual: BEEP ( period in 8 us units, duration in ms ): 200 -> 1600 us -> 625 Hz. */
    CHECK(hz > 580 && hz < 670);
    CHECK(peak > 0.15f && peak <= 0.5f);
    ace_destroy(m);
}

static void test_audio_volume_and_priming(void)
{
    ace_machine *m = boot();
    float buf[4096];
    ace_audio_set_volume(m, 0.0f);
    ace_spool(m, "100 500 BEEP\n");
    static float samples[44100];
    size_t n = collect_audio(m, 60, samples, 44100);
    float peak = 0;
    for (size_t k = 0; k < n; k++)
        peak = fabsf(samples[k]) > peak ? fabsf(samples[k]) : peak;
    CHECK(peak < 0.001f);
    ace_destroy(m);

    /* Priming: less than 40 ms buffered gives no real samples. */
    ace_machine *fresh = ace_create(rom, rom_len);
    ace_run_frame(fresh); /* 20 ms */
    CHECK(ace_audio_read(fresh, buf, 256) == 0);
    ace_run_frame(fresh);
    ace_run_frame(fresh); /* 60 ms */
    CHECK(ace_audio_read(fresh, buf, 256) == 256);

    /* Nobody reading for a long time: the ring does not overflow into garbage. */
    for (int k = 0; k < 500; k++)
        ace_run_frame(fresh);
    size_t got = ace_audio_read(fresh, buf, 4096);
    CHECK(got > 0 && got <= 4096);
    ace_destroy(fresh);
}

int main(void)
{
    rom = read_file("../../assets/ace.rom", &rom_len);

    test_create_rejects_bad_rom();
    test_boot_and_arithmetic();
    test_framebuffer();
    test_memory_mirrors_and_rom();
    test_keyboard_matrix();
    test_spool_cancel();
    test_snapshot_round_trip();
    test_snapshot_rejects_bad_input();
    test_tape_save_and_load();
    test_tape_missing_loads_stub();
    test_tape_malformed_is_treated_as_missing();
    test_spool_waits_for_input_line();
    test_frogger_tape_loads();
    test_beeper_events();
    test_audio_silent_when_idle();
    test_audio_beep_pitch();
    test_audio_volume_and_priming();

    free(rom);
    printf("test_core: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
