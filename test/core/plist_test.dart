import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/plist/plist.dart';

void main() {
  for (final format in ['xml', 'binary']) {
    test('reads a $format plist', () {
      final plist = parsePlist(
        File('test/fixtures/plist/sample.$format.plist').readAsBytesSync(),
      ) as Map<String, Object?>;
      expect(plist['name'], 'ACE');
      expect(plist['count'], 42);
      expect(plist['big'], 1 << 40);
      expect(plist['negative'], -5);
      expect(plist['ratio'], 1.5);
      expect(plist['on'], isTrue);
      expect(plist['off'], isFalse);
      expect(plist['blob'], Uint8List.fromList([0, 1, 255]));
      expect(plist['list'], [
        1,
        'two',
        [3],
      ]);
      expect(plist['unicode'], 'Jüpiter © ACE');
      expect(plist['nested'], {'a': 1});
    });
  }

  test('rejects garbage', () {
    expect(
      () => parsePlist(Uint8List.fromList('bplist00 nope'.codeUnits)),
      throwsA(isA<PlistFormatException>()),
    );
    final truncated = File('test/fixtures/plist/sample.binary.plist')
        .readAsBytesSync()
        .sublist(0, 60);
    expect(() => parsePlist(truncated), throwsA(anything));
  });
}
