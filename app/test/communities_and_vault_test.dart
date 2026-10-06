import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/theme/nexa_theme.dart';
import 'package:nexa_app/features/communities/presentation/explore_communities_screen.dart';
import 'package:nexa_app/features/communities/presentation/community_channel_screen.dart';
import 'package:nexa_app/features/auth/presentation/recovery_key_vault_screen.dart';

void main() {
  testWidgets('ExploreCommunitiesScreen renders categories and filters communities', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.darkTheme,
        home: const ExploreCommunitiesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Explore Communities'), findsOneWidget);
    expect(find.text('AI Builders'), findsOneWidget);
    expect(find.text('IoT Developers'), findsOneWidget);

    // Tap AI category chip
    await tester.tap(find.text('🤖 AI'));
    await tester.pumpAndSettle();

    expect(find.text('AI Builders'), findsOneWidget);
    expect(find.text('IoT Developers'), findsNothing);
  });

  testWidgets('CommunityChannelScreen displays messages and allows posting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.darkTheme,
        home: const CommunityChannelScreen(
          communityName: 'AI Builders',
          channelName: 'research',
          memberCount: 1240,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI Builders • #research'), findsOneWidget);
    expect(find.text('Dr. Elena Vance'), findsOneWidget);
    expect(find.text('Moderator'), findsOneWidget);

    // Post message
    await tester.enterText(find.byType(TextField), 'Testing community post');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Testing community post'), findsOneWidget);
  });

  testWidgets('RecoveryKeyVaultScreen renders obscured words and reveals on tap', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: NexaTheme.darkTheme,
        home: const RecoveryKeyVaultScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recovery Key Vault'), findsOneWidget);
    expect(find.text('Tap to Reveal Recovery Words'), findsOneWidget);

    // Tap reveal
    await tester.tap(find.text('Tap to Reveal Recovery Words'));
    await tester.pumpAndSettle();

    expect(find.text('Copy 24 Words'), findsOneWidget);
    expect(find.text('Confirm Backup Complete'), findsOneWidget);
  });
}
