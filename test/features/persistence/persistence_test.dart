import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/db/app_database.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/emulator/session_autosave.dart';
import 'package:iace/features/emulator/snapshot_store.dart';
import 'package:iace/features/legacy/legacy_import.dart';
import 'package:iace/features/settings/settings_repository.dart';
import 'package:iace/features/tapes/db_tape_library.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final frogger = File('assets/tapes/frogger.dic').readAsBytesSync();

AppDatabase memoryDb({Map<String, Uint8List> seed = const {}}) =>
    AppDatabase(NativeDatabase.memory(), seedTapes: seed);

void runFrames(EmulatorController c, int n) {
  for (var i = 0; i < n; i++) {
    c.runFrame();
  }
}

/// Types into [c] and waits for tape futures, like the running app.
Future<void> typeAndSettle(EmulatorController c, String text) async {
  c.type(text);
  for (var i = 0; i < 3000 && c.machine.isSpooling; i++) {
    c.runFrame();
    await Future<void>.delayed(Duration.zero);
  }
  for (var i = 0; i < 25; i++) {
    c.runFrame();
    await Future<void>.delayed(Duration.zero);
  }
}

EmulatorController booted(DbTapeLibrary tapes) {
  final c = EmulatorController(machine: AceMachine(rom), tapes: tapes);
  runFrames(c, 100);
  return c;
}

