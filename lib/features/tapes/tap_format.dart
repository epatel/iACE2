import 'dart:typed_data';

import '../../core/ffi/ace_machine.dart';

/// One file on a `.TAP` tape: a header block and a data block.
typedef TapFile = ({String name, TapeKind kind, Uint8List data});

/// `.TAP` files, as used by Jupiter ACE emulators: a sequence of blocks, each
/// `[u16 little-endian length][length bytes]`, in header/data pairs. A header
/// block is 26 bytes: type (0 = dictionary, otherwise bytes), a 10-character
/// space-padded name, parameters, and a checksum.
///
/// A tape stored by this app is exactly one such pair, so a single file is
/// also a valid `.TAP`.
abstract final class TapFormat {
  static const headerLength = 26;

  /// Splits a `.TAP` into its files. Throws [FormatException] if the data is
  /// not a sequence of header/data pairs.
  static List<TapFile> parse(Uint8List tap) {
    final files = <TapFile>[];
    var pos = 0;
    (int, int) block() {
      if (pos + 2 > tap.length) {
        throw FormatException('truncated block length', tap, pos);
      }
      final length = tap[pos] | (tap[pos + 1] << 8);
      final start = pos + 2;
      if (length < 1 || start + length > tap.length) {
        throw FormatException('truncated block', tap, pos);
      }
      pos = start + length;
      return (start, length);
    }

    while (pos < tap.length) {
      final begin = pos;
      final (headerStart, headerLength) = block();
      if (headerLength != TapFormat.headerLength) {
        throw FormatException('expected a 26-byte header', tap, begin);
      }
      block();
      final name = String.fromCharCodes(
        tap.sublist(headerStart + 1, headerStart + 11),
      ).trimRight();
      if (name.isEmpty || name.codeUnits.any((c) => c < 0x21 || c > 0x7e)) {
        throw FormatException('bad file name', tap, headerStart + 1);
      }
      files.add((
        name: name,
        kind: tap[headerStart] == 0 ? TapeKind.dict : TapeKind.bytes,
        data: Uint8List.sublistView(tap, begin, pos),
      ));
    }
    if (files.isEmpty) throw const FormatException('empty tape');
    return files;
  }

  /// Joins tapes into one `.TAP`.
  static Uint8List build(Iterable<Uint8List> tapes) {
    final out = BytesBuilder(copy: false);
    tapes.forEach(out.add);
    return out.toBytes();
  }
}
