import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';

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

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _isMuted = false;
  bool _isSpeaker = false;
  late bool _isVideoEnabled;
  final int _callDurationSeconds = 42; // Simulated active call duration

  @override
  void initState() {
    super.initState();
    _isVideoEnabled = widget.isVideo;
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: DTLS-SRTP Media Encryption Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: NexaColors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: NexaColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: NexaColors.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 13),
                        SizedBox(width: 6),
                        Text(
                          'WebRTC DTLS-SRTP E2E',
                          style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 40), // Balance spacing
                ],
              ),
            ),

            const Spacer(flex: 1),

            // Peer Identity Display & Audio Wave Pulse
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ambient Radial Wave
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NexaColors.cyanAccent.withValues(alpha: 0.08),
                        ),
                      ),
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NexaColors.cyanAccent.withValues(alpha: 0.16),
                        ),
                      ),
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: NexaColors.elevated,
                        child: Text(
                          widget.peerName.substring(0, 1),
                          style: const TextStyle(color: NexaColors.cyanAccent, fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.peerName,
                    style: const TextStyle(
                      color: NexaColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.peerNexaId,
                    style: const TextStyle(color: NexaColors.textMuted, fontSize: 13, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatDuration(_callDurationSeconds),
                    style: const TextStyle(color: NexaColors.cyanAccent, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 2),

            // Tactile Call Controls
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: NexaColors.surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: NexaColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Mute Button
                  _buildCallAction(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Muted' : 'Mute',
                    isActive: _isMuted,
                    onTap: () => setState(() => _isMuted = !_isMuted),
                  ),

                  // Speaker Button
                  _buildCallAction(
                    icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                    label: 'Speaker',
                    isActive: _isSpeaker,
                    onTap: () => setState(() => _isSpeaker = !_isSpeaker),
                  ),

                  // Video Button
                  _buildCallAction(
                    icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    label: 'Video',
                    isActive: _isVideoEnabled,
                    onTap: () => setState(() => _isVideoEnabled = !_isVideoEnabled),
                  ),

                  // End Call Button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                        const Text('End', style: TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallAction({
    required IconData icon,
    required String label,
    required bool isActive,
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
              color: isActive ? NexaColors.cyanAccent : NexaColors.elevated,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black : NexaColors.textPrimary,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
