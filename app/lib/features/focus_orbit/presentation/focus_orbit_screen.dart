import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../calls/presentation/active_call_screen.dart';
import '../../communities/presentation/explore_communities_screen.dart';
import '../../privacy_center/presentation/privacy_center_screen.dart';

class FocusOrbitScreen extends StatefulWidget {
  const FocusOrbitScreen({super.key});

  @override
  State<FocusOrbitScreen> createState() => _FocusOrbitScreenState();
}

class _FocusOrbitScreenState extends State<FocusOrbitScreen> {
  int _activeNav = 0; // 0 = Chats, 1 = Calls, 2 = Communities, 3 = Security

  final List<Map<String, dynamic>> _callLogs = [
    {
      'name': 'Dr. Elena Rostova',
      'nexaId': 'NX-48A1-99XK',
      'type': 'Incoming Video',
      'duration': '14m 20s',
      'time': 'Today, 2:30 PM',
      'isVideo': true,
      'isMissed': false,
    },
    {
      'name': 'Rahul',
      'nexaId': 'NX-9B1D-84ZT',
      'type': 'Missed Audio',
      'duration': '0s',
      'time': 'Yesterday, 8:15 PM',
      'isVideo': false,
      'isMissed': true,
    },
    {
      'name': 'Maya Lin',
      'nexaId': 'NX-33E9-01QP',
      'type': 'Outgoing Video',
      'duration': '42m 10s',
      'time': 'Oct 5, 4:10 PM',
      'isVideo': true,
      'isMissed': false,
    },
    {
      'name': 'Vikram Malhotra',
      'nexaId': 'NX-883A-120P',
      'type': 'Outgoing Audio',
      'duration': '3m 40s',
      'time': 'Oct 4, 11:22 AM',
      'isVideo': false,
      'isMissed': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      body: SafeArea(
        child: Column(
          children: [
            // Active Tab Content
            Expanded(
              child: IndexedStack(
                index: _activeNav,
                children: [
                  _buildChatsTab(),
                  _buildCallsTab(),
                  const ExploreCommunitiesScreen(isEmbedded: true),
                  const PrivacyCenterScreen(isEmbedded: true),
                ],
              ),
            ),

            // Persistent Minimalist Focus Orbit Dock
            _buildOrbitDock(context),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: CHATS (FOCUS ORBIT DASHBOARD)
  // ==========================================
  Widget _buildChatsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),
        _buildQuietIntelligenceHeader(),
        const SizedBox(height: 16),
        _buildSearchBar(),
        const SizedBox(height: 20),
        _buildPriorityCard(context),
        const SizedBox(height: 24),
        _buildOverviewMetrics(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PRIORITY CHATS',
              style: TextStyle(
                color: NexaColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              '4 active',
              style: TextStyle(color: NexaColors.textMuted, fontSize: 12),
            ),
          ],
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
          name: 'Dr. Elena Rostova',
          nexaId: 'NX-48A1-99XK',
          message: 'Lab telemetry stream encrypted and verified. Review tomorrow?',
          time: '7:15 PM',
          unread: 1,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChatScreen(contactName: 'Dr. Elena Rostova', nexaId: 'NX-48A1-99XK'),
            ),
          ),
        ),
        _buildChatTile(
          name: 'Vikram Malhotra',
          nexaId: 'NX-883A-120P',
          message: 'ESP32 firmware OTA update successful.',
          time: 'Yesterday',
          unread: 0,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChatScreen(contactName: 'Vikram Malhotra', nexaId: 'NX-883A-120P'),
            ),
          ),
        ),
        _buildChatTile(
          name: 'Hardware Design Group',
          nexaId: 'NX-GRP-7721',
          message: 'Schematic review session scheduled for 4 PM.',
          time: 'Yesterday',
          unread: 0,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ChatScreen(contactName: 'Hardware Design Group', nexaId: 'NX-GRP-7721'),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQuietIntelligenceHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good evening, Karthik',
              style: TextStyle(
                color: NexaColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 14),
                SizedBox(width: 6),
                Text(
                  'Quiet Intelligence • Nothing urgent',
                  style: TextStyle(color: NexaColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 12),
              SizedBox(width: 4),
              Text(
                'E2EE Active',
                style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexaColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.search, color: NexaColors.textMuted, size: 18),
          SizedBox(width: 10),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NexaColors.primary.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: NexaColors.primary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: NexaColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PRIORITY CHAT',
                    style: TextStyle(
                      color: NexaColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const Text('8:44 PM', style: TextStyle(color: NexaColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Rahul',
            style: TextStyle(color: NexaColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            '"Yes, 10 AM sounds perfect. See you at the coffee shop! 👍"',
            style: TextStyle(color: NexaColors.textSecondary, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChatScreen(contactName: 'Rahul', nexaId: 'NX-9B1D-84ZT'),
                  ),
                ),
                icon: const Icon(Icons.reply, size: 15),
                label: const Text('Open Conversation'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reminder set for 10:00 AM tomorrow.'),
                      backgroundColor: Color(0xFF0F172A),
                    ),
                  );
                },
                icon: const Icon(Icons.alarm, color: NexaColors.amberAttention, size: 15),
                label: const Text('Remind Me'),
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
        const SizedBox(width: 10),
        _buildMetricItem('Calls', '1', Icons.phone_outlined),
        const SizedBox(width: 10),
        _buildMetricItem('Reminders', '2', Icons.notifications_none, highlight: true),
      ],
    );
  }

  Widget _buildMetricItem(String label, String count, IconData icon, {bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: NexaColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlight ? NexaColors.amberAttention.withValues(alpha: 0.35) : NexaColors.borderLight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: highlight ? NexaColors.amberAttention : NexaColors.textSecondary, size: 18),
            const SizedBox(height: 4),
            Text(
              count,
              style: TextStyle(
                color: highlight ? NexaColors.amberAttention : NexaColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NexaColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NexaColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: NexaColors.elevatedLight,
            child: Text(
              name.substring(0, 1),
              style: const TextStyle(color: NexaColors.primary, fontWeight: FontWeight.bold),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
              ),
              Text(time, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NexaColors.textSecondary, fontSize: 13),
            ),
          ),
          trailing: unread > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: const BoxDecoration(
                    color: NexaColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unread.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: DEDICATED CALLS TAB
  // ==========================================
  Widget _buildCallsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encrypted Calls',
                  style: TextStyle(
                    color: NexaColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Direct P2P • DTLS-SRTP Audio & Video',
                  style: TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'DTLS-SRTP',
                    style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Quick Call Actions
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ActiveCallScreen(
                      peerName: 'Rahul',
                      peerNexaId: 'NX-9B1D-84ZT',
                      isVideo: false,
                    ),
                  ),
                ),
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Start Voice Call'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ActiveCallScreen(
                      peerName: 'Dr. Elena Rostova',
                      peerNexaId: 'NX-48A1-99XK',
                      isVideo: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.videocam_outlined, size: 16),
                label: const Text('Start Video Call'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Create Link Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NexaColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexaColors.borderLight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NexaColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.link, color: NexaColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Encrypted Call Link',
                      style: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Anyone with this link can join zero-knowledge call',
                      style: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: 'https://nexa.im/call/room-zk-9182?token=e2ee-direct'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E2E Call Link copied to clipboard')),
                  );
                },
                child: const Text('Copy Link', style: TextStyle(color: NexaColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'RECENT CALLS',
          style: TextStyle(
            color: NexaColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),

        ..._callLogs.map((log) {
          final isMissed = log['isMissed'] as bool;
          final isVideo = log['isVideo'] as bool;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: NexaColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: NexaColors.borderLight),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: NexaColors.elevatedLight,
                  child: Icon(
                    isVideo ? Icons.videocam : Icons.phone,
                    color: isMissed ? NexaColors.rubyDestructive : NexaColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  log['name'] as String,
                  style: TextStyle(
                    color: isMissed ? NexaColors.rubyDestructive : NexaColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Icon(
                      isMissed
                          ? Icons.call_missed
                          : (isVideo ? Icons.videocam_outlined : Icons.call_made),
                      size: 13,
                      color: isMissed ? NexaColors.rubyDestructive : NexaColors.emeraldSecure,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${log['type']} • ${log['time']}',
                      style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: Icon(
                    isVideo ? Icons.videocam_outlined : Icons.phone_outlined,
                    color: NexaColors.primary,
                  ),
                  tooltip: 'Call back',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActiveCallScreen(
                        peerName: log['name'] as String,
                        peerNexaId: log['nexaId'] as String,
                        isVideo: isVideo,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ==========================================
  // BOTTOM FOCUS ORBIT DOCK
  // ==========================================
  Widget _buildOrbitDock(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: NexaColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDockButton(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble,
            label: 'Chats',
            index: 0,
          ),
          _buildDockButton(
            icon: Icons.call_outlined,
            activeIcon: Icons.call,
            label: 'Calls',
            index: 1,
          ),

          // Central Quiet Intelligence Assistant Orb
          GestureDetector(
            onTap: () => _openAssistantModal(context),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF38BDF8),
                    Color(0xFF0284C7),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: NexaColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            ),
          ),

          _buildDockButton(
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups,
            label: 'Communities',
            index: 2,
          ),
          _buildDockButton(
            icon: Icons.shield_outlined,
            activeIcon: Icons.shield,
            label: 'Security',
            index: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _activeNav == index;
    return InkWell(
      onTap: () => setState(() => _activeNav = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? NexaColors.primary : NexaColors.textMuted,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? NexaColors.primary : NexaColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAssistantModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
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
                      color: NexaColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: NexaColors.primary, size: 22),
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
                    const SnackBar(content: Text('Processing locally: 2 work groups, no urgent promises.')),
                  );
                },
              ),
              _buildAssistantOption(
                icon: Icons.alarm_add_outlined,
                title: 'Remind me: Call Dad tomorrow at 7 PM',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder scheduled for tomorrow 7:00 PM.')),
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
        color: NexaColors.elevatedLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: NexaColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: NexaColors.primary, size: 20),
          title: Text(title, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14)),
          trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted, size: 18),
          onTap: onTap,
        ),
      ),
    );
  }
}
