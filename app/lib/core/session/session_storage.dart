import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-Platform Persistent Session Storage
///
/// Persists the active user session across application restarts, process terminations,
/// and reboots so the user never has to log in repeatedly until explicitly logging out.
class SessionStorage {
  static const MethodChannel _channel = MethodChannel('com.nexa.media_picker');

  // In-memory cache for fast access and testing
  static Map<String, dynamic>? _cachedSession;

  static File? _getFallbackFile() {
    if (kIsWeb) return null;
    try {
      final tempDir = Directory.systemTemp.path;
      return File('$tempDir/nexa_active_session.json');
    } catch (_) {
      return null;
    }
  }

  /// Saves the active user profile to persistent storage
  static Future<void> saveSession(Map<String, dynamic> sessionData) async {
    _cachedSession = Map<String, dynamic>.from(sessionData);
    final jsonStr = jsonEncode(sessionData);

    // 1. Native Android SharedPreferences via MethodChannel
    try {
      await _channel.invokeMethod('saveSession', {'session': jsonStr});
    } catch (_) {}

    // 2. File-system fallback for Desktop, Linux, and unit tests
    try {
      final file = _getFallbackFile();
      if (file != null) {
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (_) {}
  }

  /// Loads the saved session on app startup
  static Future<Map<String, dynamic>?> loadSession() async {
    if (_cachedSession != null && _cachedSession!.isNotEmpty) {
      return _cachedSession;
    }

    // 1. Try Native Android SharedPreferences
    try {
      final dynamic raw = await _channel.invokeMethod('loadSession');
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _cachedSession = decoded;
        return decoded;
      }
    } catch (_) {}

    // 2. Try File-system fallback
    try {
      final file = _getFallbackFile();
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          _cachedSession = decoded;
          return decoded;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Clears persistent session on explicit user logout
  static Future<void> clearSession() async {
    _cachedSession = null;

    // 1. Clear Native Android SharedPreferences
    try {
      await _channel.invokeMethod('clearSession');
    } catch (_) {}

    // 2. Clear File-system fallback
    try {
      final file = _getFallbackFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
