import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/db/app_database.dart';
import 'core/ffi/ace_machine.dart';
import 'features/emulator/emulator_controller.dart';
import 'features/emulator/session_autosave.dart';
import 'features/emulator/snapshot_store.dart';
import 'features/keyboard/keyboard_controller.dart';
import 'features/keyboard/keyboard_map.dart';
import 'features/legacy/legacy_import.dart';
import 'features/manual/manual_annotations.dart';
import 'features/manual/manual_controller.dart';
import 'features/settings/settings_lid.dart';
import 'features/settings/settings_repository.dart';
import 'features/shell/home_page.dart';
import 'features/tapes/db_tape_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final frogger = await rootBundle.load('assets/tapes/frogger.dic');
  final db = AppDatabase.open(
    seedTapes: {'frogger.dic': frogger.buffer.asUint8List()},
  );
  final settings = SettingsRepository(db);
  final tapes = DbTapeLibrary(db);

  if (Platform.isIOS) {
    final library = await getLibraryDirectory();
    await LegacyImporter(
      tapes: tapes,
      settings: settings,
      documentsDir: await getApplicationDocumentsDirectory(),
      preferencesFile: File(
        p.join(library.path, LegacyImporter.preferencesPath),
      ),
    ).run();
  }

  final rom = await rootBundle.load('assets/ace.rom');
  final keyboardMap = await KeyboardMap.load(rootBundle);
  final machine = AceMachine(rom.buffer.asUint8List());
  final volume = VolumeSetting(
    initial: await settings.getDouble(SettingsRepository.volume) ?? 1.0,
    machine: machine,
    settings: settings,
  );
  final controller = EmulatorController(
    machine: machine,
    tapes: tapes,
    playSound: true,
  );
  final autosave = SessionAutosave(
    controller: controller,
    store: SnapshotStore(db),
  );
  await autosave.restore();
  autosave.start();
  controller.start();

  final keyboard = KeyboardController(
    emulator: controller,
    stickyShift:
        await settings.getBool(SettingsRepository.stickyShift) ?? false,
  );
  var stickyShift = keyboard.stickyShift;
  keyboard.addListener(() {
    if (keyboard.stickyShift == stickyShift) return;
    stickyShift = keyboard.stickyShift;
    settings.setBool(SettingsRepository.stickyShift, stickyShift);
  });

  final manual = ManualController(
    initialPage: await settings.getInt(SettingsRepository.lastPage) ?? 1,
    onPageSettled: (page) => settings.setInt(SettingsRepository.lastPage, page),
  );
  final annotations = await ManualAnnotations.load(rootBundle);

  runApp(
    IaceApp(
      controller: controller,
      keyboardMap: keyboardMap,
      keyboard: keyboard,
      manual: manual,
      annotations: annotations,
      settings: settings,
      volume: volume,
      showRevealHint:
          await settings.getBool(SettingsRepository.revealHintShown) != true,
    ),
  );
}

class IaceApp extends StatelessWidget {
  const IaceApp({
    super.key,
    required this.controller,
    required this.keyboardMap,
    this.keyboard,
    this.manual,
    this.annotations,
    this.settings,
    this.volume,
    this.showRevealHint = false,
    this.drawersOpen = false,
  });

  final EmulatorController controller;
  final KeyboardMap keyboardMap;

  /// Created for [controller] if not given.
  final KeyboardController? keyboard;
  final ManualController? manual;
  final ManualAnnotations? annotations;
  final SettingsRepository? settings;

  /// Created for [controller]'s machine if not given.
  final VolumeSetting? volume;
  final bool showRevealHint;
  final bool drawersOpen;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        Provider<SettingsRepository?>.value(value: settings),
        if (volume case final volume?)
          ChangeNotifierProvider.value(value: volume)
        else
          ChangeNotifierProvider(
            create: (_) => VolumeSetting(
              initial: 1.0,
              machine: controller.machine,
              settings: settings,
            ),
          ),
        if (keyboard case final keyboard?)
          ChangeNotifierProvider.value(value: keyboard)
        else
          ChangeNotifierProvider(
            create: (_) => KeyboardController(emulator: controller),
          ),
      ],
      child: MaterialApp(
        title: 'iACE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: HomePage(
          keyboardMap: keyboardMap,
          manual: manual,
          annotations: annotations,
          showRevealHint: showRevealHint,
          drawersOpen: drawersOpen,
        ),
      ),
    );
  }
}
