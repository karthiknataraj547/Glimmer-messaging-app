import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../network/auth_service.dart';
import '../theme/nexa_theme.dart';
import '../../features/updates/presentation/app_update_center_screen.dart';
import 'web_reload.dart';

/// Data model representing server release manifest
class UpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String releaseNotes;
  final String releaseDate;
  final String downloadUrl;
  final String webUrl;
  final bool mandatory;
  final bool isNewer;

  const UpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.releaseNotes,
    required this.releaseDate,
    required this.downloadUrl,
    required this.webUrl,
    required this.mandatory,
    required this.isNewer,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, int currentBuild, String currentVer) {
    final serverVer = (json['latest_version'] as String?) ?? '1.2.0';
    final serverBuild = (json['build_number'] as num?)?.toInt() ?? 4;
    final notes = (json['release_notes'] as String?) ?? 'Performance and security updates.';
    final date = (json['release_date'] as String?) ?? '';
    final dlUrl = (json['download_url'] as String?) ?? UpdateEngine.defaultDownloadUrl;
    final wUrl = (json['web_url'] as String?) ?? 'https://glimmer-messaging-app-web.vercel.app/';
    final mand = (json['mandatory'] as bool?) ?? false;

    // Determine if server version is strictly newer
    bool newer = serverBuild > currentBuild;
    if (!newer && serverBuild == currentBuild) {
      newer = UpdateEngine.compareSemanticVersions(serverVer, currentVer) > 0;
    }

    return UpdateInfo(
      latestVersion: serverVer,
      buildNumber: serverBuild,
      releaseNotes: notes,
      releaseDate: date,
      downloadUrl: dlUrl,
      webUrl: wUrl,
      mandatory: mand,
      isNewer: newer,
    );
  }
}

/// In-App Application Update Engine
///
/// Features:
/// 1. Query server release metadata on `/v1/app/check-update`.
/// 2. Stream-download release APK directly inside the app with real-time byte counters and progress.
/// 3. Multi-source CDN failover and auto-retries.
/// 4. Invoke native Android PackageInstaller (`REQUEST_INSTALL_PACKAGES` + `FileProvider`).
/// 5. Direct integration with dedicated `AppUpdateCenterScreen`.
/// 6. Cross-platform support for Web cache-busting reload.
class UpdateEngine {
  static final UpdateEngine instance = UpdateEngine._internal();
  UpdateEngine._internal();

  static const String currentVersion = '1.2.9';
  static const int currentBuildNumber = 13;
  static const String defaultDownloadUrl = 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk';
  static const String fallbackDownloadUrl = 'https://raw.githubusercontent.com/karthiknataraj547/Glimmer-messaging-app/master/public/nexa-release.apk';
  static const MethodChannel _channel = MethodChannel('com.nexa.media_picker');

  bool _isChecking = false;
  bool _hasPromptedThisSession = false;
  UpdateInfo? _lastUpdateInfo;

  UpdateInfo? get lastUpdateInfo => _lastUpdateInfo;

