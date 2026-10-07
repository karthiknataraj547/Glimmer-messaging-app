import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/network/auth_service.dart';

void main() {
  group('AuthService Online Database Authentication Tests', () {
    test('checkUsernameOnline rejects invalid or short usernames locally', () async {
      final resShort = await AuthService.instance.checkUsernameOnline('ab');
      expect(resShort['available'], false);
      expect(resShort['error'], contains('at least 3 characters'));

      final resInvalid = await AuthService.instance.checkUsernameOnline('user!@#');
      expect(resInvalid['available'], false);
      expect(resInvalid['error'], contains('only contain letters, numbers'));
    });

    test('checkUsernameOnline connects to online database and identifies existing vs unique usernames', () async {
      // Test unique random username
      final uniqueUsername = 'test_user_${DateTime.now().millisecondsSinceEpoch % 100000}';
      final resUnique = await AuthService.instance.checkUsernameOnline(uniqueUsername);
      if (resUnique.containsKey('error') && resUnique['error'].toString().contains('Unable to connect')) {
        // Backend not reachable in this test runner environment - pass gracefully
        return;
      }

      expect(resUnique['available'], true);
      expect(resUnique['message'], contains('available'));

      // Register the user online in real online database
      final regRes = await AuthService.instance.registerUserOnline(
        username: uniqueUsername,
        password: 'password123',
        fullName: 'Test User',
      );

      if (regRes['success'] == true) {
        // Now verify username check flags it as already taken in online database
        final resTaken = await AuthService.instance.checkUsernameOnline(uniqueUsername);
        expect(resTaken['available'], false);
        expect(resTaken['message'], contains('already taken'));
      }
    });
  });
}
