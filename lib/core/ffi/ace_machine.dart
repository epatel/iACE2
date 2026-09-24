import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ace_bindings.g.dart' as native;

/// What a tape holds: a FORTH dictionary (`.dic`) or a block of memory (`.byt`).
enum TapeKind {
  dict('dic'),
  bytes('byt');

  const TapeKind(this.extension);

  final String extension;

  static TapeKind fromNative(int value) =>
      value == native.ace_tape_kind.ACE_TAPE_BYTES.value ? bytes : dict;
}

/// A tape the ROM asked for with `LOAD` / `BLOAD`.
typedef TapeRequest = ({String name, TapeKind kind});

/// A tape the ROM wrote with `SAVE` / `BSAVE`. [data] is in `.TAP` block layout.
typedef SavedTape = ({String name, TapeKind kind, Uint8List data});

/// Flags returned by [AceMachine.runFrame].
abstract final class FrameFlags {
  static const screenDirty = native.ACE_FRAME_SCREEN_DIRTY;
  static const tapeLoad = native.ACE_FRAME_TAPE_LOAD;
  static const tapeSaved = native.ACE_FRAME_TAPE_SAVED;
}

/// Special character codes accepted by [AceMachine.keyChar] (see cards/keyboard-matrix.md).
abstract final class AceChars {
  static const deleteLine = 0x01;
  static const inverseVideo = 0x02;
  static const graphics = 0x03;
  static const left = 0x04;
  static const down = 0x05;
  static const up = 0x06;
  static const right = 0x07;
  static const delete = 0x08;
  static const enter = 0x0a;
  static const breakKey = 0x1b;
  static const pound = 0x60;
  static const copyright = 0x7f;
}

final _destroyer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<native.ace_machine>)>>(
    native.ace_destroy,
  ).cast(),
);

/// A Jupiter ACE, backed by the C core in `native/`.
///
/// This is the only class that touches `dart:ffi` types; features use it
/// instead of the generated bindings.
class AceMachine implements Finalizable {
  AceMachine(Uint8List rom) : _machine = _create(rom) {
    _destroyer.attach(this, _machine.cast(), detach: this);
    _framebuffer = native
        .ace_framebuffer(_machine)
        .asTypedList(width * height * 4);
  }

  static const width = native.ACE_SCREEN_WIDTH;
  static const height = native.ACE_SCREEN_HEIGHT;
  static const framesPerSecond = 50;

  static Pointer<native.ace_machine> _create(Uint8List rom) {
    final buffer = malloc<Uint8>(rom.length);
    try {
      buffer.asTypedList(rom.length).setAll(0, rom);
      final machine = native.ace_create(buffer, rom.length);
      if (machine == nullptr) {
        throw ArgumentError('Not a Jupiter ACE ROM (${rom.length} bytes)');
      }
      return machine;
    } finally {
      malloc.free(buffer);
    }
  }

  final Pointer<native.ace_machine> _machine;
  late final Uint8List _framebuffer;
  bool _disposed = false;

  Pointer<native.ace_machine> get _m {
    if (_disposed) throw StateError('AceMachine used after dispose');
    return _machine;
  }

