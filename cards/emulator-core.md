# Emulator core (C)

**Origin.** The Z80 core is xz80 by Ian Collier (1994), through xAce by Edward Patel and Lawrence Woodman. The originals are in `archive/iACE/iACE/`.

## Files (`native/`)
- `include/ace_api.h`: the public API (the only header ffigen reads).
- `src/ace_internal.h`: the `ace_machine` struct and the `ace_fetch`/`ace_store` memory functions (ROM protection, mirrors).
- `src/z80.c`: `z80_run_frame`. Macros map xz80's register names (`a`, `pc`, …), `fetch`/`store`, `in`/`out` and `load_p`/`save_p` onto the machine.
- `src/z80ops.c`, `cbops.c`, `edops.c`: **unmodified** xz80 instruction files, `#include`d into the switch in `z80.c`. Never compile them on their own, and don't edit them.
- `src/ace_core.c`: ports, spooler, video, tape hooks, snapshots, lifecycle.
- `src/keyboard.c`: character → key matrix table.
- `test/test_core.c`: host tests, run by `make core-test` (and `make core-test-ubsan`). They load `assets/ace.rom` and `assets/tapes/frogger.dic`.

There are no globals, so several machines can coexist (the tests rely on that).

## Memory map (64K, `mem[]`)
- `0x0000–0x1FFF`: ROM (8K, `ace.rom`). Writes are ignored (`memattr[0] = 0`).
- `0x2000–0x23FF` mirrors `0x2400–0x27FF`: video RAM, 32×24 cells at **`0x2400`**.
- `0x2800–0x2BFF` mirrors `0x2C00–0x2FFF`: character set RAM at **`0x2C00`**, 128 chars × 8 bytes.
- `0x3000–0x3FFF`: 1K RAM mirrored 4×. The `store` macro writes to all mirrors.
- From `0x4000`: RAM, filled with `0xFF` at boot.

## Video
Cell byte `c`: bit 7 = inverse, `c & 0x7F` = character index into the charset. The output is 256×192 RGBA, with MSB first in each charset row. Ink is white and paper is black, both with alpha 255. The screen is redrawn only when video RAM **or charset RAM** changed; iACE 1.x only checked video RAM. `ace_run_frame` returns `ACE_FRAME_SCREEN_DIRTY` when it redraws.

After a cold boot the screen is blank except for the cursor on the bottom line. The machine is ready after about 100 frames.

## Timing
Clock 3.25 MHz, frame 50 Hz → 65000 T-states per frame. When `tstates > 65000`, the frame ends and `interrupted = 1`. At the next instruction boundary with `iff1` set, it runs `push pc; pc = 0x38`. `ace_run_frame` returns at the frame boundary; the host paces frames (nothing sleeps in C). HALT jumps straight to the end of the frame, as in xz80.

## I/O port 0xFE
- `in(h=row, l=0xFE)` returns the keyboard half-row. `h` is one of `FE FD FB F7 EF DF BF 7F` → `keyboard_ports[0..7]`. Active low.
- The beeper: `IN 0xFE` pulls the speaker to level 0 and `OUT 0xFE` pushes it to level 1. Each level change is recorded as `(tstate << 1) | level`, readable with `ace_beeper_events` until the next frame. (iACE 1.x turned the period between OUTs into a sine wave instead.)
- The spooler is driven from `in(0xFEFE)` scans. It presses one char, then releases it on the next scan, and waits 4 more `0xFDFE` scans after a newline. It only presses a **new** key when the input line is waiting for one: the interrupted pc (`irq_pc`) must be in the ROM's key-wait loop `0x059B–0x059E` (`BIT 5,(3C28h) / JR Z`). If a program never returns to the prompt, it types anyway after 250 blocked scans (about 5 s). Without this gate, lines typed after a slow command such as `LOAD` got mangled (`VLIST` became `?IST`), which is an iACE 1.x bug.

## ROM patches (tape)
- `0x18A7: ED FC C9` → `load_p(de, hl)`
- `0x1820: ED FD C9` → `save_p(de, hl)`

