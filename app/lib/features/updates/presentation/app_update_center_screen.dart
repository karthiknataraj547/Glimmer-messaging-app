import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/update_engine.dart';

/// Dedicated In-App Update Center Screen
///
/// Provides a sleek obsidian-style console to check server releases,
/// inspect changelogs, stream-download APK updates in real-time,
/// and trigger native Android package installations.
class AppUpdateCenterScreen extends StatefulWidget {
  final bool autoCheck;
  const AppUpdateCenterScreen({super.key, this.autoCheck = true});

  @override
  State<AppUpdateCenterScreen> createState() => _AppUpdateCenterScreenState();
}

class _AppUpdateCenterScreenState extends State<AppUpdateCenterScreen> {
  final UpdateEngine _engine = UpdateEngine.instance;

  bool _isChecking = false;
  String? _errorMessage;
  UpdateInfo? _updateInfo;
  int? _serverLatencyMs;

  // In-App Download state
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStats = '';
  String? _downloadedFilePath;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    if (widget.autoCheck) {
      _checkServer();
    } else {
      _updateInfo = _engine.lastUpdateInfo;
    }
  }

  Future<void> _checkServer() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final info = await _engine.queryServerUpdate();
      stopwatch.stop();

      if (mounted) {
        setState(() {
          _isChecking = false;
          _serverLatencyMs = stopwatch.elapsedMilliseconds;
          _updateInfo = info;
          if (info == null) {
            _errorMessage = 'Could not retrieve update manifest from server.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _startInAppDownload() async {
    final url = _updateInfo?.downloadUrl ?? UpdateEngine.defaultDownloadUrl;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStats = 'Connecting to CDN...';
      _downloadError = null;
    });

    try {
      final filePath = await _engine.downloadApkWithProgress(
        url: url,
        onProgress: (received, total, speed) {
          if (mounted) {
            setState(() {
              if (total > 0) {
                _downloadProgress = received / total;
                final recMb = (received / 1024 / 1024).toStringAsFixed(1);
                final totMb = (total / 1024 / 1024).toStringAsFixed(1);
                final pct = (_downloadProgress * 100).toInt();
                _downloadStats = '$recMb MB / $totMb MB ($pct%) • $speed';
              } else {
                final recMb = (received / 1024 / 1024).toStringAsFixed(1);
                _downloadStats = '$recMb MB downloaded • $speed';
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadedFilePath = filePath;
          _downloadStats = 'Download complete. Ready to install.';
        });

        // Trigger native package installer automatically
        await _triggerInstall(filePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = 'Download failed: $e';
        });
      }
    }
  }

  Future<void> _triggerInstall(String filePath) async {
    try {
      final success = await _engine.installApk(filePath);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Installation launched. If prompted, please allow installing apps from this source.'),
            backgroundColor: Color(0xFF0284C7),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Install error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNewer = _updateInfo?.isNewer ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D16),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'App Update Engine',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                  )
                : const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
            tooltip: 'Check Server Now',
            onPressed: _isChecking ? null : _checkServer,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          children: [
            // 1. Status Hero Banner
            _buildHeroStatus(isNewer),

            const SizedBox(height: 20),

            // 2. Version Comparison Grid
            _buildVersionGrid(),

            const SizedBox(height: 20),

            // 3. In-App Download & Installation Center
            _buildDownloadCard(isNewer),

            const SizedBox(height: 20),

            // 4. Release Notes / Changelog
            _buildReleaseNotesCard(),

            const SizedBox(height: 20),

            // 5. Server Architecture & Telemetry
            _buildServerTelemetryCard(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStatus(bool isNewer) {
    Color statusColor;
    String statusTitle;
    String statusSubtitle;
    IconData statusIcon;

    if (_isChecking) {
      statusColor = const Color(0xFF00E5FF);
      statusTitle = 'Checking Gateway...';
      statusSubtitle = 'Querying release manifest on Vercel CDN';
      statusIcon = Icons.cloud_sync;
    } else if (_errorMessage != null) {
      statusColor = const Color(0xFFEF4444);
      statusTitle = 'Check Failed';
      statusSubtitle = _errorMessage!;
      statusIcon = Icons.error_outline;
    } else if (isNewer) {
      statusColor = const Color(0xFF00E5FF);
      statusTitle = 'Update Available';
      statusSubtitle = 'Version v${_updateInfo!.latestVersion} (Build ${_updateInfo!.buildNumber}) is ready';
      statusIcon = Icons.system_update_alt;
    } else {
      statusColor = const Color(0xFF10B981);
      statusTitle = 'NEXA is Up to Date';
      statusSubtitle = 'You are on the latest production release v${UpdateEngine.currentVersion}';
      statusIcon = Icons.verified;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusTitle,
                  style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  statusSubtitle,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionGrid() {
    final serverVer = _updateInfo?.latestVersion ?? 'Checking...';
    final serverBuild = _updateInfo != null ? '${_updateInfo!.buildNumber}' : '-';

    return Row(
      children: [
        // Installed Version
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.phone_android, color: Color(0xFF64748B), size: 14),
                    SizedBox(width: 6),
                    Text('INSTALLED', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'v${UpdateEngine.currentVersion}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Build ${UpdateEngine.currentBuildNumber}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Server Version
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.cloud_done, color: Color(0xFF00E5FF), size: 14),
                    SizedBox(width: 6),
                    Text('SERVER LATEST', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  serverVer.startsWith('v') ? serverVer : 'v$serverVer',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'Build $serverBuild',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadCard(bool isNewer) {
    if (kIsWeb) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Web Client Service Worker',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'On Web, updates are applied by refreshing and refreshing cached service workers.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh & Apply Update'),
              onPressed: () => _engine.triggerWebReload(),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.download_for_offline, color: Color(0xFF00E5FF), size: 20),
                  SizedBox(width: 8),
                  Text('In-App APK Downloader', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              if (_downloadedFilePath != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('READY', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Download Progress Bar
          if (_isDownloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                minHeight: 10,
                backgroundColor: const Color(0xFF1E293B),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _downloadStats,
              style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
          ] else if (_downloadStats.isNotEmpty) ...[
            Text(_downloadStats, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            const SizedBox(height: 14),
          ],

          if (_downloadError != null) ...[
            Text(_downloadError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            const SizedBox(height: 14),
          ],

          // Buttons
          Row(
            children: [
              if (_downloadedFilePath != null) ...[
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.install_mobile, size: 18),
                    label: const Text('Install APK Now', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _triggerInstall(_downloadedFilePath!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _startInAppDownload,
                    child: const Text('Re-download'),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isNewer ? const Color(0xFF00E5FF) : const Color(0xFF0284C7),
                      foregroundColor: isNewer ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(
                      _isDownloading
                          ? 'Downloading...'
                          : (isNewer ? 'Download & Install Update' : 'Reinstall / Download Latest APK'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isDownloading ? null : _startInAppDownload,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 15, color: Color(0xFF64748B)),
              label: const Text(
                'Open Direct Download in Browser',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
              onPressed: () {
                final url = _updateInfo?.downloadUrl ?? UpdateEngine.defaultDownloadUrl;
                _engine.openUrlInBrowser(url);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotesCard() {
    final notes = _updateInfo?.releaseNotes ??
        '• Redesigned Modern Minimalist UI with Obsidian Dark aesthetic.\n'
        '• Real-time Video Call module with Dual Camera Vision (PIP).\n'
        '• Voice Call module with dynamic acoustic waveforms.\n'
        '• Native device contacts synchronization via E.164 normalization.\n'
        '• Autonomous In-App Update Engine v1.2.0 (Build 4).';

    final releaseDate = _updateInfo?.releaseDate ?? '2026-10-09';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.notes, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 8),
                  Text("What's New in Release", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(
                releaseDate,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            notes,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildServerTelemetryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Update Gateway Architecture', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _telemetryRow('CDN Endpoint', 'glimmer-messaging-app-web.vercel.app'),
          _telemetryRow('Release Channel', 'Production Stable (Master)'),
          _telemetryRow('Gateway Ping', _serverLatencyMs != null ? '$_serverLatencyMs ms' : 'Verified'),
          _telemetryRow('Package Target', 'im.nexa.nexa_app (arm64-v8a / universal)'),
        ],
      ),
    );
  }

  Widget _telemetryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
