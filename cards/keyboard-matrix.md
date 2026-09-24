# Keyboard matrix

- There are 8 half-rows. `keyboard_ports[0..7]` is active low (`0xFF` = nothing pressed). A key press ANDs a mask into one or two ports; a release ORs it back.
- On-screen keys come from `archive/iACE/iACE/en.lproj/ViewController.xib`: 40 buttons over `jupiterace.jpg` (780×687; the photo sits at x = −6 in the keyboard view). A button's tag is `(mask << 8) | port`. `tool/extract_keyboard_map.py` (`make assets`) writes `assets/keyboard_map.json`: label, port, mask, shift flag, and rectangle in photo pixels. It also copies the photo to `assets/images/` (plus `2.0x/`).
- Shift keys are tags 256 and 512 (port 0, masks 1 and 2). With "sticky shift" (setting `toggle_shift_keys`), a tap toggles the key and it stays latched.
- The char → (port, mask, port2, mask2) table is `keypress_response` in the original `ViewController.m`. It moves into C and the spooler uses it. Uppercase letters and symbols add shift keys through the second port/mask pair.
- Break is Shift+Space. A key-up of Space (tag 263) while spooling cancels the spool. All other input is ignored while spooling.
- Hardware keyboard support is deferred past v1.

## Flutter implementation (`lib/features/keyboard/`)
- `KeyboardMap` / `KeyDef` hold the parsed JSON. `AceKeyboard` draws the photo and places one `Listener` per key, so multi-touch works (hold SHIFT with one finger, tap a letter with another). Each key's touch area is enlarged by 8 photo px, half the gap between keys. Keys carry `Semantics` labels and the key `ValueKey('ace-key-<LABEL>')`, which tests use.
- Layout: the keyboard fills the available width. When height is short it crops the photo's top (the logo) first; if even the keys don't fit, it scales down and centres. Keys are never cut off.
- `KeyboardController` handles press and release, multi-touch counts, sticky shift and spool cancelling.
- **Minimum hold:** the ROM debounces and needs a key down for **3 frames** (60 ms), measured. A release that comes sooner is deferred until the key has been down for `minHoldFrames` = 4 emulator frames. It uses `EmulatorController.addFrameListener`. Without this, quick taps (and `adb shell input tap`) are lost.
- The screen and keyboard sit in `PortraitFrame` (shell), which pillarboxes wide windows (decision 6 in the plan).
- **In the drawer:** the keyboard drawer has a vertical-drag recognizer. It is alone in the gesture arena, so it wins on pointer-down and fires at once. The shell only treats a touch as a drawer drag after `kTouchSlop` of travel, and then calls `KeyboardController.cancelAll()`. Without this, every key press was cancelled the moment it started.