Each tape operation is **two calls**: the header block, then the data block. `ace_core.c` tracks this with `tape_load_state` / `tape_save_half` (iACE 1.x used static `firstTime`).

Load flow: on the first ED FC the core records the requested name and kind, moves `pc` back 2 so ED FC runs again, and ends the frame with `ACE_FRAME_TAPE_LOAD`. The host answers with `ace_tape_supply` (length 0, or a malformed tape, means "missing"), and the next frame loads both blocks. Save flow: after the second ED FD the frame returns `ACE_FRAME_TAPE_SAVED` and `ace_tape_saved` gives the tape. The filename is at `mem[hl+1..]` for save and `mem[9985+1..]` for load, up to 10 chars terminated by a space. `mem[8961]` (save) and `mem[9985]` (load) are non-zero for bytes (`.byt`) and zero for a dictionary (`.dic`). A stored tape is `[len_lo len_hi][len bytes]` for the header (26 bytes: 25 plus checksum), followed by the same layout for data. That is the `.TAP` layout. When a file is missing, the core loads the built-in stub `empty_dict` / `empty_bytes` ("Couldn't load your file!").

## Reset
Zero all registers, `pc = 0`, `tstates = 0`. RAM is **not** cleared, which matches the original `reset_ace`.

## Character codes (`ace_key_char`, spooler)
Printable ASCII maps to itself. Special codes: 0x01 delete line, 0x02 inverse video, 0x03 graphics, 0x04–0x07 left/down/up/right, 0x08 delete, 0x09 tab (types a space), 0x0A Enter, **0x1B BREAK**. The ACE character set puts **£ at 0x60** and **© at 0x7F**, so the host must convert Unicode text before spooling. iACE 1.x had bugs here: `z` couldn't be typed and BREAK collided with `&`.

## Snapshots
`ace_snapshot_save` / `ace_snapshot_load` use the versioned format described in the persistence card. Saving refuses (returns 0) while a tape transfer is half done. A machine waiting for a tape can be saved, and after restoring it asks for the tape again.

## Frogger
The bundled `frogger.dic` redefines `VLIST` to start the game: `LOAD frogger`, then `VLIST`.

## Sound (`audio.c`)
- **Rendering** (emulator thread, inside `ace_run_frame`): each frame's beeper events become 882 samples, 20 ms at `ACE_AUDIO_SAMPLE_RATE` = 44100. Each sample is the fraction of its T-state slice the speaker was high (a box filter, which avoids aliasing). That then goes through a DC-blocking high-pass (`y = 0.995·(y' + x − x')`, about 35 Hz; the real speaker is AC-coupled), scaled by 0.5·volume. The idle speaker is therefore silent even though keyboard scans (`IN 0xFE`) keep pulling it low.
- **Ring:** an 8192-sample single-producer/single-consumer ring with C11 atomics (`audio_write`/`audio_read`). If it's full, the producer drops the whole frame. The consumer (`ace_audio_read`, on the device thread) starts playing at 40 ms buffered, skips ahead above 150 ms, and on underrun fades the last sample and re-primes.
- **Device:** vendored `native/third_party/miniaudio.h` (v0.11.25, public domain/MIT-0) configured in `ace_miniaudio.h`: playback only, CoreAudio, AAudio or OpenSL. On iOS the implementation must be Objective-C, so the hook compiles `miniaudio_impl.m` there and `miniaudio_impl.c` elsewhere. The iOS session category is **Playback + mix-with-others**: it plays with the silent switch on, as iACE 1.x did, and doesn't stop other apps' music. miniaudio's default, PlayAndRecord, would ask for microphone access.
- `ace_audio_start`/`stop` open and close the device; `EmulatorController(playSound: true)` does this on resume/pause. Tests never open a device; they call `ace_audio_read` directly.
- **Measured:** `200 1000 BEEP` → 625 Hz (the manual's period unit is 8 µs: 200·8 µs = 1.6 ms). On the host Mac the device consumed 2.98 s of 3.00 s produced. It was verified running on the iPad simulator and via AAudio on the Android emulator (`dumpsys audio`: started, 44.1 kHz mono).
