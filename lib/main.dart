import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/ffi/ace_machine.dart';
import 'features/emulator/emulator_controller.dart';
import 'features/emulator/screen_view.dart';
import 'features/tapes/tape_library.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final rom = await rootBundle.load('assets/ace.rom');
  final tapes = await InMemoryTapeLibrary.withBundledTapes(rootBundle);
  final controller = EmulatorController(
    machine: AceMachine(rom.buffer.asUint8List()),
    tapes: tapes,
  )..start();
  runApp(IaceApp(controller: controller));
}

class IaceApp extends StatelessWidget {
  const IaceApp({super.key, required this.controller});

  final EmulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        title: 'iACE',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: const Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Align(alignment: Alignment.topCenter, child: ScreenView()),
          ),
        ),
      ),
    );
  }
}
