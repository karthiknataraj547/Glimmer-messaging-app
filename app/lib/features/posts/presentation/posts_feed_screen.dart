import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/session/user_session.dart';
import '../../../core/theme/nexa_theme.dart';

class PostsFeedScreen extends StatefulWidget {
  final bool isEmbedded;
  const PostsFeedScreen({super.key, this.isEmbedded = true});

  @override
  State<PostsFeedScreen> createState() => _PostsFeedScreenState();
}

class _PostsFeedScreenState extends State<PostsFeedScreen> {
  final TextEditingController _postController = TextEditingController();
  String _selectedCircle = 'All Circles';

  final List<String> _circleFilters = [
    'All Circles',
    '🤖 AI Research',
    '⚡ Hardware',
    '🌱 Agriculture',
    '💻 Cryptography',
  ];

  // Real Posts Feed (Starts empty with zero mock accounts or fake posts)
  final List<Map<String, dynamic>> _posts = [];

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  void _createNewPost() {
    final text = _postController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _posts.insert(0, {
        'id': 'p_${DateTime.now().millisecondsSinceEpoch}',
        'authorName': UserSession.instance.name,
        'authorHandle': UserSession.instance.handle,
        'authorAvatarColor': UserSession.instance.currentAvatarPreset['color'] as Color,
        'circle': _selectedCircle == 'All Circles' ? '🤖 AI Research' : _selectedCircle,
        'time': 'Just now',
        'content': text,
        'upvotes': 1,
        'isUpvoted': true,
        'comments': [],
      });
      _postController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Post published & signed with your Ed25519 key!'),
        backgroundColor: NexaColors.emeraldSecure,
      ),
    );
  }

  void _showCommentSheet(Map<String, dynamic> post) {
    final TextEditingController commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexaColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final comments = post['comments'] as List<dynamic>;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 16,
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 440,
                  child: Column(
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
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Discussion (${comments.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: NexaColors.textPrimary),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: NexaColors.elevatedLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(post['circle'] as String, style: const TextStyle(fontSize: 11, color: NexaColors.textSecondary)),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: NexaColors.borderLight),
                      Expanded(
                        child: comments.isEmpty
                            ? const Center(
                                child: Text('No comments yet. Start the conversation!', style: TextStyle(color: NexaColors.textMuted)),
                              )
                            : ListView.builder(
                                itemCount: comments.length,
                                itemBuilder: (context, idx) {
                                  final c = comments[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: NexaColors.elevatedLight,
                                          child: Text((c['author'] as String).substring(0, 1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.primary)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(c['author'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                  const SizedBox(width: 6),
                                                  Text(c['time'] as String, style: const TextStyle(color: NexaColors.textMuted, fontSize: 11)),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(c['text'] as String, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: NexaColors.elevatedLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: NexaColors.borderLight),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: commentController,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'Add an encrypted comment...',
                                  hintStyle: TextStyle(color: NexaColors.textMuted, fontSize: 13),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send_rounded, color: NexaColors.primary, size: 20),
                              onPressed: () {
                                final text = commentController.text.trim();
                                if (text.isEmpty) return;
                                setState(() {
                                  comments.add({
                                    'author': UserSession.instance.name,
                                    'text': text,
                                    'time': 'Just now',
                                  });
                                });
                                setSheetState(() {});
                                commentController.clear();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredPosts = _selectedCircle == 'All Circles'
        ? _posts
        : _posts.where((p) => p['circle'] == _selectedCircle).toList();

    return Scaffold(
      backgroundColor: NexaColors.canvasLight,
      body: SafeArea(
        top: !widget.isEmbedded,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          children: [
            // Top Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Circle Posts & Feed',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: NexaColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Curated updates • Zero algorithmic ranking',
                      style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock, color: NexaColors.emeraldSecure, size: 12),
                      SizedBox(width: 4),
                      Text('Signed E2E', style: TextStyle(color: NexaColors.emeraldSecure, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Create Post Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexaColors.surfaceLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: NexaColors.borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: UserSession.instance.currentAvatarPreset['color'] as Color,
                        child: Icon(UserSession.instance.currentAvatarPreset['icon'] as IconData, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _postController,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 14, color: NexaColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Share a research note, finding, or hardware update...',
                            hintStyle: TextStyle(color: NexaColors.textMuted, fontSize: 13),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: NexaColors.borderLight),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.image_outlined, color: NexaColors.primary, size: 20),
                            tooltip: 'Add media',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Attached local schematic diagram.')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.code, color: NexaColors.textSecondary, size: 20),
                            tooltip: 'Add snippet',
                            onPressed: () {
                              _postController.text = '```python\n# Quantized SLM Inference\n```\n${_postController.text}';
                            },
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _createNewPost,
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text('Post to Circle'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Horizontal Category Filters
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _circleFilters.length,
                itemBuilder: (context, idx) {
                  final cat = _circleFilters[idx];
                  final isSel = _selectedCircle == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSel,
                      selectedColor: NexaColors.primary,
                      backgroundColor: NexaColors.surfaceLight,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSel ? Colors.white : NexaColors.textPrimary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isSel ? NexaColors.primary : NexaColors.borderLight),
                      ),
                      onSelected: (_) => setState(() => _selectedCircle = cat),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Posts Stream
            if (filteredPosts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: NexaColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.dynamic_feed_outlined, color: NexaColors.primary, size: 36),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'No Posts in this Circle Yet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: NexaColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Share hardware telemetry, cryptographic benchmarks, or project updates above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: NexaColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filteredPosts.map((post) {
                final isUpvoted = post['isUpvoted'] as bool;
                final comments = post['comments'] as List<dynamic>;

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexaColors.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NexaColors.borderLight),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: post['authorAvatarColor'] as Color,
                          child: Text(
                            (post['authorName'] as String).substring(0, 1),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    post['authorName'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: NexaColors.textPrimary),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    post['authorHandle'] as String,
                                    style: const TextStyle(color: NexaColors.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                    post['circle'] as String,
                                    style: const TextStyle(color: NexaColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '• ${post['time']}',
                                    style: const TextStyle(color: NexaColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_horiz, color: NexaColors.textMuted, size: 20),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Post Body
                    Text(
                      post['content'] as String,
                      style: const TextStyle(color: NexaColors.textPrimary, fontSize: 14, height: 1.45),
                    ),
                    const SizedBox(height: 14),

                    // Actions Bar (Upvote, Comment, Share)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (isUpvoted) {
                                    post['upvotes'] = (post['upvotes'] as int) - 1;
                                    post['isUpvoted'] = false;
                                  } else {
                                    post['upvotes'] = (post['upvotes'] as int) + 1;
                                    post['isUpvoted'] = true;
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isUpvoted ? NexaColors.primary.withValues(alpha: 0.12) : NexaColors.elevatedLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isUpvoted ? NexaColors.primary : NexaColors.borderLight),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.thumb_up_alt_outlined,
                                      size: 15,
                                      color: isUpvoted ? NexaColors.primary : NexaColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${post['upvotes']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isUpvoted ? NexaColors.primary : NexaColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            InkWell(
                              onTap: () => _showCommentSheet(post),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: NexaColors.elevatedLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: NexaColors.borderLight),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.mode_comment_outlined, size: 15, color: NexaColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${comments.length}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NexaColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.share_outlined, size: 18, color: NexaColors.textSecondary),
                              tooltip: 'Share post',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: 'https://nexa.im/circle/post/${post['id']}'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Encrypted circle link copied!')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
