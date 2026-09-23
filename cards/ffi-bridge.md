# FFI bridge

- `native/include/ace_api.h` is the **only** header ffigen reads. Keep it plain C: an opaque `ace_machine*`, fixed-width ints, and no macros that ffigen can't parse.
- Bindings are generated with `make ffigen`, which runs `tool/ffigen.dart` (ffigen 22 takes a Dart config, not YAML), into `lib/core/ffi/ace_bindings.g.dart`. The generated file is committed. Never hand-edit it; regenerate it after every change to `ace_api.h`. The visitor includes only `ace_*` / `ACE_*` names; unnamed-enum constants need the `unnamedEnumConstant` callback.
- The bindings use `@Native` with the default asset ID `package:iace/core/ffi/ace_bindings.g.dart`, which is why the hook's `assetName` is `core/ffi/ace_bindings.g.dart`. If either changes, change both.
- `lib/core/ffi/ace_machine.dart` wraps the bindings. It owns the pointer and attaches a `NativeFinalizer` that calls `ace_destroy`. Only this class touches `dart:ffi` types; features use the wrapper.
- The native build is `hook/build.dart` using `package:native_toolchain_c`. It compiles `ace_core.c`, `keyboard.c` and `z80.c` (listed explicitly; the op files are `#include`d). If you add a C file, add it there **and** check the Makefile's `CORE_SOURCES`. The same hook builds for the host, so `flutter test` loads the real core. It is verified to build for the iOS simulator and for Android arm64-v8a, armeabi-v7a and x86_64.
- The framebuffer is a stable native pointer (256×192×4 RGBA). Wrap it as `Uint8List` with `asTypedList` without copying, and copy into a `ui.Image` only on frames flagged dirty.
- Calls are synchronous and cheap (one frame is well under 1 ms). Don't call from multiple isolates at once unless the core is made thread-safe.
- Tests: `test/core/ace_machine_test.dart` runs on the host through `flutter test`. `integration_test/ace_core_test.dart` checks that the asset loads on a real target: `make integration-test DEVICE=<id>`. It passed on the iPad Pro 13" simulator and an Android API 35 emulator.
- `AceMachine.spool` takes Unicode. `toAceCodes` converts £/© to 0x60/0x7F, turns CR/LF into Enter, and drops characters the ACE can't type.
- Tape I/O doesn't use callbacks into Dart. `ace_run_frame` returns a flag, Dart reads the request with `ace_tape_pending`, and answers with `ace_tape_supply`.