/// An XML plist dictionary of tapes, as iACE 1.x's NSDictionary wrote it.
String tapesPlist(Map<String, Uint8List> tapes) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${tapes.entries.map((e) => '\t<key>${e.key}</key>\n\t<data>\n\t${base64.encode(e.value)}\n\t</data>').join('\n')}
</dict>
</plist>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('database', () {
    test('seeds bundled tapes once, on creation', () async {
      final db = memoryDb(seed: {'frogger.dic': frogger});
      final tapes = DbTapeLibrary(db);
      final rows = await tapes.all();
      expect(rows.map((t) => '${t.name}.${t.kind}'), ['frogger.dic']);
      expect(rows.single.source, 'seed');
      expect(rows.single.data, frogger);
      await db.close();
    });

    test('settings store typed values', () async {
      final db = memoryDb();
      final settings = SettingsRepository(db);
      expect(await settings.getInt(SettingsRepository.lastPage), isNull);
      await settings.setInt(SettingsRepository.lastPage, 12);
      await settings.setInt(SettingsRepository.lastPage, 13);
      await settings.setBool(SettingsRepository.stickyShift, true);
      expect(await settings.getInt(SettingsRepository.lastPage), 13);
      expect(await settings.getBool(SettingsRepository.stickyShift), isTrue);
      expect(await settings.getBool(SettingsRepository.lastPage), isNull);
      await settings.setDouble(SettingsRepository.volume, 0.25);
      expect(await settings.getDouble(SettingsRepository.volume), 0.25);
      await db.close();
    });

    test('file database keeps data between opens', () async {
      final dir = await Directory.systemTemp.createTemp('iace_db');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/iace.sqlite');

      final first = AppDatabase(
        NativeDatabase(file),
        seedTapes: {'frogger.dic': frogger},
      );
      await SettingsRepository(first).setInt(SettingsRepository.lastPage, 7);
      await first.close();

      final second = AppDatabase(
        NativeDatabase(file),
        seedTapes: {'other.dic': frogger},
      );
      expect(
        await SettingsRepository(second).getInt(SettingsRepository.lastPage),
        7,
      );
      // Seeding only happens when the database is created.
      expect((await DbTapeLibrary(second).all()).map((t) => t.name), [
        'frogger',
      ]);
      await second.close();
    });
  });

  group('tapes', () {
    test('SAVE and LOAD go through the database', () async {
      final db = memoryDb(seed: {'frogger.dic': frogger});
      final tapes = DbTapeLibrary(db);

      final first = booted(tapes);
      await typeAndSettle(first, ': HALF 2 / ;\n');
      await typeAndSettle(first, 'SAVE half\n');
      first.dispose();
      expect(await tapes.sourceOf('half', 'dic'), TapeSource.user);

      final second = booted(tapes);
      await typeAndSettle(second, 'LOAD half\n');
      await typeAndSettle(second, '84 HALF .\n');
      expect(second.machine.screenText(), contains('84 HALF . 42  OK'));
      await typeAndSettle(second, 'LOAD frogger\n');
      expect(second.machine.screenText(), contains('Dict: frogger'));
      second.dispose();
      await db.close();
    });

    test('saving again replaces the tape', () async {
      final db = memoryDb();
      final tapes = DbTapeLibrary(db);
      await tapes.put('x', 'byt', Uint8List.fromList([1]), TapeSource.user);
      await tapes.put('x', 'byt', Uint8List.fromList([2]), TapeSource.user);
      final rows = await tapes.all();
      expect(rows, hasLength(1));
      expect(rows.single.data, [2]);
      await db.close();
    });
  });

  group('session autosave', () {
    test('restores the session in a new machine', () async {
      final db = memoryDb();
      final store = SnapshotStore(db);
      final tapes = DbTapeLibrary(db);

      final first = booted(tapes);
      await typeAndSettle(first, ': TRIPLE 3 * ;\n');
      final autosave = SessionAutosave(controller: first, store: store);
      await autosave.save();
      autosave.dispose();
      first.dispose();

      final row = await db.select(db.snapshots).getSingle();
      expect(row.formatVersion, 1);

      final second = EmulatorController(machine: AceMachine(rom), tapes: tapes);
      final restored = SessionAutosave(controller: second, store: store);
      expect(await restored.restore(), isTrue);
      await typeAndSettle(second, '5 TRIPLE .\n');
      expect(second.machine.screenText(), contains('5 TRIPLE . 15  OK'));
      restored.dispose();
      second.dispose();
      await db.close();
    });

    test('an unreadable snapshot is dropped and the machine boots', () async {
      final db = memoryDb();
      final store = SnapshotStore(db);
      await store.save(Uint8List.fromList(utf8.encode('ACE2SNAP?? broken')));
      final c = EmulatorController(
        machine: AceMachine(rom),
        tapes: DbTapeLibrary(db),
      );
      final autosave = SessionAutosave(controller: c, store: store);
      expect(await autosave.restore(), isFalse);
      expect(await store.load(), isNull);
      runFrames(c, 100);
      await typeAndSettle(c, '1 1 + .\n');
      expect(c.machine.screenText(), contains('1 1 + . 2  OK'));
      autosave.dispose();
      c.dispose();
      await db.close();
    });
  });

  group('legacy import from iACE 1.x', () {
    late Directory home;
    late AppDatabase db;
    late DbTapeLibrary tapes;
    late SettingsRepository settings;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('iace_legacy');
      await Directory('${home.path}/Documents').create();
      await Directory('${home.path}/Library/Preferences')
          .create(recursive: true);
      db = memoryDb(seed: {'frogger.dic': frogger});
      tapes = DbTapeLibrary(db);
      settings = SettingsRepository(db);
    });

    tearDown(() async {
      await db.close();
      await home.delete(recursive: true);
    });

    LegacyImporter importer() => LegacyImporter(
      tapes: tapes,
      settings: settings,
      documentsDir: Directory('${home.path}/Documents'),
      preferencesFile: File(
        '${home.path}/Library/${LegacyImporter.preferencesPath}',
      ),
    );

    test('imports tapes and preferences once', () async {
      // A tape saved by the ACE, as iACE 1.x stored it.
      final maker = booted(tapes);
      await typeAndSettle(maker, ': OLD 1000 + ;\n');
      await typeAndSettle(maker, 'SAVE old\n');
      maker.dispose();
      final oldTape = (await tapes.load('old', TapeKind.dict))!;
      await (db.delete(db.tapes)..where((t) => t.name.equals('old'))).go();

      File('${home.path}/Documents/tapes.dic').writeAsStringSync(
        tapesPlist({
          'old.dic': oldTape,
          'frogger.dic': frogger,
          'weird': Uint8List(3),
        }),
      );
      File('test/fixtures/legacy/com.memention.iACE.plist')
          .copySync('${home.path}/Library/${LegacyImporter.preferencesPath}');

      final result = await importer().run();
      expect(result.ran, isTrue);
      expect(result.errors, isEmpty);
      expect(result.tapes, 2);
      expect(await tapes.sourceOf('old', 'dic'), TapeSource.legacy);
      expect(await tapes.sourceOf('frogger', 'dic'), TapeSource.legacy);
      expect(await settings.getInt(SettingsRepository.lastPage), 57);
      expect(await settings.getBool(SettingsRepository.stickyShift), isTrue);
      expect(
        await settings.getBool(SettingsRepository.revealHintShown),
        isTrue,
      );

      // The imported tape works.
      final c = booted(tapes);
      await typeAndSettle(c, 'LOAD old\n');
      await typeAndSettle(c, '24 OLD .\n');
      expect(c.machine.screenText(), contains('24 OLD . 1024  OK'));
      c.dispose();

      // Second launch: nothing happens.
      expect((await importer().run()).ran, isFalse);
    });

    test('keeps tapes and settings the user already has', () async {
      await tapes.put('mine', 'dic', Uint8List.fromList([9]), TapeSource.user);
      await settings.setInt(SettingsRepository.lastPage, 3);
      File('${home.path}/Documents/tapes.dic').writeAsStringSync(
        tapesPlist({
          'mine.dic': Uint8List.fromList([1]),
        }),
      );
      File('test/fixtures/legacy/com.memention.iACE.plist')
          .copySync('${home.path}/Library/${LegacyImporter.preferencesPath}');

      final result = await importer().run();
      expect(result.tapes, 0);
      expect(await tapes.load('mine', TapeKind.dict), [9]);
      expect(await settings.getInt(SettingsRepository.lastPage), 3);
    });

    test('no old files: marks done, imports nothing', () async {
      final result = await importer().run();
      expect(result.ran, isTrue);
      expect(result.tapes, 0);
      expect(result.settings, isEmpty);
      expect(result.errors, isEmpty);
      expect(
        await settings.getBool(SettingsRepository.legacyImportDone),
        isTrue,
      );
    });

    test('broken old files are reported, not fatal', () async {
      File('${home.path}/Documents/tapes.dic').writeAsStringSync('garbage');
      File('${home.path}/Library/${LegacyImporter.preferencesPath}')
          .writeAsBytesSync(utf8.encode('bplist00 broken'));
      final result = await importer().run();
      expect(result.errors, hasLength(2));
      expect(
        await settings.getBool(SettingsRepository.legacyImportDone),
        isTrue,
      );
    });
  });
}