  /// Frees the native machine now instead of waiting for garbage collection.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroyer.detach(this);
    native.ace_destroy(_machine);
  }

  void reset() => native.ace_reset(_m);

  /// Runs one 20 ms frame and returns [FrameFlags].
  int runFrame() => native.ace_run_frame(_m);

  /// The screen as RGBA pixels, [width] x [height]. A live view of native
  /// memory: it changes on [runFrame] and must not be used after [dispose].
  Uint8List get framebuffer {
    _m;
    return _framebuffer;
  }

  // Keyboard

  /// Presses or releases keys on the raw matrix (port 0..7, bit mask).
  void key(int port, int mask, {required bool down}) =>
      native.ace_key(_m, port, mask, down ? 1 : 0);

  /// Presses or releases the keys for an ACE character code (see [AceChars]).
  void keyChar(int aceChar, {required bool down}) =>
      native.ace_key_char(_m, aceChar, down ? 1 : 0);

  void releaseAllKeys() => native.ace_key_release_all(_m);

  // Spooler

  /// Types [text] into the machine, one key at a time. `\n` is Enter.
  void spool(String text) {
    final codes = toAceCodes(text);
    if (codes.isEmpty) return;
    final buffer = malloc<Uint8>(codes.length + 1);
    try {
      buffer.asTypedList(codes.length + 1)
        ..setAll(0, codes)
        ..[codes.length] = 0;
      native.ace_spool(_m, buffer.cast());
    } finally {
      malloc.free(buffer);
    }
  }

  void cancelSpool() => native.ace_spool_cancel(_m);

  bool get isSpooling => native.ace_spool_active(_m) != 0;

  /// Converts text to ACE character codes: `£` and `©` move to their ACE
  /// positions, `\r\n` becomes Enter, and characters the ACE lacks are dropped.
  static List<int> toAceCodes(String text) {
    final codes = <int>[];
    for (final rune in text.replaceAll('\r\n', '\n').runes) {
      switch (rune) {
        case 0x0a || 0x0d:
          codes.add(AceChars.enter);
        case 0xa3: // £
          codes.add(AceChars.pound);
        case 0xa9: // ©
          codes.add(AceChars.copyright);
        case 0x60: // ` has no key on the ACE
          break;
        case >= 0x20 && < 0x7f:
          codes.add(rune);
      }
    }
    return codes;
  }

  // Tapes

  /// The tape the ROM is waiting for, if any. Answer with [supplyTape].
  TapeRequest? tapeRequest() {
    return using((arena) {
      final name = arena<Char>(native.ACE_TAPE_NAME_MAX + 1);
      final kind = arena<Int>();
      if (native.ace_tape_request(
            _m,
            name,
            native.ACE_TAPE_NAME_MAX + 1,
            kind,
          ) ==
          0) {
        return null;
      }
      return (
        name: _latin1(name.cast<Uint8>()),
        kind: TapeKind.fromNative(kind.value),
      );
    });
  }

  /// Answers a [tapeRequest]. `null` (or a malformed tape) loads the
  /// "Couldn't load your file!" stub instead.
  void supplyTape(Uint8List? tape) {
    if (tape == null || tape.isEmpty) {
      native.ace_tape_supply(_m, nullptr, 0);
      return;
    }
    final buffer = malloc<Uint8>(tape.length);
    try {
      buffer.asTypedList(tape.length).setAll(0, tape);
      native.ace_tape_supply(_m, buffer, tape.length);
    } finally {
      malloc.free(buffer);
    }
  }

  /// The tape saved during the last frame, if [FrameFlags.tapeSaved] was set.
  SavedTape? savedTape() {
    return using((arena) {
      final name = arena<Char>(native.ACE_TAPE_NAME_MAX + 1);
      final kind = arena<Int>();
      final data = arena<Pointer<Uint8>>();
      final length = native.ace_tape_saved(
        _m,
        name,
        native.ACE_TAPE_NAME_MAX + 1,
        kind,
        data,
      );
      if (length == 0) return null;
      return (
        name: _latin1(name.cast<Uint8>()),
        kind: TapeKind.fromNative(kind.value),
        data: Uint8List.fromList(data.value.asTypedList(length)),
      );
    });
  }

  // Snapshots

  /// The whole machine state in the versioned snapshot format, or `null`
  /// while a tape transfer is half done.
  Uint8List? saveSnapshot() {
    final size = native.ace_snapshot_size();
    final buffer = malloc<Uint8>(size);
    try {
      final written = native.ace_snapshot_save(_m, buffer, size);
      if (written == 0) return null;
      return Uint8List.fromList(buffer.asTypedList(written));
    } finally {
      malloc.free(buffer);
    }
  }

  /// Restores a snapshot. Returns false, leaving the machine unchanged, if
  /// the data is not a snapshot this version understands.
  bool loadSnapshot(Uint8List snapshot) {
    if (snapshot.isEmpty) return false;
    final buffer = malloc<Uint8>(snapshot.length);
    try {
      buffer.asTypedList(snapshot.length).setAll(0, snapshot);
      return native.ace_snapshot_load(_m, buffer, snapshot.length) != 0;
    } finally {
      malloc.free(buffer);
    }
  }

  // Memory and sound

  int peek(int address) => native.ace_peek(_m, address & 0xffff);

  void poke(int address, int value) =>
      native.ace_poke(_m, address & 0xffff, value & 0xff);

  /// Opens the audio device and plays the beeper. Returns false if no audio
  /// device could be opened (the machine keeps running silently).
  bool startAudio() => native.ace_audio_start(_m) != 0;

  void stopAudio() => native.ace_audio_stop(_m);

  /// Beeper volume, 0..1.
  set volume(double value) =>
      native.ace_audio_set_volume(_m, value.clamp(0.0, 1.0));

  /// Speaker level changes during the last frame, as `(tstate << 1) | level`.
  Uint32List beeperEvents() {
    return using((arena) {
      final events = arena<Pointer<Uint32>>();
      final count = native.ace_beeper_events(_m, events);
      if (count == 0) return Uint32List(0);
      return Uint32List.fromList(events.value.asTypedList(count));
    });
  }

  /// The screen as text: 24 lines of 32 characters, inverse video ignored and
  /// non-printable characters shown as `.`.
  String screenText() {
    final lines = <String>[];
    for (var y = 0; y < 24; y++) {
      final line = StringBuffer();
      for (var x = 0; x < 32; x++) {
        final ch = peek(0x2400 + y * 32 + x) & 0x7f;
        line.writeCharCode(ch >= 0x20 && ch < 0x7f ? ch : 0x2e);
      }
      lines.add(line.toString());
    }
    return lines.join('\n');
  }

  static String _latin1(Pointer<Uint8> text) {
    final codes = <int>[];
    for (var i = 0; text[i] != 0; i++) {
      codes.add(text[i]);
    }
    return String.fromCharCodes(codes);
  }
}
