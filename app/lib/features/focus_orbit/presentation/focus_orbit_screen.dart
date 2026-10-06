import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../communities/presentation/community_channel_screen.dart';
import '../../communities/presentation/explore_communities_screen.dart';
import '../../privacy_center/presentation/privacy_center_screen.dart';

class FocusOrbitScreen extends StatefulWidget {
  const FocusOrbitScreen({super.key});

  @override
  State<FocusOrbitScreen> createState() => _FocusOrbitScreenState();
}

class _FocusOrbitScreenState extends State<FocusOrbitScreen> {
  int _activeNav = 0; // 0 = Home Orbit, 1 = Chats, 2 = Calls, 3 = Groups

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Quiet Intelligence Indicator
            _buildQuietIntelligenceHeader(),

            const SizedBox(height: 16),

            // Main Dynamic Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Search & Discovery Bar
                  _buildSearchBar(),

                  const SizedBox(height: 24),

                  // Priority Pulse Card
                  _buildPriorityCard(context),

                  const SizedBox(height: 28),

                  // Active Sections Summary
                  _buildOverviewMetrics(),

                  const SizedBox(height: 28),

                  // Recent Encrypted Conversations
                  const Text(
                    'PRIORITY CHATS',
                    style: TextStyle(
                      color: NexaColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildChatTile(
                    name: 'Rahul',
                    nexaId: 'NX-9B1D-84ZT',
                    message: 'Yes, 10 AM sounds perfect. See you at the coffee shop! 👍',
                    time: '8:44 PM',
                    unread: 0,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChatScreen(contactName: 'Rahul', nexaId: 'NX-9B1D-84ZT'),
                      ),
                    ),
                  ),
                  _buildChatTile(
                    name: 'AI Builders Community',
                    nexaId: 'COMMUNITY',
                    message: 'Alex: New quantization benchmark posted in #research',
                    time: '6:15 PM',
                    unread: 2,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CommunityChannelScreen(
                          communityName: 'AI Builders',
                          channelName: 'research',
                          memberCount: 1240,
                        ),
                      ),
                    ),
                  ),
                  _buildChatTile(
                    name: 'Hardware Design Group',
                    nexaId: 'GROUP',
                    message: 'Vikram: Schematic review at 4 PM tomorrow',
                    time: 'Yesterday',
                    unread: 0,
                    onTap: () {},
                  ),
                ],
              ),
            ),

            // Bottom Focus Orbit Dock
            _buildOrbitDock(context),
          ],
        ),
      ),
    );
  }

  Widget _buildQuietIntelligenceHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good evening, Karthik',
                style: TextStyle(
                  color: NexaColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.nightlight_round, color: NexaColors.cyanAccent, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Quiet Intelligence • Nothing urgent',
                    style: TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 24),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: NexaColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexaColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.search, color: NexaColors.textMuted, size: 20),
          SizedBox(width: 12),
          Text(
            'Search messages, NEXA ID, or communities...',
            style: TextStyle(color: NexaColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexaColors.elevated,
            NexaColors.surface.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NexaColors.cyanAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: NexaColors.cyanAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PRIORITY CHAT',
                    style: TextStyle(
                      color: NexaColors.cyanAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const Text('8:44 PM', style: TextStyle(color: NexaColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Rahul',
            style: TextStyle(color: NexaColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            '"Yes, 10 AM sounds perfect. See you at the coffee shop! 👍"',
            style: TextStyle(color: NexaColors.textSecondary, fontSize: 14, height: 1.3),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChatScreen(contactName: 'Rahul', nexaId: 'NX-9B1D-84ZT'),
                  ),
                ),
                icon: const Icon(Icons.reply, size: 16),
                label: const Text('Open Conversation'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reminder set for 10:00 AM tomorrow'),
                      backgroundColor: NexaColors.elevated,
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: NexaColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.alarm, color: NexaColors.amberAttention, size: 16),
                label: const Text('Remind Me', style: TextStyle(color: NexaColors.textPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewMetrics() {
    return Row(
      children: [
        _buildMetricItem('Chats', '4', Icons.chat_bubble_outline),
        const SizedBox(width: 12),
        _buildMetricItem('Calls', '1', Icons.phone_outlined),
        const SizedBox(width: 12),
        _buildMetricItem('Reminders', '2', Icons.notifications_none, highlight: true),
      ],
    );
  }

  Widget _buildMetricItem(String label, String count, IconData icon, {bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: NexaColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: highlight ? NexaColors.amberAttention.withValues(alpha: 0.3) : NexaColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: highlight ? NexaColors.amberAttention : NexaColors.textSecondary, size: 20),
            const SizedBox(height: 6),
            Text(
              count,
              style: TextStyle(
                color: highlight ? NexaColors.amberAttention : NexaColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTile({
    required String name,
    required String nexaId,
    required String message,
    required String time,
    required int unread,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: NexaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: NexaColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: NexaColors.elevated,
            child: Text(name.substring(0, 1), style: const TextStyle(color: NexaColors.cyanAccent, fontWeight: FontWeight.bold)),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
              Text(time, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NexaColors.textSecondary, fontSize: 13),
            ),
          ),
          trailing: unread > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: const BoxDecoration(
                    color: NexaColors.cyanAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unread.toString(),
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildOrbitDock(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: NexaColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: NexaColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, color: _activeNav == 0 ? NexaColors.cyanAccent : NexaColors.textSecondary),
            onPressed: () => setState(() => _activeNav = 0),
          ),
          IconButton(
            icon: Icon(Icons.call_outlined, color: _activeNav == 1 ? NexaColors.cyanAccent : NexaColors.textSecondary),
            onPressed: () => setState(() => _activeNav = 1),
          ),

          // Glowing Center Assistant Orb
          GestureDetector(
            onTap: () => _openAssistantModal(context),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    NexaColors.cyanAccent,
                    Color(0xFF007799),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: NexaColors.cyanAccent.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.black, size: 24),
            ),
          ),

          IconButton(
            icon: Icon(Icons.groups_outlined, color: _activeNav == 2 ? NexaColors.cyanAccent : NexaColors.textSecondary),
            onPressed: () {
              setState(() => _activeNav = 2);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExploreCommunitiesScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.security_outlined, color: NexaColors.textSecondary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()),
            ),
          ),
        ],
      ),
    );
  }

  void _openAssistantModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NexaColors.cyanAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: NexaColors.cyanAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NEXA Assistant', style: TextStyle(color: NexaColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Local on-device intelligence • Zero cloud exposure', style: TextStyle(color: NexaColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Suggested Tasks', style: TextStyle(color: NexaColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _buildAssistantOption(
                icon: Icons.summarize_outlined,
                title: 'Summarize unread messages',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Processing locally: 2 work groups, no urgent promises.'), backgroundColor: NexaColors.elevated),
                  );
                },
              ),
              _buildAssistantOption(
                icon: Icons.alarm_add_outlined,
                title: 'Remind me: Call Dad tomorrow at 7 PM',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder scheduled for tomorrow 7:00 PM.'), backgroundColor: NexaColors.elevated),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssistantOption({required IconData icon, required String title, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NexaColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: NexaColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: NexaColors.cyanAccent, size: 20),
          title: Text(title, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14)),
          trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted, size: 18),
          onTap: onTap,
        ),
      ),
    );
  }
}
