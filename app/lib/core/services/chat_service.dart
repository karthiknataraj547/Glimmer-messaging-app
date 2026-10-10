import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../network/auth_service.dart';
import '../session/user_session.dart';

/// Bidirectional Real-Time Chat & Persistent Conversation Storage Service
class ChatService {
  static final ChatService instance = ChatService._internal();
  ChatService._internal();

  static const MethodChannel _channel = MethodChannel('com.nexa.media_picker');

  // Broadcast stream for real-time incoming messages
  final StreamController<Map<String, dynamic>> _incomingMessageStream = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessageReceived => _incomingMessageStream.stream;

  // In-memory message cache for instant 0ms UI render
  final Map<String, List<Map<String, dynamic>>> _memoryThreadCache = {};
  List<Map<String, dynamic>>? _cachedRecentChats;
  final Map<String, int> _memoryReadState = {};

  /// Formats seconds to mm:ss
  static String formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Converts a raw backend/socket message dictionary to a UI-ready message item
  static Map<String, dynamic> formatMessageForUi(Map<String, dynamic> m) {
    final myHandle = UserSession.instance.handle.replaceAll('@', '').toLowerCase();
    final myNexaId = UserSession.instance.nexaId.toLowerCase();
    final senderHandle = ((m['sender_handle'] ?? '').toString()).toLowerCase().replaceAll('@', '');
    final senderNexaId = ((m['sender_nexa_id'] ?? '').toString()).toLowerCase();
    final isMe = senderHandle == myHandle || (myNexaId.isNotEmpty && (senderHandle == myNexaId || senderNexaId == myNexaId));
    final ts = (m['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final timeStr = '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    final msgId = (m['id'] ?? 'm_${ts}_${DateTime.now().microsecond}').toString();
    final text = (m['text'] ?? '').toString();

    final attId = (m['attachment_id'] ?? m['attachmentId'])?.toString();
    final attUrl = (m['attachment_url'] ?? m['attachmentUrl'])?.toString();
    final attType = (m['attachment_type'] ?? m['attachmentType'] ?? m['type'])?.toString();
    final attName = (m['attachment_name'] ?? m['attachmentName'])?.toString();
    final locData = m['location_data'] is Map
        ? Map<String, dynamic>.from(m['location_data'] as Map)
        : (m['extra'] is Map ? Map<String, dynamic>.from(m['extra'] as Map) : null);

    String deliveryStatus = 'sent';
    if (m['read'] == true || m['status'] == 'read') {
      deliveryStatus = 'read';
    } else if (m['delivered'] == true || m['status'] == 'delivered') {
      deliveryStatus = 'delivered';
    }

    return {
      'id': msgId,
      'isMe': isMe,
      'text': text,
      'time': timeStr,
      'timestamp': ts,
      'status': deliveryStatus,
      'isAudio': m['type'] == 'voice',
      'attachmentId': attId,
      'attachmentUrl': attUrl,
      'attachmentName': attName,
      'attachmentType': attType != null && attType != 'text' ? attType : null,
      'extra': locData ?? m['extra'],
      'audioDuration': m['audio_duration'] != null && (m['audio_duration'] as num) > 0
          ? formatDuration((m['audio_duration'] as num).toInt())
          : null,
      'hasAction': false,
      'actionAdded': false,
      'actionDismissed': false,
      'reactions': <String>[],
    };
  }

  /// Processes live WebSocket incoming message, persists it locally, and broadcasts to listeners
  void handleRealtimeIncomingMessage(Map<String, dynamic> rawMsg) {
    try {
      final uiMsg = formatMessageForUi(rawMsg);
      final convId = rawMsg['conversation_id']?.toString();
      final senderNexaId = (rawMsg['sender_nexa_id'] ?? '').toString();
      final senderHandle = (rawMsg['sender_handle'] ?? '').toString();

      final current = getCachedMessagesFast(
        conversationId: convId,
        peerNexaId: senderNexaId,
        peerHandle: senderHandle,
      );
      final list = List<Map<String, dynamic>>.from(current);
      final msgId = uiMsg['id']?.toString() ?? '';
      final existingIdx = list.indexWhere((m) => m['id'] == msgId);
      if (existingIdx >= 0) {
        list[existingIdx] = uiMsg;
      } else {
        list.add(uiMsg);
      }
      list.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));

      saveLocalMessagesMulti(
        conversationId: convId,
        peerNexaId: senderNexaId,
        peerHandle: senderHandle,
        messages: list,
      );

      final isMe = uiMsg['isMe'] == true;
      if (!isMe) {
        updateRecentChat(
          peerName: senderHandle.isNotEmpty ? '@$senderHandle' : senderNexaId,
          peerNexaId: senderNexaId,
          lastMessage: uiMsg['text']?.toString() ?? '',
          timestamp: (uiMsg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          unread: 1,
          conversationId: convId,
        );
      }

      _incomingMessageStream.add({
        'message': uiMsg,
        'conversation_id': convId,
        'sender_handle': senderHandle,
        'sender_nexa_id': senderNexaId,
      });
    } catch (e) {
      debugPrint('[ChatService] handleRealtimeIncomingMessage error: $e');
    }
  }

  /// Active backend base URL for resolving attachment downloads and media assets
  String get baseUrl {
    final current = AuthService.instance.currentResolvedUrl;
    if (current != null && current.isNotEmpty && !current.contains('localhost') && !current.contains('127.0.0.1')) {
      return current;
    }
    return 'https://glimmer-messaging-app-web.vercel.app';
  }

  /// Returns canonical peer key for safe indexing
  static String getCanonicalKey(String peerIdOrHandle) {
    return peerIdOrHandle.trim().toLowerCase().replaceAll('@', '');
  }

  static File? _getThreadFile(String peerKey) {
    if (kIsWeb) return null;
    try {
      final tempDir = Directory.systemTemp.path;
      final safe = peerKey.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      return File('$tempDir/nexa_thread_$safe.json');
    } catch (_) {
      return null;
    }
  }

  static File? _getRecentChatsFile() {
    if (kIsWeb) return null;
    try {
      final tempDir = Directory.systemTemp.path;
      return File('$tempDir/nexa_recent_chats.json');
    } catch (_) {
      return null;
    }
  }

  /// Synchronously retrieve cached messages from memory for instant first frame rendering (<5ms)
  List<Map<String, dynamic>> getCachedMessagesFast({
    String? conversationId,
    String? peerNexaId,
    String? peerHandle,
  }) {
    final candidateKeys = <String>[];
    if (conversationId != null && conversationId.trim().isNotEmpty) {
      candidateKeys.add(conversationId.trim());
    }
    if (peerNexaId != null && peerNexaId.trim().isNotEmpty) {
      candidateKeys.add(getCanonicalKey(peerNexaId));
    }
    if (peerHandle != null && peerHandle.trim().isNotEmpty) {
      candidateKeys.add(getCanonicalKey(peerHandle));
    }

    for (final k in candidateKeys) {
      if (_memoryThreadCache.containsKey(k) && _memoryThreadCache[k]!.isNotEmpty) {
        return List<Map<String, dynamic>>.from(_memoryThreadCache[k]!);
      }
    }
    return [];
  }

  /// Loads locally stored messages with multi-key resolution (conversationId, nexaId, handle)
  Future<List<Map<String, dynamic>>> loadLocalMessagesMulti({
    String? conversationId,
    String? peerNexaId,
    String? peerHandle,
  }) async {
    // 1. Instant check in memory cache
    final fast = getCachedMessagesFast(
      conversationId: conversationId,
      peerNexaId: peerNexaId,
      peerHandle: peerHandle,
    );
    if (fast.isNotEmpty) return fast;

    final candidateKeys = <String>[];
    if (conversationId != null && conversationId.trim().isNotEmpty) {
      candidateKeys.add(conversationId.trim());
    }
    if (peerNexaId != null && peerNexaId.trim().isNotEmpty) {
      final k = getCanonicalKey(peerNexaId);
      if (!candidateKeys.contains(k)) candidateKeys.add(k);
    }
    if (peerHandle != null && peerHandle.trim().isNotEmpty) {
      final k = getCanonicalKey(peerHandle);
      if (!candidateKeys.contains(k)) candidateKeys.add(k);
    }

    // 2. Query persistent stores across candidate keys
    for (final key in candidateKeys) {
      // 2a. Native Android SharedPreferences
      try {
        final dynamic raw = await _channel.invokeMethod('loadChatThread', {'key': key});
        if (raw is String && raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw) as List;
          final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (list.isNotEmpty) {
            // Index under all candidate keys for future 0ms lookups
            for (final k in candidateKeys) {
              _memoryThreadCache[k] = list;
            }
            return list;
          }
        }
      } catch (_) {}

      // 2b. File-system fallback
      try {
        final file = _getThreadFile(key);
        if (file != null && await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw) as List;
            final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            if (list.isNotEmpty) {
              for (final k in candidateKeys) {
                _memoryThreadCache[k] = list;
              }
              return list;
            }
          }
        }
      } catch (e) {
        debugPrint('[ChatService] loadLocalMessages fallback error on $key: $e');
      }
    }

    return [];
  }

  /// Loads locally stored messages for an immediate, flicker-free chat window
  Future<List<Map<String, dynamic>>> loadLocalMessages(String peerIdOrHandle) async {
    return loadLocalMessagesMulti(peerNexaId: peerIdOrHandle, peerHandle: peerIdOrHandle);
  }

  /// Saves conversation messages to local persistent storage across all canonical keys
  Future<void> saveLocalMessagesMulti({
    String? conversationId,
    String? peerNexaId,
    String? peerHandle,
    required List<Map<String, dynamic>> messages,
  }) async {
    final copy = messages.map((m) => Map<String, dynamic>.from(m)).toList();
    copy.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));

    final candidateKeys = <String>[];
    if (conversationId != null && conversationId.trim().isNotEmpty) {
      candidateKeys.add(conversationId.trim());
    }
    if (peerNexaId != null && peerNexaId.trim().isNotEmpty) {
      final k = getCanonicalKey(peerNexaId);
      if (!candidateKeys.contains(k)) candidateKeys.add(k);
    }
    if (peerHandle != null && peerHandle.trim().isNotEmpty) {
      final k = getCanonicalKey(peerHandle);
      if (!candidateKeys.contains(k)) candidateKeys.add(k);
    }

    if (candidateKeys.isEmpty) return;

    // Cache in memory across all keys
    for (final k in candidateKeys) {
      _memoryThreadCache[k] = copy;
    }

    final jsonStr = jsonEncode(copy);

    // Persist to disk/SharedPreferences across all candidate keys
    for (final key in candidateKeys) {
      try {
        await _channel.invokeMethod('saveChatThread', {'key': key, 'data': jsonStr});
      } catch (_) {}

      try {
        final file = _getThreadFile(key);
        if (file != null) {
          await file.writeAsString(jsonStr, flush: true);
        }
      } catch (_) {}
    }
  }

  /// Saves conversation messages to local persistent storage
  Future<void> saveLocalMessages(String peerIdOrHandle, List<Map<String, dynamic>> messages) async {
    return saveLocalMessagesMulti(
      peerNexaId: peerIdOrHandle,
      peerHandle: peerIdOrHandle,
      messages: messages,
    );
  }

  /// Loads recent chat list from local storage
  Future<List<Map<String, dynamic>>> loadRecentChats() async {
    if (_cachedRecentChats != null && _cachedRecentChats!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_cachedRecentChats!);
    }

    // 1. Native Android Persistent SharedPreferences
    try {
      final dynamic raw = await _channel.invokeMethod('loadRecentChats');
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cachedRecentChats = list;
        return list;
      }
    } catch (_) {}

    // 2. File-system fallback
    try {
      final file = _getRecentChatsFile();
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw) as List;
          final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _cachedRecentChats = list;
          return list;
        }
      }
    } catch (e) {
      debugPrint('[ChatService] loadRecentChats fallback error: $e');
    }
    return [];
  }

  /// Formats timestamp for display in recent chats
  static String formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '${dt.month}/${dt.day}';
  }

  /// Updates or prepends a conversation in the recent chats list
  Future<void> updateRecentChat({
    required String peerName,
    required String peerNexaId,
    required String lastMessage,
    required int timestamp,
    int unread = 0,
    String? conversationId,
  }) async {
    final currentChats = await loadRecentChats();
    final cleanPeer = peerName.replaceAll('@', '');
    final cleanName = peerName.startsWith('@')
        ? peerName
        : (peerName.startsWith('NX-') ? peerName : '@$peerName');
    final targetNexaId = peerNexaId.isNotEmpty
        ? peerNexaId
        : (cleanPeer.toUpperCase().startsWith('NX-') ? cleanPeer.toUpperCase() : 'NX-${cleanPeer.toUpperCase()}');

    final idx = currentChats.indexWhere((c) {
      final cId = (c['conversationId'] as String?) ?? '';
      if (conversationId != null && conversationId.isNotEmpty && cId.isNotEmpty && cId == conversationId) return true;
      final n = ((c['name'] as String?) ?? '').toLowerCase().replaceAll('@', '');
      final id = ((c['nexaId'] as String?) ?? '').toLowerCase();
      return (cleanPeer.isNotEmpty && n == cleanPeer.toLowerCase()) ||
          (targetNexaId.isNotEmpty && id == targetNexaId.toLowerCase());
    });

    final entry = {
      if (conversationId != null && conversationId.isNotEmpty) 'conversationId': conversationId,
      'name': cleanName,
      'nexaId': targetNexaId,
      'message': lastMessage,
      'time': formatTimestamp(timestamp),
      'timestamp': timestamp,
      'unread': unread,
    };

    if (idx >= 0) {
      if (conversationId == null && currentChats[idx]['conversationId'] != null) {
        entry['conversationId'] = currentChats[idx]['conversationId'];
      }
      currentChats.removeAt(idx);
    }
    currentChats.insert(0, entry);
    await saveRecentChats(currentChats);
  }

  /// Transmits user telemetry & location update to Sovereign server
  Future<void> reportUserLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    String? address,
  }) async {
    final username = UserSession.instance.username;
    if (username.isEmpty) return;
    try {
      await AuthService.instance.postJson('/v1/users/telemetry/location', {
        'username': username,
        'handle': UserSession.instance.handle,
        'nexa_id': UserSession.instance.nexaId,
        'full_name': UserSession.instance.fullName,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy ?? 0.0,
        'altitude': altitude ?? 0.0,
        'address': address ?? '',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// Saves recent chat list to local storage
  Future<void> saveRecentChats(List<Map<String, dynamic>> chats) async {
    final copy = chats.map((c) => Map<String, dynamic>.from(c)).toList();
    _cachedRecentChats = copy;
    final jsonStr = jsonEncode(copy);

    // 1. Native Android Persistent SharedPreferences
    try {
      await _channel.invokeMethod('saveRecentChats', {'data': jsonStr});
    } catch (_) {}

    // 2. File-system fallback
    try {
      final file = _getRecentChatsFile();
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (e) {
      debugPrint('[ChatService] saveRecentChats fallback error: $e');
    }
  }

  /// Records the latest read timestamp for a peer thread
  Future<void> saveReadTimestamp(String peerIdOrHandle, int timestamp) async {
    final key = getCanonicalKey(peerIdOrHandle);
    if (key.isEmpty) return;
    _memoryReadState[key] = timestamp;
    try {
      await _channel.invokeMethod('saveReadState', {
        'peerKey': key,
        'lastReadTimestamp': timestamp,
      });
    } catch (_) {}
  }

  /// Retrieves the latest read timestamp for a peer thread
  Future<int> getReadTimestamp(String peerIdOrHandle) async {
    final key = getCanonicalKey(peerIdOrHandle);
    if (key.isEmpty) return 0;
    if (_memoryReadState.containsKey(key)) return _memoryReadState[key]!;
    try {
      final dynamic res = await _channel.invokeMethod('loadReadState', {'peerKey': key});
      if (res is num) {
        final val = res.toInt();
        _memoryReadState[key] = val;
        return val;
      }
    } catch (_) {}
    return 0;
  }

  /// Send message to a peer by Handle or NEXA ID
  /// Send message to a peer with strict idempotency, attachments, and location data
  Future<Map<String, dynamic>?> sendMessage({
    required String recipientHandle,
    required String recipientNexaId,
    required String text,
    String type = 'text',
    String? audioPath,
    int audioDuration = 0,
    String? clientMessageId,
    String? conversationId,
    String? attachmentId,
    String? attachmentUrl,
    String? attachmentType,
    String? attachmentName,
    int? attachmentSize,
    Map<String, dynamic>? locationData,
  }) async {
    final senderHandle = UserSession.instance.handle.replaceAll('@', '');
    final senderNexaId = UserSession.instance.nexaId;
    final cMsgId = clientMessageId ?? 'cl_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';

    final Map<String, dynamic> body = {
      'client_message_id': cMsgId,
      'sender_handle': senderHandle,
      'sender_nexa_id': senderNexaId,
      'recipient_handle': recipientHandle.replaceAll('@', ''),
      'recipient_nexa_id': recipientNexaId,
      'text': text,
      'type': type,
      'audio_path': audioPath,
      'audio_duration': audioDuration,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (conversationId != null) body['conversation_id'] = conversationId;
    if (attachmentId != null) body['attachment_id'] = attachmentId;
    if (attachmentUrl != null) body['attachment_url'] = attachmentUrl;
    if (attachmentType != null) body['attachment_type'] = attachmentType;
    if (attachmentName != null) body['attachment_name'] = attachmentName;
    if (attachmentSize != null) body['attachment_size'] = attachmentSize;
    if (locationData != null) body['location_data'] = locationData;

    try {
      final res = await AuthService.instance.postJson('/v1/messages/send', body);
      if (res != null && res['success'] == true) {
        return res['message'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[ChatService] sendMessage error: $e');
    }
    return null;
  }

  /// Atomically resolve or create canonical direct conversation with peer
  Future<Map<String, dynamic>?> getOrCreateDirectConversation(String peerHandleOrNexaId, {String? peerNexaId}) async {
    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    final myNexaId = UserSession.instance.nexaId;
    final cleanPeer = peerHandleOrNexaId.replaceAll('@', '');
    final pNexaId = peerNexaId ?? (peerHandleOrNexaId.toUpperCase().startsWith('NX-') ? peerHandleOrNexaId : '');

    final body = {
      'sender_handle': myHandle,
      'sender_nexa_id': myNexaId,
      'recipient_handle': cleanPeer,
      'recipient_nexa_id': pNexaId,
    };

    try {
      final res = await AuthService.instance.postJson('/v1/conversations/direct', body);
      if (res != null && res['success'] == true) {
        return res['conversation'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[ChatService] getOrCreateDirectConversation error: $e');
    }
    return null;
  }

  /// Retrieve all server-persisted conversations for the current user
  Future<List<Map<String, dynamic>>> fetchConversations() async {
    final myIdent = UserSession.instance.nexaId.isNotEmpty ? UserSession.instance.nexaId : UserSession.instance.handle.replaceAll('@', '');
    if (myIdent.isEmpty) return [];

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/conversations?user=${Uri.encodeComponent(myIdent)}');
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['conversations'] is List) {
        return List<Map<String, dynamic>>.from(res['conversations'] as List);
      }
    } catch (e) {
      debugPrint('[ChatService] fetchConversations error: $e');
    }
    return [];
  }

  /// Retrieve messages for a canonical conversation with cursor pagination & verification
  Future<Map<String, dynamic>?> fetchConversationMessages(String conversationId, {int limit = 50, int? cursor}) async {
    final myIdent = UserSession.instance.nexaId.isNotEmpty ? UserSession.instance.nexaId : UserSession.instance.handle.replaceAll('@', '');
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      var uriStr = '$baseUrl/v1/conversations/$conversationId/messages?limit=$limit&user=${Uri.encodeComponent(myIdent)}';
      if (cursor != null) {
        uriStr += '&cursor=$cursor';
      }
      final uri = Uri.parse(uriStr);
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['success'] == true) {
        return res;
      }
    } catch (e) {
      debugPrint('[ChatService] fetchConversationMessages error: $e');
    }
    return null;
  }

  /// Upload an attachment to object storage
  Future<Map<String, dynamic>?> uploadAttachment({
    required String name,
    required String mediaType,
    required List<int> bytes,
  }) async {
    final myIdent = UserSession.instance.handle.isNotEmpty ? UserSession.instance.handle : UserSession.instance.nexaId;
    final b64 = base64Encode(bytes);
    final body = {
      'name': name,
      'media_type': mediaType,
      'data_base64': b64,
      'size_bytes': bytes.length,
      'uploader': myIdent,
    };

    try {
      final res = await AuthService.instance.postJson('/v1/attachments/upload', body);
      if (res != null && res['success'] == true) {
        final att = res['attachment'] is Map ? Map<String, dynamic>.from(res['attachment'] as Map) : <String, dynamic>{};
        final attId = (res['attachmentId'] ?? att['id'])?.toString();
        final rawUrl = (res['url'] ?? att['download_url'])?.toString();
        final fileName = (res['fileName'] ?? att['name'])?.toString() ?? name;
        final sizeBytes = res['sizeBytes'] ?? att['size_bytes'] ?? bytes.length;
        return {
          'attachmentId': attId,
          'url': rawUrl,
          'fileName': fileName,
          'sizeBytes': sizeBytes is num ? sizeBytes.toInt() : bytes.length,
          ...att,
        };
      }
    } catch (e) {
      debugPrint('[ChatService] uploadAttachment error: $e');
    }
    return null;
  }

  /// Register device push notification token
  Future<bool> registerPushToken(String token, {String platform = 'android', String deviceId = 'default'}) async {
    final myIdent = UserSession.instance.nexaId.isNotEmpty ? UserSession.instance.nexaId : UserSession.instance.handle.replaceAll('@', '');
    if (myIdent.isEmpty || token.isEmpty) return false;

    final body = {
      'user': myIdent,
      'device_id': deviceId,
      'push_token': token,
      'platform': platform,
    };

    try {
      final res = await AuthService.instance.postJson('/v1/devices/push-token', body);
      return res != null && res['success'] == true;
    } catch (e) {
      debugPrint('[ChatService] registerPushToken error: $e');
      return false;
    }
  }

  /// Fetch conversation thread between the logged-in user and a peer
  Future<List<Map<String, dynamic>>> fetchThread(String peerHandleOrNexaId, {String? peerNexaId}) async {
    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    final myNexaId = UserSession.instance.nexaId;
    final cleanPeer = peerHandleOrNexaId.replaceAll('@', '');

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      var uriStr = '$baseUrl/v1/messages/thread/$myHandle/$cleanPeer';
      final params = <String, String>{};
      if (myNexaId.isNotEmpty) params['my_id'] = myNexaId;
      if (peerNexaId != null && peerNexaId.isNotEmpty) params['peer_id'] = peerNexaId;
      if (params.isNotEmpty) {
        uriStr += '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }
      final uri = Uri.parse(uriStr);
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['messages'] is List) {
        final messages = List<Map<String, dynamic>>.from(res['messages'] as List);
        return messages;
      }
    } catch (e) {
      debugPrint('[ChatService] fetchThread error: $e');
    }
    return [];
  }

  /// Fetch incoming inbox messages for current user
  Future<List<Map<String, dynamic>>> fetchInbox() async {
    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    final myNexaId = UserSession.instance.nexaId;
    final ident = myHandle.isNotEmpty ? myHandle : myNexaId;
    if (ident.isEmpty) return [];

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      var uriStr = '$baseUrl/v1/messages/inbox/$ident';
      if (myNexaId.isNotEmpty) {
        uriStr += '?nexa_id=${Uri.encodeComponent(myNexaId)}';
      }
      final uri = Uri.parse(uriStr);
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['messages'] is List) {
        return List<Map<String, dynamic>>.from(res['messages'] as List);
      }
    } catch (e) {
      debugPrint('[ChatService] fetchInbox error: $e');
    }
    return [];
  }
}
