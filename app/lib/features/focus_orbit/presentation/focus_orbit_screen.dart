import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/session/user_session.dart';
import '../../../core/services/contacts_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/update_engine.dart';
import '../../auth/presentation/device_link_qr_screen.dart';
import '../../auth/presentation/recovery_key_vault_screen.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../privacy_center/presentation/privacy_center_screen.dart';
import '../../auth/presentation/auth_flow_screen.dart';

class FocusOrbitScreen extends StatefulWidget {
  const FocusOrbitScreen({super.key});

  @override
  State<FocusOrbitScreen> createState() => _FocusOrbitScreenState();
}

class _FocusOrbitScreenState extends State<FocusOrbitScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final UserSession _session = UserSession.instance;

  int _activeNav = 0; // 0 = Chats, 1 = Contacts, 2 = Calls, 3 = Settings

  // Chats
  final List<Map<String, dynamic>> _chats = [];
  Timer? _inboxSyncTimer;
  final TextEditingController _chatSearchController = TextEditingController();
  String _chatSearchQuery = '';

  // Contacts
  List<Map<String, dynamic>> _deviceContacts = [];
  List<Map<String, dynamic>> _directoryUsers = [];
  bool _isLoadingContacts = false;
  int _activeContactsTab = 0; // 0 = On NEXA, 1 = All Contacts, 2 = ID Search
  final TextEditingController _contactsSearchController = TextEditingController();
  String _contactsSearchQuery = '';

  // Calls
  final List<Map<String, dynamic>> _callLogs = [];

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);

    // 1. Initial message sync & periodic background polling
    _syncInbox();
    _inboxSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncInbox());

    // 2. Start global real-time call invitation listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallService.instance.startListening(context);
      UpdateEngine.instance.checkForUpdate(context);
      _loadContacts();
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _inboxSyncTimer?.cancel();
    CallService.instance.stopListening();
    _chatSearchController.dispose();
    _contactsSearchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  /// Synchronize incoming chat messages from server relay
  Future<void> _syncInbox() async {
    if (!mounted || !_session.isLoggedIn) return;
    try {
      final messages = await ChatService.instance.fetchInbox();
      if (messages.isEmpty) return;

      bool changed = false;
      for (final msg in messages) {
        final senderHandle = (msg['sender_handle'] as String?) ?? 'Peer';
        final senderNexaId = (msg['sender_nexa_id'] as String?) ?? 'NX-${senderHandle.toUpperCase()}';
        final text = (msg['text'] as String?) ?? 'Encrypted Memo';
        final ts = (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        final timeStr = _formatTimestamp(ts);

        final idx = _chats.indexWhere((c) {
          final n = (c['name'] as String).toLowerCase();
          final id = (c['nexaId'] as String).toLowerCase();
          return n == senderHandle.toLowerCase() ||
              n == '@${senderHandle.toLowerCase()}' ||
              id == senderNexaId.toLowerCase();
        });

        if (idx >= 0) {
          if (_chats[idx]['message'] != text) {
            _chats[idx]['message'] = text;
            _chats[idx]['time'] = timeStr;
            _chats[idx]['unread'] = ((_chats[idx]['unread'] as int?) ?? 0) + 1;
            final item = _chats.removeAt(idx);
            _chats.insert(0, item);
            changed = true;
          }
        } else {
          _chats.insert(0, {
            'name': '@$senderHandle',
            'nexaId': senderNexaId,
            'message': text,
            'time': timeStr,
            'unread': 1,
          });
          changed = true;
        }
      }

      if (changed && mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  /// Load device contacts and online user directory
  Future<void> _loadContacts() async {
    if (!mounted) return;
    setState(() => _isLoadingContacts = true);

    try {
      // Fetch online directory
      final onlineUsers = await AuthService.instance.getRegisteredUsersOnline();
      _directoryUsers = onlineUsers;

      // Fetch device contacts
      final rawDevice = await ContactsService.instance.fetchDeviceContacts();
      _deviceContacts = ContactsService.instance.correlateContactsWithRegistered(rawDevice, onlineUsers);
    } catch (e) {
      debugPrint('[FocusOrbit] Contacts loading error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingContacts = false);
    }
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${dt.month}/${dt.day}';
  }

  void _openChat(String contactName, String nexaId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: contactName,
          nexaId: nexaId,
        ),
      ),
    );
  }

  void _startCall({required String contactName, required String nexaId, required bool isVideo}) {
    // Record to local call logs
    setState(() {
      _callLogs.insert(0, {
        'name': contactName,
        'nexaId': nexaId,
        'isVideo': isVideo,
        'isOutgoing': true,
        'time': 'Just now',
      });
    });

    CallService.instance.initiateCall(
      context: context,
      recipientHandle: contactName,
      recipientNexaId: nexaId,
      peerName: contactName,
      isVideo: isVideo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF090D16),
      drawer: _buildModernDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Minimalist Top App Bar
            _buildMinimalistTopBar(),

            // Screen Content
            Expanded(
              child: IndexedStack(
                index: _activeNav,
                children: [
                  _buildChatsView(),
                  _buildContactsView(),
                  _buildCallsView(),
                  _buildSettingsView(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildModernBottomBar(),
      floatingActionButton: _activeNav == 0
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: _showNewChatDialog,
              child: const Icon(Icons.add_comment_rounded, size: 24),
            )
          : null,
    );
  }

  // =====================================================================
  // 1. MINIMALIST TOP APP BAR
  // =====================================================================
  Widget _buildMinimalistTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              const SizedBox(width: 14),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E5FF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8, spreadRadius: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'NEXA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // User handle chip with green online dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x26FFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _session.handle.isNotEmpty ? _session.handle : '@user',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 2. TAB 0: CHATS VIEW
  // =====================================================================
  Widget _buildChatsView() {
    final filtered = _chats.where((c) {
      if (_chatSearchQuery.isEmpty) return true;
      final q = _chatSearchQuery.toLowerCase();
      final n = (c['name'] as String).toLowerCase();
      final m = (c['message'] as String).toLowerCase();
      return n.contains(q) || m.contains(q);
    }).toList();

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: TextField(
            controller: _chatSearchController,
            onChanged: (val) => setState(() => _chatSearchQuery = val),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search encrypted conversations...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 18),
              filled: true,
              fillColor: const Color(0xFF111827),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
              ),
            ),
          ),
        ),

        // Chat List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 36),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Encrypted Conversations Yet',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Start a chat from Contacts or search any peer by NEXA ID.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.person_search, size: 16),
                        label: const Text('Find Peer by NEXA ID'),
                        onPressed: _showNewChatDialog,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final name = (item['name'] as String?) ?? 'Peer';
                    final msg = (item['message'] as String?) ?? '';
                    final time = (item['time'] as String?) ?? '';
                    final unread = (item['unread'] as int?) ?? 0;
                    final nexaId = (item['nexaId'] as String?) ?? 'NX-PEER';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      onTap: () => _openChat(name, nexaId),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFF1E293B),
                        child: Text(
                          name.isNotEmpty ? name.replaceAll('@', '').substring(0, 1).toUpperCase() : '?',
                          style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(time, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                        ],
                      ),
                      subtitle: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              msg,
                              style: TextStyle(
                                color: unread > 0 ? Colors.white : const Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =====================================================================
  // 3. TAB 1: CONTACTS VIEW (DEVICE CONTACTS & ONLINE DIRECTORY)
  // =====================================================================
  Widget _buildContactsView() {
    return Column(
      children: [
        // Top Segmented Bar: [On NEXA] | [Device Contacts] | [Find by ID]
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              children: [
                _buildSegmentButton('On NEXA', 0),
                _buildSegmentButton('Device Contacts', 1),
                _buildSegmentButton('Directory', 2),
              ],
            ),
          ),
        ),

        // Search + Sync Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _contactsSearchController,
                  onChanged: (val) => setState(() => _contactsSearchQuery = val),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _activeContactsTab == 2 ? 'Search by NEXA ID or @handle...' : 'Filter contacts...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 16),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isLoadingContacts
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                    : const Icon(Icons.sync, color: Color(0xFF00E5FF), size: 22),
                tooltip: 'Sync Device Contacts',
                onPressed: _isLoadingContacts ? null : _loadContacts,
              ),
            ],
          ),
        ),

        // Contacts List
        Expanded(
          child: _isLoadingContacts
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                      SizedBox(height: 12),
                      Text('Accessing device contacts...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    ],
                  ),
                )
              : _buildContactsListContent(),
        ),
      ],
    );
  }

  Widget _buildSegmentButton(String label, int index) {
    final isSelected = _activeContactsTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeContactsTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)) : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsListContent() {
    final query = _contactsSearchQuery.toLowerCase();

    if (_activeContactsTab == 0) {
      // TAB 0: On NEXA (Matched device contacts + Directory registered peers)
      final onNexa = [
        ..._deviceContacts.where((c) => c['isOnNexa'] == true),
        ..._directoryUsers.where((u) => (u['username'] ?? '') != _session.username).map((u) => {
          'name': u['full_name'] ?? u['fullName'] ?? u['username'],
          'handle': u['handle'] ?? '@${u['username']}',
          'phone': u['phone'] ?? '',
          'nexaId': u['nexa_id'] ?? u['nexaId'] ?? 'NX-USER',
          'isOnNexa': true,
        }),
      ].where((c) {
        if (query.isEmpty) return true;
        final name = (c['name'] ?? '').toString().toLowerCase();
        final handle = (c['handle'] ?? '').toString().toLowerCase();
        final nid = (c['nexaId'] ?? '').toString().toLowerCase();
        return name.contains(query) || handle.contains(query) || nid.contains(query);
      }).toList();

      if (onNexa.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.group_outlined, color: Color(0xFF64748B), size: 36),
              const SizedBox(height: 12),
              const Text('No NEXA peers found in address book', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Switch to "Device Contacts" or "Directory" to find users.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF111827)),
                onPressed: () => setState(() => _activeContactsTab = 2),
                child: const Text('Browse Directory'),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: onNexa.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
        itemBuilder: (context, i) {
          final item = onNexa[i];
          final name = (item['name'] ?? 'Peer').toString();
          final handle = (item['handle'] ?? '@${item['username'] ?? name}').toString();
          final nexaId = (item['nexaId'] ?? 'NX-PEER').toString();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('$handle • $nexaId', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 20),
                  tooltip: 'Chat',
                  onPressed: () => _openChat(handle, nexaId),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: Color(0xFF10B981), size: 20),
                  tooltip: 'Voice Call',
                  onPressed: () => _startCall(contactName: name, nexaId: nexaId, isVideo: false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: Color(0xFF00E5FF), size: 20),
                  tooltip: 'Video Call',
                  onPressed: () => _startCall(contactName: name, nexaId: nexaId, isVideo: true),
                ),
              ],
            ),
          );
        },
      );
    } else if (_activeContactsTab == 1) {
      // TAB 1: ALL DEVICE CONTACTS
      final list = _deviceContacts.where((c) {
        if (query.isEmpty) return true;
        final name = (c['name'] ?? '').toString().toLowerCase();
        final phone = (c['phone'] ?? '').toString().toLowerCase();
        return name.contains(query) || phone.contains(query);
      }).toList();

      if (list.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.contact_phone_outlined, color: Color(0xFF64748B), size: 36),
              const SizedBox(height: 12),
              Text(
                kIsWeb ? 'Device Address Book on Mobile Devices' : 'No Contacts Detected',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  kIsWeb
                      ? 'Native contacts are fetched on mobile devices. Use Directory search to find peers.'
                      : 'Ensure address book permission is granted in Android system settings.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Request Permission & Refresh'),
                onPressed: _loadContacts,
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
        itemBuilder: (context, i) {
          final item = list[i];
          final name = (item['name'] ?? 'Contact').toString();
          final phone = (item['phone'] ?? '').toString();
          final isOnNexa = item['isOnNexa'] == true;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: isOnNexa ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF1E293B),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(color: isOnNexa ? const Color(0xFF10B981) : Colors.white60, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(phone, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            trailing: isOnNexa
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('ON NEXA', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(
                        text: 'Connect with me on NEXA: https://glimmer-messaging-app-web.vercel.app/',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('NEXA invite link copied to clipboard!')),
                      );
                    },
                    child: const Text('Invite', style: TextStyle(fontSize: 11)),
                  ),
          );
        },
      );
    } else {
      // TAB 2: DIRECTORY / NEXA ID SEARCH
      final list = _directoryUsers.where((u) {
        if (query.isEmpty) return true;
        final un = (u['username'] ?? '').toString().toLowerCase();
        final fn = (u['full_name'] ?? u['fullName'] ?? '').toString().toLowerCase();
        final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
        return un.contains(query) || fn.contains(query) || nid.contains(query);
      }).toList();

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
        itemBuilder: (context, i) {
          final u = list[i];
          final un = (u['username'] ?? '').toString();
          final fn = (u['full_name'] ?? u['fullName'] ?? un).toString();
          final nid = (u['nexa_id'] ?? u['nexaId'] ?? 'NX-USER').toString();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              child: Text(
                fn.isNotEmpty ? fn.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(fn, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('@$un • $nid', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 18),
                  onPressed: () => _openChat('@$un', nid),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: Color(0xFF10B981), size: 18),
                  onPressed: () => _startCall(contactName: fn, nexaId: nid, isVideo: false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: Color(0xFF00E5FF), size: 18),
                  onPressed: () => _startCall(contactName: fn, nexaId: nid, isVideo: true),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  // =====================================================================
  // 4. TAB 2: CALLS LOG VIEW
  // =====================================================================
  Widget _buildCallsView() {
    if (_callLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Call History',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start end-to-end encrypted voice and video calls with any peer.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      itemCount: _callLogs.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
      itemBuilder: (context, i) {
        final log = _callLogs[i];
        final name = (log['name'] ?? 'Peer').toString();
        final nexaId = (log['nexaId'] ?? 'NX-PEER').toString();
        final isVideo = log['isVideo'] == true;
        final time = (log['time'] ?? 'Recent').toString();

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1E293B),
            child: Icon(
              isVideo ? Icons.videocam : Icons.call,
              color: isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
              size: 20,
            ),
          ),
          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Row(
            children: [
              const Icon(Icons.call_made, color: Color(0xFF10B981), size: 12),
              const SizedBox(width: 4),
              Text(
                '${isVideo ? 'Video' : 'Voice'} Call • $time',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              isVideo ? Icons.videocam : Icons.call,
              color: isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
            ),
            tooltip: 'Call back',
            onPressed: () => _startCall(contactName: name, nexaId: nexaId, isVideo: isVideo),
          ),
        );
      },
    );
  }

  // =====================================================================
  // 5. TAB 3: SETTINGS & UPDATE ENGINE VIEW
  // =====================================================================
  Widget _buildSettingsView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      children: [
        // User Profile Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                child: Text(
                  _session.username.isNotEmpty ? _session.username.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _session.fullName.isNotEmpty ? _session.fullName : _session.username,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _session.handle,
                      style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _session.nexaId,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'Courier'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // In-App Update Engine Tile
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.system_update_alt, color: Color(0xFF00E5FF), size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Application Update Engine',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Text('v1.2.0 (Build 4)', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'NEXA autonomously checks for server releases, security patches, and calling engine updates.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Check for Updates Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => UpdateEngine.instance.openUpdateCenter(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Security & Vault Settings
        Material(
          color: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x1AFFFFFF)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.security, color: Color(0xFF10B981)),
                title: const Text('Zero-Knowledge Security', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Double Ratchet • X3DH • AES-256-GCM', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen())),
              ),
              const Divider(height: 1, color: Color(0x0FFFFFFF)),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B)),
                title: const Text('Recovery Key Vault', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('24-word self-sovereign seed', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryKeyVaultScreen())),
              ),
              const Divider(height: 1, color: Color(0x0FFFFFFF)),
              ListTile(
                leading: const Icon(Icons.devices, color: Color(0xFF00E5FF)),
                title: const Text('Linked Devices', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Authorize secondary devices', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Logout Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: const Color(0xFFEF4444),
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Lock Vault & Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () {
            _session.logout();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AuthFlowScreen(isLoginInitial: true)),
              (route) => false,
            );
          },
        ),
      ],
    );
  }

  // =====================================================================
  // 6. MODERN BOTTOM NAVIGATION BAR
  // =====================================================================
  Widget _buildModernBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: BottomNavigationBar(
        currentIndex: _activeNav,
        onTap: (index) => setState(() => _activeNav = index),
        backgroundColor: const Color(0xFF090D16),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: const Color(0xFF64748B),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.phone_outlined),
            activeIcon: Icon(Icons.phone),
            label: 'Calls',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune_outlined),
            activeIcon: Icon(Icons.tune),
            label: 'Vault',
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 7. NEW CHAT & NEXA ID SERVICING MODAL
  // =====================================================================
  void _showNewChatDialog() {
    final textCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
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
                  const Text(
                    'Start Encrypted Conversation',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the peer\'s unique NEXA ID (e.g. NX-C53E-AEE9) or @username to begin end-to-end encrypted messaging.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. @alice or NX-C53E-AEE9',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final input = textCtrl.text.trim();
                  if (input.isEmpty) return;
                  Navigator.pop(ctx);
                  final name = input.startsWith('@') ? input : '@$input';
                  final nexaId = input.startsWith('NX-') ? input : 'NX-${input.replaceAll('@', '').toUpperCase()}';
                  _openChat(name, nexaId);
                },
                child: const Text('Open Chat Channel', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF090D16),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    child: Text(
                      _session.username.isNotEmpty ? _session.username.substring(0, 1).toUpperCase() : '?',
                      style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_session.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(_session.handle, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF)),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF10B981)),
              title: const Text('Privacy Center', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices, color: Color(0xFF00E5FF)),
              title: const Text('Linked Devices', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_alt, color: Color(0xFFF59E0B)),
              title: const Text('App Update Engine', style: TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                UpdateEngine.instance.openUpdateCenter(context);
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
              title: const Text('Lock Vault', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14)),
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
