# FFI bridge

- `native/include/ace_api.h` is the **only** header ffigen reads. Keep it plain C: an opaque `ace_machine*`, fixed-width ints, and no macros that ffigen can't parse.
- Bindings are generated with `make ffigen` (config in `ffigen.yaml`) into `lib/core/ffi/ace_bindings.g.dart`. Never hand-edit generated files.
- `lib/core/ffi/ace_machine.dart` wraps the bindings. It owns the pointer and attaches a `NativeFinalizer` that calls `ace_destroy`. Only this class touches `dart:ffi` types; features use the wrapper.
- The native build is `hook/build.dart` using `package:native_toolchain_c`, which compiles `native/src/*.c` except the `#include`d op files. The same hook builds for the host, so `flutter test` loads the real core.
- The framebuffer is a stable native pointer (256×192×4 RGBA). Wrap it as `Uint8List` with `asTypedList` without copying, and copy into a `ui.Image` only on frames flagged dirty.
- Calls are synchronous and cheap (one frame is well under 1 ms). Don't call from multiple isolates at once unless the core is made thread-safe.
- Tape I/O doesn't use callbacks into Dart. `ace_run_frame` returns a flag, Dart reads the request with `ace_tape_pending`, and answers with `ace_tape_supply`.
