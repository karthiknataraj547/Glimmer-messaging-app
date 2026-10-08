import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../network/auth_service.dart';
import '../theme/nexa_theme.dart';

/// In-App Application Update Engine
///
/// Automatically checks the server for updates and presents
/// a seamless in-app prompt when a new version is pushed to the server.
class UpdateEngine {
  static final UpdateEngine instance = UpdateEngine._internal();
  UpdateEngine._internal();

  static const String currentVersion = '1.2.0';
  static const int currentBuildNumber = 4;

  bool _isChecking = false;
  bool _hasPromptedThisSession = false;

  /// Checks for updates on the server and displays a prompt if available
  Future<void> checkForUpdate(BuildContext context, {bool userInitiated = false}) async {
    if (_isChecking) return;
    if (!userInitiated && _hasPromptedThisSession) return;

    _isChecking = true;

    try {
      final baseUrl = await AuthService.instance.getBaseUrl();
      final uri = Uri.parse('$baseUrl/v1/app/check-update');
      final data = await AuthService.instance.getJson(uri);

      if (data != null && data['success'] == true) {
        final serverVersion = (data['latest_version'] as String?) ?? '1.2.0';
        final serverBuild = (data['build_number'] as num?)?.toInt() ?? 4;
        final releaseNotes = (data['release_notes'] as String?) ?? 'Bug fixes and performance improvements.';
        final releaseDate = (data['release_date'] as String?) ?? '';
        final downloadUrl = (data['download_url'] as String?) ?? 'https://glimmer-messaging-app-web.vercel.app/nexa-release.apk';

        final isNewer = _isVersionNewer(serverVersion, serverBuild);

        if (isNewer && context.mounted) {
          _hasPromptedThisSession = true;
          _showUpdateModal(
            context,
            serverVersion: serverVersion,
            serverBuild: serverBuild,
            releaseNotes: releaseNotes,
            releaseDate: releaseDate,
            downloadUrl: downloadUrl,
          );
        } else if (userInitiated && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You are using the latest version of NEXA (v1.2.0+4).'),
              backgroundColor: NexaColors.emeraldSecure,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UpdateEngine] Check update error: $e');
    } finally {
      _isChecking = false;
    }
  }

  bool _isVersionNewer(String serverVer, int serverBuild) {
    if (serverBuild > currentBuildNumber) return true;
    final sParts = serverVer.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final cParts = currentVersion.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    for (int i = 0; i < sParts.length && i < cParts.length; i++) {
      if (sParts[i] > cParts[i]) return true;
      if (sParts[i] < cParts[i]) return false;
    }
    return sParts.length > cParts.length;
  }

  void _showUpdateModal(
    BuildContext context, {
    required String serverVersion,
    required int serverBuild,
    required String releaseNotes,
    required String releaseDate,
    required String downloadUrl,
  }) {
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
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, -5),
              ),
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
                        color: NexaColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.system_update_alt, color: NexaColors.primary, size: 28),
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
                                  color: NexaColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: NexaColors.emeraldSecure.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'v$serverVersion+$serverBuild',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: NexaColors.emeraldSecure,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Current: v$currentVersion+$currentBuildNumber • Released: $releaseDate',
                            style: const TextStyle(fontSize: 12, color: NexaColors.textSecondary),
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
                    color: NexaColors.elevatedLight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NexaColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.notes, size: 16, color: NexaColors.primary),
                          SizedBox(width: 6),
                          Text(
                            "What's New in This Release",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: NexaColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        releaseNotes,
                        style: const TextStyle(fontSize: 13, color: NexaColors.textPrimary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Later'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(kIsWeb ? 'Refresh App' : 'Download Update'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NexaColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          if (kIsWeb) {
                            // On web, reload window to pick up new service worker
                            windowReload();
                          } else {
                            // On mobile, open download URL via platform intent or browser
                            try {
                              const channel = MethodChannel('com.nexa.media_picker');
                              await channel.invokeMethod('openUrlInBrowser', {'url': downloadUrl});
                            } catch (_) {}
                          }
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

  void windowReload() {
    // In web builds, this can trigger a refresh
  }
}
