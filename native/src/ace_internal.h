/* Internal machine state of the Jupiter ACE emulator, copyright (C) 2026 Edward Patel.
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
 */

#ifndef ACE_INTERNAL_H
#define ACE_INTERNAL_H

#include "ace_api.h"

#define ACE_ROM_SIZE 0x2000
#define ACE_VIDEO_RAM 0x2400
#define ACE_CHARSET_RAM 0x2c00
#define ACE_TSTATES_PER_FRAME 65000UL

#define ACE_MAX_BEEPER_EVENTS 4096

/* Z80 registers, as in xz80. */
typedef struct {
    unsigned char a, f, b, c, d, e, h, l;
    unsigned char r, a1, f1, b1, c1, d1, e1, h1, l1, i, iff1, iff2, im;
    unsigned short pc;
    unsigned short ix, iy, sp;
    unsigned int radjust;
    unsigned char ixoriy, new_ixoriy;
    unsigned char intsample;
    unsigned char op;
} z80_regs;

typedef enum {
    TAPE_IDLE,     /* no tape operation in progress */
    TAPE_WAITING,  /* the ROM asked for a tape; waiting for ace_tape_supply */
    TAPE_SUPPLIED, /* tape data is ready for the header block */
    TAPE_DATA,     /* header block loaded; the data block comes next */
} tape_load_state;

struct ace_machine {
    unsigned char mem[65536];
    z80_regs cpu;
    unsigned long tstates;
    int interrupted;

    unsigned char keyboard_ports[8];

    /* Spooler */
    char *spool;
    size_t spool_pos;
    int spool_held_key;
    int spool_scans_left;

    /* Video */
    uint8_t framebuffer[ACE_SCREEN_WIDTH * ACE_SCREEN_HEIGHT * 4];
    unsigned char video_old[32 * 24];
    unsigned char charset_old[128 * 8];
    int video_valid;

    /* Tape load */
    tape_load_state tape_load_state;
    char tape_load_name[ACE_TAPE_NAME_MAX + 1];
    int tape_load_kind;
    uint8_t *tape_load_data;
    size_t tape_load_len;
    size_t tape_load_pos;

    /* Tape save */
    int tape_save_half;
    char tape_save_name[ACE_TAPE_NAME_MAX + 1];
    int tape_save_kind;
    uint8_t *tape_save_data;
    size_t tape_save_len;
    int tape_saved;

    /* Beeper */
    uint32_t beeper_events[ACE_MAX_BEEPER_EVENTS];
    size_t beeper_count;
    int beeper_level;

    int frame_flags;
    int frame_stop;
};

/* Memory, with ROM write protection and the ACE's mirrored RAM regions. */
static inline unsigned char ace_fetch(ace_machine *m, unsigned addr)
{
    return m->mem[addr & 0xffff];
}

static inline void ace_store(ace_machine *m, unsigned addr, unsigned char value)
{
    addr &= 0xffff;
    if (addr < ACE_ROM_SIZE)
        return;
    m->mem[addr] = value;
    if ((addr >= 0x2000 && addr <= 0x23ff) || (addr >= 0x2800 && addr <= 0x2bff)) {
        m->mem[addr + 0x400] = value;
    } else if ((addr >= 0x2400 && addr <= 0x27ff) || (addr >= 0x2c00 && addr <= 0x2fff)) {
        m->mem[addr - 0x400] = value;
    } else if (addr >= 0x3000 && addr <= 0x3fff) {
        unsigned off = addr & 0x03ff;
        m->mem[0x3000 + off] = value;
        m->mem[0x3400 + off] = value;
        m->mem[0x3800 + off] = value;
        m->mem[0x3c00 + off] = value;
    }
}

/* z80.c */
void z80_reset(ace_machine *m);
void z80_run_frame(ace_machine *m);

/* ace_core.c: hooks called by the CPU */
unsigned int ace_port_in(ace_machine *m, int h, int l);
unsigned int ace_port_out(ace_machine *m, int h, int l, int a);
void ace_tape_load_hook(ace_machine *m, int de, int hl);
void ace_tape_save_hook(ace_machine *m, int de, int hl);

/* keyboard.c */
int keyboard_char_keys(int ace_char, int *port1, int *mask1, int *port2, int *mask2);

#endif
