import 'package:flutter_test/flutter_test.dart';
import 'package:iace/main.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const IaceApp());
    expect(find.text('iACE'), findsOneWidget);
  });
}
