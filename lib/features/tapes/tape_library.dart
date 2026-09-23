import 'package:flutter/services.dart';

import '../../core/ffi/ace_machine.dart';

/// Where the emulator's `LOAD` and `SAVE` go. Tapes are in `.TAP` block layout.
abstract interface class TapeLibrary {
  /// The tape called [name], or `null` if there is none.
  Future<Uint8List?> load(String name, TapeKind kind);

  Future<void> save(String name, TapeKind kind, Uint8List data);
}

/// Keeps tapes in memory. Used by tests; the app uses DbTapeLibrary.
class InMemoryTapeLibrary implements TapeLibrary {
  InMemoryTapeLibrary([Map<String, Uint8List>? tapes]) : _tapes = {...?tapes};

  static Future<InMemoryTapeLibrary> withBundledTapes(
    AssetBundle bundle,
  ) async {
    final frogger = await bundle.load('assets/tapes/frogger.dic');
    return InMemoryTapeLibrary({'frogger.dic': frogger.buffer.asUint8List()});
  }

  final Map<String, Uint8List> _tapes;

  static String _key(String name, TapeKind kind) => '$name.${kind.extension}';

  @override
  Future<Uint8List?> load(String name, TapeKind kind) async =>
      _tapes[_key(name, kind)];

  @override
  Future<void> save(String name, TapeKind kind, Uint8List data) async {
    _tapes[_key(name, kind)] = data;
  }
}
