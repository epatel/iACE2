import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/keyboard/ace_keyboard.dart';
import 'package:iace/features/keyboard/keyboard_controller.dart';
import 'package:iace/features/keyboard/keyboard_map.dart';
import 'package:iace/features/shell/portrait_frame.dart';
import 'package:iace/features/tapes/tape_library.dart';
import 'package:iace/main.dart';
import 'package:provider/provider.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final keyboardMap = KeyboardMap.fromJson(
  jsonDecode(File('assets/keyboard_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// The input line: the bottom row of the ACE screen, trimmed.
String inputLine(EmulatorController c) =>
    c.machine.screenText().split('\n').last.trim();

void runFrames(EmulatorController c, int n) {
  for (var i = 0; i < n; i++) {
    c.runFrame();
  }
}

/// A booted machine in the app, with the ticker stopped so tests drive frames.
Future<EmulatorController> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1668, 2388); // iPad 11" portrait
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final controller = EmulatorController(
    machine: AceMachine(rom),
    tapes: InMemoryTapeLibrary(),
  );
  runFrames(controller, 100);
  await tester.pumpWidget(
    IaceApp(
      controller: controller,
      keyboardMap: keyboardMap,
      drawersOpen: true,
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  return controller;
}

Offset keyCenter(WidgetTester tester, String label) =>
    tester.getCenter(find.byKey(ValueKey('ace-key-$label')));

/// Holds a key down for a few frames, like a finger would.
Future<void> tapKey(
  WidgetTester tester,
  EmulatorController c,
  String label,
) async {
  final gesture = await tester.startGesture(keyCenter(tester, label));
  runFrames(c, 3);
  await gesture.up();
  runFrames(c, 3);
  await tester.pump();
}

void main() {
  test('keyboard map has 40 distinct keys on the photo', () {
    expect(keyboardMap.keys, hasLength(40));
    final bounds = Offset.zero & keyboardMap.imageSize;
    for (final key in keyboardMap.keys) {
      expect(bounds.contains(key.rect.topLeft), isTrue, reason: '$key');
      expect(bounds.contains(key.rect.bottomRight), isTrue, reason: '$key');
    }
    final shifts = keyboardMap.keys.where((k) => k.isShift).map((k) => k.label);
    expect(shifts, unorderedEquals(['SHIFT', 'SYMBOL SHIFT']));
  });

  testWidgets('typing on the keyboard reaches the ACE', (tester) async {
    final c = await pumpApp(tester);
    expect(find.byType(AceKeyboard), findsOneWidget);
    for (final label in ['2', 'SPACE', '3', 'SPACE']) {
      await tapKey(tester, c, label);
    }
    // SYMBOL SHIFT + K is '+', then ' .' and ENTER.
    final symbol = await tester.startGesture(keyCenter(tester, 'SYMBOL SHIFT'));
    await tapKey(tester, c, 'K');
    await symbol.up();
    await tapKey(tester, c, 'SPACE');
    final symbol2 = await tester.startGesture(
      keyCenter(tester, 'SYMBOL SHIFT'),
    );
    await tapKey(tester, c, 'M');
    await symbol2.up();
    await tapKey(tester, c, 'ENTER');
    runFrames(c, 10);
    expect(c.machine.screenText(), contains('2 3 + . 5  OK'));
  });

  testWidgets('a very quick tap is held long enough for the ROM', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    for (final label in ['X', 'Y']) {
      final gesture = await tester.startGesture(keyCenter(tester, label));
      await gesture.up(); // released before any frame ran
      runFrames(c, 8);
    }
    await tester.pump();
    expect(inputLine(c), contains('xy'));
  });

  testWidgets('SHIFT held with a letter gives a capital', (tester) async {
    final c = await pumpApp(tester);
    await tapKey(tester, c, 'A');
    final shift = await tester.startGesture(keyCenter(tester, 'SHIFT'));
    await tapKey(tester, c, 'A');
    await shift.up();
    expect(inputLine(c), contains('aA'));
  });

  testWidgets('sticky shift latches until tapped again', (tester) async {
    final c = await pumpApp(tester);
    final keyboard = tester
        .element(find.byType(AceKeyboard))
        .read<KeyboardController>();
    keyboard.stickyShift = true;
    final shift = keyboardMap.byLabel('SHIFT');

    await tapKey(tester, c, 'SHIFT');
    expect(keyboard.isDown(shift), isTrue);
    await tapKey(tester, c, 'B');
    await tapKey(tester, c, 'C');
    await tapKey(tester, c, 'SHIFT');
    expect(keyboard.isDown(shift), isFalse);
    await tapKey(tester, c, 'D');
    expect(inputLine(c), contains('BCd'));

    // Turning sticky shift off releases a latched shift.
    await tapKey(tester, c, 'SHIFT');
    keyboard.stickyShift = false;
    expect(keyboard.isDown(shift), isFalse);
    await tapKey(tester, c, 'E');
    expect(inputLine(c), contains('BCde'));
  });

  testWidgets('keys are ignored while typing from the manual, SPACE stops it', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    c.type('1 2 3 4 5 6 7 8 9 10 11 12\n');
    runFrames(c, 5);
    expect(c.machine.isSpooling, isTrue);
    await tapKey(tester, c, 'Q');
    await tapKey(tester, c, 'SPACE');
    expect(c.machine.isSpooling, isFalse);
    runFrames(c, 10);
    expect(inputLine(c), isNot(contains('q')));
    expect(inputLine(c), isNot(contains('12')));
  });

  for (final (height, shrunk) in [(400.0, false), (250.0, true)]) {
    testWidgets('keyboard in ${height}px keeps every key visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final controller = EmulatorController(
        machine: AceMachine(rom),
        tapes: InMemoryTapeLibrary(),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => KeyboardController(emulator: controller),
          child: MaterialApp(
            home: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: height,
                child: AceKeyboard(map: keyboardMap),
              ),
            ),
          ),
        ),
      );
      final area = tester.getRect(find.byType(AceKeyboard));
      final photo = tester.getRect(find.byType(Image));
      expect(photo.top < area.top, isTrue, reason: 'logo cropped');
      expect(photo.width < area.width, shrunk, reason: 'scaled down');
      for (final key in keyboardMap.keys) {
        final rect = tester.getRect(
          find.byKey(ValueKey('ace-key-${key.label}')),
        );
        expect(area.contains(rect.center), isTrue, reason: '$key');
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('wide windows get a centred portrait layout', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600); // landscape tablet
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: PortraitFrame(child: SizedBox.expand(key: ValueKey('content'))),
      ),
    );
    final rect = tester.getRect(find.byKey(const ValueKey('content')));
    expect(rect.width, closeTo(800 * 3 / 4, 0.01));
    expect(rect.center.dx, closeTo(640, 0.01));
  });
}
