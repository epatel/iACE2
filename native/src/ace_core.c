/* Jupiter ACE machine: ports, spooler, video, tapes and snapshots.
 * Copyright (C) 2012-2026 Edward Patel.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <stdlib.h>
#include <string.h>

#include "ace_internal.h"

/* System variables used by the tape routines (see cards/emulator-core.md). */
#define SAVE_KIND_ADDR 8961 /* non-zero: bytes, zero: dictionary */
#define LOAD_HEADER_ADDR 9985 /* kind byte followed by the requested name */

/* Loaded when the requested tape does not exist (from iACE 1.x). */
static const uint8_t stub_bytes[799] = {
    0x1a, 0x00, 0x20, 0x6f, 0x74, 0x68, 0x65, 0x72, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x00, 0x03, 0x00, 0x24, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x01, 0x03, 0x43, 0x6f, 0x75, 0x6c, 0x64, 0x6e,
    0x27, 0x74, 0x20, 0x6c, 0x6f, 0x61, 0x64, 0x20, 0x79, 0x6f, 0x75, 0x72,
    0x20, 0x66, 0x69, 0x6c, 0x65, 0x21, 0x20,
};

static const uint8_t stub_dict[] = {
    0x1a, 0x00, 0x00, 0x6f, 0x74, 0x68, 0x65, 0x72, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x2a, 0x00, 0x51, 0x3c, 0x58, 0x3c, 0x4c, 0x3c, 0x4c, 0x3c, 0x4f,
    0x3c, 0x7b, 0x3c, 0x20, 0x2b, 0x00, 0x52, 0x55, 0xce, 0x27, 0x00, 0x49,
    0x3c, 0x03, 0xc3, 0x0e, 0x1d, 0x0a, 0x96, 0x13, 0x18, 0x00, 0x43, 0x6f,
    0x75, 0x6c, 0x64, 0x6e, 0x27, 0x74, 0x20, 0x6c, 0x6f, 0x61, 0x64, 0x20,
    0x79, 0x6f, 0x75, 0x72, 0x20, 0x66, 0x69, 0x6c, 0x65, 0x21, 0xb6, 0x04,
    0xff, 0x00,
};

static void patch_rom(ace_machine *m)
{
    m->mem[0x18a7] = 0xed; /* ED FC: tape load hook */
    m->mem[0x18a8] = 0xfc;
    m->mem[0x18a9] = 0xc9;

    m->mem[0x1820] = 0xed; /* ED FD: tape save hook */
    m->mem[0x1821] = 0xfd;
    m->mem[0x1822] = 0xc9;
}

/* ---- Keyboard ---------------------------------------------------------- */

void ace_key(ace_machine *m, int port, int mask, int down)
{
    if (!m || port < 0 || port > 7)
        return;
    if (down)
        m->keyboard_ports[port] &= ~mask & 0xff;
    else
        m->keyboard_ports[port] |= mask & 0xff;
}

void ace_key_char(ace_machine *m, int ace_char, int down)
{
    int port1, mask1, port2, mask2;
    if (!m || !keyboard_char_keys(ace_char, &port1, &mask1, &port2, &mask2))
        return;
    ace_key(m, port1, mask1, down);
    if (port2 >= 0)
        ace_key(m, port2, mask2, down);
}

void ace_key_release_all(ace_machine *m)
{
    if (!m)
        return;
    memset(m->keyboard_ports, 0xff, sizeof(m->keyboard_ports));
}

/* ---- Spooler ----------------------------------------------------------- */

void ace_spool(ace_machine *m, const char *text)
{
    if (!m || !text)
        return;
    ace_spool_cancel(m);
    if (!*text)
        return;
    m->spool = strdup(text);
    m->spool_pos = 0;
}

void ace_spool_cancel(ace_machine *m)
{
    if (!m)
        return;
    free(m->spool);
    m->spool = NULL;
    m->spool_pos = 0;
    if (m->spool_held_key)
        ace_key_release_all(m);
    m->spool_held_key = 0;
    m->spool_scans_left = 0;
    m->spool_blocked_scans = 0;
}

int ace_spool_active(ace_machine *m)
{
    return m && (m->spool || m->spool_held_key);
}

/* Scans to wait for the ROM to get back to the input line before typing anyway, so a
 * program that never returns to the prompt cannot stall the spooler (about 5 s). */
#define SPOOL_MAX_BLOCKED_SCANS 250

/* True while the ROM's input line is waiting for a key. The keyboard is scanned by the
 * interrupt routine, so what matters is where the main program was interrupted. Keys
 * typed while a command is still running would be mangled (e.g. after LOAD). */
