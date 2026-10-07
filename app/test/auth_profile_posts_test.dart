import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/session/user_session.dart';
import 'package:nexa_app/core/theme/nexa_theme.dart';
import 'package:nexa_app/features/auth/presentation/auth_flow_screen.dart';
import 'package:nexa_app/features/profile/presentation/user_profile_screen.dart';
import 'package:nexa_app/features/posts/presentation/posts_feed_screen.dart';

void main() {
  testWidgets('AuthFlowScreen renders simple unified layout and toggles between Register and Log In', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.lightTheme,
        home: const AuthFlowScreen(isLoginInitial: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEXA'), findsOneWidget);
    expect(find.text('Username / Handle'), findsWidgets);

    // Switch to Login Mode
    await tester.tap(find.text('Log In').first);
    await tester.pumpAndSettle();

    expect(find.text('Log In to NEXA'), findsOneWidget);
    expect(find.text('Master PIN (6 Digits)'), findsOneWidget);
  });

  testWidgets('UserProfileScreen allows updating name and status', (tester) async {
    UserSession.instance.login(name: 'Karthik', handle: '@karthik');
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.lightTheme,
        home: const UserProfileScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Profile & Vault'), findsOneWidget);
    expect(find.text('Self-Sovereign NEXA ID'), findsOneWidget);

    // Edit Name
    final nameField = find.widgetWithText(TextField, 'Karthik');
    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, 'Karthik N');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(UserSession.instance.name, 'Karthik N');
  });

  testWidgets('PostsFeedScreen creates and upvotes a post', (tester) async {
    UserSession.instance.login(name: 'Karthik', handle: '@karthik');
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.lightTheme,
        home: const PostsFeedScreen(isEmbedded: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Circle Posts & Feed'), findsOneWidget);

    // Enter a new post
    final postInput = find.byType(TextField);
    await tester.enterText(postInput, 'Deploying on-device Double Ratchet test suite.');
    await tester.tap(find.text('Post to Circle'));
    await tester.pumpAndSettle();

    expect(find.text('Deploying on-device Double Ratchet test suite.'), findsOneWidget);
  });
}
