import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide DrawerController;
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/db/app_database.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/keyboard/ace_keyboard.dart';
import 'package:iace/features/keyboard/keyboard_controller.dart';
import 'package:iace/features/keyboard/keyboard_map.dart';
import 'package:iace/features/settings/settings_lid.dart';
import 'package:iace/features/settings/settings_repository.dart';
import 'package:iace/features/shell/drawer_controller.dart';
import 'package:iace/features/tapes/tape_library.dart';
import 'package:iace/main.dart';
import 'package:provider/provider.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final keyboardMap = KeyboardMap.fromJson(
  jsonDecode(File('assets/keyboard_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

/// iPad 10.9"/13" proportions: 1024 units tall, like the original layout.
const ipad = Size(1536, 2048);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('DrawerController (the iACE 1.x drawer rules)', () {
    late DrawerController d;
    setUp(() {
      d = DrawerController(vsync: const TestVSync())
        ..setLayout(height: 1024, keyboardHeight: 687);
    });
    tearDown(() => d.dispose());

    test('starts closed with the manual below the keyboard strip', () {
      expect(d.screenY, -500);
      expect(d.keyboardY, -500);
      expect(d.manualTop, 187);
      expect(d.isOpen, isFalse);
    });

    test('open positions match the original on a 1024-unit iPad', () {
      expect(d.keyboardOpenY, 317);
      d.dragKeyboard(2000);
      expect(d.keyboardY, 317);
      expect(d.manualTop, 1024 - DrawerController.minManualHeight);
    });

    test('the screen drawer drags the keyboard drawer along', () {
      d.dragKeyboard(817); // keyboard fully open, screen follows to -265
      expect(d.keyboardY, 317);
      expect(d.screenY, 317 - DrawerController.maxGap);
      d.dragScreen(-1000); // screen closes; keyboard may stay 582 below
      expect(d.screenY, -500);
      expect(d.keyboardY, -500 + DrawerController.maxGap);
      d.dragKeyboard(-1000); // keyboard closes; the screen can't be below it
      expect(d.keyboardY, -500);
      expect(d.screenY, -500);
    });

    test('keyboard never goes above the screen drawer', () {
      d.dragScreen(500);
      expect(d.screenY, 0);
      expect(d.keyboardY, 0);
    });

    test('taller screens keep the keyboard at the bottom', () {
      d.setLayout(height: 1228, keyboardHeight: 676);
      expect(d.keyboardOpenY, 1228 - 676 - 20);
    });
  });

  group('shell', () {
    late EmulatorController controller;
    late AppDatabase db;

    Future<void> pumpShell(
      WidgetTester tester, {
      bool open = false,
      bool hint = false,
    }) async {
      tester.view.physicalSize = ipad;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      db = AppDatabase(NativeDatabase.memory());
      controller = EmulatorController(
        machine: AceMachine(rom),
        tapes: InMemoryTapeLibrary(),
      );
      for (var i = 0; i < 100; i++) {
        controller.runFrame();
      }
      await tester.pumpWidget(
        IaceApp(
          controller: controller,
          keyboardMap: keyboardMap,
          settings: SettingsRepository(db),
          drawersOpen: open,
          showRevealHint: hint,
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await db.close();
      });
    }

    DrawerController drawers(WidgetTester tester) =>
        tester.element(find.byType(AceKeyboard)).read<DrawerController>();

    testWidgets('tap the manual to open, tap the screen to close', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(drawers(tester).isOpen, isFalse);
      await tester.tapAt(const Offset(384, 900)); // on the manual
      await tester.pumpAndSettle();
      expect(drawers(tester).isOpen, isTrue);
      await tester.tapAt(const Offset(384, 200)); // on the screen
      await tester.pumpAndSettle();
      expect(drawers(tester).screenY, DrawerController.closedY);
      expect(drawers(tester).keyboardY, DrawerController.closedY);
    });

    testWidgets('a drag that starts on a key moves the drawer, not the key', (
      tester,
    ) async {
      await pumpShell(tester, open: true);
      final keyboard = tester
          .element(find.byType(AceKeyboard))
          .read<KeyboardController>();
      final k = keyboardMap.byLabel('K');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ace-key-K'))),
      );
      expect(keyboard.isDown(k), isTrue);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
      }
      expect(keyboard.isDown(k), isFalse, reason: 'drag cancels the key');
      expect(drawers(tester).keyboardY, lessThan(317));
      await gesture.up();
    });

    testWidgets('settings under the lid', (tester) async {
      await pumpShell(tester, hint: true);
      // Close the screen drawer but keep the keyboard open to see the lid.
      drawers(tester).dragKeyboard(2000);
      drawers(tester).dragScreen(-2000);
      await tester.pumpAndSettle();
      expect(
        find.image(const AssetImage('assets/images/reveal.png')),
        findsOne,
      );

      await tester.tap(find.byKey(const ValueKey('settings-lid')));
      await tester.pumpAndSettle();
      expect(
        find.image(const AssetImage('assets/images/reveal.png')),
        findsNothing,
      );
      expect(
        await SettingsRepository(db)
            .getBool(SettingsRepository.revealHintShown),
        isTrue,
      );

      // Sticky shift
      final keyboard = tester
          .element(find.byType(AceKeyboard))
          .read<KeyboardController>();
      await tester.tap(find.byKey(const ValueKey('sticky-shift')));
      await tester.pumpAndSettle();
      expect(keyboard.stickyShift, isTrue);

      // Volume
      await tester.drag(
        find.byKey(const ValueKey('volume')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      final volume = tester
          .element(find.byType(SettingsLid))
          .read<VolumeSetting>();
      expect(volume.value, 0);
      expect(
        await SettingsRepository(db).getDouble(SettingsRepository.volume),
        0,
      );

      // Reset asks first
      controller.type('1 2 3\n');
      for (var i = 0; i < 300 && controller.machine.isSpooling; i++) {
        controller.runFrame();
      }
      for (var i = 0; i < 25; i++) {
        controller.runFrame();
      }
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(controller.machine.screenText(), contains('1 2 3'));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 100; i++) {
        controller.runFrame();
      }
      expect(controller.machine.screenText(), isNot(contains('1 2 3')));
    });
  });
}
