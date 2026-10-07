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

  // Candidate server endpoints: Cloudflare HTTPS tunnel (works anywhere on 4G/5G/Wi-Fi), LAN IP, and loopback
  static const List<String> _defaultCandidateUrls = [
    'https://absent-wise-chambers-could.trycloudflare.com', // Public secure HTTPS Cloudflare tunnel
    'http://192.168.31.54:8080',                           // Host LAN Wi-Fi IP for physical mobile phones
    'http://10.0.2.2:8080',                               // Android Emulator host loopback
    'http://127.0.0.1:8080',                              // Localhost loopback
    'http://localhost:8080',                              // Desktop fallback
  ];

  String? _customServerUrl;
  String? _resolvedBaseUrl;

  /// Custom server override
  String? get customServerUrl => _customServerUrl;
  String? get currentResolvedUrl => _resolvedBaseUrl;

  void setCustomServerUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      _customServerUrl = null;
    } else {
      String clean = url.trim();
      if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
        clean = 'http://$clean';
      }
      if (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      _customServerUrl = clean;
    }
    _resolvedBaseUrl = null; // Invalidate cache to force re-probe
  }

  HttpClient _createHttpClient({Duration timeout = const Duration(seconds: 4)}) {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return client;
  }

  /// Pings an endpoint to verify whether the backend and database are reachable
  Future<bool> testServerHealth(String baseUrl) async {
    try {
      final client = _createHttpClient(timeout: const Duration(milliseconds: 1500));
      final clean = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$clean/health');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(milliseconds: 2000));
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Resolves the first active and reachable backend URL using fast concurrent probing
  Future<String> getBaseUrl({bool forceRecheck = false}) async {
    if (!forceRecheck && _resolvedBaseUrl != null) return _resolvedBaseUrl!;

    final candidateList = <String>[];
    if (_customServerUrl != null && _customServerUrl!.isNotEmpty) {
      candidateList.add(_customServerUrl!);
    }
    candidateList.addAll(_defaultCandidateUrls);

    // Parallel fast probing: whichever responds first with 200 OK wins
    final completer = Completer<String>();
    int pending = candidateList.length;

    for (final candidate in candidateList) {
      testServerHealth(candidate).then((isHealthy) {
        if (isHealthy && !completer.isCompleted) {
          completer.complete(candidate);
        } else {
          pending--;
          if (pending == 0 && !completer.isCompleted) {
            completer.complete(candidateList.first);
          }
        }
      }).catchError((_) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(candidateList.first);
        }
      });
    }

    _resolvedBaseUrl = await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => candidateList.first,
    );
    return _resolvedBaseUrl!;
  }

  /// Fetches live database health and connection status
  Future<Map<String, dynamic>> getDatabaseStatus() async {
    final baseUrl = await getBaseUrl();
    final client = _createHttpClient(timeout: const Duration(seconds: 3));

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/db-status');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 4));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      return {
        'online': true,
        'baseUrl': baseUrl,
        ...data,
      };
    } catch (e) {
      return {
        'online': false,
        'baseUrl': baseUrl,
        'error': e.toString(),
      };
    } finally {
      client.close();
    }
  }

  /// Checks whether a username already exists in the online database.
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
    final client = _createHttpClient(timeout: const Duration(seconds: 4));

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/check-username/$clean');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 5));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      return data;
    } on SocketException catch (_) {
      _resolvedBaseUrl = null;
      return {
        'available': false,
        'error': 'Unable to connect to server. Please check your internet connection.',
      };
    } catch (e) {
      return {
        'available': false,
        'error': 'Username check failed: $e',
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
    final client = _createHttpClient(timeout: const Duration(seconds: 5));

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

      final response = await request.close().timeout(const Duration(seconds: 6));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return {'success': true, 'baseUrl': baseUrl, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Registration failed (${response.statusCode}).',
        };
      }
    } on SocketException catch (_) {
      _resolvedBaseUrl = null;
      return {
        'success': false,
        'error': 'Server unreachable. Please check your internet connection.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Registration error: $e',
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
    final client = _createHttpClient(timeout: const Duration(seconds: 5));

    try {
      final uri = Uri.parse('$baseUrl/v1/auth/login-user');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final payload = jsonEncode({
        'username': username.trim().replaceFirst(RegExp(r'^@+'), ''),
        'password': password.trim(),
      });
      request.write(payload);

      final response = await request.close().timeout(const Duration(seconds: 6));
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true, 'baseUrl': baseUrl, ...data};
      } else {
        return {
          'success': false,
          'error': data['error'] ?? 'Invalid username or password.',
        };
      }
    } on SocketException catch (_) {
      _resolvedBaseUrl = null;
      return {
        'success': false,
        'error': 'Server unreachable. Please check your internet connection.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Sign-in error: $e',
      };
    } finally {
      client.close();
    }
  }

  /// Retrieves verified registered users from the online database.
  Future<List<Map<String, dynamic>>> getRegisteredUsersOnline() async {
    final baseUrl = await getBaseUrl();
    final client = _createHttpClient(timeout: const Duration(seconds: 4));

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
