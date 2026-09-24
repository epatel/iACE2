import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/features/manual/manual_annotations.dart';
import 'package:iace/features/manual/manual_controller.dart';
import 'package:iace/features/manual/manual_view.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:integration_test/integration_test.dart';

/// Renders the real manual PDF (PDFium is only bundled for device targets).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads the manual PDF and follows the controller', (
    tester,
  ) async {
    final annotations = await ManualAnnotations.load(rootBundle);
    final controller = ManualController(initialPage: 10);
    final actions = <ManualAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ManualView(
          controller: controller,
          annotations: annotations,
          onAction: actions.add,
        ),
      ),
    );
    for (var i = 0; i < 100 && controller.pageCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(controller.pageCount, 184);
    expect(find.text('10 / 184'), findsOneWidget);

    // The VLIST example on page 10.
    await tester.tap(find.text('Enter'));
    expect((actions.single as TypeAction).text, 'vlist\n');

    // A contents link jumps to its chapter (goto is handled by the view).
    controller.goTo(5);
    await tester.pumpAndSettle();
    expect(find.text('5 / 184'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('annotation-5-0'))) +
          const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    expect(controller.page, isNot(5));

    // Swiping moves one page.
    final before = controller.page;
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(controller.page, before + 1);
  });

  testWidgets('pages keep their size and place when the view shrinks', (
    tester,
  ) async {
    final annotations = await ManualAnnotations.load(rootBundle);
    final controller = ManualController(initialPage: 10);
    final height = ValueNotifier(900.0);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder(
            valueListenable: height,
            // A new ManualView widget on every change, as the drawers do.
            builder: (context, h, _) => SizedBox(
              height: h,
              child: ManualView(
                controller: controller,
                annotations: annotations,
                onAction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 100 && controller.pageCount == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    // Like the app: the view is shorter than a full-width page (1.29 x width).
    final width = tester.getSize(find.byType(ManualView)).width;
    height.value = width * 1.1;
    await tester.pumpAndSettle();

    final view = tester.getRect(find.byType(ManualView));
    final page = tester.getRect(find.byType(PdfPageView).first);
    expect(page.width, view.width, reason: 'full width, no side padding');
    expect(
      page.bottom,
      greaterThan(view.bottom),
      reason: 'runs under the slider',
    );

    for (final f in [0.9, 0.6, 0.3, 1.1]) {
      final h = width * f;
      height.value = h;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final resized = tester.getRect(find.byType(PdfPageView).first);
      expect(resized.size, page.size, reason: 'page keeps its size at $h');
    }
    await tester.pumpAndSettle();
    expect(controller.page, 10);
    expect(find.text('10 / 184'), findsOneWidget);
  });
}
