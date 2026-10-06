/// Actionable intent recognized completely on-device without cloud transmission.
class NexaAssistantIntent {
  final String type; // 'REMINDER', 'SUMMARIZE', 'PROMISE_CHECK', 'UNKNOWN'
  final String title;
  final String? timeExpression;
  final String? targetContact;
  final Map<String, dynamic> metadata;

  const NexaAssistantIntent({
    required this.type,
    required this.title,
    this.timeExpression,
    this.targetContact,
    this.metadata = const {},
  });
}

/// On-Device Private Assistant Engine.
/// 
/// Runs strictly offline using pattern tokenizers and local heuristics.
/// Guarantees that personal requests never touch any cloud server.
class LocalIntentEngine {
  /// Evaluates an input phrase and extracts structured intent.
  static NexaAssistantIntent parse(String input) {
    final cleaned = input.trim();
    final lower = cleaned.toLowerCase();

    // 1. Summarization Intents
    if (lower.contains('summarize') || lower.contains('summary')) {
      final target = _extractGroupOrContact(lower);
      return NexaAssistantIntent(
        type: 'SUMMARIZE',
        title: target != null ? 'Summarize $target' : 'Summarize unread messages',
        targetContact: target,
      );
    }

    // 2. Promise Tracking Intents ("What did I promise...")
    if (lower.contains('promise') || lower.contains('promised')) {
      final contact = _extractContactAfter(lower, ['to', 'promise', 'promised']);
      return NexaAssistantIntent(
        type: 'PROMISE_CHECK',
        title: contact != null ? 'Promises made to $contact' : 'Tracked promises and commitments',
        targetContact: contact,
      );
    }

    // 3. Reminder & Meeting Scheduling Intents
    if (lower.contains('remind') || lower.contains('meeting') || lower.contains('call')) {
      return _parseReminder(cleaned, lower);
    }

    return NexaAssistantIntent(
      type: 'UNKNOWN',
      title: cleaned,
    );
  }

  static NexaAssistantIntent _parseReminder(String original, String lower) {
    // Extract time references (e.g. tomorrow at 7 pm, next month, at 10)
    String? timeExpr;
    final timeRegex = RegExp(r'(tomorrow\s+at\s+\d{1,2}(:\d{2})?\s*(am|pm)?|tomorrow|next\s+month|next\s+week|at\s+\d{1,2}(:\d{2})?\s*(am|pm)?)', caseSensitive: false);
    final match = timeRegex.firstMatch(lower);
    if (match != null) {
      timeExpr = match.group(0);
    }

    // Clean title from "remind me to..."
    var title = original;
    final prefixRegex = RegExp(r'^(please\s+)?remind(\s+me)?(\s+to)?\s*', caseSensitive: false);
    title = title.replaceAll(prefixRegex, '');

    // Strip time expression from title if found
    if (timeExpr != null) {
      final stripRegex = RegExp(RegExp.escape(timeExpr), caseSensitive: false);
      title = title.replaceAll(stripRegex, '').trim();
    }

    // Clean trailing/leading prepositions
    title = title.replaceAll(RegExp(r'\s+at\s*$|\s+on\s*$', caseSensitive: false), '').trim();
    if (title.isEmpty) title = original;

    // Capitalize first letter
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    }

    return NexaAssistantIntent(
      type: 'REMINDER',
      title: title,
      timeExpression: timeExpr,
    );
  }

  static String? _extractGroupOrContact(String lower) {
    if (lower.contains('work group')) return 'Work Group';
    if (lower.contains('family')) return 'Family Group';
    return null;
  }

  static String? _extractContactAfter(String lower, List<String> triggers) {
    final words = lower.split(RegExp(r'\s+'));
    for (int i = 0; i < words.length - 1; i++) {
      if (triggers.contains(words[i])) {
        final candidate = words[i + 1].replaceAll(RegExp(r'[^\w]'), '');
        if (candidate.isNotEmpty && candidate != 'me' && candidate != 'to') {
          return candidate[0].toUpperCase() + candidate.substring(1);
        }
      }
    }
    return null;
  }
}
