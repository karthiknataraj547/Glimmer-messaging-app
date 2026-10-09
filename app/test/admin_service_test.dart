import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_app/core/network/auth_service.dart';
import 'package:nexa_app/features/admin/services/admin_service.dart';

void main() {
  group('AdminService Online Administration and Security Tests', () {
    final admin = AdminService.instance;

    setUp(() {
      admin.logout();
      AuthService.instance.setCustomServerUrl('http://127.0.0.1:8080');
    });

    tearDown(() {
      AuthService.instance.setCustomServerUrl(null);
    });

    test('Initial state is not authenticated', () {
      expect(admin.isAuthenticated, isFalse);
      expect(admin.currentToken, isNull);
    });

    test('Login with wrong PIN fails gracefully', () async {
      final res = await admin.login(pin: '000000');
      expect(res['success'], isFalse);
      expect(admin.isAuthenticated, isFalse);
    });

    test('Login with Master Admin PIN 123456 succeeds and retrieves database telemetry', () async {
      final res = await admin.login(pin: '123456');
      expect(res['success'], isTrue);
      expect(admin.isAuthenticated, isTrue);
      expect(admin.currentToken, isNotNull);

      // Verify overview metrics
      final overview = await admin.getOverview();
      expect(overview['success'], isTrue);
      final metrics = overview['metrics'] as Map<String, dynamic>;
      expect(metrics.containsKey('total_users'), isTrue);
      expect(metrics.containsKey('registered_devices'), isTrue);

      // Verify detailed user database inspection
      final users = await admin.getUsers();
      expect(users, isNotEmpty);
      final hasAdmin = users.any((u) => u['username'] == 'admin');
      expect(hasAdmin, isTrue);

      // Verify activity logs audit trail
      final logs = await admin.getActivityLogs();
      expect(logs, isA<List<Map<String, dynamic>>>());

      // Logout cleans up token
      admin.logout();
      expect(admin.isAuthenticated, isFalse);
      expect(admin.currentToken, isNull);
    });
  });
}
