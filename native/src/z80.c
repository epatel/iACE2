/* Emulation of the Z80 CPU with hooks into the other parts of the Jupiter ACE emulator.
 * Copyright (C) 1994 Ian Collier.
 * Frame-stepped, global-free version copyright (C) 2026 Edward Patel.
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

#include <string.h>

#include "ace_internal.h"

static const unsigned char partable[256] = {
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    0, 4, 4, 0, 4, 0, 0, 4, 4, 0, 0, 4, 0, 4, 4, 0,
    4, 0, 0, 4, 0, 4, 4, 0, 0, 4, 4, 0, 4, 0, 0, 4
};

void z80_reset(ace_machine *m)
{
    memset(&m->cpu, 0, sizeof(m->cpu));
    m->tstates = 0;
    m->interrupted = 0;
}

/* The instruction files below are the unmodified xz80 sources. These macros map the names
 * they use onto the machine passed to z80_run_frame. */
#define op      (cpu->op)
#define a       (cpu->a)
#define f       (cpu->f)
#define b       (cpu->b)
#define c       (cpu->c)
#define d       (cpu->d)
#define e       (cpu->e)
#define h       (cpu->h)
#define l       (cpu->l)
#define r       (cpu->r)
#define a1      (cpu->a1)
#define f1      (cpu->f1)
#define b1      (cpu->b1)
#define c1      (cpu->c1)
#define d1      (cpu->d1)
#define e1      (cpu->e1)
#define h1      (cpu->h1)
#define l1      (cpu->l1)
#define i       (cpu->i)
#define iff1    (cpu->iff1)
#define iff2    (cpu->iff2)
#define im      (cpu->im)
#define pc      (cpu->pc)
#define ix      (cpu->ix)
#define iy      (cpu->iy)
#define sp      (cpu->sp)
#define radjust (cpu->radjust)
#define ixoriy  (cpu->ixoriy)
#define new_ixoriy (cpu->new_ixoriy)
#define intsample  (cpu->intsample)

#define tstates (m->tstates)
#define tsmax   ACE_TSTATES_PER_FRAME

#define parity(x) (partable[x])

#define fetch(x)  ace_fetch(m, (x))
#define fetch2(x) ((fetch((x) + 1) << 8) | fetch(x))
#define store(x, y) ace_store(m, (x), (y))
#define store2b(x, hi, lo) do { unsigned short store_addr_ = (x); \
        ace_store(m, store_addr_, (lo)); ace_store(m, store_addr_ + 1, (hi)); } while (0)
#define store2(x, y) store2b(x, (y) >> 8, (y) & 255)

#define in(hi, lo)       ace_port_in(m, (hi), (lo))
#define out(hi, lo, val) ace_port_out(m, (hi), (lo), (val))
#define load_p(x, y)     ace_tape_load_hook(m, (x), (y))
#define save_p(x, y)     ace_tape_save_hook(m, (x), (y))

#define bc ((b << 8) | c)
#define de ((d << 8) | e)
#define hl ((h << 8) | l)

void z80_run_frame(ace_machine *m)
{
    z80_regs *cpu = &m->cpu;
    int frame_done = 0;

    while (!frame_done) {
        ixoriy = new_ixoriy;
        new_ixoriy = 0;
        intsample = 1;
        op = fetch(pc);
        pc++;
        radjust++;

        switch (op) {
#include "z80ops.c"
        }

        if (tstates > tsmax) {
            tstates -= tsmax;
            m->interrupted = 1;
            frame_done = 1;
        }

        if (m->interrupted && intsample && iff1) {
            m->irq_pc = pc;
            push2(pc);
            pc = 0x38;
            m->interrupted = 0;
        }

        if (m->frame_stop) {
            m->frame_stop = 0;
            frame_done = 1;
        }
    }
}
