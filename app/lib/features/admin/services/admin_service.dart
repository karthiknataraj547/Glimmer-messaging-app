import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/auth_service.dart';

/// Secure Administrative Service for NEXA Server Control and Telemetry.
///
/// Communicates with authenticated admin endpoints protected by Bearer tokens
/// and cryptographic master keys.
class AdminService {
  static final AdminService instance = AdminService._internal();
  AdminService._internal();

  String? _adminToken;
  Map<String, dynamic>? _adminProfile;

  bool get isAuthenticated => _adminToken != null && _adminToken!.isNotEmpty;
  String? get currentToken => _adminToken;
  Map<String, dynamic>? get adminProfile => _adminProfile;

  void logout() {
    _adminToken = null;
    _adminProfile = null;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_adminToken != null) {
      headers['Authorization'] = 'Bearer $_adminToken';
    }
    return headers;
  }

  /// Authenticates using Master PIN or Master Secret Key.
  Future<Map<String, dynamic>> login({String? pin, String? masterKey}) async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/login');
      final body = jsonEncode({
        'username': 'admin',
        if (pin != null && pin.isNotEmpty) ...{
          'password': pin.trim(),
          'pin': pin.trim(),
        },
        if (masterKey != null && masterKey.isNotEmpty) ...{
          'adminKey': masterKey.trim(),
          'masterKey': masterKey.trim(),
        },
      });

      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 6));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        _adminToken = data['token'] as String?;
        _adminProfile = data['admin'] as Map<String, dynamic>?;
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Admin authentication rejected',
        };
      }
    } catch (e) {
      return {'success': false, 'error': 'Server unreachable: $e'};
    }
  }

  /// Fetches real-time server health and system metrics.
  Future<Map<String, dynamic>> getOverview() async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/overview');
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': true, 'metrics': data['metrics']};
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'success': false, 'error': data['error'] ?? 'Failed to load metrics'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetches detailed user directory with device records and account status.
  Future<List<Map<String, dynamic>>> getUsers() async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/users');
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['users'] as List?)
            ?.map((u) => u as Map<String, dynamic>)
            .toList();
        return list ?? [];
      } else {
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  /// Updates account operational status (e.g. 'active' or 'suspended').
  Future<bool> updateUserStatus(String username, String status) async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/users/status');
      final response = await http
          .post(
            uri,
            headers: _buildHeaders(),
            body: jsonEncode({'username': username, 'status': status}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Resets a user's login PIN.
  Future<bool> resetUserPin(String username, String newPin) async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/users/reset-pin');
      final response = await http
          .post(
            uri,
            headers: _buildHeaders(),
            body: jsonEncode({'username': username, 'newPin': newPin}),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Permanently deletes a user from the online database.
  Future<bool> deleteUser(String username) async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/users/$username');
      final response = await http
          .delete(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves real-time security activity and audit logs.
  Future<List<Map<String, dynamic>>> getActivityLogs({
    int limit = 100,
    String type = 'ALL',
  }) async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse(
        '$baseUrl/v1/admin/activity?limit=$limit&type=${type.toLowerCase()}',
      );
      final response = await http
          .get(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final logs = (data['logs'] as List?)
            ?.map((l) => l as Map<String, dynamic>)
            .toList();
        return logs ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Purges expired or delivered mailbox messages from server buffer.
  Future<int> purgeQueue() async {
    final baseUrl = await AuthService.instance.getBaseUrl();
    try {
      final uri = Uri.parse('$baseUrl/v1/admin/purge-queue');
      final response = await http
          .post(uri, headers: _buildHeaders())
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['purgedCount'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
