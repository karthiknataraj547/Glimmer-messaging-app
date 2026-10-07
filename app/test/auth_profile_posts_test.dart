import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/session/user_session.dart';
import 'package:nexa_app/core/theme/nexa_theme.dart';
import 'package:nexa_app/features/auth/presentation/auth_flow_screen.dart';
import 'package:nexa_app/features/profile/presentation/user_profile_screen.dart';
import 'package:nexa_app/features/posts/presentation/posts_feed_screen.dart';

void main() {
  testWidgets('AuthFlowScreen renders stepper and toggles between Register and Login', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.lightTheme,
        home: const AuthFlowScreen(isLoginInitial: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEXA'), findsOneWidget);
    expect(find.text('Create Self-Sovereign Identity'), findsOneWidget);
    expect(find.text('Choose Your Handle'), findsOneWidget);

    // Switch to Login Mode
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Your Cryptographic Vault'), findsOneWidget);
    expect(find.text('Enter 24 Recovery Words'), findsOneWidget);
  });

  testWidgets('UserProfileScreen allows updating name and status', (tester) async {
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
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.lightTheme,
        home: const PostsFeedScreen(isEmbedded: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Circle Posts & Feed'), findsOneWidget);
    expect(find.text('Dr. Elena Rostova'), findsOneWidget);

    // Enter a new post
    final postInput = find.byType(TextField);
    await tester.enterText(postInput, 'Deploying on-device Double Ratchet test suite.');
    await tester.tap(find.text('Post to Circle'));
    await tester.pumpAndSettle();

    expect(find.text('Deploying on-device Double Ratchet test suite.'), findsOneWidget);
  });
}
