import 'dart:async';
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
/// 3. Invoke native Android PackageInstaller (`REQUEST_INSTALL_PACKAGES` + `FileProvider`).
/// 4. Direct integration with dedicated `AppUpdateCenterScreen`.
/// 5. Cross-platform support for Web cache-busting reload.
class UpdateEngine {
  static final UpdateEngine instance = UpdateEngine._internal();
  UpdateEngine._internal();

  static const String currentVersion = '1.2.4';
  static const int currentBuildNumber = 8;
  static const String defaultDownloadUrl = 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk';
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

  /// Queries the server update manifest
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
      debugPrint('[UpdateEngine] queryServerUpdate error: $e');
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

  /// In-App streaming downloader with real-time bytes progress callback
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

    final targetFile = File('$cacheDirPath/nexa_update_v1_2_0.apk');
    if (targetFile.existsSync()) {
      try {
        targetFile.deleteSync();
      } catch (_) {}
    }

    // 2. Open HTTP stream
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      client.close();
      throw Exception('Server returned HTTP ${response.statusCode} for APK download.');
    }

    final totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;
    final sink = targetFile.openWrite();

    final stopwatch = Stopwatch()..start();
    int lastCheckTime = stopwatch.elapsedMilliseconds;
    int lastBytes = 0;
    String speedStr = 'Calculating...';

    final completer = Completer<String>();

    response.stream.listen(
      (chunk) {
        receivedBytes += chunk.length;
        sink.add(chunk);

        final now = stopwatch.elapsedMilliseconds;
        if (now - lastCheckTime > 500) {
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
        await sink.flush();
        await sink.close();
        client.close();
        stopwatch.stop();
        onProgress(receivedBytes, totalBytes, 'Completed');
        completer.complete(targetFile.path);
      },
      onError: (err) async {
        await sink.close();
        client.close();
        completer.completeError(err);
      },
      cancelOnError: true,
    );

    return completer.future;
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