static int input_line_waiting(ace_machine *m)
{
    return m->irq_pc >= ACE_KEY_WAIT_START && m->irq_pc <= ACE_KEY_WAIT_END;
}

/* Called on every keyboard scan. Presses one key, holds it for a few scans of the second
 * half-row, releases it, and waits a little longer after Enter. A new key is only pressed
 * when the input line is waiting for one. */
static void spooler_scan(ace_machine *m, int h)
{
    if (h == 0xfe && !m->spool_scans_left) {
        if (m->spool_held_key) {
            ace_key_release_all(m);
            if (m->spool_held_key == '\n')
                m->spool_scans_left = 4;
            m->spool_held_key = 0;
        } else if (m->spool && !input_line_waiting(m) &&
                   m->spool_blocked_scans < SPOOL_MAX_BLOCKED_SCANS) {
            m->spool_blocked_scans++;
        } else if (m->spool) {
            m->spool_blocked_scans = 0;
            int ch = (unsigned char)m->spool[m->spool_pos++];
            if (!m->spool[m->spool_pos]) {
                free(m->spool);
                m->spool = NULL;
                m->spool_pos = 0;
            }
            if (ch) {
                ace_key_char(m, ch, 1);
                m->spool_held_key = ch;
                m->spool_scans_left = 4;
            }
        }
    } else if (h == 0xfd && m->spool_scans_left) {
        m->spool_scans_left--;
    }
}

/* ---- Ports ------------------------------------------------------------- */

static void beeper_set(ace_machine *m, int level)
{
    if (m->beeper_level == level)
        return;
    m->beeper_level = level;
    if (m->beeper_count < ACE_MAX_BEEPER_EVENTS)
        m->beeper_events[m->beeper_count++] = (uint32_t)(m->tstates << 1) | (uint32_t)level;
}

unsigned int ace_port_in(ace_machine *m, int h, int l)
{
    if (l != 0xfe)
        return 255;

    spooler_scan(m, h);
    beeper_set(m, 0);

    switch (h) {
    case 0xfe: return m->keyboard_ports[0];
    case 0xfd: return m->keyboard_ports[1];
    case 0xfb: return m->keyboard_ports[2];
    case 0xf7: return m->keyboard_ports[3];
    case 0xef: return m->keyboard_ports[4];
    case 0xdf: return m->keyboard_ports[5];
    case 0xbf: return m->keyboard_ports[6];
    case 0x7f: return m->keyboard_ports[7];
    default: return 255;
    }
}

unsigned int ace_port_out(ace_machine *m, int h, int l, int a)
{
    (void)h;
    (void)a;
    if (l == 0xfe)
        beeper_set(m, 1);
    return 0;
}

size_t ace_beeper_events(ace_machine *m, const uint32_t **events_out)
{
    if (!m)
        return 0;
    if (events_out)
        *events_out = m->beeper_events;
    return m->beeper_count;
}

/* ---- Video ------------------------------------------------------------- */

/* Renders the 32x24 character screen into the RGBA framebuffer if video or charset RAM
 * changed. Returns 1 if the framebuffer changed. */
static int render_screen(ace_machine *m)
{
    const unsigned char *video = m->mem + ACE_VIDEO_RAM;
    const unsigned char *charset = m->mem + ACE_CHARSET_RAM;

    if (m->video_valid && !memcmp(video, m->video_old, sizeof(m->video_old)) &&
        !memcmp(charset, m->charset_old, sizeof(m->charset_old)))
        return 0;

    memcpy(m->video_old, video, sizeof(m->video_old));
    memcpy(m->charset_old, charset, sizeof(m->charset_old));
    m->video_valid = 1;

    uint32_t *pixels = (uint32_t *)m->framebuffer;
    const uint32_t ink = 0xffffffffu;
    const uint32_t paper = 0xff000000u; /* RGBA bytes 00 00 00 ff on little-endian */

    for (int y = 0; y < 24; y++) {
        for (int x = 0; x < 32; x++) {
            int cell = video[x + y * 32];
            const unsigned char *glyph = charset + (cell & 0x7f) * 8;
            for (int row = 0; row < 8; row++) {
                unsigned char bits = glyph[row];
                if (cell & 0x80)
                    bits ^= 0xff;
                uint32_t *out = pixels + (y * 8 + row) * ACE_SCREEN_WIDTH + x * 8;
                for (int col = 0; col < 8; col++)
                    out[col] = (bits & (0x80 >> col)) ? ink : paper;
            }
        }
    }
    return 1;
}

