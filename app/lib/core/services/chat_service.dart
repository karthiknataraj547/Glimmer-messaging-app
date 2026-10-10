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

  // In-memory message cache for instant 0ms UI render
  final Map<String, List<Map<String, dynamic>>> _memoryThreadCache = {};
  List<Map<String, dynamic>>? _cachedRecentChats;
  final Map<String, int> _memoryReadState = {};

  /// Active backend base URL for resolving attachment downloads and media assets
  String get baseUrl => AuthService.instance.currentResolvedUrl ?? 'https://glimmer-messaging-app-web.vercel.app';

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

  /// Loads locally stored messages for an immediate, flicker-free chat window
  Future<List<Map<String, dynamic>>> loadLocalMessages(String peerIdOrHandle) async {
    final key = getCanonicalKey(peerIdOrHandle);
    if (key.isEmpty) return [];

    if (_memoryThreadCache.containsKey(key) && _memoryThreadCache[key]!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_memoryThreadCache[key]!);
    }

    // 1. Native Android Persistent SharedPreferences
    try {
      final dynamic raw = await _channel.invokeMethod('loadChatThread', {'key': key});
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _memoryThreadCache[key] = list;
        return list;
      }
    } catch (_) {}

    // 2. File-system fallback
    try {
      final file = _getThreadFile(key);
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw) as List;
          final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _memoryThreadCache[key] = list;
          return list;
        }
      }
    } catch (e) {
      debugPrint('[ChatService] loadLocalMessages fallback error: $e');
    }
    return [];
  }

  /// Saves conversation messages to local persistent storage
  Future<void> saveLocalMessages(String peerIdOrHandle, List<Map<String, dynamic>> messages) async {
    final key = getCanonicalKey(peerIdOrHandle);
    if (key.isEmpty) return;

    final copy = messages.map((m) => Map<String, dynamic>.from(m)).toList();
    // Strictly sort chronologically by timestamp so storage is always ordered
    copy.sort((a, b) => ((a['timestamp'] as num?)?.toInt() ?? 0).compareTo((b['timestamp'] as num?)?.toInt() ?? 0));
    _memoryThreadCache[key] = copy;
    final jsonStr = jsonEncode(copy);

    // 1. Native Android Persistent SharedPreferences
    try {
      await _channel.invokeMethod('saveChatThread', {'key': key, 'data': jsonStr});
    } catch (_) {}

    // 2. File-system fallback
    try {
      final file = _getThreadFile(key);
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (e) {
      debugPrint('[ChatService] saveLocalMessages fallback error: $e');
    }
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
        return res['attachment'] as Map<String, dynamic>?;
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
