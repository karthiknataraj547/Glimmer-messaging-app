import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/main.dart';

void main() {
  testWidgets('NexaApp smoke test loads FocusOrbitScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const NexaApp());
    await tester.pumpAndSettle();

    // Verify calm quiet intelligence header is present
    expect(find.text('Good evening, Karthik'), findsOneWidget);
    expect(find.text('PRIORITY CHAT'), findsOneWidget);
  });
}
