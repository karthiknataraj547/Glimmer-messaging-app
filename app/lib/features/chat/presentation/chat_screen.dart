import 'package:flutter/material.dart';
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
  final List<Map<String, dynamic>> _messages = [
    {
      'isMe': false,
      'text': 'Hey Karthik, are we meeting tomorrow at 10 AM?',
      'time': '8:42 PM',
      'hasAction': true,
      'actionTitle': 'Meeting with Rahul',
      'actionTime': 'Tomorrow, 10:00 AM',
    },
    {
      'isMe': true,
      'text': 'Yes, 10 AM sounds perfect. See you at the coffee shop! 👍',
      'time': '8:44 PM',
      'hasAction': false,
    },
  ];

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'isMe': true,
        'text': text,
        'time': '8:45 PM',
        'hasAction': false,
      });
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: NexaColors.elevated,
              child: Text(
                widget.contactName.substring(0, 1),
                style: const TextStyle(color: NexaColors.cyanAccent, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contactName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    const Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 11),
                    const SizedBox(width: 4),
                    Text(
                      widget.nexaId,
                      style: const TextStyle(fontSize: 11, color: NexaColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: NexaColors.textSecondary),
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
        ],
      ),
      body: Column(
        children: [
          // E2E Security Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: NexaColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexaColors.border),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, color: NexaColors.emeraldSecure, size: 14),
                SizedBox(width: 6),
                Text(
                  'Messages end-to-end encrypted with PointyCastle Double Ratchet.',
                  style: TextStyle(color: NexaColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),

          // Message Stream
          Expanded(
            child: ListView.builder(
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
    final hasAction = msg['hasAction'] as bool;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isMe ? NexaColors.elevated : NexaColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              border: Border.all(
                color: isMe ? NexaColors.cyanAccent.withValues(alpha: 0.3) : NexaColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(color: NexaColors.textPrimary, fontSize: 15, height: 1.3),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all, color: NexaColors.cyanAccent, size: 14),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Actionable Context Card (Extracted offline by local AI)
          if (hasAction) ...[
            const SizedBox(height: 6),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexaColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NexaColors.amberAttention.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NexaColors.amberAttention.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event, color: NexaColors.amberAttention, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['actionTitle'] as String,
                          style: const TextStyle(color: NexaColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          msg['actionTime'] as String,
                          style: const TextStyle(color: NexaColors.amberAttention, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reminder added to NEXA Assistant!'),
                          backgroundColor: NexaColors.elevated,
                        ),
                      );
                    },
                    child: const Text('Add', style: TextStyle(color: NexaColors.cyanAccent, fontWeight: FontWeight.bold)),
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: NexaColors.surface,
        border: Border(top: BorderSide(color: NexaColors.border)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: NexaColors.textSecondary),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: NexaColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'End-to-end encrypted message...',
                  hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: NexaColors.elevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: NexaColors.cyanAccent,
              radius: 20,
              child: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
