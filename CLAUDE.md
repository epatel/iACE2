# iACE2

Flutter rebuild of iACE, the Jupiter ACE emulator with its bundled user manual. It targets iOS and Android **tablets and phones**, in **portrait only**. Phones get `PhoneHome`, which has no manual. The Z80 emulation is C, called through `dart:ffi`. The original Objective-C app is https://github.com/epatel/iACE. A local copy may sit in `archive/iACE`, which is git-ignored and never committed; treat it as a read-only reference. The `tool/` converters read from it.

The shared objective and phase list are in `project-plan.md`. Check which phase you are in before starting work, and update the plan when a phase finishes or a decision changes.

## Standing defaults
- **Use the Makefile.** Run `make help` for targets. Use `make test`, `make analyze`, `make format` and `make gen` rather than ad-hoc commands, so humans and agents share entry points. If you add a workflow, add a target.
- **Every persisted format has a version and a migration path.** This covers the drift DB, the snapshot binary and anything added later. Never edit an existing migration step; add a new one and test the upgrade from every older version.
- **App identity is fixed.** iOS `com.memention.iACE`, Android `com.memention.iace`. The app ships as version 2.x, an update to the App Store iACE 1.2.
- State management uses plain `provider` + `ChangeNotifier`. Don't add Riverpod, Bloc or similar.
- The code is GPL v2+ (it inherits from xz80/xAce). Keep license headers on the C files.
- Code layout is feature-first: `lib/features/<feature>/`, with shared infrastructure in `lib/core/`.

## When to read a card
- When touching `native/`, the Z80 core, memory map, ROM patches, ports or timing → read `cards/emulator-core.md`
- When changing `ace_api.h`, ffigen, `hook/build.dart` or the Dart `AceMachine` wrapper → read `cards/ffi-bridge.md`
- When adding or changing a DB table, a setting, the snapshot format or legacy import → read `cards/persistence-migrations.md`
- When working on the manual viewer or `annotations.json` → read `cards/manual-annotations.md`
- When working on keyboard input, the key map or the spooler → read `cards/keyboard-matrix.md`
- When working on the drawers, the settings lid, the layout or the app icon → read `project-plan.md` §3 and the doc comments in `lib/features/shell/drawer_controller.dart` (the iACE 1.x drawer rules, in 768-unit coordinates)
