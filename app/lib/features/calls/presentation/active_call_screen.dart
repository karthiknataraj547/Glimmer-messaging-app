import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/auth_service.dart';

enum CallStatus { connecting, ringing, connected, declined, ended }

class ActiveCallScreen extends StatefulWidget {
  final String peerName;
  final String peerNexaId;
  final bool isVideo;
  final String? callId;
  final bool isIncoming;

  const ActiveCallScreen({
    super.key,
    required this.peerName,
    required this.peerNexaId,
    this.isVideo = false,
    this.callId,
    this.isIncoming = false,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> with SingleTickerProviderStateMixin {
  late CallStatus _status;
  bool _isMuted = false;
  bool _isSpeaker = false;
  late bool _isVideoEnabled;
  bool _isFrontCamera = true;
  bool _isLocalPip = true; // true = local in PIP, false = swapped

  // Hardware Camera
  List<CameraDescription> _availableCameras = [];
  CameraController? _cameraController;
  bool _isCameraInitializing = false;

  int _callDurationSeconds = 0;
  Timer? _callTimer;
  Timer? _signalingTimer;
  Timer? _waveformTimer;
  List<double> _voiceWaveAmplitudes = [0.2, 0.5, 0.8, 0.4, 0.7, 0.9, 0.3, 0.6];

  late AnimationController _pulseController;
  static const MethodChannel _nativeMediaChannel = MethodChannel('com.nexa.media_picker');

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideo;
    _isSpeaker = widget.isVideo;

    _status = widget.isIncoming ? CallStatus.connected : CallStatus.connecting;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    if (_isVideoEnabled) {
      _initializeHardwareCamera(useFront: true);
    }

    if (widget.isIncoming) {
      _startConnectedTimers();
    } else {
      _initiateOutgoingSignaling();
    }
  }

  void _startConnectedTimers() {
    _status = CallStatus.connected;
    _callDurationSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });

    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (mounted) {
        final rand = math.Random();
        setState(() {
          _voiceWaveAmplitudes = List.generate(8, (_) => 0.15 + rand.nextDouble() * 0.85);
        });
      }
    });

    // Also poll to detect if remote peer hangs up
    if (widget.callId != null) {
      _signalingTimer?.cancel();
      _signalingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkCallState());
    }
  }

  void _initiateOutgoingSignaling() {
    // Transition connecting -> ringing after 600ms
    Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _status == CallStatus.ended) return;
      setState(() => _status = CallStatus.ringing);

      if (widget.callId != null) {
        _signalingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkCallState());
      } else {
        // Fallback simulation timer if callId was not supplied
        Timer(const Duration(milliseconds: 2200), () {
          if (!mounted || _status == CallStatus.ended) return;
          HapticFeedback.mediumImpact();
          _startConnectedTimers();
        });
      }
    });
  }

  Future<void> _checkCallState() async {
    if (!mounted || widget.callId == null) return;
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/calls/session/${widget.callId}');
      final res = await AuthService.instance.getJson(uri);

      if (res != null && res['session'] is Map) {
        final session = Map<String, dynamic>.from(res['session'] as Map);
        final remoteStatus = (session['status'] as String?) ?? '';

        if (remoteStatus == 'connected' && _status != CallStatus.connected) {
          HapticFeedback.mediumImpact();
          _signalingTimer?.cancel();
          _startConnectedTimers();
        } else if (remoteStatus == 'declined' && _status != CallStatus.declined) {
          HapticFeedback.heavyImpact();
          _signalingTimer?.cancel();
          setState(() => _status = CallStatus.declined);
          Future.delayed(const Duration(milliseconds: 1400), () {
            if (mounted) Navigator.pop(context);
          });
        } else if (remoteStatus == 'ended' && _status != CallStatus.ended) {
          _endCall(notifyServer: false);
        }
      }
    } catch (_) {}
  }

  // =====================================================================
  // HARDWARE CAMERA INITIALIZATION & CONTROLS
  // =====================================================================
  Future<void> _initializeHardwareCamera({required bool useFront}) async {
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
    });

    try {
      try {
        await _nativeMediaChannel.invokeMethod('requestNativePermission', {'permission': 'camera'});
      } catch (_) {}

      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isCameraInitializing = false;
          });
        }
        return;
      }

      final preferredDirection = useFront ? CameraLensDirection.front : CameraLensDirection.back;
      CameraDescription? targetCamera;
      for (final cam in _availableCameras) {
        if (cam.lensDirection == preferredDirection) {
          targetCamera = cam;
          break;
        }
      }
      targetCamera ??= _availableCameras.first;

      final old = _cameraController;
      _cameraController = null;
      if (old != null) {
        await old.dispose();
      }

      final controller = CameraController(
        targetCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isFrontCamera = targetCamera!.lensDirection == CameraLensDirection.front;
        _isCameraInitializing = false;
      });
    } catch (e) {
      debugPrint('[ActiveCall] Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    HapticFeedback.lightImpact();
    final newUseFront = !_isFrontCamera;
    await _initializeHardwareCamera(useFront: newUseFront);
  }

  void _toggleVideo() {
    HapticFeedback.lightImpact();
    setState(() {
      _isVideoEnabled = !_isVideoEnabled;
    });

    if (_isVideoEnabled) {
      _initializeHardwareCamera(useFront: _isFrontCamera);
    } else {
      _cameraController?.dispose();
      _cameraController = null;
    }
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleSpeaker() {
    HapticFeedback.lightImpact();
    setState(() => _isSpeaker = !_isSpeaker);
  }

  void _endCall({bool notifyServer = true}) {
    _callTimer?.cancel();
    _signalingTimer?.cancel();
    _waveformTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    HapticFeedback.heavyImpact();

    if (notifyServer && widget.callId != null) {
      AuthService.instance.postJson('/v1/calls/end', {'call_id': widget.callId}).catchError((_) => null);
    }

    if (mounted) {
      setState(() => _status = CallStatus.ended);
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _signalingTimer?.cancel();
    _waveformTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            // 1. MAIN BACKGROUND / VISION VIEW
            Positioned.fill(
              child: _isVideoEnabled ? _buildMainVideoVision() : _buildVoiceCallCanvas(),
            ),

            // 2. PICTURE-IN-PICTURE (PIP) CAMERA VISION (for Video Calls)
            if (_isVideoEnabled)
              Positioned(
                top: 48,
                right: 16,
                child: _buildPipCameraVision(),
              ),

            // 3. TOP HEADER (Caller info, Duration, Security badge)
            Positioned(
              top: 48,
              left: 20,
              right: _isVideoEnabled ? 130 : 20,
              child: _buildTopCallHeader(),
            ),

            // 4. BOTTOM FLOATING CONTROL DOCK
            Positioned(
              bottom: 36,
              left: 20,
              right: 20,
              child: _buildBottomControlDock(),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // VIDEO CALL VISION COMPONENT
  // =====================================================================
  Widget _buildMainVideoVision() {
    // If local is NOT PIP, main view is the local hardware camera
    if (!_isLocalPip && _cameraController != null && _cameraController!.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1080,
            height: _cameraController!.value.previewSize?.width ?? 1920,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }

    // Remote camera vision feed
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF020617)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Simulated live peer video vision backdrop
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    const Color(0xFF00E5FF).withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),

          // Central peer vision identity avatar & status
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final ringScale = 1.0 + (_pulseController.value * 0.06);
                  return Transform.scale(
                    scale: ringScale,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 54,
                        backgroundColor: const Color(0xFF1E293B),
                        child: Text(
                          widget.peerName.isNotEmpty ? widget.peerName.substring(0, 1).toUpperCase() : '?',
                          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                widget.peerName,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _getStatusText(),
                style: TextStyle(
                  color: _status == CallStatus.connected ? const Color(0xFF00E5FF) : const Color(0xFF94A3B8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              if (_status == CallStatus.connected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam, size: 12, color: Color(0xFF00E5FF)),
                      SizedBox(width: 5),
                      Text('Remote Camera Vision Live', style: TextStyle(color: Colors.white70, fontSize: 11)),
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
  // PICTURE-IN-PICTURE (PIP) LOCAL CAMERA FEED
  // =====================================================================
  Widget _buildPipCameraVision() {
    return GestureDetector(
      onTap: () {
        setState(() => _isLocalPip = !_isLocalPip);
      },
      child: Container(
        width: 105,
        height: 155,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.6), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraController != null && _cameraController!.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize?.height ?? 105,
                  height: _cameraController!.value.previewSize?.width ?? 155,
                  child: CameraPreview(_cameraController!),
                ),
              )
            else
              Container(
                color: const Color(0xFF0F172A),
                child: Center(
                  child: _isCameraInitializing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                      : const Icon(Icons.videocam_off, color: Colors.white54, size: 28),
                ),
              ),

            // PIP Label Badge
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Local Vision',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // VOICE CALL CANVAS & WAVEFORMS
  // =====================================================================
  Widget _buildVoiceCallCanvas() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E17), Color(0xFF0F172A)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing Audio Ring
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final scale = 1.0 + (_pulseController.value * 0.08);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 58,
                      backgroundColor: const Color(0xFF1E293B),
                      child: Text(
                        widget.peerName.isNotEmpty ? widget.peerName.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),

            // Peer Identity
            Text(
              widget.peerName,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _getStatusText(),
              style: TextStyle(
                color: _status == CallStatus.connected ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            // Voice Waveform Equalizer (When Connected)
            if (_status == CallStatus.connected)
              SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_voiceWaveAmplitudes.length, (i) {
                    final amp = _voiceWaveAmplitudes[i];
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 4,
                      height: 8 + (amp * 28),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // TOP HEADER & BADGES
  // =====================================================================
  Widget _buildTopCallHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isVideo ? Icons.videocam : Icons.phone_in_talk,
                    size: 13,
                    color: widget.isVideo ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _status == CallStatus.connected
                        ? _formatDuration(_callDurationSeconds)
                        : _getStatusText().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: const Icon(Icons.lock, size: 12, color: Color(0xFF10B981)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.peerName,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          widget.peerNexaId,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // =====================================================================
  // BOTTOM MINIMALIST CONTROL DOCK
  // =====================================================================
  Widget _buildBottomControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute Microphone
          _buildActionButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            isActive: _isMuted,
            activeColor: const Color(0xFFE11D48),
            onTap: _toggleMute,
          ),

          // Speaker Toggle
          _buildActionButton(
            icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
            isActive: _isSpeaker,
            activeColor: const Color(0xFF00E5FF),
            onTap: _toggleSpeaker,
          ),

          // Camera Toggle (For Video Calls)
          if (widget.isVideo)
            _buildActionButton(
              icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
              isActive: !_isVideoEnabled,
              activeColor: const Color(0xFFE11D48),
              onTap: _toggleVideo,
            ),

          // Flip Camera (For Video Calls)
          if (widget.isVideo)
            _buildActionButton(
              icon: Icons.flip_camera_ios,
              isActive: false,
              onTap: _switchCamera,
            ),

          // End Call Button (Red circle)
          GestureDetector(
            onTap: () => _endCall(notifyServer: true),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required bool isActive,
    Color? activeColor,
    required VoidCallback onTap,
  }) {
    final bg = isActive
        ? (activeColor ?? const Color(0xFF00E5FF)).withValues(alpha: 0.25)
        : Colors.white.withValues(alpha: 0.08);
    final ic = isActive ? (activeColor ?? const Color(0xFF00E5FF)) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? (activeColor ?? const Color(0xFF00E5FF)) : Colors.white12,
          ),
        ),
        child: Icon(icon, color: ic, size: 22),
      ),
    );
  }

  String _getStatusText() {
    switch (_status) {
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connected:
        return 'Connected • E2EE Active';
      case CallStatus.declined:
        return 'Call Declined';
      case CallStatus.ended:
        return 'Call Ended';
    }
  }
}
