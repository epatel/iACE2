import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/db/app_database.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/emulator/screen_view.dart';
import 'package:iace/features/settings/about.dart';
import 'package:iace/features/tapes/db_tape_library.dart';
import 'package:iace/features/tapes/tap_format.dart';
import 'package:iace/features/tapes/tape_browser.dart';
import 'package:iace/features/tapes/tape_library.dart';
import 'package:provider/provider.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final frogger = File('assets/tapes/frogger.dic').readAsBytesSync();

/// Runs [text] on a fresh machine and returns the tapes it saved.
Map<String, Uint8List> saveOnAce(String text) {
  final tapes = <String, Uint8List>{};
  final m = AceMachine(rom);
  for (var i = 0; i < 100; i++) {
    m.runFrame();
  }
  m.spool(text);
  // Keep going a little after the typing ends: the last command still runs.
  for (var i = 0, idle = 0; i < 3000 && idle < 50; i++) {
    if (!m.isSpooling) idle++;
    if (m.runFrame() & FrameFlags.tapeSaved != 0) {
      final saved = m.savedTape()!;
      tapes['${saved.name}.${saved.kind.extension}'] = saved.data;
    }
  }
  m.dispose();
  return tapes;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('.TAP format', () {
    test('a stored tape is a one-file .TAP', () {
      final files = TapFormat.parse(frogger);
      expect(files.single.name, 'frogger');
      expect(files.single.kind, TapeKind.dict);
      expect(files.single.data, frogger);
    });

    test('dictionaries and bytes from the ACE, joined into one file', () {
      final saved = saveOnAce(': ONE 1 ;\nSAVE one\n16384 32 BSAVE blob\n');
      expect(saved.keys, unorderedEquals(['one.dic', 'blob.byt']));
      final tap = TapFormat.build([saved['one.dic']!, saved['blob.byt']!]);
      final files = TapFormat.parse(tap);
      expect(files.map((f) => '${f.name}.${f.kind.extension}'), [
        'one.dic',
        'blob.byt',
      ]);
      expect(files[1].data, saved['blob.byt']);
    });

    test('rejects what is not a .TAP', () {
      expect(() => TapFormat.parse(Uint8List(0)), throwsFormatException);
      expect(
        () => TapFormat.parse(frogger.sublist(0, 100)),
        throwsFormatException,
      );
      final wrongHeader = Uint8List.fromList([3, 0, 1, 2, 3, 1, 0, 9]);
      expect(() => TapFormat.parse(wrongHeader), throwsFormatException);
    });
  });

  test('importing a .TAP stores every file and LOAD finds it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final library = DbTapeLibrary(db);
    final saved = saveOnAce(': SEVEN 7 ;\nSAVE seven\n');
    final names = await library.importTap(
      TapFormat.build([frogger, saved['seven.dic']!]),
    );
    expect(names, ['frogger.dic', 'seven.dic']);
    expect(await library.sourceOf('seven', 'dic'), TapeSource.import);

    final c = EmulatorController(machine: AceMachine(rom), tapes: library);
    for (var i = 0; i < 100; i++) {
      c.runFrame();
    }
    for (final line in ['LOAD seven\n', 'SEVEN .\n']) {
      c.type(line);
      for (var i = 0; i < 3000 && c.machine.isSpooling; i++) {
        c.runFrame();
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 25; i++) {
        c.runFrame();
      }
    }
    expect(c.machine.screenText(), contains('SEVEN . 7  OK'));
    c.dispose();
    await db.close();
  });

  testWidgets('tape browser lists, loads and deletes tapes', (tester) async {
    final db = AppDatabase(
      NativeDatabase.memory(),
      seedTapes: {'frogger.dic': frogger},
    );
    final library = DbTapeLibrary(db);
    await library.put('blob', 'byt', Uint8List(40), TapeSource.user);
    final controller = EmulatorController(
      machine: AceMachine(rom),
      tapes: InMemoryTapeLibrary(),
    );
    var loaded = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => TapeBrowser.show(
                context,
                tapes: library,
                onLoad: () => loaded = true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('frogger'), findsOneWidget);
    expect(find.text('blob'), findsOneWidget);
    expect(find.text('LOAD'), findsOneWidget, reason: 'only dictionaries');

    // Delete asks first.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tape-blob.byt')),
        matching: find.byTooltip('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(); // the dialog closes, the delete starts
    for (var i = 0; i < 5; i++) {
      // The delete, then the reload: both real database calls.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('blob'), findsNothing);

    await tester.tap(find.text('LOAD'));
    await tester.pumpAndSettle();
    expect(loaded, isTrue);
    expect(controller.machine.isSpooling, isTrue);
    expect(find.text('Tapes'), findsNothing, reason: 'sheet closed');

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(db.close);
  });

  testWidgets('licences include the GPL text and bundled parts', (
    tester,
  ) async {
    registerLicenses();
    final entries = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    final packages = entries!.expand((e) => e.packages).toSet();
    expect(packages, containsAll(['iACE', 'xz80', 'miniaudio']));
    final gpl = entries.firstWhere((e) => e.packages.contains('iACE'));
    expect(
      gpl.paragraphs.map((p) => p.text).join(' '),
      contains('GNU GENERAL PUBLIC LICENSE'),
    );
  });

  testWidgets('the screen reads out as text', (tester) async {
    final controller = EmulatorController(
      machine: AceMachine(rom),
      tapes: InMemoryTapeLibrary(),
    );
    for (var i = 0; i < 100; i++) {
      controller.runFrame();
    }
    controller.type('2 2 + .\n');
    for (var i = 0; i < 300 && controller.machine.isSpooling; i++) {
      controller.runFrame();
    }
    for (var i = 0; i < 25; i++) {
      controller.runFrame();
    }
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ScreenView()),
      ),
    );
    expect(tester.getSemantics(find.byType(ScreenView).last), isA<Object>());
    expect(find.bySemanticsLabel('Jupiter ACE screen'), findsOneWidget);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Jupiter ACE screen'),
    );
    expect(node.value, contains('2 2 + . 4  OK'));
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
