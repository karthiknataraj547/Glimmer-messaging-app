import 'package:flutter/foundation.dart';
import '../network/auth_service.dart';
import '../session/user_session.dart';

/// Bidirectional Real-Time Chat Service
class ChatService {
  static final ChatService instance = ChatService._internal();
  ChatService._internal();

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
  Future<List<Map<String, dynamic>>> fetchThread(String peerHandleOrNexaId) async {
    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    final cleanPeer = peerHandleOrNexaId.replaceAll('@', '');

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/messages/thread/$myHandle/$cleanPeer');
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['messages'] is List) {
        return List<Map<String, dynamic>>.from(res['messages'] as List);
      }
    } catch (e) {
      debugPrint('[ChatService] fetchThread error: $e');
    }
    return [];
  }

  /// Fetch incoming inbox messages for current user
  Future<List<Map<String, dynamic>>> fetchInbox() async {
    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/messages/inbox/$myHandle');
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
