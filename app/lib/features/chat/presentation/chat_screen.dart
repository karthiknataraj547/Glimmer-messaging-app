import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/nexa_theme.dart';
import '../../calls/presentation/active_call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;
  final String nexaId;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.nexaId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isComposing = false;
  String _disappearingTimer = 'Off';
  bool _isSafetyNumberVerified = false;

  final List<Map<String, dynamic>> _messages = [
    {
      'id': 'm1',
      'isMe': false,
      'text': 'Hey Karthik, are we meeting tomorrow at 10 AM?',
      'time': '8:42 PM',
      'hasAction': true,
      'actionAdded': false,
      'actionDismissed': false,
      'actionTitle': 'Meeting with Rahul',
      'actionTime': 'Tomorrow, 10:00 AM',
      'reactions': <String>[],
    },
    {
      'id': 'm2',
      'isMe': true,
      'text': 'Yes, 10 AM sounds perfect. See you at the coffee shop! 👍',
      'time': '8:44 PM',
      'hasAction': false,
      'actionAdded': false,
      'actionDismissed': false,
      'reactions': <String>['👍'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final composing = _messageController.text.trim().isNotEmpty;
      if (composing != _isComposing) {
        setState(() => _isComposing = composing);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final now = TimeOfDay.now();
    final timeStr = '${now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';

    setState(() {
      _messages.add({
        'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
        'isMe': true,
        'text': text,
        'time': timeStr,
        'hasAction': false,
        'actionAdded': false,
        'actionDismissed': false,
        'reactions': <String>[],
      });
      _messageController.clear();
      _isComposing = false;
    });

    _scrollToBottom();
  }

  void _sendAudioNote() {
    final now = TimeOfDay.now();
    final timeStr = '${now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';

    setState(() {
      _messages.add({
        'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
        'isMe': true,
        'isAudio': true,
        'audioDuration': '0:14',
        'text': 'Voice memo (0:14)',
        'time': timeStr,
        'hasAction': false,
        'actionAdded': false,
        'actionDismissed': false,
        'reactions': <String>[],
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Encrypted audio memo sent.'),
        duration: Duration(seconds: 2),
      ),
    );

    _scrollToBottom();
  }

  void _sendAttachment(String type, String title) {
    final now = TimeOfDay.now();
    final timeStr = '${now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';

    setState(() {
      _messages.add({
        'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
        'isMe': true,
        'attachmentType': type,
        'text': title,
        'time': timeStr,
        'hasAction': false,
        'actionAdded': false,
        'actionDismissed': false,
        'reactions': <String>[],
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type encrypted and sent.'),
        duration: const Duration(seconds: 2),
      ),
    );

    _scrollToBottom();
  }

  void _showAttachmentPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: NexaColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Encrypted Attachment',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: NexaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  children: [
                    _buildAttachmentItem(
                      icon: Icons.camera_alt_outlined,
                      color: const Color(0xFF0284C7),
                      label: 'Camera',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAttachment('Photo', '📷 Encrypted photo captured');
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.image_outlined,
                      color: const Color(0xFF10B981),
                      label: 'Gallery',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAttachment('Image', '🖼️ Schematic_diagram.png (2.1 MB)');
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.insert_drive_file_outlined,
                      color: const Color(0xFF8B5CF6),
                      label: 'Document',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAttachment('Document', '📄 audit_report_2026.pdf (1.4 MB)');
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.timer_outlined,
                      color: const Color(0xFFF59E0B),
                      label: 'Timer',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDisappearingMessagesModal();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.mic_none_outlined,
                      color: const Color(0xFFEC4899),
                      label: 'Audio',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAudioNote();
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.location_on_outlined,
                      color: const Color(0xFFEF4444),
                      label: 'Location',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAttachment('Location', '📍 Ephemeral Location • 12.9716° N, 77.5946° E');
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.person_outline,
                      color: const Color(0xFF06B6D4),
                      label: 'Contact',
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendAttachment('Contact', '👤 Dr. Elena Rostova (NX-48A1-99XK)');
                      },
                    ),
                    _buildAttachmentItem(
                      icon: Icons.shield_outlined,
                      color: NexaColors.emeraldSecure,
                      label: 'Verify Key',
                      onTap: () {
                        Navigator.pop(ctx);
                        _showSafetyNumberModal();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: NexaColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showDisappearingMessagesModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final options = ['Off', '30 Seconds', '5 Minutes', '1 Hour', '24 Hours', '7 Days'];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Disappearing Messages Timer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: NexaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Messages will be zeroized and securely wiped on both devices after viewing.',
                  style: TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...options.map((opt) {
                  final isSelected = _disappearingTimer == opt;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      opt,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? NexaColors.cyanAccent : NexaColors.textPrimary,
                      ),
                    ),
                    trailing: isSelected ? const Icon(Icons.check, color: NexaColors.cyanAccent) : null,
                    onTap: () {
                      setState(() => _disappearingTimer = opt);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Disappearing messages set to: $opt')),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSafetyNumberModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NexaColors.emeraldSecure.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified_user, color: NexaColors.emeraldSecure, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Verify Safety Number',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Compare this 60-digit cryptographic fingerprint with ${widget.contactName} to ensure no man-in-the-middle.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NexaColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: NexaColors.elevatedLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: NexaColors.borderLight),
                      ),
                      child: const SelectableText(
                        '38402 91847 20194 88371\n92847 10482 77361 99284\n10293 84729 10492 85720',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: NexaColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(
                                text: '384029184720194883719284710482773619928410293847291049285720',
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Safety number copied to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy Fingerprint'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isSafetyNumberVerified ? NexaColors.borderStrongLight : NexaColors.emeraldSecure,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              setState(() => _isSafetyNumberVerified = !_isSafetyNumberVerified);
                              setModalState(() {});
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_isSafetyNumberVerified
                                      ? 'Marked as verified! Cryptographic channel authenticated.'
                                      : 'Safety number verification reset.'),
                                ),
                              );
                            },
                            icon: Icon(_isSafetyNumberVerified ? Icons.check : Icons.done_all, size: 16),
                            label: Text(_isSafetyNumberVerified ? 'Verified ✓' : 'Mark Verified'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMessageOptions(Map<String, dynamic> msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji Reaction Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['👍', '❤️', '💡', '🔥', '🚀'].map((emoji) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          final reactions = (msg['reactions'] as List<String>);
                          if (reactions.contains(emoji)) {
                            reactions.remove(emoji);
                          } else {
                            reactions.add(emoji);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const Divider(height: 1, color: NexaColors.borderLight),
              ListTile(
                leading: const Icon(Icons.copy, size: 20),
                title: const Text('Copy Text'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg['text'] as String));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied to clipboard')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply, size: 20),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  _messageController.text = 'Re: "${msg['text']}" ';
                  _messageController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _messageController.text.length),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, size: 20, color: NexaColors.rubyDestructive),
                title: const Text('Delete for Me', style: TextStyle(color: NexaColors.rubyDestructive)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _messages.remove(msg));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: NexaColors.surfaceLight,
        elevation: 0.5,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: NexaColors.elevatedLight,
              child: Text(
                widget.contactName.substring(0, 1),
                style: const TextStyle(color: NexaColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.contactName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: NexaColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_isSafetyNumberVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, color: NexaColors.emeraldSecure, size: 14),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        widget.nexaId,
                        style: const TextStyle(fontSize: 11, color: NexaColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: NexaColors.textSecondary),
            tooltip: 'Encrypted Voice Call',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActiveCallScreen(
                  peerName: widget.contactName,
                  peerNexaId: widget.nexaId,
                  isVideo: false,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: NexaColors.textSecondary),
            tooltip: 'Encrypted Video Call',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActiveCallScreen(
                  peerName: widget.contactName,
                  peerNexaId: widget.nexaId,
                  isVideo: true,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isSafetyNumberVerified ? Icons.verified_user : Icons.shield_outlined,
              color: NexaColors.emeraldSecure,
              size: 20,
            ),
            tooltip: 'Safety Number',
            onPressed: _showSafetyNumberModal,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: NexaColors.textSecondary),
            onSelected: (val) {
              if (val == 'verify') {
                _showSafetyNumberModal();
              } else if (val == 'timer') {
                _showDisappearingMessagesModal();
              } else if (val == 'clear') {
                setState(() => _messages.clear());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat messages cleared locally')),
                );
              } else if (val == 'export') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exporting zero-knowledge encrypted backup...')),
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'verify',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: NexaColors.emeraldSecure),
                    SizedBox(width: 10),
                    Text('Verify Safety Number'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'timer',
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text('Disappearing: $_disappearingTimer'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Export Encrypted Backup'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: NexaColors.rubyDestructive),
                    SizedBox(width: 10),
                    Text('Clear Messages', style: TextStyle(color: NexaColors.rubyDestructive)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // E2E Minimalist Security Notice
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCFCE7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 14),
                const SizedBox(width: 6),
                Text(
                  _disappearingTimer == 'Off'
                      ? 'PointyCastle Double Ratchet 256-bit active. Zero-Knowledge.'
                      : 'Messages disappear after $_disappearingTimer. Double Ratchet active.',
                  style: const TextStyle(color: Color(0xFF166534), fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Message Stream
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageItem(msg);
              },
            ),
          ),

          // Chat Input Bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final isMe = msg['isMe'] as bool;
    final text = msg['text'] as String;
    final time = msg['time'] as String;
    final hasAction = (msg['hasAction'] as bool?) ?? false;
    final actionAdded = (msg['actionAdded'] as bool?) ?? false;
    final actionDismissed = (msg['actionDismissed'] as bool?) ?? false;
    final reactions = (msg['reactions'] as List<String>?) ?? [];
    final isAudio = (msg['isAudio'] as bool?) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showMessageOptions(msg),
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFE0F2FE) : NexaColors.surfaceLight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe ? const Color(0xFFBAE6FD) : NexaColors.borderLight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isAudio) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: NexaColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.graphic_eq, color: NexaColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          msg['audioDuration'] as String? ?? '0:14',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: NexaColors.textPrimary),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      text,
                      style: const TextStyle(color: NexaColors.textPrimary, fontSize: 15, height: 1.35),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(time, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.done_all, color: NexaColors.primary, size: 14),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Message Reactions
          if (reactions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                children: reactions.map((emoji) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexaColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NexaColors.borderLight),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
              ),
            ),
          ],

          // Actionable Context Card (Extracted offline by local AI)
          if (hasAction && !actionDismissed) ...[
            const SizedBox(height: 6),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NexaColors.amberAttention.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event, color: NexaColors.amberAttention, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['actionTitle'] as String,
                          style: const TextStyle(color: Color(0xFF92400E), fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          msg['actionTime'] as String,
                          style: const TextStyle(color: Color(0xFFB45309), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (actionAdded) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: NexaColors.emeraldSecure.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check, color: NexaColors.emeraldSecure, size: 14),
                          SizedBox(width: 2),
                          Text('Added', style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: NexaColors.textMuted),
                      tooltip: 'Dismiss',
                      onPressed: () {
                        setState(() {
                          msg['actionDismissed'] = true;
                        });
                      },
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          msg['actionAdded'] = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Scheduled: ${msg['actionTitle']} (${msg['actionTime']})'),
                            backgroundColor: const Color(0xFF0F172A),
                          ),
                        );
                      },
                      child: const Text('Add', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: NexaColors.surfaceLight,
        border: Border(top: BorderSide(color: NexaColors.borderLight)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: NexaColors.textSecondary, size: 24),
              tooltip: 'Attach encrypted item',
              onPressed: _showAttachmentPanel,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: NexaColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'End-to-end encrypted message...',
                  hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: NexaColors.elevatedLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 6),
            if (_isComposing) ...[
              CircleAvatar(
                backgroundColor: NexaColors.primary,
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                  tooltip: 'Send message',
                  onPressed: _sendMessage,
                ),
              ),
            ] else ...[
              CircleAvatar(
                backgroundColor: NexaColors.elevatedLight,
                radius: 20,
                child: IconButton(
                  icon: const Icon(Icons.mic_none_outlined, color: NexaColors.textSecondary, size: 20),
                  tooltip: 'Record voice note',
                  onPressed: _sendAudioNote,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
