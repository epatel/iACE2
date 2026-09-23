import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/ffi/ace_machine.dart';
import 'features/emulator/emulator_controller.dart';
import 'features/keyboard/keyboard_controller.dart';
import 'features/keyboard/keyboard_map.dart';
import 'features/shell/home_page.dart';
import 'features/tapes/tape_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final rom = await rootBundle.load('assets/ace.rom');
  final tapes = await InMemoryTapeLibrary.withBundledTapes(rootBundle);
  final keyboardMap = await KeyboardMap.load(rootBundle);
  final controller = EmulatorController(
    machine: AceMachine(rom.buffer.asUint8List()),
    tapes: tapes,
  )..start();
  runApp(IaceApp(controller: controller, keyboardMap: keyboardMap));
}

class IaceApp extends StatelessWidget {
  const IaceApp({
    super.key,
    required this.controller,
    required this.keyboardMap,
  });

  final EmulatorController controller;
  final KeyboardMap keyboardMap;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider(
          create: (_) => KeyboardController(emulator: controller),
        ),
      ],
      child: MaterialApp(
        title: 'iACE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: HomePage(keyboardMap: keyboardMap),
      ),
    );
  }
}
