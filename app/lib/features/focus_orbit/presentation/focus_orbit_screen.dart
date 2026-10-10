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
import '../../../core/theme/nexa_theme.dart';
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
  bool _isSyncingInbox = false;
  final TextEditingController _chatSearchController = TextEditingController();
  String _chatSearchQuery = '';
  int _chatFilterIndex = 0; // 0 = All, 1 = Unread, 2 = Direct, 3 = Groups

  // Contacts
  List<Map<String, dynamic>> _deviceContacts = [];
  List<Map<String, dynamic>> _directoryUsers = [];
  bool _isLoadingContacts = false;
  int _activeContactsTab = 0; // 0 = On NEXA, 1 = All Contacts, 2 = ID Search
  final TextEditingController _contactsSearchController = TextEditingController();
  String _contactsSearchQuery = '';

  // Calls
  final List<Map<String, dynamic>> _callLogs = [];
  StreamSubscription? _incomingMessageSub;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);

    // 0. Load cached recent chats for instant offline render
    _loadCachedChats();

    // 1. Initial message sync & high-speed periodic background polling (1500ms for fast delivery)
    _syncInbox();
    _inboxSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _syncInbox());

    // 2. Real-time incoming WebSocket message subscription
    _incomingMessageSub = ChatService.instance.onMessageReceived.listen((_) {
      if (mounted) _loadCachedChats();
    });

    // 3. Start global real-time call invitation listener
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
    _incomingMessageSub?.cancel();
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
    if (cached.isNotEmpty && mounted) {
      setState(() {
        if (_chats.isEmpty) {
          _chats.addAll(cached);
        } else {
          for (final c in cached) {
            final cName = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
            final cId = ((c['nexaId'] as String?) ?? '').toLowerCase();
            final exists = _chats.any((x) {
              final xName = ((x['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
              final xId = ((x['nexaId'] as String?) ?? '').toLowerCase();
              return (cName.isNotEmpty && xName == cName) || (cId.isNotEmpty && xId == cId);
            });
            if (!exists) _chats.add(Map<String, dynamic>.from(c));
          }
          _chats.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0).compareTo((a['timestamp'] as num?)?.toInt() ?? 0));
        }
      });
    }
  }

  /// Synchronize incoming chat messages and canonical conversations from server relay
  Future<void> _syncInbox() async {
    if (_isSyncingInbox || !mounted || !_session.isLoggedIn) return;
    _isSyncingInbox = true;
    try {
      final myHandle = UserSession.instance.handle.replaceAll('@', '').toLowerCase();
      final myNexaId = UserSession.instance.nexaId.toLowerCase();
      final myUsername = UserSession.instance.username.toLowerCase();
      bool changed = false;

      // 1. Fetch server-persisted canonical conversations
      final serverConvs = await ChatService.instance.fetchConversations();
      for (final conv in serverConvs) {
        final convId = conv['id']?.toString() ?? '';

        // Resolve Peer Identifier & Name
        String peerName = (conv['peer_name'] as String?) ?? '';
        String peerHandle = (conv['peer_handle'] as String?) ?? '';
        String peerNexaId = (conv['peer_nexa_id'] as String?) ?? '';

        if (peerHandle.isEmpty && peerNexaId.isEmpty) {
          final p1 = (conv['participant_1'] as String?) ?? '';
          final p2 = (conv['participant_2'] as String?) ?? '';
          final isP1Me = p1.toLowerCase() == myNexaId || p1.toLowerCase() == myHandle || p1.toLowerCase() == myUsername;
          final pPeer = isP1Me ? p2 : p1;
          if (pPeer.isNotEmpty) {
            if (pPeer.toUpperCase().startsWith('NX-')) {
              peerNexaId = pPeer;
            } else {
              peerHandle = pPeer;
            }
          }
        }

        if (peerHandle.isEmpty && peerNexaId.isEmpty && conv['participants'] is List) {
          for (final p in conv['participants']) {
            final pStr = p?.toString() ?? '';
            final pLower = pStr.toLowerCase();
            if (pLower != myNexaId && pLower != myHandle && pLower != myUsername && pLower.isNotEmpty) {
              if (pStr.toUpperCase().startsWith('NX-')) {
                peerNexaId = pStr;
              } else {
                peerHandle = pStr;
              }
              break;
            }
          }
        }

        final cleanHandle = peerHandle.replaceAll('@', '');
        final displayName = peerName.isNotEmpty
            ? peerName
            : (cleanHandle.isNotEmpty ? '@$cleanHandle' : peerNexaId);
        final finalNexaId = peerNexaId.isNotEmpty
            ? peerNexaId
            : (cleanHandle.isNotEmpty ? 'NX-${cleanHandle.toUpperCase()}' : 'NX-PEER');

        if (displayName.isEmpty && finalNexaId.isEmpty) continue;

        String lastMsg = 'Direct Conversation';
        int lastTs = DateTime.now().millisecondsSinceEpoch;

        final rawLastMsg = conv['last_message'];
        if (rawLastMsg is Map) {
          lastMsg = rawLastMsg['text']?.toString() ?? 'Direct Conversation';
          final tsVal = rawLastMsg['timestamp'];
          if (tsVal is num) lastTs = tsVal.toInt();
        } else if (rawLastMsg is String && rawLastMsg.isNotEmpty) {
          lastMsg = rawLastMsg;
        } else if (conv['last_message_text'] is String && (conv['last_message_text'] as String).isNotEmpty) {
          lastMsg = conv['last_message_text'] as String;
        }

        if (conv['last_message_at'] is num) {
          lastTs = (conv['last_message_at'] as num).toInt();
        } else if (conv['updated_at'] is num) {
          lastTs = (conv['updated_at'] as num).toInt();
        } else if (conv['created_at'] is num) {
          lastTs = (conv['created_at'] as num).toInt();
        }

        final timeStr = _formatTimestamp(lastTs);
        final canonicalKey = ChatService.getCanonicalKey(finalNexaId.isNotEmpty ? finalNexaId : cleanHandle);
        final lastReadTs = await ChatService.instance.getReadTimestamp(canonicalKey);
        final unreadCount = (conv['unread_count'] as int?) ?? (lastTs > lastReadTs ? 1 : 0);

        final idx = _chats.indexWhere((c) {
          final cId = (c['conversationId'] as String?) ?? '';
          if (convId.isNotEmpty && cId.isNotEmpty && cId == convId) return true;
          final n = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
          final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
          return (cleanHandle.isNotEmpty && n == cleanHandle.toLowerCase()) ||
              (finalNexaId.isNotEmpty && id == finalNexaId.toLowerCase());
        });

        if (idx >= 0) {
          final existing = _chats[idx];
          final exMsg = existing['message'];
          final exTime = existing['time'];
          final exUnread = existing['unread'];
          final exTs = (existing['timestamp'] as num?)?.toInt() ?? 0;

          if (exMsg != lastMsg || exUnread != unreadCount || exTime != timeStr || (convId.isNotEmpty && existing['conversationId'] != convId)) {
            existing['message'] = lastMsg;
            existing['time'] = timeStr;
            existing['unread'] = unreadCount;
            if (convId.isNotEmpty) existing['conversationId'] = convId;
            if (lastTs > exTs) existing['timestamp'] = lastTs;
            changed = true;
          }
        } else {
          _chats.add({
            'conversationId': convId,
            'name': displayName,
            'nexaId': finalNexaId,
            'message': lastMsg,
            'time': timeStr,
            'timestamp': lastTs,
            'unread': unreadCount,
          });
          changed = true;
        }
      }

      // Always merge local recent chats so locally created direct conversations are never lost
      final cachedRecent = await ChatService.instance.loadRecentChats();
      for (final c in cachedRecent) {
        final cConvId = (c['conversationId'] as String?) ?? '';
        final cName = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
        final cNexaId = ((c['nexaId'] as String?) ?? '').toLowerCase();
        final exists = _chats.any((existing) {
          final exConvId = (existing['conversationId'] as String?) ?? '';
          if (cConvId.isNotEmpty && exConvId.isNotEmpty && cConvId == exConvId) return true;
          final exName = ((existing['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
          final exNexaId = ((existing['nexaId'] as String?) ?? '').toLowerCase();
          return (cName.isNotEmpty && exName == cName) || (cNexaId.isNotEmpty && exNexaId == cNexaId);
        });
        if (!exists) {
          _chats.add(Map<String, dynamic>.from(c));
          changed = true;
        }
      }

      // 2. Also check real-time inbox messages
      final messages = await ChatService.instance.fetchInbox();
      if (messages.isNotEmpty) {
        // Group incoming messages by sender
        final Map<String, List<Map<String, dynamic>>> bySender = {};
        for (final msg in messages) {
          final senderHandle = ((msg['sender_handle'] as String?) ?? '').replaceAll('@', '').toLowerCase();
          final senderNexaId = ((msg['sender_nexa_id'] as String?) ?? '').toLowerCase();
          // Ignore messages sent by me
          if (senderHandle == myHandle || senderHandle == myUsername ||
              (myNexaId.isNotEmpty && (senderHandle == myNexaId || senderNexaId == myNexaId))) {
            continue;
          }
          final peerKey = senderNexaId.isNotEmpty ? senderNexaId : senderHandle;
          if (peerKey.isEmpty) continue;
          bySender.putIfAbsent(peerKey, () => []).add(msg);
        }

        for (final entry in bySender.entries) {
          final peerMessages = entry.value;
          if (peerMessages.isEmpty) continue;
          peerMessages.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
          final lastMsg = peerMessages.last;

          final senderHandle = (lastMsg['sender_handle'] as String?) ?? 'Peer';
          final senderNexaId = (lastMsg['sender_nexa_id'] as String?) ?? 'NX-${senderHandle.toUpperCase()}';
          final text = (lastMsg['text'] as String?) ?? 'Encrypted Memo';
          final ts = (lastMsg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          final timeStr = _formatTimestamp(ts);
          final convId = lastMsg['conversation_id'] as String?;

          final cleanSenderHandle = senderHandle.replaceAll('@', '');

          // Immediately persist incoming messages to local thread storage for 0ms instantaneous chat rendering
          final cachedThread = await ChatService.instance.loadLocalMessagesMulti(
            conversationId: convId,
            peerNexaId: senderNexaId,
            peerHandle: cleanSenderHandle,
          );
          final Map<String, Map<String, dynamic>> threadMap = {};
          for (final m in cachedThread) {
            final id = (m['id'] ?? '').toString();
            if (id.isNotEmpty) threadMap[id] = m;
          }
          for (final raw in peerMessages) {
            final formatted = ChatService.formatMessageForUi(raw);
            final id = (formatted['id'] ?? '').toString();
            if (id.isNotEmpty) threadMap[id] = formatted;
          }
          final mergedThread = threadMap.values.toList();
          mergedThread.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
          ChatService.instance.saveLocalMessagesMulti(
            conversationId: convId,
            peerNexaId: senderNexaId,
            peerHandle: cleanSenderHandle,
            messages: mergedThread,
          );

          final canonicalKey = ChatService.getCanonicalKey(senderNexaId.isNotEmpty ? senderNexaId : senderHandle);
          final readTs1 = await ChatService.instance.getReadTimestamp(canonicalKey);
          final readTs2 = await ChatService.instance.getReadTimestamp(ChatService.getCanonicalKey(senderHandle));
          final lastReadTs = readTs1 > readTs2 ? readTs1 : readTs2;

          final unreadCount = peerMessages.where((m) {
            final mTs = (m['timestamp'] as num?)?.toInt() ?? 0;
            return mTs > lastReadTs;
          }).length;

          final idx = _chats.indexWhere((c) {
            final cId = (c['conversationId'] as String?) ?? '';
            if (convId != null && convId.isNotEmpty && cId.isNotEmpty && cId == convId) return true;
            final n = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
            final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
            return (cleanSenderHandle.isNotEmpty && n == cleanSenderHandle.toLowerCase()) ||
                (senderNexaId.isNotEmpty && id == senderNexaId.toLowerCase());
          });

          if (idx >= 0) {
            final existing = _chats[idx];
            final currentMsg = existing['message'];
            final currentUnread = existing['unread'];
            final currentTs = (existing['timestamp'] as num?)?.toInt() ?? 0;

            if (ts >= currentTs) {
              if (currentMsg != text || existing['time'] != timeStr || currentUnread != unreadCount || (convId != null && convId.isNotEmpty && existing['conversationId'] != convId)) {
                existing['message'] = text;
                existing['time'] = timeStr;
                existing['unread'] = unreadCount;
                existing['timestamp'] = ts;
                if (convId != null && convId.isNotEmpty) existing['conversationId'] = convId;
                changed = true;
              }
            } else {
              if (currentUnread != unreadCount) {
                existing['unread'] = unreadCount;
                changed = true;
              }
            }
          } else {
            _chats.add({
              'conversationId': convId,
              'name': '@$cleanSenderHandle',
              'nexaId': senderNexaId,
              'message': text,
              'time': timeStr,
              'timestamp': ts,
              'unread': unreadCount,
            });
            changed = true;
          }
        }
      }

      // Sort chats strictly by timestamp descending
      _chats.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0).compareTo((a['timestamp'] as num?)?.toInt() ?? 0));

      if (changed && mounted) {
        setState(() {});
        ChatService.instance.saveRecentChats(_chats);
      }
    } catch (e) {
      debugPrint('[_syncInbox error] $e');
    } finally {
      _isSyncingInbox = false;
    }
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

  void _openChat(String contactName, String nexaId, {String? conversationId}) {
    // 1. Immediate optimistic UI insertion or unread reset
    final cleanContact = contactName.replaceAll('@', '');
    final displayName = contactName.startsWith('@') ? contactName : (contactName.startsWith('NX-') ? contactName : '@$cleanContact');
    final targetNexaId = nexaId.isNotEmpty ? nexaId : (cleanContact.isNotEmpty ? 'NX-${cleanContact.toUpperCase()}' : 'NX-PEER');

    final idx = _chats.indexWhere((c) {
      final n = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
      final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
      final targetN = cleanContact.toLowerCase();
      final targetId = targetNexaId.toLowerCase();
      final cId = (c['conversationId'] as String?) ?? '';
      return (targetN.isNotEmpty && n == targetN) ||
          (targetId.isNotEmpty && id == targetId) ||
          (conversationId != null && conversationId.isNotEmpty && cId == conversationId);
    });

    if (idx >= 0 && mounted) {
      setState(() {
        _chats[idx]['unread'] = 0;
        if (conversationId != null && conversationId.isNotEmpty) {
          _chats[idx]['conversationId'] = conversationId;
        }
      });
      ChatService.instance.saveRecentChats(_chats);
    } else if (mounted) {
      setState(() {
        _chats.insert(0, {
          if (conversationId != null && conversationId.isNotEmpty) 'conversationId': conversationId,
          'name': displayName,
          'nexaId': targetNexaId,
          'message': 'Starting conversation...',
          'time': 'Just now',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'unread': 0,
        });
      });
      ChatService.instance.saveRecentChats(_chats);
    }

    // 2. Asynchronously record read state without blocking screen transition
    final canonicalKey = ChatService.getCanonicalKey(targetNexaId.isNotEmpty ? targetNexaId : contactName);
    final now = DateTime.now().millisecondsSinceEpoch;
    ChatService.instance.saveReadTimestamp(canonicalKey, now);
    if (contactName.isNotEmpty) {
      ChatService.instance.saveReadTimestamp(ChatService.getCanonicalKey(contactName), now);
    }

    // 3. Instant navigation to ChatScreen (<50ms transition)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: contactName,
          nexaId: nexaId,
          conversationId: conversationId,
        ),
      ),
    ).then((_) async {
      if (!mounted) return;
      final updated = await ChatService.instance.loadRecentChats();
      if (mounted && updated.isNotEmpty) {
        for (final u in updated) {
          final uName = ((u['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
          final uId = ((u['nexaId'] as String?) ?? '').toLowerCase();
          final cIdx = _chats.indexWhere((c) {
            final n = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
            final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
            return (uName.isNotEmpty && n == uName) || (uId.isNotEmpty && id == uId);
          });
          if (cIdx >= 0) {
            _chats[cIdx]['message'] = u['message'] ?? _chats[cIdx]['message'];
            _chats[cIdx]['time'] = u['time'] ?? _chats[cIdx]['time'];
            _chats[cIdx]['unread'] = u['unread'] ?? _chats[cIdx]['unread'];
            _chats[cIdx]['timestamp'] = u['timestamp'] ?? _chats[cIdx]['timestamp'];
          } else {
            _chats.add(Map<String, dynamic>.from(u));
          }
        }
        _chats.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0).compareTo((a['timestamp'] as num?)?.toInt() ?? 0));
        setState(() {});
      }
      _syncInbox();
    });
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
      backgroundColor: NexaColors.cyberBgVoid,
      drawer: _buildModernDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Maximalist Cyberpunk Command Bar
            _buildMaximalistTopBar(),

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
          ? Container(
              height: 58,
              width: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: NexaColors.cyberGradient,
                boxShadow: NexaColors.glowCyan,
              ),
              child: FloatingActionButton(
                backgroundColor: Colors.transparent,
                elevation: 0,
                onPressed: _showNewChatDialog,
                child: const Icon(Icons.add_comment_rounded, color: Colors.white, size: 24),
              ),
            )
          : null,
    );
  }

  // =====================================================================
  // 1. MAXIMALIST CYBERPUNK COMMAND BAR
  // =====================================================================
  Widget _buildMaximalistTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: NexaColors.borderLight, width: 1.0),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Light Maximalist Menu Button
              InkWell(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NexaColors.borderLight, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: const Icon(Icons.menu_rounded, color: NexaColors.primary, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              // Brand Icon Shield with Vibrant Gradient
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: NexaColors.cyberGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: NexaColors.glowCyan,
                ),
                child: const Center(
                  child: Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 10),
              // Brand Info & Badges
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'NEXA',
                        style: TextStyle(
                          color: NexaColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: NexaColors.cyberGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'E2EE 256-BIT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Row(
                    children: [
                      Text(
                        'QUANTUM SECURE RELAY',
                        style: TextStyle(
                          color: NexaColors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (UpdateEngine.instance.lastUpdateInfo?.isNewer == true) ...[
                GestureDetector(
                  onTap: () => UpdateEngine.instance.openUpdateCenter(context),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 6),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.system_update, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Update',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // Glowing Live Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A059669), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: NexaColors.neonEmerald,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x4D059669), blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _session.handle.isNotEmpty ? _session.handle : '@user',
                      style: const TextStyle(
                        color: NexaColors.neonEmerald,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 2. TAB 0: CHATS VIEW
  // =====================================================================
  Widget _buildChatsView() {
    // Filter chats by search query and category tab
    final filtered = _chats.where((c) {
      // Category filter
      if (_chatFilterIndex == 1) {
        // Unread only
        final unread = (c['unread'] as int?) ?? 0;
        if (unread <= 0) return false;
      }

      // Search query filter
      if (_chatSearchQuery.isEmpty) return true;
      final q = _chatSearchQuery.toLowerCase();
      final n = ((c['name'] as String?) ?? '').toLowerCase();
      final m = ((c['message'] as String?) ?? '').toLowerCase();
      final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
      final qAlpha = q.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final idAlpha = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      return n.contains(q) || m.contains(q) || id.contains(q) ||
          (qAlpha.length >= 3 && idAlpha.contains(qAlpha));
    }).toList();

    final unreadTotal = _chats.where((c) => ((c['unread'] as int?) ?? 0) > 0).length;

    return Column(
      children: [
        // Maximalist Light Search Field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _chatSearchQuery.isNotEmpty ? NexaColors.primary : NexaColors.borderLight,
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: TextField(
              controller: _chatSearchController,
              onChanged: (val) => setState(() => _chatSearchQuery = val),
              style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search encrypted conversations & peers...',
                hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: NexaColors.primary, size: 20),
                suffixIcon: _chatSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: NexaColors.textMuted, size: 18),
                        onPressed: () {
                          _chatSearchController.clear();
                          setState(() => _chatSearchQuery = '');
                        },
                      )
                    : null,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ),

        // User-Friendly Filter Chips (All, Unread, Direct, Groups)
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterChipItem(0, 'All Chats (${_chats.length})'),
              const SizedBox(width: 8),
              _buildFilterChipItem(1, 'Unread ($unreadTotal)'),
              const SizedBox(width: 8),
              _buildFilterChipItem(2, 'Direct Messages'),
              const SizedBox(width: 8),
              _buildFilterChipItem(3, 'Encrypted Vault'),
            ],
          ),
        ),

        // Active Orbit Peer Reels (Top story-style quick contacts tray)
        if (_chats.isNotEmpty && _chatSearchQuery.isEmpty)
          _buildActiveOrbitReel(),

        // Chat List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF161F38), Color(0xFF0F1527)],
                          ),
                          border: Border.all(color: const Color(0x4000F0FF), width: 1.5),
                          boxShadow: NexaColors.glowCyan,
                        ),
                        child: const Icon(Icons.mark_chat_unread_outlined, color: NexaColors.neonCyan, size: 40),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _chatFilterIndex == 1
                            ? 'No Unread Conversations'
                            : 'No Encrypted Conversations Yet',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Start a peer session or find contacts by NEXA ID.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _showNewChatDialog,
                        icon: const SizedBox.shrink(),
                        label: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: NexaColors.cyberGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: NexaColors.glowCyan,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_search_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Find Peer by NEXA ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _buildMaximalistChatCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChipItem(int index, String label) {
    final isSelected = _chatFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _chatFilterIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected ? NexaColors.cyberGradient : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : NexaColors.borderLight,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? NexaColors.glowIndigo
              : const [
                  BoxShadow(color: Color(0x0A0F172A), blurRadius: 4, offset: Offset(0, 1)),
                ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : NexaColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  /// Active Orbit Quick Contact Reel (Instagram/Telegram style stories tray)
  Widget _buildActiveOrbitReel() {
    return Container(
      height: 96,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _chats.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // "New Peer" quick launcher
            return GestureDetector(
              onTap: _showNewChatDialog,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFC7D2FE), width: 1.5),
                        boxShadow: const [
                          BoxShadow(color: Color(0x104F46E5), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.add_rounded, color: NexaColors.electricIndigo, size: 28),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'New Peer',
                      style: TextStyle(color: NexaColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            );
          }

          final chat = _chats[index - 1];
          final name = (chat['name'] as String?) ?? 'Peer';
          final nexaId = (chat['nexaId'] as String?) ?? 'NX-PEER';
          final initial = name.replaceAll('@', '').isNotEmpty ? name.replaceAll('@', '').substring(0, 1).toUpperCase() : '?';

          return GestureDetector(
            onTap: () => _openChat(name, nexaId, conversationId: chat['conversationId'] as String?),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x264F46E5), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: NexaColors.electricIndigo,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: NexaColors.mintEmerald,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33059669), blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 58,
                    child: Text(
                      name.replaceAll('@', ''),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: NexaColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Maximalist Chat Card with Glowing Rings and Crisp Contrast
  Widget _buildMaximalistChatCard(Map<String, dynamic> item) {
    final name = (item['name'] as String?) ?? 'Peer';
    final msg = (item['message'] as String?) ?? '';
    final time = (item['time'] as String?) ?? '';
    final unread = (item['unread'] as int?) ?? 0;
    final nexaId = (item['nexaId'] as String?) ?? 'NX-PEER';
    final isUnread = unread > 0;
    final initial = name.replaceAll('@', '').isNotEmpty ? name.replaceAll('@', '').substring(0, 1).toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isUnread ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread ? const Color(0xFF818CF8) : NexaColors.borderLight,
          width: isUnread ? 1.5 : 1.0,
        ),
        boxShadow: [
          if (isUnread)
            const BoxShadow(color: Color(0x1F4F46E5), blurRadius: 10, offset: Offset(0, 2))
          else
            const BoxShadow(color: Color(0x0A0F172A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openChat(name, nexaId, conversationId: item['conversationId'] as String?),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Glowing Circular Avatar with Dual Gradient Ring
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: isUnread
                              ? [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]
                              : [const Color(0xFF818CF8), const Color(0xFFA78BFA)],
                        ),
                        boxShadow: [
                          if (isUnread)
                            const BoxShadow(color: Color(0x334F46E5), blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: isUnread ? NexaColors.electricIndigo : NexaColors.laserViolet,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: NexaColors.mintEmerald,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33059669), blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Chat Info & Preview
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: NexaColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                      letterSpacing: -0.2,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Icon(Icons.verified_rounded, color: NexaColors.electricIndigo, size: 15),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isUnread ? const Color(0xFFE0E7FF) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isUnread ? const Color(0xFFC7D2FE) : NexaColors.borderLight),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                color: isUnread ? NexaColors.electricIndigo : NexaColors.textMuted,
                                fontSize: 10.5,
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              msg,
                              style: TextStyle(
                                color: isUnread ? NexaColors.textPrimary : NexaColors.textSecondary,
                                fontSize: 13,
                                fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: NexaColors.cyberGradient,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: NexaColors.glowIndigo,
                              ),
                              child: Text(
                                '$unread',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Text(
                                'E2EE',
                                style: TextStyle(
                                  color: NexaColors.mintEmerald,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
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
        ),
      ),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NexaColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x080F172A), blurRadius: 4, offset: Offset(0, 1)),
              ],
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
                  style: const TextStyle(color: NexaColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _activeContactsTab == 2 ? 'Search by NEXA ID or @handle...' : 'Filter contacts...',
                    hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: NexaColors.electricIndigo, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: NexaColors.borderLight)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: NexaColors.borderLight)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: NexaColors.electricIndigo, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isLoadingContacts
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: NexaColors.electricIndigo))
                    : const Icon(Icons.sync, color: NexaColors.electricIndigo, size: 22),
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
                      CircularProgressIndicator(strokeWidth: 2, color: NexaColors.electricIndigo),
                      SizedBox(height: 12),
                      Text('Accessing device contacts...', style: TextStyle(color: NexaColors.textSecondary, fontSize: 12)),
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
            gradient: isSelected ? NexaColors.cyberGradient : null,
            color: isSelected ? null : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.transparent : NexaColors.borderLight,
              width: 1.0,
            ),
            boxShadow: isSelected ? NexaColors.glowIndigo : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : NexaColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
              const Icon(Icons.group_outlined, color: NexaColors.textMuted, size: 36),
              const SizedBox(height: 12),
              const Text('No NEXA peers found in address book', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Switch to "Device Contacts" or "Directory" to find users.', style: TextStyle(color: NexaColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 14),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: NexaColors.electricIndigo, foregroundColor: Colors.white),
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
        separatorBuilder: (_, _) => const Divider(height: 1, color: NexaColors.borderLight),
        itemBuilder: (context, i) {
          final item = onNexa[i];
          final name = (item['name'] ?? 'Peer').toString();
          final handle = (item['handle'] ?? '@${item['username'] ?? name}').toString();
          final nexaId = (item['nexaId'] ?? 'NX-PEER').toString();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFECFDF5),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: NexaColors.mintEmerald, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text('$handle • $nexaId', style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: NexaColors.electricIndigo, size: 20),
                  tooltip: 'Chat',
                  onPressed: () => _openChat(handle, nexaId),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: NexaColors.mintEmerald, size: 20),
                  tooltip: 'Voice Call',
                  onPressed: () => _startCall(contactName: name, nexaId: nexaId, isVideo: false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: NexaColors.laserViolet, size: 20),
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
              const Icon(Icons.contact_phone_outlined, color: NexaColors.textMuted, size: 36),
              const SizedBox(height: 12),
              Text(
                kIsWeb ? 'Device Address Book on Mobile Devices' : 'No Contacts Detected',
                style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  kIsWeb
                      ? 'Native contacts are fetched on mobile devices. Use Directory search to find peers.'
                      : 'Ensure address book permission is granted in Android system settings.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12),
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
        separatorBuilder: (_, _) => const Divider(height: 1, color: NexaColors.borderLight),
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
              backgroundColor: isOnNexa ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: TextStyle(color: isOnNexa ? NexaColors.mintEmerald : NexaColors.electricIndigo, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(name, style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Text(
              isOnNexa ? '$phone • $targetHandle' : phone,
              style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isOnNexa) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Text('ON NEXA', style: TextStyle(color: NexaColors.mintEmerald, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: NexaColors.electricIndigo, size: 18),
                    tooltip: 'Start Chat',
                    onPressed: () => _openChat(targetHandle, targetNexaId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.phone_outlined, color: NexaColors.mintEmerald, size: 18),
                    tooltip: 'Voice Call',
                    onPressed: () => _startCall(contactName: name, nexaId: targetNexaId, isVideo: false),
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: NexaColors.electricIndigo, size: 18),
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
      final list = _directoryUsers.where((u) {
        if (query.isEmpty) return true;
        final un = (u['username'] ?? '').toString().toLowerCase();
        final fn = (u['full_name'] ?? u['fullName'] ?? '').toString().toLowerCase();
        final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
        final qAlpha = query.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        final nidAlpha = nid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        return un.contains(query) || fn.contains(query) || nid.contains(query) ||
            (qAlpha.length >= 3 && nidAlpha.contains(qAlpha));
      }).toList();

      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: NexaColors.borderLight),
        itemBuilder: (context, i) {
          final u = list[i];
          final un = (u['username'] ?? '').toString();
          final fn = (u['full_name'] ?? u['fullName'] ?? un).toString();
          final nid = (u['nexa_id'] ?? u['nexaId'] ?? 'NX-USER').toString();

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEEF2FF),
              child: Text(
                fn.isNotEmpty ? fn.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: NexaColors.electricIndigo, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(fn, style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('@$un • $nid', style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: NexaColors.electricIndigo, size: 18),
                  onPressed: () => _openChat('@$un', nid),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_outlined, color: NexaColors.mintEmerald, size: 18),
                  onPressed: () => _startCall(contactName: fn, nexaId: nid, isVideo: false),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_outlined, color: NexaColors.laserViolet, size: 18),
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
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: NexaColors.borderLight),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: NexaColors.mintEmerald, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Call History',
              style: TextStyle(color: NexaColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start end-to-end encrypted voice and video calls with any peer.',
              style: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      itemCount: _callLogs.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: NexaColors.borderLight),
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
            backgroundColor: const Color(0xFFEEF2FF),
            child: Icon(
              isVideo ? Icons.videocam : Icons.call,
              color: isVideo ? NexaColors.laserViolet : NexaColors.mintEmerald,
              size: 20,
            ),
          ),
          title: Text(name, style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Row(
            children: [
              const Icon(Icons.call_made, color: NexaColors.mintEmerald, size: 12),
              const SizedBox(width: 4),
              Text(
                '${isVideo ? 'Video' : 'Voice'} Call • $time',
                style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              isVideo ? Icons.videocam : Icons.call,
              color: isVideo ? NexaColors.laserViolet : NexaColors.mintEmerald,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: NexaColors.borderLight),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFFEEF2FF),
                child: Text(
                  _session.username.isNotEmpty ? _session.username.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(color: NexaColors.electricIndigo, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _session.fullName.isNotEmpty ? _session.fullName : _session.username,
                      style: const TextStyle(color: NexaColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _session.handle,
                      style: const TextStyle(color: NexaColors.electricIndigo, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _session.nexaId,
                      style: const TextStyle(color: NexaColors.textMuted, fontSize: 11, fontFamily: 'Courier'),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFC7D2FE)),
            boxShadow: const [
              BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.system_update_alt, color: NexaColors.electricIndigo, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Application Update Engine',
                        style: TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Text('v${UpdateEngine.currentVersion} (Build ${UpdateEngine.currentBuildNumber})', style: TextStyle(color: NexaColors.electricIndigo, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'NEXA autonomously checks for server releases, security patches, and calling engine updates.',
                style: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexaColors.electricIndigo,
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
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: NexaColors.borderLight),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.security, color: NexaColors.mintEmerald),
                title: const Text('Zero-Knowledge Security', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14)),
                subtitle: const Text('Double Ratchet • X3DH • AES-256-GCM', style: TextStyle(color: NexaColors.textSecondary, fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted, size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen())),
              ),
              const Divider(height: 1, color: NexaColors.borderLight),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined, color: NexaColors.sunfireAmber),
                title: const Text('Recovery Key Vault', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14)),
                subtitle: const Text('24-word self-sovereign seed', style: TextStyle(color: NexaColors.textSecondary, fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted, size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryKeyVaultScreen())),
              ),
              const Divider(height: 1, color: NexaColors.borderLight),
              ListTile(
                leading: const Icon(Icons.devices, color: NexaColors.vividAzure),
                title: const Text('Linked Devices', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14)),
                subtitle: const Text('Authorize secondary devices', style: TextStyle(color: NexaColors.textSecondary, fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, color: NexaColors.textMuted, size: 18),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Logout Button
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFEE2E2),
            foregroundColor: const Color(0xFFDC2626),
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
    final navItems = [
      {'icon': Icons.chat_bubble_outline_rounded, 'activeIcon': Icons.chat_bubble_rounded, 'label': 'CHATS'},
      {'icon': Icons.people_outline_rounded, 'activeIcon': Icons.people_rounded, 'label': 'CONTACTS'},
      {'icon': Icons.phone_outlined, 'activeIcon': Icons.phone_rounded, 'label': 'CALLS'},
      {'icon': Icons.tune_outlined, 'activeIcon': Icons.tune_rounded, 'label': 'VAULT'},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: NexaColors.borderLight, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(color: Color(0x0A0F172A), blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final isSelected = _activeNav == index;
              final item = navItems[index];
              return InkWell(
                onTap: () => setState(() => _activeNav = index),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: isSelected ? NexaColors.cyberGradient : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isSelected ? NexaColors.glowIndigo : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? item['activeIcon'] as IconData : item['icon'] as IconData,
                        color: isSelected ? Colors.white : NexaColors.textMuted,
                        size: 22,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item['label'] as String,
                        style: TextStyle(
                          color: isSelected ? Colors.white : NexaColors.textMuted,
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

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
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: NexaColors.borderLight, width: 1.0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: NexaColors.cyberGradient,
                      boxShadow: NexaColors.glowIndigo,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: Center(
                        child: Text(
                          _session.username.isNotEmpty ? _session.username.substring(0, 1).toUpperCase() : '?',
                          style: const TextStyle(color: NexaColors.electricIndigo, fontWeight: FontWeight.w900, fontSize: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _session.fullName.isNotEmpty ? _session.fullName : _session.username,
                          style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _session.handle,
                          style: const TextStyle(
                            color: NexaColors.electricIndigo,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.verified_user_rounded, color: NexaColors.mintEmerald, size: 22),
              title: const Text('Privacy Center', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyCenterScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices_rounded, color: NexaColors.vividAzure, size: 22),
              title: const Text('Linked Devices', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceLinkQrScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_rounded, color: NexaColors.sunfireAmber, size: 22),
              title: const Text('App Update Engine', style: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                UpdateEngine.instance.openUpdateCenter(context);
              },
            ),
            const Spacer(),
            const Divider(color: NexaColors.borderLight, height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
              title: const Text('Lock Vault', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w800, fontSize: 14)),
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
      final qAlpha = query.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final nidAlpha = nid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      return un.contains(query) || fn.contains(query) || nid.contains(query) || ph.contains(query) ||
          (qAlpha.length >= 3 && nidAlpha.contains(qAlpha));
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: NexaColors.borderLight, width: 1.0)),
        boxShadow: [
          BoxShadow(color: Color(0x140F172A), blurRadius: 20, spreadRadius: -5),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              gradient: NexaColors.cyberGradient,
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
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: NexaColors.cyberGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: NexaColors.glowIndigo,
                        ),
                        child: const Center(
                          child: Icon(Icons.add_comment_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Start Conversation',
                              style: TextStyle(color: NexaColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'PEER DISCOVERY // ZERO-KNOWLEDGE E2EE',
                              style: TextStyle(color: NexaColors.electricIndigo, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: NexaColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search / Custom ID Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: NexaColors.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search registered NEXA ID (NX-...), @handle...',
                hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.search_rounded, color: NexaColors.electricIndigo, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: NexaColors.textMuted, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexaColors.borderLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexaColors.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexaColors.electricIndigo, width: 1.5),
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
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.perm_contact_calendar_outlined, color: NexaColors.electricIndigo, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kIsWeb
                          ? 'Native address book is available on mobile.'
                          : 'Load address book to find phone contacts on NEXA.',
                      style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: NexaColors.electricIndigo,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isSyncing
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                          color: _searchQuery.isNotEmpty ? const Color(0xFFEF4444) : NexaColors.textMuted,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty ? 'No account found' : 'No peers or contacts found',
                          style: TextStyle(
                            color: _searchQuery.isNotEmpty ? const Color(0xFFDC2626) : NexaColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No registered NEXA account matches "$_searchQuery".'
                              : 'Sync device contacts or search registered users above.',
                          style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    itemCount: displayedItems.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: NexaColors.borderLight),
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
    final cleanAlpha = cleanInput.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    // Check for exact or best matching registered user
    Map<String, dynamic>? match;
    for (final u in filteredDirectory) {
      final un = (u['username'] ?? '').toString().toLowerCase().replaceAll('@', '');
      final nid = (u['nexa_id'] ?? u['nexaId'] ?? '').toString().toLowerCase();
      final nidAlpha = nid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (un == cleanLower || nid == cleanLower || nid == cleanInput.toLowerCase() ||
          (cleanAlpha.isNotEmpty && (nidAlpha == cleanAlpha || (cleanAlpha.length >= 4 && (nidAlpha.endsWith(cleanAlpha) || nidAlpha.contains(cleanAlpha)))))) {
        match = u;
        break;
      }
    }

    if (match == null) {
      for (final c in onNexaContacts) {
        final un = (c['handle'] ?? '').toString().toLowerCase().replaceAll('@', '');
        final nid = (c['nexaId'] ?? '').toString().toLowerCase();
        final nidAlpha = nid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        final ph = (c['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
        if (un == cleanLower || nid == cleanLower ||
            (cleanAlpha.isNotEmpty && (nidAlpha == cleanAlpha || (cleanAlpha.length >= 4 && (nidAlpha.endsWith(cleanAlpha) || nidAlpha.contains(cleanAlpha))))) ||
            (ph.isNotEmpty && ph == cleanInput.replaceAll(RegExp(r'[^0-9]'), ''))) {
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
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF86EFAC)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14059669),
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
                color: NexaColors.mintEmerald,
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
                          style: const TextStyle(color: NexaColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('REGISTERED', style: TextStyle(color: NexaColors.mintEmerald, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$matchedHandle • $matchedNexaId',
                    style: const TextStyle(color: NexaColors.electricIndigo, fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: NexaColors.electricIndigo,
                foregroundColor: Colors.white,
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NexaColors.borderLight),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: NexaColors.electricIndigo)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Searching server directory for "$cleanInput"...',
                style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12),
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
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_off_rounded, color: Color(0xFFDC2626), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No account found',
                  style: TextStyle(color: Color(0xFF991B1B), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 1),
                Text(
                  'No registered account matches "$cleanInput". You can only text registered accounts.',
                  style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 11),
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
          color: isSelected ? const Color(0xFFEEF2FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? NexaColors.electricIndigo : NexaColors.borderLight,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? NexaColors.electricIndigo : NexaColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? NexaColors.electricIndigo : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : NexaColors.textSecondary,
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
        backgroundColor: isOnNexa ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: TextStyle(
            color: isOnNexa ? NexaColors.mintEmerald : NexaColors.electricIndigo,
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
              style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isOnNexa)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Text('ON NEXA', style: TextStyle(color: NexaColors.mintEmerald, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      subtitle: Text(
        isOnNexa ? '$phone • $targetHandle' : (phone.isNotEmpty ? phone : 'Mobile Contact'),
        style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
      ),
      trailing: isOnNexa
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_rounded, color: NexaColors.electricIndigo, size: 20),
                  tooltip: 'Start Chat',
                  onPressed: () => widget.onSelectPeer(targetHandle, targetNexaId),
                ),
                IconButton(
                  icon: const Icon(Icons.phone_rounded, color: NexaColors.mintEmerald, size: 20),
                  tooltip: 'Voice Call',
                  onPressed: () => widget.onStartCall(name, targetNexaId, false),
                ),
              ],
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexaColors.borderLight),
              ),
              child: const Text('Not on NEXA', style: TextStyle(color: NexaColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
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
        backgroundColor: const Color(0xFFEEF2FF),
        child: Text(
          fn.isNotEmpty ? fn.substring(0, 1).toUpperCase() : '?',
          style: const TextStyle(color: NexaColors.electricIndigo, fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              fn,
              style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Text('VERIFIED PEER', style: TextStyle(color: NexaColors.mintEmerald, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      subtitle: Text(
        '$targetHandle • $nid',
        style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_rounded, color: NexaColors.electricIndigo, size: 20),
            tooltip: 'Start Chat',
            onPressed: () => widget.onSelectPeer(targetHandle, nid),
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: NexaColors.mintEmerald, size: 20),
            tooltip: 'Voice Call',
            onPressed: () => widget.onStartCall(fn, nid, false),
          ),
        ],
      ),
    );
  }
}
