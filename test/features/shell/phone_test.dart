import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/db/app_database.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:iace/features/emulator/emulator_controller.dart';
import 'package:iace/features/keyboard/ace_keyboard.dart';
import 'package:iace/features/keyboard/keyboard_controller.dart';
import 'package:iace/features/keyboard/keyboard_map.dart';
import 'package:iace/features/manual/manual_view.dart';
import 'package:iace/features/settings/settings_lid.dart';
import 'package:iace/features/settings/settings_repository.dart';
import 'package:iace/features/shell/phone_home.dart';
import 'package:iace/features/tapes/tape_library.dart';
import 'package:iace/main.dart';
import 'package:provider/provider.dart';

final rom = File('assets/ace.rom').readAsBytesSync();
final keyboardMap = KeyboardMap.fromJson(
  jsonDecode(File('assets/keyboard_map.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('tap areas', () {
    final hits = keyboardMap.hitRects;

    test('contain their key and never overlap', () {
      for (final key in keyboardMap.keys) {
        final hit = hits[key]!;
        expect(hit.contains(key.rect.topLeft), isTrue, reason: '$key');
        expect(hit.contains(key.rect.bottomRight - const Offset(1, 1)), isTrue);
        for (final other in keyboardMap.keys) {
          if (identical(other, key)) continue;
          final overlap = hit.intersect(hits[other]!);
          expect(
            overlap.width <= 0 || overlap.height <= 0,
            isTrue,
            reason: '$key and $other overlap',
          );
        }
      }
    });

    test('neighbours in a row touch', () {
      final row = keyboardMap.keys.where((k) => k.rect.top == 525).toList()
        ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      expect(row.map((k) => k.label).first, 'A');
      for (var i = 0; i + 1 < row.length; i++) {
        expect(hits[row[i]]!.right, hits[row[i + 1]]!.left);
      }
      // Rows touch too: A's area meets Q's (the row above) halfway.
      final q = keyboardMap.byLabel('Q');
      final a = keyboardMap.byLabel('A');
      expect(hits[a]!.top, hits[q]!.bottom);
    });
  });

  group('PhoneLayout', () {
    for (final (name, size) in [
      ('iPhone SE', const Size(375, 647)),
      ('iPhone 15', const Size(393, 759)),
      ('iPhone 15 Pro Max', const Size(430, 839)),
    ]) {
      test('$name: keys are never under the screen', () {
        final l = PhoneLayout(
          size: size,
          photo: keyboardMap.imageSize,
          photoKeysTop: keyboardMap.keysTop,
        );
        expect(l.keyboardTop + l.keyboardHeight, closeTo(size.height, 0.01));
        expect(l.panelHeight, greaterThan(150));
        expect(l.screenHeight, greaterThanOrEqualTo(l.screenMinHeight));
        final openKeyboardTop = l.keyboardTop - l.panelHeight;
        expect(
          l.screenHeight,
          lessThanOrEqualTo(openKeyboardTop + l.keysTop + 0.01),
        );
      });
    }
  });

  group('phone', () {
    late EmulatorController controller;
    late AppDatabase db;

    Future<void> pumpPhone(WidgetTester tester, {bool hint = false}) async {
      tester.view.physicalSize = const Size(1179, 2556); // iPhone 15
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
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
          showRevealHint: hint,
        ),
      );
      await tester.pump();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await db.close();
      });
    }

    Rect keyboardRect(WidgetTester tester) =>
        tester.getRect(find.byType(AceKeyboard));

    testWidgets('screen and keyboard, no manual', (tester) async {
      await pumpPhone(tester);
      expect(find.byType(PhoneHome), findsOneWidget);
      expect(find.byType(ManualView), findsNothing);
      expect(
        keyboardRect(tester).bottom,
        closeTo(852 - 34, 0.5),
      ); // above the home indicator

      // The keyboard types.
      for (final label in ['4', '2', 'ENTER']) {
        final g = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey('ace-key-$label'))),
        );
        for (var i = 0; i < 5; i++) {
          controller.runFrame();
        }
        await g.up();
        for (var i = 0; i < 5; i++) {
          controller.runFrame();
        }
      }
      for (var i = 0; i < 20; i++) {
        controller.runFrame();
      }
      expect(controller.machine.screenText(), contains('42  OK'));
    });

    testWidgets('drag the keyboard up to reveal the settings', (tester) async {
      await pumpPhone(tester);
      final closed = keyboardRect(tester);
      final panel = tester.getRect(find.byType(SettingsPanel));
      expect(closed.bottom, greaterThanOrEqualTo(panel.bottom - 0.5));

      // Dragging far only lifts the keyboard by the panel's height.
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('ace-key-G'))),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final open = keyboardRect(tester);
      expect(closed.top - open.top, closeTo(panel.height, 0.5));
      expect(open.bottom, closeTo(panel.top, 0.5));
      expect(
        await SettingsRepository(db)
            .getBool(SettingsRepository.revealHintShown),
        isTrue,
      );

      // The settings work, including the link to the manual.
      final keyboard = tester
          .element(find.byType(AceKeyboard))
          .read<KeyboardController>();
      await tester.tap(find.byKey(const ValueKey('sticky-shift')));
      await tester.pumpAndSettle();
      expect(keyboard.stickyShift, isTrue);
      expect(find.text('Manual'), findsOneWidget);

      // A short slow drag snaps back open; a flick down closes it.
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('ace-key-G'))),
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      expect(keyboardRect(tester).top, closeTo(open.top, 0.5));
      await tester.flingFrom(
        tester.getCenter(find.byKey(const ValueKey('ace-key-G'))),
        const Offset(0, 60),
        800,
      );
      await tester.pumpAndSettle();
      expect(keyboardRect(tester).top, closeTo(closed.top, 0.5));
    });

    testWidgets('first run: the keyboard lifts a little, then settles', (
      tester,
    ) async {
      await pumpPhone(tester, hint: true);
      final closed = keyboardRect(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 200));
      expect(keyboardRect(tester).top, lessThan(closed.top - 10));
      await tester.pumpAndSettle();
      expect(keyboardRect(tester).top, closed.top);
    });
  });
}
