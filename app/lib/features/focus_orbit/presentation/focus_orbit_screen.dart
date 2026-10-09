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

    // 0. Load cached recent chats for instant offline render
    _loadCachedChats();

    // 1. Initial message sync & high-speed periodic background polling (1500ms for fast delivery)
    _syncInbox();
    _inboxSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _syncInbox());

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

  /// Instant cached recent chats restore
  Future<void> _loadCachedChats() async {
    final cached = await ChatService.instance.loadRecentChats();
    if (cached.isNotEmpty && mounted && _chats.isEmpty) {
      setState(() {
        _chats.addAll(cached);
      });
    }
  }

  /// Synchronize incoming chat messages from server relay
  Future<void> _syncInbox() async {
    if (!mounted || !_session.isLoggedIn) return;
    try {
      final messages = await ChatService.instance.fetchInbox();
      if (messages.isEmpty) return;

      final myHandle = UserSession.instance.handle.replaceAll('@', '').toLowerCase();
      final myNexaId = UserSession.instance.nexaId.toLowerCase();

      // Group incoming messages by sender
      final Map<String, List<Map<String, dynamic>>> bySender = {};
      for (final msg in messages) {
        final senderHandle = ((msg['sender_handle'] as String?) ?? '').replaceAll('@', '').toLowerCase();
        final senderNexaId = ((msg['sender_nexa_id'] as String?) ?? '').toLowerCase();
        // Ignore messages sent by me
        if (senderHandle == myHandle || (myNexaId.isNotEmpty && (senderHandle == myNexaId || senderNexaId == myNexaId))) {
          continue;
        }
        final peerKey = senderNexaId.isNotEmpty ? senderNexaId : senderHandle;
        if (peerKey.isEmpty) continue;
        bySender.putIfAbsent(peerKey, () => []).add(msg);
      }

      bool changed = false;
      for (final entry in bySender.entries) {
        final peerMessages = entry.value;
        if (peerMessages.isEmpty) continue;
        // Sort ascending by timestamp
        peerMessages.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
        final lastMsg = peerMessages.last;

        final senderHandle = (lastMsg['sender_handle'] as String?) ?? 'Peer';
        final senderNexaId = (lastMsg['sender_nexa_id'] as String?) ?? 'NX-${senderHandle.toUpperCase()}';
        final text = (lastMsg['text'] as String?) ?? 'Encrypted Memo';
        final ts = (lastMsg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
        final timeStr = _formatTimestamp(ts);

        final canonicalKey = ChatService.getCanonicalKey(senderNexaId.isNotEmpty ? senderNexaId : senderHandle);
        final readTs1 = await ChatService.instance.getReadTimestamp(canonicalKey);
        final readTs2 = await ChatService.instance.getReadTimestamp(ChatService.getCanonicalKey(senderHandle));
        final lastReadTs = readTs1 > readTs2 ? readTs1 : readTs2;

        // Calculate unread count strictly: count messages timestamped AFTER lastReadTs
        final unreadCount = peerMessages.where((m) {
          final mTs = (m['timestamp'] as num?)?.toInt() ?? 0;
          return mTs > lastReadTs;
        }).length;

        final idx = _chats.indexWhere((c) {
          final n = (c['name'] as String).toLowerCase();
          final id = (c['nexaId'] as String).toLowerCase();
          return n == senderHandle.toLowerCase() ||
              n == '@${senderHandle.toLowerCase()}' ||
              id == senderNexaId.toLowerCase();
        });

        if (idx >= 0) {
          final currentMsg = _chats[idx]['message'];
          final currentUnread = _chats[idx]['unread'];
          if (currentMsg != text || currentUnread != unreadCount) {
            _chats[idx]['message'] = text;
            _chats[idx]['time'] = timeStr;
            _chats[idx]['unread'] = unreadCount;
            if (currentMsg != text) {
              final item = _chats.removeAt(idx);
              _chats.insert(0, item);
            }
            changed = true;
          }
        } else {
          _chats.insert(0, {
            'name': '@$senderHandle',
            'nexaId': senderNexaId,
            'message': text,
            'time': timeStr,
            'unread': unreadCount,
          });
          changed = true;
        }
      }

      if (changed && mounted) {
        setState(() {});
        ChatService.instance.saveRecentChats(_chats);
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

  void _openChat(String contactName, String nexaId) async {
    final canonicalKey = ChatService.getCanonicalKey(nexaId.isNotEmpty ? nexaId : contactName);
    final now = DateTime.now().millisecondsSinceEpoch;
    await ChatService.instance.saveReadTimestamp(canonicalKey, now);
    if (contactName.isNotEmpty) {
      await ChatService.instance.saveReadTimestamp(ChatService.getCanonicalKey(contactName), now);
    }

    final idx = _chats.indexWhere((c) {
      final n = (c['name'] as String).toLowerCase();
      final id = (c['nexaId'] as String).toLowerCase();
      return n == contactName.toLowerCase() ||
          n == '@${contactName.replaceAll('@', '').toLowerCase()}' ||
          id == nexaId.toLowerCase();
    });
    if (idx >= 0 && mounted) {
      setState(() {
        _chats[idx]['unread'] = 0;
      });
      ChatService.instance.saveRecentChats(_chats);
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: contactName,
          nexaId: nexaId,
        ),
      ),
    );

    if (mounted) {
      _syncInbox();
    }
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
          final targetHandle = isOnNexa ? (item['handle'] ?? name) : name;
          final targetNexaId = item['nexaId'] ?? (phone.isNotEmpty ? phone : 'NX-${name.toUpperCase()}');

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            onTap: () => _openChat(targetHandle, targetNexaId),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: isOnNexa ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF1E293B),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(color: isOnNexa ? const Color(0xFF10B981) : Colors.white60, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              isOnNexa ? '$phone • $targetHandle' : phone,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOnNexa) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('ON NEXA', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 18),
                    tooltip: 'Start Chat',
                    onPressed: () => _openChat(targetHandle, targetNexaId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.phone_outlined, color: Color(0xFF10B981), size: 18),
                    tooltip: 'Voice Call',
                    onPressed: () => _startCall(contactName: name, nexaId: targetNexaId, isVideo: false),
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00E5FF), size: 18),
                    tooltip: 'Start Chat',
                    onPressed: () => _openChat(targetHandle, targetNexaId),
                  ),
                  OutlinedButton(
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
                ],
              ],
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
                  Text('v${UpdateEngine.currentVersion} (Build ${UpdateEngine.currentBuildNumber})', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold)),
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
  // =====================================================================
  // 7. NEW CHAT & IDENTITY DISCOVERY MODAL
  // =====================================================================
  void _showNewChatDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _NewChatSheet(
          deviceContacts: _deviceContacts,
          directoryUsers: _directoryUsers,
          onSelectPeer: (contactName, nexaId) {
            Navigator.pop(ctx);
            _openChat(contactName, nexaId);
          },
          onStartCall: (contactName, nexaId, isVideo) {
            Navigator.pop(ctx);
            _startCall(contactName: contactName, nexaId: nexaId, isVideo: isVideo);
          },
          onRequestSyncContacts: () async {
            await _loadContacts();
          },
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

// =====================================================================
// 8. RICH NEW CHAT & IDENTITY SELECTOR SHEET
// =====================================================================
class _NewChatSheet extends StatefulWidget {
  final List<Map<String, dynamic>> deviceContacts;
  final List<Map<String, dynamic>> directoryUsers;
  final Function(String contactName, String nexaId) onSelectPeer;
  final Function(String contactName, String nexaId, bool isVideo) onStartCall;
  final Future<void> Function() onRequestSyncContacts;

  const _NewChatSheet({
    required this.deviceContacts,
    required this.directoryUsers,
    required this.onSelectPeer,
    required this.onStartCall,
    required this.onRequestSyncContacts,
  });

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _activeFilter = 0; // 0 = All, 1 = Contacts, 2 = On NEXA, 3 = Directory
  bool _isSyncing = false;
  List<Map<String, dynamic>> _onlineResults = [];
  bool _isSearchingOnline = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    final clean = val.trim();
    if (clean.length < 2) {
      setState(() {
        _onlineResults = [];
        _isSearchingOnline = false;
      });
      return;
    }

    setState(() => _isSearchingOnline = true);
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await ContactsService.instance.searchNexaDirectory(clean);
        if (mounted && _searchQuery.trim() == clean) {
          setState(() {
            _onlineResults = res;
            _isSearchingOnline = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingOnline = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();

    // 1. Filtered Device Contacts
    final filteredDevice = widget.deviceContacts.where((c) {
      if (query.isEmpty) return true;
      final name = (c['name'] ?? '').toString().toLowerCase();
      final phone = (c['phone'] ?? '').toString().toLowerCase();
      final handle = (c['handle'] ?? '').toString().toLowerCase();
      final nexaId = (c['nexaId'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query) || handle.contains(query) || nexaId.contains(query);
    }).toList();

    // 2. Filtered On-NEXA Contacts
    final onNexaContacts = filteredDevice.where((c) => c['isOnNexa'] == true).toList();

    // 3. Filtered Directory Peers (combining local directory and online search results)
    final allDirectoryPeers = <Map<String, dynamic>>[...widget.directoryUsers];
    for (final onlineUser in _onlineResults) {
      final onNid = (onlineUser['nexaId'] ?? onlineUser['nexa_id'] ?? '').toString().toUpperCase();
      final onUn = (onlineUser['username'] ?? '').toString().toLowerCase();
      final exists = allDirectoryPeers.any((p) {
        final pNid = (p['nexa_id'] ?? p['nexaId'] ?? '').toString().toUpperCase();
        final pUn = (p['username'] ?? '').toString().toLowerCase();
        return (onNid.isNotEmpty && pNid == onNid) || (onUn.isNotEmpty && pUn == onUn);
      });
      if (!exists) {
        allDirectoryPeers.add(onlineUser);
      }
    }

    final filteredDirectory = allDirectoryPeers.where((u) {
      if (query.isEmpty) return true;
      final un = (u['username'] ?? '').toString().toLowerCase();
      final fn = (u['full_name'] ?? u['fullName'] ?? '').toString().toLowerCase();
      final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
      final ph = (u['phone'] ?? '').toString().toLowerCase();
      return un.contains(query) || fn.contains(query) || nid.contains(query) || ph.contains(query);
    }).toList();

    // Construct unified list based on active filter
    final List<Map<String, dynamic>> displayedItems = [];
    if (_activeFilter == 0) {
      // ALL: Device Contacts first, then Directory Peers not already in contacts
      final seenPhones = <String>{};
      final seenNexaIds = <String>{};

      for (final c in filteredDevice) {
        final ph = (c['phone'] ?? '').toString();
        final nid = (c['nexaId'] ?? '').toString().toUpperCase();
        if (ph.isNotEmpty) seenPhones.add(ph.replaceAll(RegExp(r'[^0-9]'), ''));
        if (nid.isNotEmpty) seenNexaIds.add(nid);
        displayedItems.add({
          'type': 'device',
          'data': c,
        });
      }

      for (final u in filteredDirectory) {
        final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toUpperCase();
        final ph = (u['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        if ((nid.isNotEmpty && seenNexaIds.contains(nid)) || (ph.isNotEmpty && seenPhones.contains(ph))) {
          continue; // Already displayed as correlated contact
        }
        displayedItems.add({
          'type': 'directory',
          'data': u,
        });
      }
    } else if (_activeFilter == 1) {
      // Device Contacts only
      for (final c in filteredDevice) {
        displayedItems.add({'type': 'device', 'data': c});
      }
    } else if (_activeFilter == 2) {
      // On NEXA only
      for (final c in onNexaContacts) {
        displayedItems.add({'type': 'device', 'data': c});
      }
      for (final u in filteredDirectory) {
        displayedItems.add({'type': 'directory', 'data': u});
      }
    } else {
      // Directory only
      for (final u in filteredDirectory) {
        displayedItems.add({'type': 'directory', 'data': u});
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x3300E5FF), width: 1.2)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add_comment_rounded, color: Color(0xFF00E5FF), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Start Conversation',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Select mobile contact, identity, or enter new ID',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search / Custom ID Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search registered NEXA ID (NX-...), @handle...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF111827),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0x26FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0x26FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                ),
              ),
            ),
          ),

          // Search Status & Verification Banner (Only registered accounts allowed)
          if (_searchQuery.trim().isNotEmpty)
            _buildVerifiedSearchStatusCard(_searchQuery.trim(), filteredDirectory, onNexaContacts),

          // Filter Selector Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(0, 'All', widget.deviceContacts.length + widget.directoryUsers.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(1, '📱 Contacts', widget.deviceContacts.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(2, '⚡ On NEXA', widget.deviceContacts.where((c) => c['isOnNexa'] == true).length + widget.directoryUsers.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(3, '🌐 Directory', widget.directoryUsers.length),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Permission Helper Banner (If no device contacts loaded)
          if (widget.deviceContacts.isEmpty && (_activeFilter == 0 || _activeFilter == 1))
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x26FFFFFF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.perm_contact_calendar_outlined, color: Color(0xFF00E5FF), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kIsWeb
                          ? 'Native address book is available on mobile.'
                          : 'Load address book to find phone contacts on NEXA.',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      foregroundColor: const Color(0xFF00E5FF),
                    ),
                    icon: _isSyncing
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                        : const Icon(Icons.sync, size: 14),
                    label: Text(_isSyncing ? 'Syncing...' : 'Sync Contacts', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _isSyncing ? null : () async {
                      setState(() => _isSyncing = true);
                      await widget.onRequestSyncContacts();
                      if (mounted) setState(() => _isSyncing = false);
                    },
                  ),
                ],
              ),
            ),

          // Contacts & Identities List
          Expanded(
            child: displayedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty ? Icons.person_off_rounded : Icons.person_search_outlined,
                          color: _searchQuery.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? 'No account found' : 'No peers or contacts found',
                          style: TextStyle(
                            color: _searchQuery.isNotEmpty ? const Color(0xFFFCA5A5) : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No registered NEXA account matches "$_searchQuery".'
                              : 'Sync device contacts or search registered users above.',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    itemCount: displayedItems.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0x0FFFFFFF)),
                    itemBuilder: (ctx, idx) {
                      final item = displayedItems[idx];
                      if (item['type'] == 'device') {
                        return _buildDeviceContactTile(item['data'] as Map<String, dynamic>);
                      } else {
                        return _buildDirectoryUserTile(item['data'] as Map<String, dynamic>);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedSearchStatusCard(
    String rawInput,
    List<Map<String, dynamic>> filteredDirectory,
    List<Map<String, dynamic>> onNexaContacts,
  ) {
    final cleanInput = rawInput.trim();
    final cleanLower = cleanInput.toLowerCase().replaceAll('@', '');

    // Check for exact or best matching registered user
    Map<String, dynamic>? match;
    for (final u in filteredDirectory) {
      final un = (u['username'] ?? '').toString().toLowerCase().replaceAll('@', '');
      final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
      if (un == cleanLower || nid == cleanLower || nid == cleanInput.toLowerCase()) {
        match = u;
        break;
      }
    }

    if (match == null) {
      for (final c in onNexaContacts) {
        final un = (c['handle'] ?? '').toString().toLowerCase().replaceAll('@', '');
        final nid = (c['nexaId'] ?? '').toString().toLowerCase();
        final ph = (c['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        if (un == cleanLower || nid == cleanLower || (ph.isNotEmpty && ph == cleanInput.replaceAll(RegExp(r'[^0-9]'), ''))) {
          match = c;
          break;
        }
      }
    }

    // 1. If a registered user is found -> Show verified account card with "Chat Now"
    if (match != null) {
      final matchedHandle = (match['handle'] ?? '@${match['username']}').toString();
      final matchedNexaId = (match['nexa_id'] ?? match['nexaId'] ?? 'NX-REGISTERED').toString();
      final matchedName = (match['full_name'] ?? match['fullName'] ?? match['name'] ?? match['username'] ?? 'User').toString();

      return Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1929),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          matchedName,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('REGISTERED', style: TextStyle(color: Color(0xFF10B981), fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$matchedHandle • $matchedNexaId',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => widget.onSelectPeer(matchedHandle, matchedNexaId),
              child: const Text('Chat Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // 2. If currently probing online directory
    if (_isSearchingOnline) {
      return Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x26FFFFFF)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF))),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Searching server directory for "$cleanInput"...',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // 3. NO ACCOUNT FOUND -> Clear warning, absolutely NO messaging allowed
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1311),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_off_rounded, color: Color(0xFFEF4444), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No account found',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 1),
                Text(
                  'No registered account matches "$cleanInput". You can only text registered accounts.',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label, int count) {
    final isSelected = _activeFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withValues(alpha: 0.15) : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00E5FF) : const Color(0x1AFFFFFF),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceContactTile(Map<String, dynamic> c) {
    final name = (c['name'] ?? 'Contact').toString();
    final phone = (c['phone'] ?? '').toString();
    final isOnNexa = c['isOnNexa'] == true;
    final targetHandle = isOnNexa ? (c['handle'] ?? name).toString() : name;
    final targetNexaId = (c['nexaId'] ?? (phone.isNotEmpty ? phone : 'NX-${name.toUpperCase()}')).toString();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      onTap: isOnNexa ? () => widget.onSelectPeer(targetHandle, targetNexaId) : null,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isOnNexa ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF1E293B),
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: TextStyle(
            color: isOnNexa ? const Color(0xFF10B981) : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isOnNexa)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('ON NEXA', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      subtitle: Text(
        isOnNexa ? '$phone • $targetHandle' : (phone.isNotEmpty ? phone : 'Mobile Contact'),
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
      ),
      trailing: isOnNexa
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF00E5FF), size: 20),
                  tooltip: 'Start Chat',
                  onPressed: () => widget.onSelectPeer(targetHandle, targetNexaId),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_rounded, color: Color(0xFF10B981), size: 20),
                  tooltip: 'Voice Call',
                  onPressed: () => widget.onStartCall(name, targetNexaId, false),
                ),
              ],
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: const Text('Not on NEXA', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w600)),
            ),
    );
  }

  Widget _buildDirectoryUserTile(Map<String, dynamic> u) {
    final un = (u['username'] ?? '').toString();
    final fn = (u['full_name'] ?? u['fullName'] ?? un).toString();
    final nid = (u['nexa_id'] ?? u['nexaId'] ?? 'NX-PEER').toString();
    final targetHandle = '@$un';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      onTap: () => widget.onSelectPeer(targetHandle, nid),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.15),
        child: Text(
          fn.isNotEmpty ? fn.substring(0, 1).toUpperCase() : '?',
          style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              fn,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('VERIFIED PEER', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      subtitle: Text(
        '$targetHandle • $nid',
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF00E5FF), size: 20),
            tooltip: 'Start Chat',
            onPressed: () => widget.onSelectPeer(targetHandle, nid),
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: Color(0xFF10B981), size: 20),
            tooltip: 'Voice Call',
            onPressed: () => widget.onStartCall(fn, nid, false),
          ),
        ],
      ),
    );
  }
}
