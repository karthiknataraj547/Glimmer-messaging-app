import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/features/assistant/domain/local_intent_engine.dart';

void main() {
  group('Private On-Device Assistant Intent Engine', () {
    test('Parses reminder with specific time expression', () {
      final intent = LocalIntentEngine.parse('Remind me to call Dad tomorrow at 7 PM');
      expect(intent.type, equals('REMINDER'));
      expect(intent.title, equals('Call Dad'));
      expect(intent.timeExpression, contains('tomorrow at 7 pm'));
    });

    test('Parses insurance renewal reminder', () {
      final intent = LocalIntentEngine.parse('Remind me to renew my insurance next month');
      expect(intent.type, equals('REMINDER'));
      expect(intent.title, equals('Renew my insurance'));
      expect(intent.timeExpression, contains('next month'));
    });

    test('Parses message summarization intent for work group', () {
      final intent = LocalIntentEngine.parse('Summarize the unread messages from my work group');
      expect(intent.type, equals('SUMMARIZE'));
      expect(intent.targetContact, equals('Work Group'));
    });

    test('Parses promise tracking commitment', () {
      final intent = LocalIntentEngine.parse('What did I promise Rahul last week');
      expect(intent.type, equals('PROMISE_CHECK'));
      expect(intent.targetContact, equals('Rahul'));
    });
  });
}
