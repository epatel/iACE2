# Emulator core (C)

**Origin.** The Z80 core is xz80 by Ian Collier (1994), through xAce by Edward Patel and Lawrence Woodman. The original files are in `archive/iACE/iACE/`: `z80.c` holds the loop, `z80ops.c`, `cbops.c` and `edops.c` are `#include`d into the switch, `z80.h` has the memory macros, and `iace.m` is the machine glue.

## Memory map (64K, `mem[]`)
- `0x0000–0x1FFF`: ROM (8K, `ace.rom`). Writes are ignored (`memattr[0] = 0`).
- `0x2000–0x23FF` mirrors `0x2400–0x27FF`: video RAM, 32×24 cells at **`0x2400`**.
- `0x2800–0x2BFF` mirrors `0x2C00–0x2FFF`: character set RAM at **`0x2C00`**, 128 chars × 8 bytes.
- `0x3000–0x3FFF`: 1K RAM mirrored 4×. The `store` macro writes to all mirrors.
- From `0x4000`: RAM, filled with `0xFF` at boot.

## Video
Cell byte `c`: bit 7 = inverse, `c & 0x7F` = character index into the charset. The output is 256×192, 1 bit per pixel, with MSB first in each charset row. Only redraw when video RAM changed. The original compares against a copy of video RAM. It does not check charset changes, which is a known gap.

## Timing
Clock 3.25 MHz, frame 50 Hz → `tsmax = 65000` T-states per frame. When `tstates > tsmax`, the frame ends and `interrupted = 1`. At the next instruction boundary with `iff1` set, it runs `push pc; pc = 0x38`. In the port, a frame boundary returns to the caller instead of sleeping.

## I/O port 0xFE
- `in(h=row, l=0xFE)` returns the keyboard half-row. `h` is one of `FE FD FB F7 EF DF BF 7F` → `keyboard_ports[0..7]`. Active low.
- `out(l=0xFE)` toggles the beeper. The original derives the period from the T-state delta between outs. The port records edge T-states per frame for the audio code.
- The spooler is driven from `in(0xFEFE)` scans. It presses one char, then releases it on the next scan, and waits 4 more `0xFDFE` scans after a newline.

## ROM patches (tape)
- `0x18A7: ED FC C9` → `load_p(de, hl)`
- `0x1820: ED FD C9` → `save_p(de, hl)`

Each tape operation is **two calls**: the header block, then the data block. The original tracks this with static `firstTime`. The filename is at `mem[hl+1..]` for save and `mem[9985+1..]` for load, up to 10 chars terminated by a space. `mem[8961]` (save) and `mem[9985]` (load) are non-zero for bytes (`.byt`) and zero for a dictionary (`.dic`). A stored tape is `[len_lo len_hi][len bytes]` for the header, followed by the same layout for data. When a file is missing, the core loads the built-in stub `empty_dict` / `empty_bytes` ("Couldn't load your file!").

## Reset
Zero all registers, `pc = 0`, `tstates = 0`. RAM is **not** cleared, which matches the original `reset_ace`.
