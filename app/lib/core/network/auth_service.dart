import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Online Database Authentication and Uniqueness Verification Service.
/// 
/// Communicates directly with the online backend server over HTTP REST
/// with multi-candidate failover, mobile cellular latency resilience,
/// and automatic retry across Cloudflare tunnels and local network addresses.
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  // Candidate server endpoints: Active Cloudflare tunnel, Vercel gateway, LAN IP, and loopback
  static const List<String> _defaultCandidateUrls = [
    'https://dude-living-poll-expert.trycloudflare.com',            // Active Public secure HTTPS Cloudflare tunnel
    'https://glimmer-messaging-app-web.vercel.app',                 // Vercel Production Web & API Gateway
    'http://192.168.31.54:8080',                                     // Host LAN Wi-Fi IP for physical mobile phones
    'http://10.0.2.2:8080',                                         // Android Emulator host loopback
    'http://127.0.0.1:8080',                                        // Localhost loopback
    'http://localhost:8080',                                        // Desktop fallback
  ];

  String? _customServerUrl;
  String? _resolvedBaseUrl;

  /// ValueNotifier signaling live server connectivity for UI indicators
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  /// Custom server override
  String? get customServerUrl => _customServerUrl;
  String? get currentResolvedUrl => _resolvedBaseUrl;

  void setCustomServerUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      _customServerUrl = null;
    } else {
      String clean = url.trim();
      if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
        clean = 'https://$clean';
      }
      if (clean.endsWith('/')) {
        clean = clean.substring(0, clean.length - 1);
      }
      _customServerUrl = clean;
      _resolvedBaseUrl = clean;
    }
    // Re-verify health
    checkHealthAsync();
  }

  /// Returns ordered candidates: custom first, web origin (if browser), then resolved, then defaults
  List<String> getAllCandidateUrls() {
    final list = <String>[];
    if (_customServerUrl != null && _customServerUrl!.isNotEmpty) {
      list.add(_customServerUrl!);
    }
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && !origin.startsWith('file:') && !list.contains(origin)) {
          list.add(origin);
        }
      } catch (_) {}
    }
    if (_resolvedBaseUrl != null && !list.contains(_resolvedBaseUrl)) {
      list.add(_resolvedBaseUrl!);
    }
    for (final def in _defaultCandidateUrls) {
      if (!list.contains(def)) {
        list.add(def);
      }
    }
    return list;
  }

  /// Pings an endpoint to verify whether the backend and database are reachable
  Future<bool> testServerHealth(String baseUrl) async {
    try {
      final clean = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$clean/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      final healthy = response.statusCode == 200;
      if (healthy) {
        isConnectedNotifier.value = true;
      }
      return healthy;
    } catch (_) {
      return false;
    }
  }

  /// Tests a given URL and returns latency and status
  Future<Map<String, dynamic>> testConnectionDiagnostic(String candidateUrl) async {
    final clean = candidateUrl.trim().endsWith('/')
        ? candidateUrl.trim().substring(0, candidateUrl.trim().length - 1)
        : candidateUrl.trim();
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$clean/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      stopwatch.stop();
      if (response.statusCode == 200) {
        _resolvedBaseUrl = clean;
        isConnectedNotifier.value = true;
        return {
          'success': true,
          'statusCode': 200,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'url': clean,
        };
      }
      return {
        'success': false,
        'statusCode': response.statusCode,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'error': 'Server responded with HTTP ${response.statusCode}',
        'url': clean,
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'error': e.toString(),
        'url': clean,
      };
    }
  }

  /// Asynchronous background health probe
  void checkHealthAsync() {
    getBaseUrl(forceRecheck: true).then((url) {
      testServerHealth(url);
    }).catchError((_) {
      isConnectedNotifier.value = false;
    });
  }

  /// Resolves the first active and reachable backend URL using fast concurrent probing
  Future<String> getBaseUrl({bool forceRecheck = false}) async {
    if (!forceRecheck && _resolvedBaseUrl != null) return _resolvedBaseUrl!;

    final candidateList = getAllCandidateUrls();

    // Fast probing across candidate list
    final completer = Completer<String>();
    int pending = candidateList.length;

    for (final candidate in candidateList) {
      testServerHealth(candidate).then((isHealthy) {
        if (isHealthy && !completer.isCompleted) {
          _resolvedBaseUrl = candidate;
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
      const Duration(seconds: 5),
      onTimeout: () => candidateList.first,
    );
    return _resolvedBaseUrl!;
  }

  /// Fetches live database health and connection status
  Future<Map<String, dynamic>> getDatabaseStatus() async {
    final candidates = getAllCandidateUrls();
    for (final baseUrl in candidates) {
      try {
        final uri = Uri.parse('$baseUrl/v1/auth/db-status');
        final response = await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          _resolvedBaseUrl = baseUrl;
          isConnectedNotifier.value = true;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return {
            'online': true,
            'baseUrl': baseUrl,
            ...data,
          };
        }
      } catch (_) {
        continue;
      }
    }

    isConnectedNotifier.value = false;
    return {
      'online': false,
      'baseUrl': candidates.first,
      'error': 'Database unreachable over current network connection.',
    };
  }

  /// Checks whether a username already exists in the online database with multi-candidate failover.
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

    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base/v1/auth/check-username/$clean');
        final response = await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return data;
        }
      } catch (_) {
        continue; // Try next candidate
      }
    }

    _resolvedBaseUrl = null;
    isConnectedNotifier.value = false;
    return {
      'available': false,
      'error': 'Unable to connect to online database. Please check your internet connection or configure the server URL.',
    };
  }

  /// Registers a new user account in the online database with multi-candidate failover.
  Future<Map<String, dynamic>> registerUserOnline({
    required String username,
    required String password,
    String? fullName,
    String? about,
    String? phone,
  }) async {
    final cleanUsername = username.trim().replaceFirst(RegExp(r'^@+'), '');
    final cleanPassword = password.trim();
    final payload = jsonEncode({
      'username': cleanUsername,
      'password': cleanPassword,
      'fullName': fullName?.trim(),
      'about': about?.trim(),
      'phone': phone?.trim(),
    });

    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base/v1/auth/register-user');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        ).timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 201) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          return {'success': true, 'baseUrl': base, ...data};
        } else if (response.statusCode == 400 || response.statusCode == 409) {
          // Validation or conflict error from server — return directly
          return {
            'success': false,
            'error': data['error'] ?? 'Registration failed (${response.statusCode}).',
          };
        }
      } catch (_) {
        continue; // Network error on this candidate, try next
      }
    }

    _resolvedBaseUrl = null;
    isConnectedNotifier.value = false;
    return {
      'success': false,
      'error': 'Server unreachable. Please verify your mobile internet connection.',
    };
  }

  /// Validates user credentials against the online database with multi-candidate failover.
  Future<Map<String, dynamic>> loginUserOnline({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim().replaceFirst(RegExp(r'^@+'), '');
    final cleanPassword = password.trim();
    final payload = jsonEncode({
      'username': cleanUsername,
      'password': cleanPassword,
    });

    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base/v1/auth/login-user');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        ).timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (response.statusCode == 200) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          return {'success': true, 'baseUrl': base, ...data};
        } else if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 400) {
          // Authentication error returned by valid server (e.g. wrong password or suspended)
          return {
            'success': false,
            'error': data['error'] ?? 'Invalid username or password.',
          };
        }
      } catch (_) {
        continue; // Network error, try next candidate endpoint
      }
    }

    _resolvedBaseUrl = null;
    isConnectedNotifier.value = false;
    return {
      'success': false,
      'error': 'Database unreachable. Please check mobile data or tap the server settings icon above.',
    };
  }

  /// Retrieves verified registered users from the online database with multi-candidate failover.
  Future<List<Map<String, dynamic>>> getRegisteredUsersOnline() async {
    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final uri = Uri.parse('$base/v1/auth/users');
        final response = await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final list = (data['users'] as List?)?.map((u) => u as Map<String, dynamic>).toList();
          return list ?? [];
        }
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  /// Generic resilient GET JSON request with multi-candidate failover
  Future<Map<String, dynamic>?> getJson(Uri uri) async {
    final path = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final target = Uri.parse('$base$path');
        final response = await http.get(target).timeout(const Duration(seconds: 6));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Generic resilient POST JSON request with multi-candidate failover
  Future<Map<String, dynamic>?> postJson(String path, Map<String, dynamic> body) async {
    final payload = jsonEncode(body);
    final candidates = getAllCandidateUrls();
    for (final base in candidates) {
      try {
        final target = Uri.parse('$base$path');
        final response = await http.post(
          target,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _resolvedBaseUrl = base;
          isConnectedNotifier.value = true;
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

