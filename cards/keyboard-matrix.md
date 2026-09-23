# Keyboard matrix

- There are 8 half-rows. `keyboard_ports[0..7]` is active low (`0xFF` = nothing pressed). A key press ANDs a mask into one or two ports; a release ORs it back.
- On-screen keys come from `archive/iACE/iACE/en.lproj/ViewController.xib`: about 40 buttons over `jupiterace.jpg`. A button's tag is `(mask << 8) | port`: down does `ports[port] &= ~mask` and up does `ports[port] |= mask`. `tool/` extracts the frames and tags into `assets/keyboard_map.json`.
- Shift keys are tags 256 and 512 (port 0, masks 1 and 2). With "sticky shift" (setting `toggle_shift_keys`), a tap toggles the key and it stays latched.
- The char → (port, mask, port2, mask2) table is `keypress_response` in the original `ViewController.m`. It moves into C and the spooler uses it. Uppercase letters and symbols add shift keys through the second port/mask pair.
- Break is Shift+Space. A key-up of Space (tag 263) while spooling cancels the spool. All other input is ignored while spooling.
- Hardware keyboard support is deferred past v1.
