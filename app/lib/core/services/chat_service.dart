import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../network/auth_service.dart';
import '../session/user_session.dart';

/// Bidirectional Real-Time Chat & Persistent Conversation Storage Service
class ChatService {
  static final ChatService instance = ChatService._internal();
  ChatService._internal();

  // In-memory message cache for instant 0ms UI render
  final Map<String, List<Map<String, dynamic>>> _memoryThreadCache = {};
  List<Map<String, dynamic>>? _cachedRecentChats;

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
      debugPrint('[ChatService] loadLocalMessages error: $e');
    }
    return [];
  }

  /// Saves conversation messages to local persistent storage
  Future<void> saveLocalMessages(String peerIdOrHandle, List<Map<String, dynamic>> messages) async {
    final key = getCanonicalKey(peerIdOrHandle);
    if (key.isEmpty) return;

    final copy = messages.map((m) => Map<String, dynamic>.from(m)).toList();
    _memoryThreadCache[key] = copy;

    try {
      final file = _getThreadFile(key);
      if (file != null) {
        await file.writeAsString(jsonEncode(copy), flush: true);
      }
    } catch (e) {
      debugPrint('[ChatService] saveLocalMessages error: $e');
    }
  }

  /// Loads recent chat list from local storage
  Future<List<Map<String, dynamic>>> loadRecentChats() async {
    if (_cachedRecentChats != null && _cachedRecentChats!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_cachedRecentChats!);
    }

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
      debugPrint('[ChatService] loadRecentChats error: $e');
    }
    return [];
  }

  /// Saves recent chat list to local storage
  Future<void> saveRecentChats(List<Map<String, dynamic>> chats) async {
    final copy = chats.map((c) => Map<String, dynamic>.from(c)).toList();
    _cachedRecentChats = copy;

    try {
      final file = _getRecentChatsFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(copy), flush: true);
      }
    } catch (e) {
      debugPrint('[ChatService] saveRecentChats error: $e');
    }
  }

  /// Send message to a peer by Handle or NEXA ID
  Future<Map<String, dynamic>?> sendMessage({
    required String recipientHandle,
    required String recipientNexaId,
    required String text,
    String type = 'text',
    String? audioPath,
    int audioDuration = 0,
  }) async {
    final senderHandle = UserSession.instance.handle.replaceAll('@', '');
    final senderNexaId = UserSession.instance.nexaId;

    final body = {
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
