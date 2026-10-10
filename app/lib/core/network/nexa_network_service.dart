import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../crypto/nexa_envelope.dart';
import '../services/chat_service.dart';
import '../session/user_session.dart';
import 'auth_service.dart';

/// Network event received from the NEXA Zero-Knowledge Relay.
class NexaNetworkEvent {
  final String event;
  final dynamic data;
  const NexaNetworkEvent({required this.event, required this.data});
}

/// Network service for NEXA client.
/// 
/// Communicates with backend using Dart standard library (dart:io):
/// - HTTP REST requests with automatic JSON serialization
/// - Persistent WebSocket with auto-reconnect and device binding
class NexaNetworkService {
  static final NexaNetworkService instance = NexaNetworkService._internal();
  NexaNetworkService._internal()
      : baseUrl = '',
        wsUrl = '',
        deviceId = 'device_${Platform.operatingSystem}';

  final String baseUrl;
  final String wsUrl;
  final String deviceId;

  WebSocket? _webSocket;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  final StreamController<NexaEncryptedEnvelope> _incomingEnvelopesController =
      StreamController<NexaEncryptedEnvelope>.broadcast();
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();

  NexaNetworkService({
    required this.baseUrl,
    required this.wsUrl,
    required this.deviceId,
  });

  bool get isConnected => _isConnected;
  Stream<NexaEncryptedEnvelope> get incomingEnvelopes => _incomingEnvelopesController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get onPresenceUpdate => _presenceController.stream;

  /// Transmit message instantly over active WebSocket frame (<10ms latency)
  bool sendRealtimeMessage(Map<String, dynamic> msgBody) {
    if (_webSocket != null && _isConnected) {
      try {
        _webSocket!.add(jsonEncode({
          'action': 'SEND_MESSAGE',
          'data': msgBody,
        }));
        return true;
      } catch (e) {
        debugPrint('[NexaNetworkService] sendRealtimeMessage error: $e');
      }
    }
    return false;
  }

  /// Request live presence for a target user over WebSocket or HTTP
  Future<Map<String, dynamic>> fetchPresence(String peerIdOrHandle) async {
    try {
      final clean = peerIdOrHandle.replaceAll('@', '');
      final httpBase = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$httpBase/v1/presence/${Uri.encodeComponent(clean)}');
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['success'] == true) {
        return {
          'is_online': res['is_online'] == true,
          'last_seen': (res['last_seen'] as num?)?.toInt() ?? 0,
        };
      }
    } catch (_) {}
    return {'is_online': false, 'last_seen': 0};
  }

  /// Establishes persistent WebSocket connection and binds device ID.
  Future<void> connectRealtime({String? customWsUrl}) async {
    if (_isConnected) return;

    try {
      String resolvedWs = customWsUrl ?? wsUrl;
      if (resolvedWs.isEmpty) {
        final httpBase = await AuthService.instance.getBaseUrl();
        resolvedWs = httpBase.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
        if (resolvedWs.endsWith('/')) resolvedWs = resolvedWs.substring(0, resolvedWs.length - 1);
        resolvedWs += '/v1/realtime';
      }

      _webSocket = await WebSocket.connect(resolvedWs).timeout(const Duration(seconds: 4));
      _isConnected = true;
      _connectionStateController.add(true);

      // Bind device identity and user credentials to the connection
      final userHandle = UserSession.instance.handle;
      final userNexaId = UserSession.instance.nexaId;
      _webSocket!.add(jsonEncode({
        'action': 'BIND_DEVICE',
        'device_id': deviceId,
        if (userHandle.isNotEmpty) 'user': userHandle,
        if (userHandle.isNotEmpty) 'handle': userHandle,
        if (userNexaId.isNotEmpty) 'nexa_id': userNexaId,
      }));

      // Start periodic presence heartbeat
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        if (_webSocket != null && _isConnected) {
          try {
            _webSocket!.add(jsonEncode({
              'action': 'PING',
              'handle': UserSession.instance.handle,
              'nexa_id': UserSession.instance.nexaId,
            }));
          } catch (_) {}
        }
        // Background HTTP heartbeat backup
        AuthService.instance.postJson('/v1/presence/heartbeat', {
          'user': UserSession.instance.handle,
          'nexa_id': UserSession.instance.nexaId,
        }).catchError((_) => null);
      });

      _webSocket!.listen(
        _handleIncomingWsMessage,
        onError: (err) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleIncomingWsMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString()) as Map<String, dynamic>;
      final event = json['event'] as String?;

      if (event == 'NEW_ENVELOPE') {
        final envJson = json['envelope'] as Map<String, dynamic>;
        final envelope = NexaEncryptedEnvelope.fromJson(envJson);
        _incomingEnvelopesController.add(envelope);
      } else if (event == 'MAILBOX_FLUSH') {
        final envelopes = json['envelopes'] as List<dynamic>;
        for (final raw in envelopes) {
          final envelope = NexaEncryptedEnvelope.fromJson(raw as Map<String, dynamic>);
          _incomingEnvelopesController.add(envelope);
        }
      } else if (event == 'NEW_CHAT_MESSAGE') {
        final rawMsg = json['message'];
        if (rawMsg is Map) {
          ChatService.instance.handleRealtimeIncomingMessage(Map<String, dynamic>.from(rawMsg));
        }
      } else if (event == 'PRESENCE_UPDATE') {
        _presenceController.add(json);
      }
    } catch (_) {
      // Ignored malformed frame
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _connectionStateController.add(false);
    _webSocket = null;
    _heartbeatTimer?.cancel();

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      connectRealtime();
    });
  }

  /// Sends a batch of zero-knowledge encrypted envelopes to the server.
  Future<bool> sendEnvelopes(List<NexaEncryptedEnvelope> envelopes) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl/v1/mailbox/send');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'envelopes': envelopes.map((e) => e.toJson()).toList(),
      });
      request.write(body);

      final response = await request.close();
      return response.statusCode == 202 || response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Acknowledges envelopes to immediately purge them from server memory.
  Future<bool> acknowledgeEnvelopes(List<String> envelopeIds) async {
    if (envelopeIds.isEmpty) return true;

    final client = HttpClient();
    try {
      final uri = Uri.parse('$baseUrl/v1/mailbox/ack');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'device_id': deviceId,
        'acknowledged_envelope_ids': envelopeIds,
      });
      request.write(body);

      final response = await request.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Disconnects and cleans up resources.
  void dispose() {
    _reconnectTimer?.cancel();
    _webSocket?.close();
    _incomingEnvelopesController.close();
    _connectionStateController.close();
  }
}
