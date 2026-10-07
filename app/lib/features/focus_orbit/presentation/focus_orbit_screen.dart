import 'package:flutter/material.dart';
import '../../../core/session/user_session.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../auth/presentation/auth_flow_screen.dart';
import '../../auth/presentation/device_link_qr_screen.dart';
import '../../auth/presentation/recovery_key_vault_screen.dart';
import '../../calls/presentation/active_call_screen.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../communities/presentation/explore_communities_screen.dart';
import '../../posts/presentation/posts_feed_screen.dart';
import '../../privacy_center/presentation/privacy_center_screen.dart';
import '../../profile/presentation/user_profile_screen.dart';
import '../../stories/presentation/story_viewer_screen.dart';

class FocusOrbitScreen extends StatefulWidget {
  const FocusOrbitScreen({super.key});

  @override
  State<FocusOrbitScreen> createState() => _FocusOrbitScreenState();
}

class _FocusOrbitScreenState extends State<FocusOrbitScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final UserSession _session = UserSession.instance;

  int _activeNav = 0; // 0 = Chats, 1 = Posts, 2 = Communities, 3 = Calls
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeFilter = 'All'; // All, Direct, Groups, Unread
  bool _quietModeActive = false;
  String? _myStoryStatus;

  // Contact Stories Data
  final List<Map<String, dynamic>> _stories = [
    {
      'authorName': 'Dr. Elena Rostova',
      'authorNexaId': 'NX-48A1-99XK',
      'avatarColor': Color(0xFF0284C7),
      'hasStory': true,
      'slides': [
        {
          'content': 'Telemetric stream synced with edge sensor node 04. Zero packet loss on DTLS.',
          'tag': '#sensor-telemetry',
          'time': '25m ago',
          'icon': Icons.sensors,
        },
        {
          'content': 'Reviewing hardware crypto benchmarks before tomorrow\'s lab deployment.',
          'tag': '#hardware-security',
          'time': '10m ago',
          'icon': Icons.security,
        },
      ],
    },
    {
      'authorName': 'Rahul',
      'authorNexaId': 'NX-9B1D-84ZT',
      'avatarColor': Color(0xFFD97706),
      'hasStory': true,
      'slides': [
        {
          'content': 'Meeting at 10 AM coffee shop confirmed. Bringing the newly flashed firmware badge!',
          'tag': '#coffee-hack',
          'time': '1h ago',
          'icon': Icons.local_cafe,
        },
      ],
    },
    {
      'authorName': 'Maya Lin',
      'authorNexaId': 'NX-33E9-01QP',
      'avatarColor': Color(0xFF7C3AED),
      'hasStory': true,
      'slides': [
        {
          'content': 'Post-Quantum Double Ratchet paper manuscript accepted! Finalizing code release.',
          'tag': '#quantum-e2ee',
          'time': '3h ago',
          'icon': Icons.hub,
        },
      ],
    },
    {
      'authorName': 'Vikram Malhotra',
      'authorNexaId': 'NX-883A-120P',
      'avatarColor': Color(0xFF059669),
      'hasStory': true,
      'slides': [
        {
          'content': 'PCB revision v2 assembled. 4-layer impedance matched for RF transceiver.',
          'tag': '#hardware-pcb',
          'time': '4h ago',
          'icon': Icons.memory,
        },
      ],
    },
    {
      'authorName': 'Alex Rivera',
      'authorNexaId': 'NX-11E2-55TA',
      'avatarColor': Color(0xFFE11D48),
      'hasStory': true,
      'slides': [
        {
          'content': 'Quantized SLM running offline at 50 t/s on mobile NPU. No network permissions.',
          'tag': '#local-ai',
          'time': '6h ago',
          'icon': Icons.smart_toy,
        },
      ],
    },
  ];

  // Conversations Data
  final List<Map<String, dynamic>> _chats = [
    {
      'name': 'Rahul',
      'nexaId': 'NX-9B1D-84ZT',
      'message': 'Yes, 10 AM sounds perfect. See you at the coffee shop! 👍',
      'time': '8:44 PM',
      'unread': 0,
      'isGroup': false,
    },
    {
      'name': 'Dr. Elena Rostova',
      'nexaId': 'NX-48A1-99XK',
      'message': 'Lab telemetry stream encrypted and verified. Review tomorrow?',
      'time': '7:15 PM',
      'unread': 1,
      'isGroup': false,
    },
    {
      'name': 'Hardware Design Group',
      'nexaId': 'NX-GRP-7721',
      'message': 'Schematic review session scheduled for 4 PM.',
      'time': 'Yesterday',
      'unread': 0,
      'isGroup': true,
    },
    {
      'name': 'Vikram Malhotra',
      'nexaId': 'NX-883A-120P',
      'message': 'ESP32 firmware OTA update successful.',
      'time': 'Yesterday',
      'unread': 0,
      'isGroup': false,
    },
  ];

  // Call Logs
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
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _showAddStoryModal() {
    final TextEditingController storyTextController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Post an Encrypted Moment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Disappears in 24 hours. Shared strictly with your pairwise contacts.',
                  style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: storyTextController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'What are you working on or building today?',
                    filled: true,
                    fillColor: NexaColors.elevatedLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _myStoryStatus = '📷 Attached local laboratory photo');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Photo moment uploaded & encrypted!')),
                        );
                      },
                      icon: const Icon(Icons.photo_camera_outlined, size: 16),
                      label: const Text('Add Photo'),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        final text = storyTextController.text.trim();
                        if (text.isEmpty) return;
                        setState(() => _myStoryStatus = text);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Your moment is live and end-to-end encrypted!')),
                        );
                      },
                      child: const Text('Share Moment'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOrbitQuickFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune, color: NexaColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text('Focus Orbit Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.nightlight_round, color: NexaColors.primary),
                      title: const Text('Quiet Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Silences all non-priority background pings'),
                      value: _quietModeActive,
                      onChanged: (val) {
                        setState(() => _quietModeActive = val);
                        setModalState(() {});
                      },
                    ),
                    const Divider(height: 16, color: NexaColors.borderLight),
                    const Text('FILTER BY STREAM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['All', 'Direct', 'Groups', 'Unread'].map((filter) {
                        final isSel = _activeFilter == filter;
                        return ChoiceChip(
                          label: Text(filter),
                          selected: isSel,
                          selectedColor: NexaColors.primary,
                          backgroundColor: NexaColors.elevatedLight,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : NexaColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          onSelected: (_) {
                            setState(() => _activeFilter = filter);
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: NexaColors.canvasLight,
      drawer: _buildAppDrawer(context),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _activeNav,
              children: [
                _buildChatsTab(),
                const PostsFeedScreen(isEmbedded: true),
                const ExploreCommunitiesScreen(isEmbedded: true),
                _buildCallsTab(),
              ],
            ),
          ),

          // Floating Bottom-Left "=" Widget
          Positioned(
            left: 20,
            bottom: 82,
            child: GestureDetector(
              onTap: _showOrbitQuickFilters,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _quietModeActive || _activeFilter != 'All' ? NexaColors.primary : NexaColors.surfaceLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _quietModeActive || _activeFilter != 'All' ? NexaColors.primary : NexaColors.borderLight,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.menu,
                  size: 20,
                  color: _quietModeActive || _activeFilter != 'All' ? Colors.white : NexaColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildOrbitDock(context),
      ),
    );
  }

  // ==========================================
  // SIDE DRAWER (TOP MENU DROPDOWN)
  // ==========================================
  Widget _buildAppDrawer(BuildContext context) {
    final avatarColor = _session.currentAvatarPreset['color'] as Color;
    final avatarIcon = _session.currentAvatarPreset['icon'] as IconData;

    return Drawer(
      backgroundColor: NexaColors.surfaceLight,
      child: SafeArea(
        child: Column(
          children: [
            // User Profile Header in Drawer
            InkWell(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfileScreen()));
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: NexaColors.borderLight)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: avatarColor,
                      child: Icon(avatarIcon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _session.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.edit, size: 14, color: NexaColors.textMuted),
                            ],
                          ),
                          Text(
                            _session.handle,
                            style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _session.nexaId,
                            style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: NexaColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Security & Privacy Center (Shifted here from bottom nav!)
                  ListTile(
                    leading: const Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure),
                    title: const Text('Security & Privacy Center', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Zero-knowledge & hardware isolation', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()));
                    },
                  ),

                  // Linked Devices
                  ListTile(
                    leading: const Icon(Icons.devices, color: NexaColors.primary),
                    title: const Text('Linked Devices', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Authorize desktop & secondary phones', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()));
                    },
                  ),

                  // Recovery Key Vault
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined, color: NexaColors.amberAttention),
                    title: const Text('Recovery Key Vault', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('24-word self-sovereign seed', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryKeyVaultScreen()));
                    },
                  ),

                  // Profile Settings
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: NexaColors.textSecondary),
                    title: const Text('Profile & Avatar', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Edit name, photo, and bio', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfileScreen()));
                    },
                  ),

                  const Divider(color: NexaColors.borderLight),

                  // Settings / Preferences
                  ListTile(
                    leading: const Icon(Icons.settings_outlined, color: NexaColors.textSecondary),
                    title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Notifications, chats & telemetry', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings: All telemetry hardware isolated.')),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Bottom Logout / Lock Vault Option
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: NexaColors.borderLight)),
              ),
              child: ListTile(
                leading: const Icon(Icons.lock_outline, color: NexaColors.rubyDestructive),
                title: const Text('Lock Vault / Switch Account', style: TextStyle(fontWeight: FontWeight.bold, color: NexaColors.rubyDestructive)),
                onTap: () {
                  Navigator.pop(context);
                  _session.logout();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthFlowScreen(isLoginInitial: true)),
                    (route) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 0: CHATS (WITH STORIES & SEARCH)
  // ==========================================
  Widget _buildChatsTab() {
    final filtered = _chats.where((c) {
      final name = (c['name'] as String).toLowerCase();
      final msg = (c['message'] as String).toLowerCase();
      final matchesQuery = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase()) || msg.contains(_searchQuery.toLowerCase());
      if (!matchesQuery) return false;
      if (_activeFilter == 'Direct' && (c['isGroup'] as bool)) return false;
      if (_activeFilter == 'Groups' && !(c['isGroup'] as bool)) return false;
      if (_activeFilter == 'Unread' && (c['unread'] as int) == 0) return false;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 10),
        _buildQuietIntelligenceHeader(),
        const SizedBox(height: 14),

        // Search Bar
        _buildSearchBar(),
        const SizedBox(height: 16),

        // Horizontally Scrollable Stories Bar
        _buildStoriesRow(),
        const SizedBox(height: 20),

        // Priority Pulse Card
        _buildPriorityCard(context),
        const SizedBox(height: 20),

        // Overview Metrics
        _buildOverviewMetrics(),
        const SizedBox(height: 22),

        // Priority Chats Header with Active Filter Indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
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
                if (_activeFilter != 'All') ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexaColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_activeFilter, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: NexaColors.primary)),
                  ),
                ],
              ],
            ),
            Text(
              '${filtered.length} active',
              style: const TextStyle(color: NexaColors.textMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('No conversations match your filter.', style: TextStyle(color: NexaColors.textMuted)),
            ),
          )
        else
          ...filtered.map((chat) {
            return _buildChatTile(
              name: chat['name'] as String,
              nexaId: chat['nexaId'] as String,
              message: chat['message'] as String,
              time: chat['time'] as String,
              unread: chat['unread'] as int,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(contactName: chat['name'] as String, nexaId: chat['nexaId'] as String),
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==========================================
  // STORIES HORIZONTAL ROW
  // ==========================================
  Widget _buildStoriesRow() {
    final avatarColor = _session.currentAvatarPreset['color'] as Color;
    final avatarIcon = _session.currentAvatarPreset['icon'] as IconData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 94,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _stories.length + 1,
            itemBuilder: (context, idx) {
              if (idx == 0) {
                // "Your Story" item
                final hasMyStory = _myStoryStatus != null;
                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: hasMyStory
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StoryViewerScreen(
                                  authorName: 'Your Moment',
                                  authorNexaId: _session.nexaId,
                                  themeColor: avatarColor,
                                  slides: [
                                    {
                                      'content': _myStoryStatus!,
                                      'tag': '#my-moment',
                                      'time': 'Just now',
                                      'icon': Icons.person,
                                    },
                                  ],
                                ),
                              ),
                            );
                          }
                        : _showAddStoryModal,
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: hasMyStory ? NexaColors.primary : NexaColors.borderLight,
                                  width: hasMyStory ? 2.5 : 1,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: avatarColor,
                                child: Icon(avatarIcon, color: Colors.white, size: 20),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: NexaColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(hasMyStory ? Icons.check : Icons.add, color: Colors.white, size: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Your Story',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: NexaColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Contact Story Item
              final story = _stories[idx - 1];
              final authorName = story['authorName'] as String;
              final color = story['avatarColor'] as Color;

              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StoryViewerScreen(
                          authorName: authorName,
                          authorNexaId: story['authorNexaId'] as String,
                          themeColor: color,
                          slides: (story['slides'] as List<dynamic>).cast<Map<String, dynamic>>(),
                        ),
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2.2),
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Text(
                            authorName.substring(0, 1),
                            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        authorName.split(' ')[0],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: NexaColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // QUIET INTELLIGENCE TOP BAR WITH 3-LINE MENU
  // ==========================================
  Widget _buildQuietIntelligenceHeader() {
    final avatarColor = _session.currentAvatarPreset['color'] as Color;
    final avatarIcon = _session.currentAvatarPreset['icon'] as IconData;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            // Three-line button to open drawer
            IconButton(
              icon: const Icon(Icons.menu, color: NexaColors.textPrimary, size: 26),
              tooltip: 'Navigation Menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good evening, ${_session.name}',
                  style: const TextStyle(
                    color: NexaColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'Quiet Intelligence • Nothing urgent',
                      style: TextStyle(color: NexaColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // User Profile Picture in Top Bar (Click opens Profile Screen!)
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserProfileScreen()),
          ),
          child: Tooltip(
            message: 'View & Edit Profile',
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: NexaColors.primary, width: 2),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: avatarColor,
                child: Icon(avatarIcon, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexaColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: NexaColors.textMuted, size: 20),
          hintText: 'Search chats, contacts, or messages...',
          hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
          border: InputBorder.none,
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
        ),
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
        _buildMetricItem('Chats', '${_chats.length}', Icons.chat_bubble_outline),
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
  // TAB 3: DEDICATED CALLS TAB
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
                  Text('DTLS-SRTP', style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

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
        const SizedBox(height: 24),
        const Text('RECENT CALLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
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
                subtitle: Text(
                  '${log['type']} • ${log['time']}',
                  style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: Icon(isVideo ? Icons.videocam_outlined : Icons.phone_outlined, color: NexaColors.primary),
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
  // UPDATED BOTTOM DOCK (POSTS INCLUDED, SECURITY IN TOP BAR)
  // ==========================================
  Widget _buildOrbitDock(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      height: 64,
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: NexaColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _buildDockButton(
              icon: Icons.chat_bubble_outline,
              activeIcon: Icons.chat_bubble,
              label: 'Chats',
              index: 0,
            ),
          ),
          Expanded(
            child: _buildDockButton(
              icon: Icons.article_outlined,
              activeIcon: Icons.article,
              label: 'Posts',
              index: 1,
            ),
          ),

          // Central Quiet Intelligence Assistant Orb
          GestureDetector(
            onTap: () => _openAssistantModal(context),
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 4),
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
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
          ),

          Expanded(
            child: _buildDockButton(
              icon: Icons.groups_outlined,
              activeIcon: Icons.groups,
              label: 'Community',
              index: 2,
            ),
          ),
          Expanded(
            child: _buildDockButton(
              icon: Icons.call_outlined,
              activeIcon: Icons.call,
              label: 'Calls',
              index: 3,
            ),
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
      borderRadius: BorderRadius.circular(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? NexaColors.primary : NexaColors.textMuted,
              size: 22,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? NexaColors.primary : NexaColors.textMuted,
                  letterSpacing: -0.1,
                ),
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
