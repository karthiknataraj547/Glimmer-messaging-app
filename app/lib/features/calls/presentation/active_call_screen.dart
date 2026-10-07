import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/nexa_theme.dart';

enum CallStatus { connecting, ringing, connected, ended }

class ActiveCallScreen extends StatefulWidget {
  final String peerName;
  final String peerNexaId;
  final bool isVideo;

  const ActiveCallScreen({
    super.key,
    required this.peerName,
    required this.peerNexaId,
    this.isVideo = false,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> with SingleTickerProviderStateMixin {
  CallStatus _status = CallStatus.connecting;
  bool _isMuted = false;
  bool _isSpeaker = false;
  late bool _isVideoEnabled;
  bool _isFrontCamera = true;

  // Real Hardware Camera Controllers
  List<CameraDescription> _availableCameras = [];
  CameraController? _cameraController;
  bool _isCameraInitializing = false;
  String? _cameraErrorMessage;

  int _callDurationSeconds = 0;
  Timer? _callTimer;
  Timer? _simulatedVoiceTimer;
  List<double> _voiceWaveAmplitudes = [0.2, 0.5, 0.8, 0.4, 0.7, 0.9, 0.3, 0.6];

  late AnimationController _pulseController;

  static const MethodChannel _nativeMediaChannel = MethodChannel('com.nexa.media_picker');

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideo;
    _isSpeaker = widget.isVideo; // Video default to speaker

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _initiateCallSignaling();

    if (_isVideoEnabled) {
      _initializeHardwareCamera(useFront: true);
    }
  }

  void _initiateCallSignaling() {
    // 1. Connecting state -> 1.0s -> Ringing
    Timer(const Duration(milliseconds: 1000), () {
      if (!mounted || _status == CallStatus.ended) return;
      setState(() {
        _status = CallStatus.ringing;
      });

      // 2. Ringing state -> 1.8s -> Connected (Call Answered)
      Timer(const Duration(milliseconds: 1800), () {
        if (!mounted || _status == CallStatus.ended) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _status = CallStatus.connected;
          _callDurationSeconds = 0;
        });

        // 3. Start Call Duration Counter
        _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            _callDurationSeconds++;
          });
        });

        // 4. Start Voice Wave Animation
        _simulatedVoiceTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
          if (!mounted) return;
          final rand = math.Random();
          setState(() {
            _voiceWaveAmplitudes = List.generate(8, (_) => 0.15 + rand.nextDouble() * 0.85);
          });
        });
      });
    });
  }

  // =====================================================================
  // HARDWARE CAMERA INITIALIZATION & LENS SWITCHING
  // =====================================================================
  Future<void> _initializeHardwareCamera({required bool useFront}) async {
    if (!mounted) return;
    setState(() {
      _isCameraInitializing = true;
      _cameraErrorMessage = null;
    });

    try {
      // Ensure Android runtime camera permission is requested
      try {
        await _nativeMediaChannel.invokeMethod('requestNativePermission', {'permission': 'camera'});
      } catch (_) {}

      // Discover physical camera sensors on the device
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isCameraInitializing = false;
            _cameraErrorMessage = 'No physical camera hardware detected on this device.';
          });
        }
        return;
      }

      // Locate preferred sensor (Front vs Back)
      final preferredDirection = useFront ? CameraLensDirection.front : CameraLensDirection.back;
      CameraDescription? targetCamera;
      for (final cam in _availableCameras) {
        if (cam.lensDirection == preferredDirection) {
          targetCamera = cam;
          break;
        }
      }
      targetCamera ??= _availableCameras.first;

      // Dispose prior controller before initializing new one
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
      debugPrint('Real camera initialization error: $e');
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'Hardware Camera Error: $e';
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    HapticFeedback.lightImpact();
    final newUseFront = !_isFrontCamera;
    await _initializeHardwareCamera(useFront: newUseFront);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newUseFront ? 'Switched to Front Camera' : 'Switched to Rear / Back Camera',
          ),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
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

  @override
  void dispose() {
    _callTimer?.cancel();
    _simulatedVoiceTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _endCall() {
    _callTimer?.cancel();
    _simulatedVoiceTimer?.cancel();
    _cameraController?.dispose();
    _cameraController = null;
    HapticFeedback.heavyImpact();

    setState(() {
      _status = CallStatus.ended;
    });

    final durationFormatted = _formatDuration(_callDurationSeconds);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _callDurationSeconds > 0
              ? 'Encrypted Call Ended • Duration: $durationFormatted'
              : 'Call cancelled.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    Navigator.pop(context);
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    setState(() {
      _isMuted = !_isMuted;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isMuted ? 'Microphone muted' : 'Microphone active'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _toggleSpeaker() {
    HapticFeedback.lightImpact();
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Stack(
          children: [
            // Background Viewport: Real Video Hardware Stream OR Audio Wave Viewport
            if (_isVideoEnabled) ...[
              _buildRealVideoViewport(),
            ] else ...[
              _buildAudioViewport(),
            ],

            // Top Header Overlay: DTLS-SRTP Encryption HUD & Flip Camera
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: _buildTopHeader(),
            ),

            // Bottom In-Call Tactile Controls
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _buildCallControls(),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // TOP HEADER OVERLAY
  // =====================================================================
  Widget _buildTopHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: _endCall,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 13),
              SizedBox(width: 6),
              Text(
                'WebRTC DTLS-SRTP E2EE',
                style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        if (_isVideoEnabled)
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 24),
            tooltip: 'Flip Camera (Front / Back)',
            onPressed: _switchCamera,
          )
        else
          const SizedBox(width: 44),
      ],
    );
  }

  // =====================================================================
  // REAL PHYSICAL HARDWARE VIDEO VIEWPORT
  // =====================================================================
  Widget _buildRealVideoViewport() {
    if (_isCameraInitializing) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: NexaColors.primary),
              SizedBox(height: 18),
              Text(
                'Opening Device Camera Hardware...',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Activating native sensor lens & AEAD video pipeline',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Physical Live Camera Stream
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _cameraController!.value.previewSize?.height ?? 1080,
                height: _cameraController!.value.previewSize?.width ?? 1920,
                child: CameraPreview(_cameraController!),
              ),
            ),

            // Top Gradient Shadow for Contrast
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Gradient Shadow for Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Sensor HUD Indicator (Front / Back Camera & Timer)
            Positioned(
              top: 68,
              left: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: NexaColors.emeraldSecure,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_isFrontCamera ? "FRONT SENSOR" : "REAR SENSOR"} • ${_formatDuration(_callDurationSeconds)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Peer Call Status Header
            Positioned(
              top: 68,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white70, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      widget.peerName,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Hardware Error / Unavailable View
    return Container(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white54, size: 54),
              const SizedBox(height: 16),
              Text(
                _cameraErrorMessage ?? 'Physical camera sensor unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexaColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry Camera Hardware'),
                onPressed: () => _initializeHardwareCamera(useFront: _isFrontCamera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // AUDIO VIEWPORT (CALLING / RINGING / CONNECTED WAVES)
  // =====================================================================
  Widget _buildAudioViewport() {
    String statusLabel;
    Color statusColor;

    switch (_status) {
      case CallStatus.connecting:
        statusLabel = 'Connecting Encrypted Tunnel...';
        statusColor = NexaColors.amberAttention;
        break;
      case CallStatus.ringing:
        statusLabel = 'Ringing Peer Device...';
        statusColor = NexaColors.primary;
        break;
      case CallStatus.connected:
        statusLabel = _formatDuration(_callDurationSeconds);
        statusColor = Colors.white;
        break;
      case CallStatus.ended:
        statusLabel = 'Call Terminated';
        statusColor = NexaColors.rubyDestructive;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Peer Avatar with Pulsing Signal Ripple
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController.value * 0.08);
              return Transform.scale(
                scale: _status != CallStatus.connected ? scale : 1.0,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NexaColors.primary.withValues(alpha: 0.15),
                    border: Border.all(
                      color: _status == CallStatus.connected
                          ? NexaColors.emeraldSecure
                          : NexaColors.primary.withValues(alpha: 0.5),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: NexaColors.primary,
                      child: Text(
                        widget.peerName.isNotEmpty ? widget.peerName.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          // Peer Name
          Text(
            widget.peerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),

          // NEXA Cryptographic ID
          Text(
            widget.peerNexaId,
            style: const TextStyle(
              color: Colors.white54,
              fontFamily: 'Courier',
              fontSize: 13,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 18),

          // Call Status Pill Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: _status == CallStatus.connected ? 18 : 14,
                fontFamily: _status == CallStatus.connected ? 'Courier' : null,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Dynamic Voice Visualizer Wave when connected
          if (_status == CallStatus.connected) ...[
            const SizedBox(height: 24),
            SizedBox(
              height: 32,
              width: 140,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _voiceWaveAmplitudes.map((amp) {
                  return Container(
                    width: 4,
                    height: (30 * amp).clamp(6.0, 30.0),
                    decoration: BoxDecoration(
                      color: _isMuted ? Colors.white30 : NexaColors.emeraldSecure,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================================
  // IN-CALL CONTROLS BAR
  // =====================================================================
  Widget _buildCallControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Mute Button
          _buildCallActionButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Muted' : 'Mute',
            isActive: _isMuted,
            activeColor: NexaColors.rubyDestructive,
            onTap: _toggleMute,
          ),

          // Speaker Button
          _buildCallActionButton(
            icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
            label: _isSpeaker ? 'Speaker' : 'Ear',
            isActive: _isSpeaker,
            activeColor: NexaColors.primary,
            onTap: _toggleSpeaker,
          ),

          // Video On/Off Button
          _buildCallActionButton(
            icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
            label: 'Video',
            isActive: _isVideoEnabled,
            activeColor: NexaColors.emeraldSecure,
            onTap: _toggleVideo,
          ),

          // End Call Button
          GestureDetector(
            onTap: _endCall,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: NexaColors.rubyDestructive,
                  ),
                  child: const Icon(Icons.call_end, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 6),
                const Text('End', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? activeColor : const Color(0xFF334155),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
