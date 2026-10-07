import 'package:flutter/material.dart';

class StoryViewerScreen extends StatefulWidget {
  final String authorName;
  final String authorNexaId;
  final Color themeColor;
  final List<Map<String, dynamic>> slides;

  const StoryViewerScreen({
    super.key,
    required this.authorName,
    required this.authorNexaId,
    required this.themeColor,
    required this.slides,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  int _currentSlideIndex = 0;
  late AnimationController _progressController;
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_currentSlideIndex < widget.slides.length - 1) {
          setState(() {
            _currentSlideIndex++;
          });
          _progressController.reset();
          _progressController.forward();
        } else {
          Navigator.pop(context);
        }
      }
    });

    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _nextSlide() {
    if (_currentSlideIndex < widget.slides.length - 1) {
      setState(() => _currentSlideIndex++);
      _progressController.reset();
      _progressController.forward();
    } else {
      Navigator.pop(context);
    }
  }

  void _prevSlide() {
    if (_currentSlideIndex > 0) {
      setState(() => _currentSlideIndex--);
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    _replyController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Encrypted reply sent to ${widget.authorName}!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = widget.slides[_currentSlideIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Gradient / Visual
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.themeColor.withValues(alpha: 0.85),
                    const Color(0xFF0F172A),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(slide['icon'] as IconData? ?? Icons.auto_awesome, color: Colors.white, size: 48),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        slide['content'] as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (slide['tag'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            slide['tag'] as String,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tap navigation detection (Left for prev, Right for next)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prevSlide,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _nextSlide,
                  ),
                ),
              ],
            ),
          ),

          // Top Bars & Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // Multi-slide progress indicators
                  Row(
                    children: List.generate(widget.slides.length, (idx) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: AnimatedBuilder(
                            animation: _progressController,
                            builder: (context, child) {
                              double progress = 0.0;
                              if (idx < _currentSlideIndex) {
                                progress = 1.0;
                              } else if (idx == _currentSlideIndex) {
                                progress = _progressController.value;
                              }
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  minHeight: 3,
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Header with Author & Close
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: widget.themeColor,
                        child: Text(
                          widget.authorName.substring(0, 1),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.authorName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            slide['time'] as String? ?? 'Just now',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 24),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Reply Field
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Send encrypted reply...',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sendReply,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
