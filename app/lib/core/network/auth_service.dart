import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Online Database Authentication and Uniqueness Verification Service.
/// 
/// Communicates directly with the online backend server over HTTP REST
/// to query real-time database tables and verify user handles.
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  // Candidate server endpoints for emulator, physical device on Wi-Fi, and localhost
  static const List<String> _candidateUrls = [
    'http://10.0.2.2:8080',      // Android Emulator host loopback
    'http://192.168.31.54:8080',  // Host LAN Wi-Fi IP for physical mobile phones
    'http://127.0.0.1:8080',     // Localhost loopback
    'http://localhost:8080',     // Desktop fallback
  ];

  String? _resolvedBaseUrl;

  /// Resolves the first active and reachable backend URL
  Future<String> getBaseUrl() async {
    if (_resolvedBaseUrl != null) return _resolvedBaseUrl!;

    for (final candidate in _candidateUrls) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(milliseconds: 1200);
        final uri = Uri.parse('$candidate/health');
        final request = await client.getUrl(uri);
        final response = await request.close().timeout(const Duration(milliseconds: 1500));
        client.close();
        if (response.statusCode == 200) {
          _resolvedBaseUrl = candidate;
          return candidate;
        }
      } catch (_) {
        // Try next candidate
      }
    }

    // Default to emulator/standard port if none answered immediately
    _resolvedBaseUrl = _candidateUrls.first;
    return _resolvedBaseUrl!;
  }

  /// Checks whether a username already exists in the online database.
  /// 
  /// Returns:
  /// - `{'available': true, 'username': '...', 'message': '...'}` if unique
  /// - `{'available': false, 'username': '...', 'message': '...'}` if taken
  /// - `{'available': false, 'error': '...'}` on validation or network failure
  Future<Map<String, dynamic>> checkUsernameOnline(String rawUsername) async {
    final clean = rawUsername.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
    if (clean.length < 3) {
      return {
        'available': false,
        'error': 'Username must be at least 3 characters long.',
      };
    }

    final validPattern = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!validPattern.hasMatch(clean)) {
      return {
        'available': false,
        'error': 'Username can only contain letters, numbers, and underscores.',
      };
    }

    final baseUrl = await getBaseUrl();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/check-username/$clean');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      return data;
    } on SocketException catch (_) {
      // Re-probe other candidate URLs if primary failed
      _resolvedBaseUrl = null;
      return {
        'available': false,
        'error': 'Unable to connect to the online database. Please verify backend server is running.',
      };
    } catch (e) {
      return {
        'available': false,
        'error': 'Network error checking online database: $e',
      };
    } finally {
      client.close();
    }
  }

  /// Registers a new user account in the online database.
  Future<Map<String, dynamic>> registerUserOnline({
    required String username,
    required String password,
    String? fullName,
    String? about,
    String? phone,
  }) async {
    final baseUrl = await getBaseUrl();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/register-user');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final payload = jsonEncode({
        'username': username.trim().replaceFirst(RegExp(r'^@+'), ''),
        'password': password.trim(),
        'fullName': fullName?.trim(),
        'about': about?.trim(),
        'phone': phone?.trim(),
      });
      request.write(payload);

      final response = await request.close().timeout(const Duration(seconds: 5));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Registration rejected by online database (${response.statusCode}).',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Online database connection failed: $e',
      };
    } finally {
      client.close();
    }
  }

  /// Validates user credentials against the online database.
  Future<Map<String, dynamic>> loginUserOnline({
    required String username,
    required String password,
  }) async {
    final baseUrl = await getBaseUrl();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/login-user');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final payload = jsonEncode({
        'username': username.trim().replaceFirst(RegExp(r'^@+'), ''),
        'password': password.trim(),
      });
      request.write(payload);

      final response = await request.close().timeout(const Duration(seconds: 5));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Login failed against online database (${response.statusCode}).',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Online database unreachable: $e',
      };
    } finally {
      client.close();
    }
  }

  /// Retrieves verified registered users from the online database.
  Future<List<Map<String, dynamic>>> getRegisteredUsersOnline() async {
    final baseUrl = await getBaseUrl();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/users');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final list = (data['users'] as List?)?.map((u) => u as Map<String, dynamic>).toList();
      return list ?? [];
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }
}
