import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';

class CommunityChannelScreen extends StatefulWidget {
  final String communityName;
  final String channelName;
  final int memberCount;

  const CommunityChannelScreen({
    super.key,
    required this.communityName,
    required this.channelName,
    required this.memberCount,
  });

  @override
  State<CommunityChannelScreen> createState() => _CommunityChannelScreenState();
}

class _CommunityChannelScreenState extends State<CommunityChannelScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _posts = [
    {
      'author': 'Dr. Elena Vance',
      'role': 'Moderator',
      'text': 'Welcome to #research! Please pin all papers with DOI links. Commercial spam will be filtered automatically.',
      'time': '10:14 AM',
      'upvotes': 34,
    },
    {
      'author': 'Alex M.',
      'role': 'Member',
      'text': 'We just published our benchmark on running quantized 2B models purely on Edge NPU devices with zero cloud offloading.',
      'time': '2:30 PM',
      'upvotes': 19,
    },
  ];

  void _submitPost() {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _posts.add({
        'author': 'Karthik',
        'role': 'Member',
        'text': text,
        'time': 'Just now',
        'upvotes': 1,
      });
      _msgController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              '${widget.communityName} • #${widget.channelName}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.memberCount} members • Zero tracking',
              style: const TextStyle(fontSize: 11, color: NexaColors.textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: NexaColors.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                final role = post['role'] as String;
                final isMod = role == 'Moderator' || role == 'Owner';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NexaColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: NexaColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: NexaColors.elevated,
                                child: Text(
                                  (post['author'] as String).substring(0, 1),
                                  style: const TextStyle(color: NexaColors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                post['author'] as String,
                                style: const TextStyle(color: NexaColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              if (isMod)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: NexaColors.cyanAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    role,
                                    style: const TextStyle(color: NexaColors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          Text(post['time'] as String, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post['text'] as String,
                        style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14, height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward_rounded, color: NexaColors.cyanAccent, size: 16),
                          const SizedBox(width: 4),
                          Text('${post['upvotes']}', style: const TextStyle(color: NexaColors.textSecondary, fontSize: 12)),
                          const SizedBox(width: 16),
                          const Icon(Icons.mode_comment_outlined, color: NexaColors.textMuted, size: 14),
                          const SizedBox(width: 4),
                          const Text('Reply', style: TextStyle(color: NexaColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Message input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: NexaColors.surface,
              border: Border(top: BorderSide(color: NexaColors.border)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: NexaColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Post to #${widget.channelName}...',
                        hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
                        filled: true,
                        fillColor: NexaColors.elevated,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _submitPost(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: NexaColors.cyanAccent,
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _submitPost,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