  static int compareSemanticVersions(String v1, String v2) {
    final clean1 = v1.replaceAll('v', '').trim();
    final clean2 = v2.replaceAll('v', '').trim();
    final parts1 = clean1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = clean2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// Navigates directly to the dedicated In-App Update Center
  void openUpdateCenter(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppUpdateCenterScreen()),
    );
  }

  /// Queries the server update manifest with multi-source fallback
  Future<UpdateInfo?> queryServerUpdate() async {
    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/app/check-update');
      final data = await AuthService.instance.getJson(uri);

      if (data != null && data['success'] == true) {
        _lastUpdateInfo = UpdateInfo.fromJson(data, currentBuildNumber, currentVersion);
        return _lastUpdateInfo;
      }
    } catch (e) {
      debugPrint('[UpdateEngine] queryServerUpdate primary error: $e');
    }

    // Direct fallback to Vercel production API
    try {
      final fallbackUri = Uri.parse('https://glimmer-messaging-app-web.vercel.app/v1/app/check-update');
      final resp = await http.get(fallbackUri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          _lastUpdateInfo = UpdateInfo.fromJson(data, currentBuildNumber, currentVersion);
          return _lastUpdateInfo;
        }
      }
    } catch (e) {
      debugPrint('[UpdateEngine] queryServerUpdate direct fallback error: $e');
    }

    // Fallback to cloud bin
    try {
      final binUri = Uri.parse('https://extendsclass.com/api/json-storage/bin/eafefcc');
      final resp = await http.get(binUri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['app_version'] != null) {
          final ver = data['app_version'] as Map<String, dynamic>;
          _lastUpdateInfo = UpdateInfo.fromJson(ver, currentBuildNumber, currentVersion);
          return _lastUpdateInfo;
        }
      }
    } catch (e) {
      debugPrint('[UpdateEngine] queryServerUpdate cloud bin error: $e');
    }

    return null;
  }

  /// Autonomous check executed on app launch
  Future<void> checkForUpdate(BuildContext context, {bool userInitiated = false}) async {
    if (userInitiated) {
      openUpdateCenter(context);
      return;
    }

    if (_isChecking || _hasPromptedThisSession) return;
    _isChecking = true;

    try {
      final info = await queryServerUpdate();
      if (info != null && info.isNewer && context.mounted) {
        _hasPromptedThisSession = true;
        _showUpdatePromptModal(context, info);
      }
    } catch (e) {
      debugPrint('[UpdateEngine] Auto-check error: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// In-App streaming downloader with real-time bytes progress callback & multi-CDN failover
  Future<String> downloadApkWithProgress({
    required String url,
    required void Function(int receivedBytes, int totalBytes, String speed) onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('In-App APK streaming is only supported on Android.');
    }

    // 1. Determine destination directory (Android cache directory or system temp)
    String cacheDirPath = '';
    try {
      final dir = await _channel.invokeMethod<String>('getAppCacheDir');
      if (dir != null && dir.isNotEmpty) {
        cacheDirPath = dir;
      }
    } catch (_) {}

    if (cacheDirPath.isEmpty) {
      cacheDirPath = Directory.systemTemp.path;
    }

    // Clean up older temporary update files to free device space
    try {
      final cacheDir = Directory(cacheDirPath);
      if (cacheDir.existsSync()) {
        for (final entity in cacheDir.listSync()) {
          if (entity is File && (entity.path.contains('nexa_update') || entity.path.endsWith('.apk'))) {
            try { entity.deleteSync(); } catch (_) {}
          }
        }
      }
    } catch (_) {}

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final targetFile = File('$cacheDirPath/nexa_update_v${currentBuildNumber}_$timestamp.apk');

    // Ordered list of candidate download endpoints
    final candidateUrls = <String>[];
    if (url.trim().isNotEmpty) candidateUrls.add(url.trim());
    if (!candidateUrls.contains(defaultDownloadUrl)) candidateUrls.add(defaultDownloadUrl);
    if (!candidateUrls.contains(fallbackDownloadUrl)) candidateUrls.add(fallbackDownloadUrl);

    Exception? lastException;

    for (final candidateUrl in candidateUrls) {
      http.Client? client;
      IOSink? sink;
      try {
        debugPrint('[UpdateEngine] Attempting streaming download from: $candidateUrl');
        onProgress(0, 0, 'Connecting...');

        final uri = Uri.parse(candidateUrl).replace(queryParameters: {
          't': '$timestamp',
        });

        client = http.Client();
        final request = http.Request('GET', uri);
        request.headers['User-Agent'] = 'NEXA-Updater/1.2.9';
        request.headers['Accept-Encoding'] = 'identity';
        request.headers['Cache-Control'] = 'no-cache';

        final response = await client.send(request).timeout(const Duration(seconds: 20));

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('HTTP ${response.statusCode} from $candidateUrl');
        }

        final totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        if (targetFile.existsSync()) {
          try { targetFile.deleteSync(); } catch (_) {}
        }
        sink = targetFile.openWrite();

        final stopwatch = Stopwatch()..start();
        int lastCheckTime = stopwatch.elapsedMilliseconds;
        int lastBytes = 0;
        String speedStr = 'Connecting...';

        final completer = Completer<String>();

        response.stream.listen(
          (chunk) {
            receivedBytes += chunk.length;
            sink?.add(chunk);

            final now = stopwatch.elapsedMilliseconds;
            if (now - lastCheckTime >= 400) {
              final diffBytes = receivedBytes - lastBytes;
              final diffSec = (now - lastCheckTime) / 1000.0;
              if (diffSec > 0) {
                final bytesPerSec = diffBytes / diffSec;
                final mbPerSec = (bytesPerSec / 1024 / 1024).toStringAsFixed(1);
                speedStr = '$mbPerSec MB/s';
              }
              lastCheckTime = now;
              lastBytes = receivedBytes;
              onProgress(receivedBytes, totalBytes, speedStr);
            }
          },
          onDone: () async {
            try {
              await sink?.flush();
              await sink?.close();
            } catch (_) {}
            client?.close();
            stopwatch.stop();

            // Sanity check file size (must be at least 1MB for a real APK)
            if (targetFile.existsSync() && targetFile.lengthSync() > 1000000) {
              onProgress(receivedBytes, totalBytes, 'Completed');
              completer.complete(targetFile.path);
            } else {
              completer.completeError(Exception('Downloaded file is incomplete or corrupted (${targetFile.existsSync() ? targetFile.lengthSync() : 0} bytes).'));
            }
          },
          onError: (err) async {
            try { await sink?.close(); } catch (_) {}
            client?.close();
            completer.completeError(err);
          },
          cancelOnError: true,
        );

        final resultPath = await completer.future;
        return resultPath;
      } catch (e) {
        debugPrint('[UpdateEngine] Download attempt failed on $candidateUrl: $e');
        lastException = Exception('Failed from $candidateUrl: $e');
        try { await sink?.close(); } catch (_) {}
        client?.close();
        if (targetFile.existsSync()) {
          try { targetFile.deleteSync(); } catch (_) {}
        }
        // Try next candidate endpoint
      }
    }

    throw lastException ?? Exception('All download sources failed.');
  }

  /// Triggers native Android package installer via FileProvider
  Future<bool> installApk(String filePath) async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? true;
    } catch (e) {
      debugPrint('[UpdateEngine] Native installApk failed: $e. Falling back to browser.');
      await openUrlInBrowser(defaultDownloadUrl);
      return false;
    }
  }

  /// Checks if Android allows installing unknown apps
  Future<bool> canRequestPackageInstalls() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens Android system settings to grant unknown app installation
  Future<void> openInstallPermissionSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }

  /// Opens URL via native browser intent
  Future<void> openUrlInBrowser(String url) async {
    try {
      await _channel.invokeMethod('openUrlInBrowser', {'url': url});
    } catch (_) {}
  }

  /// Triggers cross-platform web window reload
  void triggerWebReload() {
    performWebReload();
  }

  void _showUpdatePromptModal(BuildContext context, UpdateInfo info) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, -5)),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: NexaColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Header with Update Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_alt, color: Color(0xFF00E5FF), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Update Available',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'v${info.latestVersion}+${info.buildNumber}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Current: v$currentVersion+$currentBuildNumber • ${info.releaseDate}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Release Notes Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notes, size: 16, color: Color(0xFF00E5FF)),
                          SizedBox(width: 6),
                          Text(
                            "What's New in This Release",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        info.releaseNotes,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0), height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    if (!info.mandatory)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0x33FFFFFF)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Later'),
                        ),
                      ),
                    if (!info.mandatory) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('Open Update Center', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          openUpdateCenter(context);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