const uint8_t *ace_framebuffer(ace_machine *m)
{
    return m ? m->framebuffer : NULL;
}

/* ---- Tapes ------------------------------------------------------------- */

static void read_tape_name(ace_machine *m, unsigned addr, char *name)
{
    int n = 0;
    while (n < ACE_TAPE_NAME_MAX) {
        unsigned char ch = ace_fetch(m, addr + n);
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\v' || ch == '\f')
            break;
        name[n++] = (char)ch;
    }
    name[n] = '\0';
}

/* A tape must be exactly two well-formed blocks, each with at least the checksum byte. */
static int tape_is_valid(const uint8_t *tape, size_t len)
{
    size_t pos = 0;
    for (int block = 0; block < 2; block++) {
        if (pos + 2 > len)
            return 0;
        size_t block_len = tape[pos] | (tape[pos + 1] << 8);
        pos += 2;
        if (block_len < 1 || pos + block_len > len)
            return 0;
        pos += block_len;
    }
    return 1;
}

static void clear_tape_load(ace_machine *m)
{
    free(m->tape_load_data);
    m->tape_load_data = NULL;
    m->tape_load_len = 0;
    m->tape_load_pos = 0;
    m->tape_load_state = TAPE_IDLE;
}

/* Copies the next block (without its checksum byte) to hl. */
static void load_block(ace_machine *m, const uint8_t *tape, int hl)
{
    size_t block_len = tape[m->tape_load_pos] | (tape[m->tape_load_pos + 1] << 8);
    const uint8_t *src = tape + m->tape_load_pos + 2;
    for (size_t n = 0; n + 1 < block_len && hl + n < 0x10000; n++)
        ace_store(m, hl + (unsigned)n, src[n]);
    m->tape_load_pos += 2 + block_len;
}

void ace_tape_load_hook(ace_machine *m, int de, int hl)
{
    (void)de;

    switch (m->tape_load_state) {
    case TAPE_IDLE:
        read_tape_name(m, LOAD_HEADER_ADDR + 1, m->tape_load_name);
        m->tape_load_kind = ace_fetch(m, LOAD_HEADER_ADDR) ? ACE_TAPE_BYTES : ACE_TAPE_DICT;
        m->tape_load_state = TAPE_WAITING;
        /* fall through */
    case TAPE_WAITING:
        /* Stop here and run ED FC again once the host has supplied the tape. */
        m->cpu.pc -= 2;
        m->frame_flags |= ACE_FRAME_TAPE_LOAD;
        m->frame_stop = 1;
        return;

    case TAPE_SUPPLIED:
        load_block(m, m->tape_load_data ? m->tape_load_data
                      : m->tape_load_kind == ACE_TAPE_BYTES ? stub_bytes : stub_dict, hl);
        /* Make the loaded header carry the requested name so the ROM accepts it. */
        for (int n = 0; n < ACE_TAPE_NAME_MAX; n++)
            ace_store(m, hl + 1 + n, ace_fetch(m, LOAD_HEADER_ADDR + 1 + n));
        m->tape_load_state = TAPE_DATA;
        return;

    case TAPE_DATA:
        load_block(m, m->tape_load_data ? m->tape_load_data
                      : m->tape_load_kind == ACE_TAPE_BYTES ? stub_bytes : stub_dict, hl);
        clear_tape_load(m);
        return;
    }
}

int ace_tape_request(ace_machine *m, char *name_out, size_t name_cap, int *kind_out)
{
    if (!m || m->tape_load_state != TAPE_WAITING)
        return 0;
    if (name_out && name_cap) {
        strncpy(name_out, m->tape_load_name, name_cap - 1);
        name_out[name_cap - 1] = '\0';
    }
    if (kind_out)
        *kind_out = m->tape_load_kind;
    return 1;
}

void ace_tape_supply(ace_machine *m, const uint8_t *tape, size_t len)
{
    if (!m || m->tape_load_state != TAPE_WAITING)
        return;
    free(m->tape_load_data);
    m->tape_load_data = NULL;
    m->tape_load_len = 0;
    m->tape_load_pos = 0;
    if (tape && len && tape_is_valid(tape, len)) {
        m->tape_load_data = malloc(len);
        if (m->tape_load_data) {
            memcpy(m->tape_load_data, tape, len);
            m->tape_load_len = len;
        }
    }
    m->tape_load_state = TAPE_SUPPLIED;
}

