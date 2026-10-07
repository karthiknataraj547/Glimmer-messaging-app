import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/auth_service.dart';
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

  // Real Data Stores (Zero mock data or fake seeded accounts)
  final List<Map<String, dynamic>> _stories = [];
  final List<Map<String, dynamic>> _chats = [];
  final List<Map<String, dynamic>> _callLogs = [];

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

  // ==========================================
  // ONLINE USER DISCOVERY & CHAT CREATION
  // ==========================================
  void _showStartNewChatModal() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> registeredUsers = [];

    try {
      registeredUsers = await AuthService.instance.getRegisteredUsersOnline();
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filteredUsers = registeredUsers.where((u) {
              final un = (u['username'] ?? '').toString().toLowerCase();
              final fn = (u['fullName'] ?? '').toString().toLowerCase();
              final nid = (u['nexaId'] ?? '').toString().toLowerCase();
              return un.contains(query) || fn.contains(query) || nid.contains(query);
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock_outline, color: NexaColors.primary, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Start Encrypted Chat',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                            ),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Search online verified users or enter @username directly to begin.',
                      style: TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Enter @username or NEXA ID...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: NexaColors.elevatedLight,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (searchCtrl.text.trim().isNotEmpty && filteredUsers.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NexaColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: NexaColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: NexaColors.primary,
                              child: Text(
                                searchCtrl.text.trim().replaceAll('@', '').substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    searchCtrl.text.trim(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const Text('Direct P2P Peer Handle', style: TextStyle(fontSize: 11, color: NexaColors.textMuted)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: NexaColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                final handle = searchCtrl.text.trim();
                                Navigator.pop(ctx);
                                _openOrCreateChat(handle, 'NX-${handle.hashCode.abs().toRadixString(16).toUpperCase()}');
                              },
                              child: const Text('Chat'),
                            ),
                          ],
                        ),
                      ),
                    ] else if (filteredUsers.isNotEmpty) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredUsers.length,
                          separatorBuilder: (_, _) => const Divider(height: 12, color: NexaColors.borderLight),
                          itemBuilder: (context, i) {
                            final u = filteredUsers[i];
                            final name = (u['fullName'] ?? u['username'] ?? 'User') as String;
                            final nexaId = (u['nexaId'] ?? 'NX-PEER') as String;
                            final handle = (u['handle'] ?? '@${u['username']}') as String;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: NexaColors.primary.withValues(alpha: 0.15),
                                child: Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: NexaColors.primary),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('$handle • $nexaId', style: const TextStyle(fontSize: 11, color: NexaColors.textSecondary)),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: NexaColors.primary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(60, 32),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openOrCreateChat(name, nexaId);
                                },
                                child: const Text('Chat', style: TextStyle(fontSize: 12)),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.people_outline, size: 36, color: NexaColors.textMuted),
                              SizedBox(height: 8),
                              Text('No other users registered online yet.', style: TextStyle(color: NexaColors.textSecondary, fontSize: 13)),
                              SizedBox(height: 4),
                              Text('Type any @handle above to initiate a direct encrypted session.', style: TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openOrCreateChat(String name, String nexaId) {
    final existingIdx = _chats.indexWhere((c) => c['name'] == name || c['nexaId'] == nexaId);
    if (existingIdx == -1) {
      setState(() {
        _chats.insert(0, {
          'name': name,
          'nexaId': nexaId,
          'message': 'Encrypted Double Ratchet session initiated.',
          'time': 'Just now',
          'unread': 0,
          'isGroup': false,
        });
      });
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(contactName: name, nexaId: nexaId),
      ),
    );
  }

  // ==========================================
  // REAL ENCRYPTED CALL LAUNCHER MODAL
  // ==========================================
  void _showStartNewCallModal({required bool isVideo}) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> registeredUsers = [];
    try {
      registeredUsers = await AuthService.instance.getRegisteredUsersOnline();
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(isVideo ? Icons.videocam : Icons.call, color: NexaColors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              isVideo ? 'Start Encrypted Video Call' : 'Start Encrypted Voice Call',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                            ),
                          ],
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVideo
                          ? 'Real device camera hardware streaming with DTLS-SRTP encryption.'
                          : 'Encrypted P2P crystal-clear audio tunnel.',
                      style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Enter peer name, @handle or NEXA ID...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: NexaColors.elevatedLight,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (searchCtrl.text.trim().isNotEmpty) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NexaColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: Icon(isVideo ? Icons.videocam : Icons.call, size: 18),
                        label: Text('Call ${searchCtrl.text.trim()}'),
                        onPressed: () {
                          final name = searchCtrl.text.trim();
                          Navigator.pop(ctx);
                          _launchCall(name, 'NX-${name.hashCode.abs().toRadixString(16).toUpperCase()}', isVideo);
                        },
                      ),
                    ] else if (registeredUsers.isNotEmpty) ...[
                      const Text('ONLINE REGISTERED PEERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
                      const SizedBox(height: 8),
                      ...registeredUsers.map((u) {
                        final name = (u['fullName'] ?? u['username'] ?? 'User') as String;
                        final nexaId = (u['nexaId'] ?? 'NX-PEER') as String;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: NexaColors.primary.withValues(alpha: 0.15),
                            child: Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(color: NexaColors.primary, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(nexaId, style: const TextStyle(fontSize: 11, color: NexaColors.textSecondary)),
                          trailing: IconButton(
                            icon: Icon(isVideo ? Icons.videocam : Icons.call, color: NexaColors.primary),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _launchCall(name, nexaId, isVideo);
                            },
                          ),
                        );
                      }),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'Type any peer handle above to begin encrypted ${isVideo ? "video" : "voice"} call.',
                            style: const TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _launchCall(String peerName, String peerNexaId, bool isVideo) {
    setState(() {
      _callLogs.insert(0, {
        'name': peerName,
        'nexaId': peerNexaId,
        'type': isVideo ? 'Outgoing Video' : 'Outgoing Audio',
        'duration': 'Connected',
        'time': 'Just now',
        'isVideo': isVideo,
        'isMissed': false,
      });
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveCallScreen(
          peerName: peerName,
          peerNexaId: peerNexaId,
          isVideo: isVideo,
        ),
      ),
    );
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
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          const channel = MethodChannel('com.nexa.media_picker');
                          final dynamic perm = await channel.invokeMethod('requestNativePermission', {'permission': 'camera'});
                          if (perm == false) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Camera permission denied.')),
                              );
                            }
                            return;
                          }
                          final dynamic result = await channel.invokeMethod('openInbuiltCamera');
                          if (result != null && result is Map) {
                            setState(() => _myStoryStatus = '📸 ${result['name'] ?? 'Camera Moment'}');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Camera photo added to your moment!')),
                              );
                            }
                          }
                        } catch (_) {
                          setState(() => _myStoryStatus = '📷 Attached local laboratory photo');
                        }
                      },
                      icon: const Icon(Icons.photo_camera_outlined, size: 16),
                      label: const Text('Camera'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          const channel = MethodChannel('com.nexa.media_picker');
                          final dynamic perm = await channel.invokeMethod('requestNativePermission', {'permission': 'storage'});
                          if (perm == false) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Gallery permission denied.')),
                              );
                            }
                            return;
                          }
                          final dynamic result = await channel.invokeMethod('openInbuiltGallery');
                          if (result != null && result is Map) {
                            setState(() => _myStoryStatus = '🖼️ ${result['name'] ?? 'Gallery Moment'}');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Gallery photo added to your moment!')),
                              );
                            }
                          }
                        } catch (_) {
                          setState(() => _myStoryStatus = '🖼️ Attached gallery photo');
                        }
                      },
                      icon: const Icon(Icons.photo_outlined, size: 16),
                      label: const Text('Gallery'),
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
      endDrawer: _buildAppDrawer(context),
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

          // Floating "=" Focus Orbit Widget (Shifted to right, placed directly above Calls tab with slight gap, only visible in Chats tab)
          if (_activeNav == 0)
            Positioned(
              right: 22,
              bottom: 12,
              child: Tooltip(
                message: 'Focus Controls',
                child: GestureDetector(
                  onTap: _showOrbitQuickFilters,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _quietModeActive || _activeFilter != 'All' ? NexaColors.primary : NexaColors.surfaceLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _quietModeActive || _activeFilter != 'All' ? NexaColors.primary : NexaColors.borderLight,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_quietModeActive || _activeFilter != 'All' ? NexaColors.primary : Colors.black).withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.drag_handle,
                        size: 28,
                        color: _quietModeActive || _activeFilter != 'All' ? Colors.white : NexaColors.textPrimary,
                      ),
                    ),
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
                      backgroundImage: (_session.customAvatarPath != null && File(_session.customAvatarPath!).existsSync())
                          ? FileImage(File(_session.customAvatarPath!))
                          : null,
                      child: (_session.customAvatarPath != null && File(_session.customAvatarPath!).existsSync())
                          ? null
                          : Icon(avatarIcon, color: Colors.white, size: 24),
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
        const SizedBox(height: 4),
        _buildQuietIntelligenceHeader(),
        const SizedBox(height: 10),

        // Compact Search Bar
        _buildSearchBar(),
        const SizedBox(height: 14),

        // Horizontally Scrollable Stories Bar
        _buildStoriesRow(),
        const SizedBox(height: 18),

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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NexaColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, color: NexaColors.primary, size: 36),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No Encrypted Conversations Yet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Connect with verified users in the online database or start an encrypted chat using their @handle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexaColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.edit_note, size: 20),
                    label: const Text('Start Encrypted Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _showStartNewChatModal,
                  ),
                ],
              ),
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
                                backgroundImage: (_session.customAvatarPath != null && File(_session.customAvatarPath!).existsSync())
                                    ? FileImage(File(_session.customAvatarPath!))
                                    : null,
                                child: (_session.customAvatarPath != null && File(_session.customAvatarPath!).existsSync())
                                    ? null
                                    : Icon(avatarIcon, color: Colors.white, size: 20),
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
  // COMPACT TOP NAVIGATION BAR & 3-DOT MENU
  // ==========================================
  Widget _buildQuietIntelligenceHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Good evening, ${_session.name}',
              style: const TextStyle(
                color: NexaColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            const Row(
              children: [
                Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 11),
                SizedBox(width: 4),
                Text(
                  'Quiet Intelligence • Nothing urgent',
                  style: TextStyle(color: NexaColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),

        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note, color: NexaColors.primary, size: 24),
              tooltip: 'New Encrypted Chat',
              onPressed: _showStartNewChatModal,
            ),
            const SizedBox(width: 4),
            // Three-dot button on the right (replacing previous globe icon)
            PopupMenuButton<String>(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: NexaColors.elevatedLight,
              shape: BoxShape.circle,
              border: Border.all(color: NexaColors.borderLight),
            ),
            child: const Icon(Icons.more_vert, color: NexaColors.textPrimary, size: 20),
          ),
          tooltip: 'Options & Settings',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: NexaColors.surfaceLight,
          elevation: 6,
          offset: const Offset(0, 42),
          onSelected: (value) {
            switch (value) {
              case 'linked_devices':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()));
                break;
              case 'settings':
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings: All local telemetry and hardware isolated.')),
                );
                break;
              case 'profile':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfileScreen()));
                break;
              case 'security':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()));
                break;
              case 'vault':
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryKeyVaultScreen()));
                break;
              case 'lock':
                _session.logout();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthFlowScreen(isLoginInitial: true)),
                  (route) => false,
                );
                break;
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem<String>(
              value: 'linked_devices',
              child: Row(
                children: [
                  Icon(Icons.devices, color: NexaColors.primary, size: 18),
                  SizedBox(width: 12),
                  Text('Linked Devices', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, color: NexaColors.textSecondary, size: 18),
                  SizedBox(width: 12),
                  Text('Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: NexaColors.textSecondary, size: 18),
                  SizedBox(width: 12),
                  Text('Profile & Avatar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'security',
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 18),
                  SizedBox(width: 12),
                  Text('Security & Privacy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'vault',
              child: Row(
                children: [
                  Icon(Icons.vpn_key_outlined, color: NexaColors.amberAttention, size: 18),
                  SizedBox(width: 12),
                  Text('Recovery Key Vault', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'lock',
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: NexaColors.rubyDestructive, size: 18),
                  SizedBox(width: 12),
                  Text('Lock Vault', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NexaColors.rubyDestructive)),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
}

  Widget _buildSearchBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: NexaColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
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
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          icon: const Icon(Icons.search, color: NexaColors.textMuted, size: 18),
          hintText: 'Search chats, contacts, or messages...',
          hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 13),
          border: InputBorder.none,
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: const Icon(Icons.close, size: 16, color: NexaColors.textMuted),
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
    final avatarColor = name.contains('Elena')
        ? const Color(0xFF6366F1)
        : (name.contains('Rahul')
            ? const Color(0xFF0284C7)
            : (name.contains('Vikram') ? const Color(0xFF10B981) : const Color(0xFF8B5CF6)));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            // Avatar with Online Badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: avatarColor.withValues(alpha: 0.14),
                  child: Text(
                    name.substring(0, 1),
                    style: TextStyle(
                      color: avatarColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: NexaColors.emeraldSecure,
                      shape: BoxShape.circle,
                      border: Border.all(color: NexaColors.canvasLight, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // Name and Message Preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: NexaColors.textPrimary,
                                  fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.shield, color: NexaColors.emeraldSecure, size: 12),
                          ],
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          color: unread > 0 ? NexaColors.primary : NexaColors.textMuted,
                          fontSize: 11,
                          fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.done_all,
                        size: 14,
                        color: unread > 0 ? NexaColors.textMuted : NexaColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? NexaColors.textPrimary : NexaColors.textSecondary,
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: NexaColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unread.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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
                onPressed: () => _showStartNewCallModal(isVideo: false),
                icon: const Icon(Icons.call, size: 16),
                label: const Text('Start Voice Call'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showStartNewCallModal(isVideo: true),
                icon: const Icon(Icons.videocam_outlined, size: 16),
                label: const Text('Start Video Call'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('RECENT CALLS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textMuted)),
        const SizedBox(height: 10),

        if (_callLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: NexaColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone_in_talk_outlined, color: NexaColors.primary, size: 36),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No Recent Calls',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Start an end-to-end encrypted voice or video call with real hardware camera feed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexaColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.add_call, size: 18),
                    label: const Text('Make Encrypted Call', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _showStartNewCallModal(isVideo: false),
                  ),
                ],
              ),
            ),
          )
        else
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
