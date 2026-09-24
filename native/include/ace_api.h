/* Public C API of the Jupiter ACE emulator core, copyright (C) 2026 Edward Patel.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * This is the only header ffigen reads. Keep it plain C.
 */

#ifndef ACE_API_H
#define ACE_API_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define ACE_EXPORT __declspec(dllexport)
#else
#define ACE_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct ace_machine ace_machine;

enum {
    ACE_SCREEN_WIDTH = 256,
    ACE_SCREEN_HEIGHT = 192,
    ACE_TAPE_NAME_MAX = 10,
    ACE_AUDIO_SAMPLE_RATE = 44100,
};

/* Flags returned by ace_run_frame. */
enum {
    ACE_FRAME_SCREEN_DIRTY = 1 << 0, /* framebuffer changed since the last frame */
    ACE_FRAME_TAPE_LOAD = 1 << 1,    /* ROM wants a tape: see ace_tape_request, answer with ace_tape_supply */
    ACE_FRAME_TAPE_SAVED = 1 << 2,   /* a tape was saved: see ace_tape_saved */
};

typedef enum {
    ACE_TAPE_DICT = 0,  /* .dic, a FORTH dictionary */
    ACE_TAPE_BYTES = 1, /* .byt, a block of memory */
} ace_tape_kind;

/* Lifecycle. rom must be the 8K Jupiter ACE ROM; it is copied. Returns NULL on bad input. */
ACE_EXPORT ace_machine *ace_create(const uint8_t *rom, size_t rom_len);
ACE_EXPORT void ace_destroy(ace_machine *m);
ACE_EXPORT void ace_reset(ace_machine *m);

/* Runs one 20 ms frame (65000 T-states at 3.25 MHz). Returns ACE_FRAME_* flags.
 * A frame ends early when the ROM asks for a tape. */
ACE_EXPORT int ace_run_frame(ace_machine *m);

/* RGBA, ACE_SCREEN_WIDTH * ACE_SCREEN_HEIGHT * 4 bytes. The pointer stays valid for the machine's lifetime. */
ACE_EXPORT const uint8_t *ace_framebuffer(ace_machine *m);

/* Keyboard. ace_key works on the raw matrix (port 0..7, mask of the bit(s)). ace_key_char
 * presses the keys for an ACE character code, including shifts. */
ACE_EXPORT void ace_key(ace_machine *m, int port, int mask, int down);
ACE_EXPORT void ace_key_char(ace_machine *m, int ace_char, int down);
ACE_EXPORT void ace_key_release_all(ace_machine *m);

/* Spooler: types text into the machine, one key at a time. '\n' is Enter. */
ACE_EXPORT void ace_spool(ace_machine *m, const char *text);
ACE_EXPORT void ace_spool_cancel(ace_machine *m);
ACE_EXPORT int ace_spool_active(ace_machine *m);

/* Tapes. A tape is a sequence of blocks, each [u16 little-endian length][length bytes]:
 * a header block followed by a data block (the same layout as a .TAP file).
 *
 * Load: when ace_run_frame returns ACE_FRAME_TAPE_LOAD, read the requested name and kind with
 * ace_tape_request, then call ace_tape_supply with the tape, or with len 0 if there is none
 * (the machine then loads a "Couldn't load your file!" stub). */
ACE_EXPORT int ace_tape_request(ace_machine *m, char *name_out, size_t name_cap, int *kind_out);
ACE_EXPORT void ace_tape_supply(ace_machine *m, const uint8_t *tape, size_t len);

/* Save: when ace_run_frame returns ACE_FRAME_TAPE_SAVED, read it here. The data pointer is
 * valid until the next ace_run_frame. Returns the tape length, or 0 if nothing was saved. */
ACE_EXPORT size_t ace_tape_saved(ace_machine *m, char *name_out, size_t name_cap, int *kind_out,
                                 const uint8_t **data_out);

/* Snapshots: a versioned binary of the whole machine state. */
ACE_EXPORT size_t ace_snapshot_size(void);
ACE_EXPORT size_t ace_snapshot_save(ace_machine *m, uint8_t *out, size_t cap);
/* Returns 1 on success. On failure the machine state is unchanged. */
ACE_EXPORT int ace_snapshot_load(ace_machine *m, const uint8_t *in, size_t len);

/* Memory access, for tests and tools. */
ACE_EXPORT uint8_t ace_peek(ace_machine *m, uint16_t addr);
ACE_EXPORT void ace_poke(ace_machine *m, uint16_t addr, uint8_t value);

/* Beeper: the speaker level changes during the last frame, as (T-state << 1) | level pairs.
 * Valid until the next ace_run_frame. */
ACE_EXPORT size_t ace_beeper_events(ace_machine *m, const uint32_t **events_out);

/* Sound. ace_run_frame turns the beeper into 20 ms of mono float samples at
 * ACE_AUDIO_SAMPLE_RATE. ace_audio_start opens the device and plays them, and returns 1 on
 * success. Stop before ace_destroy, or let ace_destroy do it. Volume is 0..1 (default 1). */
ACE_EXPORT int ace_audio_start(ace_machine *m);
ACE_EXPORT void ace_audio_stop(ace_machine *m);
ACE_EXPORT void ace_audio_set_volume(ace_machine *m, float volume);

/* Takes up to `frames` samples, filling the rest of `out` with a fade to silence. Returns the
 * number of real samples. The audio device calls this; tests may call it when no device is
 * started. */
ACE_EXPORT size_t ace_audio_read(ace_machine *m, float *out, size_t frames);

#ifdef __cplusplus
}
#endif

#endif
