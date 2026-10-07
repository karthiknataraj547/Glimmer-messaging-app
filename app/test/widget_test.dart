import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/session/user_session.dart';
import 'package:nexa_app/main.dart';

void main() {
  testWidgets('NexaApp opens Login screen by default on first launch without auth', (WidgetTester tester) async {
    UserSession.instance.logout();
    await tester.pumpWidget(const NexaApp());
    await tester.pumpAndSettle();

    // Verify login screen is displayed on first launch
    expect(find.text('Log In to NEXA'), findsOneWidget);
    expect(find.text('Master PIN (6 Digits)'), findsOneWidget);
  });

  testWidgets('NexaApp loads FocusOrbitScreen when user is authenticated', (WidgetTester tester) async {
    UserSession.instance.login(name: 'Karthik', handle: '@karthik');
    await tester.pumpWidget(const NexaApp());
    await tester.pumpAndSettle();

    // Verify calm quiet intelligence header is present
    expect(find.text('Good evening, Karthik'), findsOneWidget);
    expect(find.text('PRIORITY CHATS'), findsOneWidget);
  });
}
