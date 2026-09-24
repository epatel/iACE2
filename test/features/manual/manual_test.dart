import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/features/manual/manual_annotations.dart';
import 'package:iace/features/manual/manual_controller.dart';
import 'package:iace/features/manual/manual_page.dart';

final annotations = ManualAnnotations.fromJson(
  jsonDecode(File('assets/annotations.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  group('annotations', () {
    test('all 104 from iACE 1.x, inside their pages', () {
      expect(annotations.count, 104);
      final page = Offset.zero & annotations.pageSize;
      for (var p = 1; p <= 184; p++) {
        for (final a in annotations.onPage(p)) {
          expect(page.contains(a.rect.topLeft), isTrue);
          expect(a.rect.right, lessThanOrEqualTo(page.right + 1));
          switch (a.action) {
            case TypeAction(:final text):
              expect(text, endsWith('\n'));
              expect(text, isNot(endsWith('\n\n')));
              expect(text, isNot(contains(r'\')));
            case GotoAction(page: final target):
              expect(target, inInclusiveRange(1, 184));
            case OpenUrlAction(:final url):
              expect(url.scheme, startsWith('http'));
          }
        }
      }
    });

    test('contents page links to the chapters', () {
      // PDF page 5 lists "Chapter 19 page 110"; printed page 110 is PDF page 111.
      final targets = annotations
          .onPage(5)
          .map((a) => a.action)
          .whereType<GotoAction>()
          .map((a) => a.page);
      expect(targets, contains(111));
    });

    test('the VLIST example on page 10', () {
      final type = annotations.onPage(10).single.action as TypeAction;
      expect(type.text, 'vlist\n');
    });
  });

  group('ManualController', () {
    test('clamps pages once the page count is known', () {
      final c = ManualController(initialPage: 50);
      c.pageCount = 20;
      expect(c.page, 20);
      c.goTo(0);
      expect(c.page, 1);
      c.goTo(99);
      expect(c.page, 20);
    });

    test('reports the page after it settles', () {
      fakeAsync((async) {
        final saved = <int>[];
        final c = ManualController(onPageSettled: saved.add)..pageCount = 184;
        c.goTo(10);
        async.elapse(const Duration(seconds: 1));
        c.goTo(11);
        c.goTo(12);
        async.elapse(const Duration(seconds: 1));
        expect(saved, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(saved, [12]);
      });
    });
  });

  testWidgets('tapping annotations reports their actions', (tester) async {
    tester.view.physicalSize = const Size(1224, 1584);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final actions = <ManualAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ManualPage(
          pageSize: annotations.pageSize,
          annotations: annotations.onPage(5),
          content: const ColoredBox(color: Colors.white),
          onAction: actions.add,
        ),
      ),
    );
    // The page fills 612 x 792 logical pixels, so PDF points map 1:1.
    await tester.tapAt(const Offset(100, 115)); // "Chapter 19 page 110"
    await tester.tapAt(const Offset(310, 598)); // www.jupiter-ace.co.uk
    await tester.tapAt(const Offset(600, 780)); // nothing there
    expect(actions, hasLength(2));
    expect((actions[0] as GotoAction).page, 111);
    expect((actions[1] as OpenUrlAction).url.host, 'www.jupiter-ace.co.uk');

    await tester.pumpWidget(
      MaterialApp(
        home: ManualPage(
          pageSize: annotations.pageSize,
          annotations: annotations.onPage(10),
          content: const ColoredBox(color: Colors.white),
          onAction: actions.add,
        ),
      ),
    );
    expect(find.text('Enter'), findsOneWidget);
    await tester.tap(find.text('Enter'));
    expect((actions.last as TypeAction).text, 'vlist\n');
  });
}
