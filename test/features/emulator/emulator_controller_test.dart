import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/emulator/screen_view.dart';
import 'package:iace/features/keyboard/keyboard_map.dart';
import 'package:iace/features/tapes/tape_library.dart';
import 'package:iace/main.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final keyboardMap = KeyboardMap.fromJson(
  jsonDecode(File('assets/keyboard_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

EmulatorController newController([TapeLibrary? tapes]) => EmulatorController(
  machine: AceMachine(rom),
  tapes: tapes ?? InMemoryTapeLibrary(),
);

/// Runs frames directly (no ticker) until the spooler is done.
void typeAndSettle(EmulatorController controller, String text) {
  controller.type(text);
  for (var i = 0; i < 3000 && controller.machine.isSpooling; i++) {
    controller.runFrame();
  }
  for (var i = 0; i < 25; i++) {
    controller.runFrame();
  }
}

void main() {
  testWidgets('runs at 50 frames per second and shows the screen', (
    tester,
  ) async {
    final controller = newController()..start();
    await tester.pumpWidget(
      IaceApp(controller: controller, keyboardMap: keyboardMap),
    );
    expect(find.byType(ScreenView), findsOneWidget);

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16, microseconds: 667));
    }
    expect(controller.frameCount, inInclusiveRange(98, 101));

    // Screen decoding uses the engine, which needs real async time.
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && controller.screen.value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(controller.screen.value, isNotNull);
    expect(controller.screen.value!.width, AceMachine.width);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('pauses while the app is hidden', (tester) async {
    final controller = newController()..start();
    await tester.pumpWidget(
      IaceApp(controller: controller, keyboardMap: keyboardMap),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isRunning, isTrue);

    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(controller.isRunning, isFalse);
    final frames = controller.frameCount;
    await tester.pump(const Duration(seconds: 1));
    expect(controller.frameCount, frames);

    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(controller.isRunning, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.frameCount, greaterThan(frames));

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('answers tape requests from the tape library', (tester) async {
    final tapes = InMemoryTapeLibrary();
    final controller = newController(tapes);
    for (var i = 0; i < 100; i++) {
      controller.runFrame();
    }
    typeAndSettle(controller, ': TWICE 2 * ;\n');
    typeAndSettle(controller, 'SAVE twice\n');
    await tester.pump();
    expect(await tapes.load('twice', TapeKind.dict), isA<Uint8List>());

    controller.reset();
    for (var i = 0; i < 100; i++) {
      controller.runFrame();
    }
    controller.type('LOAD twice\n');
    for (var i = 0; i < 3000 && controller.machine.isSpooling; i++) {
      controller.runFrame();
      await tester.pump(); // lets the tape library future complete
    }
    for (var i = 0; i < 25; i++) {
      controller.runFrame();
    }
    typeAndSettle(controller, '21 TWICE .\n');
    expect(controller.machine.screenText(), contains('21 TWICE . 42  OK'));
    controller.dispose();
  });
}