static int append_block(ace_machine *m, int de, int hl)
{
    size_t block_len = (size_t)(de + 1);
    uint8_t *grown = realloc(m->tape_save_data, m->tape_save_len + 2 + block_len);
    if (!grown)
        return 0;
    m->tape_save_data = grown;
    uint8_t *out = grown + m->tape_save_len;
    out[0] = block_len & 0xff;
    out[1] = (block_len >> 8) & 0xff;
    for (size_t n = 0; n < block_len; n++)
        out[2 + n] = ace_fetch(m, hl + (unsigned)n);
    m->tape_save_len += 2 + block_len;
    return 1;
}

void ace_tape_save_hook(ace_machine *m, int de, int hl)
{
    if (!m->tape_save_half) {
        free(m->tape_save_data);
        m->tape_save_data = NULL;
        m->tape_save_len = 0;
        m->tape_saved = 0;
        read_tape_name(m, hl + 1, m->tape_save_name);
        m->tape_save_kind = ace_fetch(m, SAVE_KIND_ADDR) ? ACE_TAPE_BYTES : ACE_TAPE_DICT;
        m->tape_save_half = append_block(m, de, hl);
    } else {
        m->tape_save_half = 0;
        if (append_block(m, de, hl)) {
            m->tape_saved = 1;
            m->frame_flags |= ACE_FRAME_TAPE_SAVED;
        }
    }
}

size_t ace_tape_saved(ace_machine *m, char *name_out, size_t name_cap, int *kind_out,
                      const uint8_t **data_out)
{
    if (!m || !m->tape_saved)
        return 0;
    if (name_out && name_cap) {
        strncpy(name_out, m->tape_save_name, name_cap - 1);
        name_out[name_cap - 1] = '\0';
    }
    if (kind_out)
        *kind_out = m->tape_save_kind;
    if (data_out)
        *data_out = m->tape_save_data;
    return m->tape_save_len;
}

/* ---- Snapshots --------------------------------------------------------- */

/* Format (little-endian), version 1:
 *   "ACE2SNAP", u16 version, u16 reserved,
 *   u8 a f b c d e h l r a1 f1 b1 c1 d1 e1 h1 l1 i iff1 iff2 im,
 *   u16 pc ix iy sp, u32 radjust, u8 ixoriy new_ixoriy intsample op,
 *   u32 tstates, u8 interrupted, u16 irq_pc, u8 keyboard_ports[8], u8 beeper_level,
 *   u8 mem[65536]
 * Add new versions by appending fields; keep the reader for every older version. */

static const char snapshot_magic[8] = {'A', 'C', 'E', '2', 'S', 'N', 'A', 'P'};
#define SNAPSHOT_VERSION 1
#define SNAPSHOT_V1_SIZE (8 + 2 + 2 + 21 + 8 + 4 + 4 + 4 + 1 + 2 + 8 + 1 + 65536)

typedef struct {
    uint8_t *p;
    const uint8_t *q;
} cursor;

static void put8(cursor *c, unsigned v) { *c->p++ = (uint8_t)v; }
static void put16(cursor *c, unsigned v) { put8(c, v & 0xff); put8(c, (v >> 8) & 0xff); }
static void put32(cursor *c, unsigned long v) { put16(c, v & 0xffff); put16(c, (v >> 16) & 0xffff); }
static unsigned get8(cursor *c) { return *c->q++; }
static unsigned get16(cursor *c) { unsigned v = get8(c); return v | (get8(c) << 8); }
static unsigned long get32(cursor *c) { unsigned long v = get16(c); return v | ((unsigned long)get16(c) << 16); }

size_t ace_snapshot_size(void)
{
    return SNAPSHOT_V1_SIZE;
}

size_t ace_snapshot_save(ace_machine *m, uint8_t *out, size_t cap)
{
    /* A snapshot in the middle of a tape transfer could not be resumed. While waiting for a
     * tape, pc points at ED FC again, so a restored machine simply asks for the tape again. */
    if (!m || !out || cap < SNAPSHOT_V1_SIZE || m->tape_load_state > TAPE_WAITING || m->tape_save_half)
        return 0;

    const z80_regs *r = &m->cpu;
    cursor c = {out, NULL};
    memcpy(c.p, snapshot_magic, sizeof(snapshot_magic));
    c.p += sizeof(snapshot_magic);
    put16(&c, SNAPSHOT_VERSION);
    put16(&c, 0);
    const unsigned char regs8[21] = {r->a, r->f, r->b, r->c, r->d, r->e, r->h, r->l, r->r,
                                     r->a1, r->f1, r->b1, r->c1, r->d1, r->e1, r->h1, r->l1,
                                     r->i, r->iff1, r->iff2, r->im};
    for (int n = 0; n < 21; n++)
        put8(&c, regs8[n]);
    put16(&c, r->pc);
    put16(&c, r->ix);
    put16(&c, r->iy);
    put16(&c, r->sp);
    put32(&c, r->radjust);
    put8(&c, r->ixoriy);
    put8(&c, r->new_ixoriy);
    put8(&c, r->intsample);
    put8(&c, r->op);
    put32(&c, m->tstates);
    put8(&c, (unsigned)m->interrupted);
    put16(&c, m->irq_pc);
    for (int n = 0; n < 8; n++)
        put8(&c, m->keyboard_ports[n]);
    put8(&c, (unsigned)m->beeper_level);
    memcpy(c.p, m->mem, sizeof(m->mem));
    c.p += sizeof(m->mem);
    return (size_t)(c.p - out);
}

