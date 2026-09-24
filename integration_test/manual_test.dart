import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/features/manual/manual_annotations.dart';
import 'package:iace/features/manual/manual_controller.dart';
import 'package:iace/features/manual/manual_view.dart';
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
}
