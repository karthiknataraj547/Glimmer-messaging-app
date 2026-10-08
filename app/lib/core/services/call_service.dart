import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/auth_service.dart';
import '../session/user_session.dart';
import '../../features/calls/presentation/active_call_screen.dart';

/// Real-Time Call Signaling & Video/Voice Calling Gateway
class CallService {
  static final CallService instance = CallService._internal();
  CallService._internal();

  Timer? _pollingTimer;
  String? _activeCallId;
  bool _isPromptingIncoming = false;
  BuildContext? _rootContext;

  /// Register app-wide context for global incoming call invitations
  void attachContext(BuildContext context) {
    _rootContext = context;
  }

  /// Start background listening for incoming calls for logged-in user
  void startListening(BuildContext context) {
    _rootContext = context;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollIncomingCall();
    });
  }

  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  bool get isInActiveCall => _activeCallId != null;

  void setActiveCallId(String? id) {
    _activeCallId = id;
  }

  /// User 1 initiates call to User 2
  Future<String?> initiateCall({
    required BuildContext context,
    required String recipientHandle,
    required String recipientNexaId,
    required String peerName,
    required bool isVideo,
  }) async {
    final callerHandle = UserSession.instance.handle.replaceAll('@', '');
    final callerNexaId = UserSession.instance.nexaId;
    final callerName = UserSession.instance.fullName.isNotEmpty
        ? UserSession.instance.fullName
        : callerHandle;

    final offerId = 'call_${DateTime.now().millisecondsSinceEpoch}_${callerHandle}_to_${recipientHandle.replaceAll('@', '')}';

    final body = {
      'caller_handle': callerHandle,
      'caller_nexa_id': callerNexaId,
      'caller_name': callerName,
      'recipient_handle': recipientHandle.replaceAll('@', ''),
      'recipient_nexa_id': recipientNexaId,
      'call_type': isVideo ? 'video' : 'voice',
      'offer_id': offerId,
    };

    try {
      final res = await AuthService.instance.postJson('/v1/calls/offer', body);
      if (res != null && res['success'] == true) {
        final callId = (res['call_id'] as String?) ?? offerId;
        _activeCallId = callId;

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ActiveCallScreen(
                peerName: peerName,
                peerNexaId: recipientNexaId,
                isVideo: isVideo,
                callId: callId,
                isIncoming: false,
              ),
            ),
          ).then((_) {
            _activeCallId = null;
          });
        }
        return callId;
      }
    } catch (e) {
      debugPrint('[CallService] initiateCall error: $e');
    }
    return null;
  }

  /// Callee polls server for incoming calls addressed to them
  Future<void> _pollIncomingCall() async {
    if (!UserSession.instance.isLoggedIn) return;
    if (_activeCallId != null || _isPromptingIncoming) return;
    if (_rootContext == null || !_rootContext!.mounted) return;

    final myHandle = UserSession.instance.handle.replaceAll('@', '');
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/calls/incoming/$myHandle');
      final res = await AuthService.instance.getJson(uri);

      if (res != null && res['has_incoming'] == true && res['call'] is Map) {
        final call = Map<String, dynamic>.from(res['call'] as Map);
        final callId = call['call_id'] as String? ?? '';
        final status = call['status'] as String? ?? 'ringing';

        if (status == 'ringing' && callId.isNotEmpty && callId != _activeCallId) {
          _isPromptingIncoming = true;
          _showIncomingCallDialog(_rootContext!, call);
        }
      }
    } catch (_) {}
  }

  /// Shows the incoming call invitation with Accept and Decline buttons
  void _showIncomingCallDialog(BuildContext context, Map<String, dynamic> call) {
    final callId = call['call_id'] as String;
    final callerName = (call['caller_name'] as String?) ?? (call['caller_handle'] as String?) ?? 'Peer';
    final callerHandle = (call['caller_handle'] as String?) ?? '';
    final callerNexaId = (call['caller_nexa_id'] as String?) ?? 'NX-PEER';
    final isVideo = (call['call_type'] as String?) == 'video';

    HapticFeedback.heavyImpact();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return _IncomingCallModal(
          callerName: callerName,
          callerHandle: callerHandle,
          callerNexaId: callerNexaId,
          isVideo: isVideo,
          onAccept: () async {
            Navigator.pop(dialogCtx);
            _isPromptingIncoming = false;
            _activeCallId = callId;

            // Notify server that call is accepted
            await AuthService.instance.postJson('/v1/calls/answer', {
              'call_id': callId,
              'accepted': true,
            });

            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActiveCallScreen(
                    peerName: callerName,
                    peerNexaId: callerNexaId,
                    isVideo: isVideo,
                    callId: callId,
                    isIncoming: true,
                  ),
                ),
              ).then((_) {
                _activeCallId = null;
              });
            }
          },
          onDecline: () async {
            Navigator.pop(dialogCtx);
            _isPromptingIncoming = false;

            // Notify server that call is declined
            await AuthService.instance.postJson('/v1/calls/answer', {
              'call_id': callId,
              'accepted': false,
            });
          },
        );
      },
    ).then((_) {
      _isPromptingIncoming = false;
    });
  }

  /// End active call on server
  Future<void> endCall(String callId) async {
    _activeCallId = null;
    try {
      await AuthService.instance.postJson('/v1/calls/end', {'call_id': callId});
    } catch (_) {}
  }

  /// Check call status from server
  Future<Map<String, dynamic>?> getCallSession(String callId) async {
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/calls/session/$callId');
      final res = await AuthService.instance.getJson(uri);
      if (res != null && res['session'] is Map) {
        return Map<String, dynamic>.from(res['session'] as Map);
      }
    } catch (_) {}
    return null;
  }
}

class _IncomingCallModal extends StatefulWidget {
  final String callerName;
  final String callerHandle;
  final String callerNexaId;
  final bool isVideo;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingCallModal({
    required this.callerName,
    required this.callerHandle,
    required this.callerNexaId,
    required this.isVideo,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_IncomingCallModal> createState() => _IncomingCallModalState();
}

class _IncomingCallModalState extends State<_IncomingCallModal> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: (widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981)).withValues(alpha: 0.25),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing pulsing caller avatar
            AnimatedBuilder(
              animation: _anim,
              builder: (context, child) {
                final scale = 1.0 + (_anim.value * 0.08);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
                        width: 2.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 38,
                      backgroundColor: const Color(0xFF1E293B),
                      child: Text(
                        widget.callerName.isNotEmpty ? widget.callerName.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // Call Type Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981)).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isVideo ? Icons.videocam : Icons.phone_in_talk,
                    size: 14,
                    color: widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isVideo ? 'INCOMING VIDEO CALL' : 'INCOMING VOICE CALL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Caller Name & Handle
            Text(
              widget.callerName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '@${widget.callerHandle} • ${widget.callerNexaId}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 12, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text(
                  'End-to-End Encrypted Call',
                  style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Answer & Decline Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline Button (Red)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: widget.onDecline,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Decline', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),

                // Accept Button (Green)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: widget.onAccept,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isVideo ? Icons.videocam : Icons.call,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Answer', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