int ace_snapshot_load(ace_machine *m, const uint8_t *in, size_t len)
{
    if (!m || !in || len < 12 || memcmp(in, snapshot_magic, sizeof(snapshot_magic)))
        return 0;

    cursor c = {NULL, in + sizeof(snapshot_magic)};
    unsigned version = get16(&c);
    get16(&c);
    if (version != 1 || len != SNAPSHOT_V1_SIZE)
        return 0;

    z80_regs r;
    memset(&r, 0, sizeof(r));
    unsigned char *regs8[21] = {&r.a, &r.f, &r.b, &r.c, &r.d, &r.e, &r.h, &r.l, &r.r,
                                &r.a1, &r.f1, &r.b1, &r.c1, &r.d1, &r.e1, &r.h1, &r.l1,
                                &r.i, &r.iff1, &r.iff2, &r.im};
    for (int n = 0; n < 21; n++)
        *regs8[n] = (unsigned char)get8(&c);
    r.pc = (unsigned short)get16(&c);
    r.ix = (unsigned short)get16(&c);
    r.iy = (unsigned short)get16(&c);
    r.sp = (unsigned short)get16(&c);
    r.radjust = (unsigned)get32(&c);
    r.ixoriy = (unsigned char)get8(&c);
    r.new_ixoriy = (unsigned char)get8(&c);
    r.intsample = (unsigned char)get8(&c);
    r.op = (unsigned char)get8(&c);

    ace_spool_cancel(m);
    clear_tape_load(m);
    m->tape_save_half = 0;

    m->cpu = r;
    m->tstates = get32(&c);
    m->interrupted = (int)get8(&c);
    m->irq_pc = (unsigned short)get16(&c);
    for (int n = 0; n < 8; n++)
        m->keyboard_ports[n] = (unsigned char)get8(&c);
    m->beeper_level = (int)get8(&c);
    memcpy(m->mem, c.q, sizeof(m->mem));
    m->video_valid = 0;
    return 1;
}

/* ---- Lifecycle --------------------------------------------------------- */

ace_machine *ace_create(const uint8_t *rom, size_t rom_len)
{
    if (!rom || rom_len != ACE_ROM_SIZE)
        return NULL;
    ace_machine *m = calloc(1, sizeof(*m));
    if (!m)
        return NULL;
    memcpy(m->mem, rom, ACE_ROM_SIZE);
    patch_rom(m);
    memset(m->mem + ACE_ROM_SIZE, 0xff, sizeof(m->mem) - ACE_ROM_SIZE);
    ace_key_release_all(m);
    z80_reset(m);
    return m;
}

void ace_destroy(ace_machine *m)
{
    if (!m)
        return;
    ace_spool_cancel(m);
    clear_tape_load(m);
    free(m->tape_save_data);
    free(m);
}

void ace_reset(ace_machine *m)
{
    if (!m)
        return;
    ace_spool_cancel(m);
    clear_tape_load(m);
    m->tape_save_half = 0;
    ace_key_release_all(m);
    z80_reset(m);
}

int ace_run_frame(ace_machine *m)
{
    if (!m)
        return 0;
    m->frame_flags = 0;
    m->beeper_count = 0;
    m->tape_saved = 0;
    z80_run_frame(m);
    if (render_screen(m))
        m->frame_flags |= ACE_FRAME_SCREEN_DIRTY;
    return m->frame_flags;
}

uint8_t ace_peek(ace_machine *m, uint16_t addr)
{
    return m ? m->mem[addr] : 0;
}

void ace_poke(ace_machine *m, uint16_t addr, uint8_t value)
{
    if (m)
        ace_store(m, addr, value);
}
