import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/ffi/ace_machine.dart';

final rom = File('assets/ace.rom').readAsBytesSync();

AceMachine boot() {
  final machine = AceMachine(rom);
  for (var i = 0; i < 100; i++) {
    machine.runFrame();
  }
  return machine;
}

/// Types [text] and runs until the machine has settled, answering tape
/// requests from [tapes] and collecting saved tapes into it.
void type(AceMachine machine, String text, [Map<String, Uint8List>? tapes]) {
  machine.spool(text);
  for (var i = 0; i < 3000 && machine.isSpooling; i++) {
    final flags = machine.runFrame();
    if (flags & FrameFlags.tapeLoad != 0) {
      final request = machine.tapeRequest()!;
      machine.supplyTape(tapes?['${request.name}.${request.kind.extension}']);
    }
    if (flags & FrameFlags.tapeSaved != 0) {
      final saved = machine.savedTape()!;
      tapes?['${saved.name}.${saved.kind.extension}'] = saved.data;
    }
  }
  expect(machine.isSpooling, isFalse, reason: 'spooler did not finish');
  for (var i = 0; i < 25; i++) {
    machine.runFrame();
  }
}

void main() {
  test('rejects a ROM of the wrong size', () {
    expect(() => AceMachine(Uint8List(100)), throwsArgumentError);
  });

  test('boots and does arithmetic', () {
    final machine = boot();
    type(machine, '2 2 + .\n');
    expect(machine.screenText(), contains('2 2 + . 4  OK'));
    machine.dispose();
  });

  test('framebuffer is RGBA and changes with the screen', () {
    final machine = boot();
    expect(
      machine.framebuffer.length,
      AceMachine.width * AceMachine.height * 4,
    );
    expect(machine.runFrame() & FrameFlags.screenDirty, 0);
    machine.poke(0x2400, 0x80 | 0x20); // inverse space, top left
    expect(machine.runFrame() & FrameFlags.screenDirty, isNot(0));
    expect(machine.framebuffer.sublist(0, 4), [255, 255, 255, 255]);
    machine.dispose();
  });

  test('converts text to ACE character codes', () {
    expect(AceMachine.toAceCodes('a£©\r\nb`é'), [0x61, 0x60, 0x7f, 0x0a, 0x62]);
  });

  test('saves and loads a tape', () {
    final tapes = <String, Uint8List>{};
    final first = boot();
    type(first, ': SQ DUP * ;\n');
    type(first, 'SAVE squares\n', tapes);
    expect(tapes.keys, ['squares.dic']);
    first.dispose();

    final second = boot();
    type(second, 'LOAD squares\n', tapes);
    type(second, '6 SQ .\n');
    expect(second.screenText(), contains('6 SQ . 36  OK'));
    second.dispose();
  });

  test('missing tape loads the stub and the machine stays usable', () {
    final machine = boot();
    type(machine, 'LOAD nothing\n', {});
    type(machine, '3 4 * .\n');
    expect(machine.screenText(), contains('3 4 * . 12  OK'));
    machine.dispose();
  });

  test('loads the bundled Frogger tape', () {
    final machine = boot();
    type(machine, 'LOAD frogger\n', {
      'frogger.dic': File('assets/tapes/frogger.dic').readAsBytesSync(),
    });
    expect(machine.screenText(), contains('Dict: frogger'));
    type(machine, 'VLIST\n');
    expect(machine.screenText(), contains('P R E S E N T S'));
    machine.dispose();
  });

  test('snapshot round trip', () {
    final original = boot();
    type(original, ': CUBE DUP DUP * * ;\n');
    final snapshot = original.saveSnapshot()!;
    original.dispose();

    final restored = AceMachine(rom);
    expect(restored.loadSnapshot(snapshot), isTrue);
    type(restored, '3 CUBE .\n');
    expect(restored.screenText(), contains('3 CUBE . 27  OK'));

    expect(restored.loadSnapshot(Uint8List(10)), isFalse);
    restored.dispose();
  });

  test('beeper produces events', () {
    final machine = boot();
    machine.spool('100 200 BEEP\n');
    var maxEvents = 0;
    for (var i = 0; i < 400; i++) {
      machine.runFrame();
      final count = machine.beeperEvents().length;
      if (count > maxEvents) maxEvents = count;
    }
    expect(maxEvents, greaterThan(20));
    machine.dispose();
  });

  test('use after dispose throws', () {
    final machine = AceMachine(rom)..dispose();
    expect(machine.runFrame, throwsStateError);
    machine.dispose(); // idempotent
  });
}
