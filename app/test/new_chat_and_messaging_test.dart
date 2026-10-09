import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/session/user_session.dart';
import 'package:nexa_app/core/services/contacts_service.dart';
import 'package:nexa_app/features/focus_orbit/presentation/focus_orbit_screen.dart';

void main() {
  setUp(() {
    UserSession.instance.updateProfile(
      name: 'Karthik N',
      handle: '@karthik_official',
      nexaId: 'NX-C53E-AEE9',
    );
  });

  test('ContactsService correlates device phone numbers with registered users', () {
    final rawDeviceContacts = [
      {
        'name': 'Bob Tester',
        'phone': '+1 234 567 8900',
        'isOnNexa': false,
        'nexaUser': null,
      },
      {
        'name': 'Mom',
        'phone': '5551234',
        'isOnNexa': false,
        'nexaUser': null,
      }
    ];

    final registeredUsers = [
      {
        'username': 'bob_official',
        'handle': '@bob_official',
        'nexa_id': 'NX-BOB-9999',
        'phone': '+12345678900',
        'full_name': 'Bob Tester',
      }
    ];

    final correlated = ContactsService.instance.correlateContactsWithRegistered(
      rawDeviceContacts,
      registeredUsers,
    );

    expect(correlated.length, 2);
    final bob = correlated.firstWhere((c) => c['name'] == 'Bob Tester');
    expect(bob['isOnNexa'], true);
    expect(bob['nexaId'], 'NX-BOB-9999');
    expect(bob['handle'], '@bob_official');

    final mom = correlated.firstWhere((c) => c['name'] == 'Mom');
    expect(mom['isOnNexa'], false);
  });

  testWidgets('FocusOrbitScreen FAB opens New Conversation modal and displays search bar', (WidgetTester tester) async {
    UserSession.instance.login(name: 'Karthik N', handle: '@karthik_official');
    await tester.pumpWidget(
      const MaterialApp(
        home: FocusOrbitScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify FAB is present
    final fabFinder = find.byType(FloatingActionButton);
    expect(fabFinder, findsOneWidget);

    // Tap FAB to open modal
    await tester.tap(fabFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify New Conversation modal opened
    expect(find.text('Start Conversation'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    // Enter an unregistered ID into the modal input field
    final modalInputFinder = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText?.contains('Search registered NEXA ID') == true,
    );
    expect(modalInputFinder, findsOneWidget);
    await tester.enterText(modalInputFinder, 'NX-UNREGISTERED-9999');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify "No account found" validation appears for unregistered ID
    expect(find.text('No account found'), findsWidgets);
  });
}
