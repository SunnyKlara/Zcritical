import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// App update information from remote version.json
class UpdateInfo {
  final String latestVersion;
  final int latestBuild;
  final String minVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: json['latest_version'] ?? '1.0.0',
      latestBuild: json['latest_build'] ?? 1,
      minVersion: json['min_version'] ?? '1.0.0',
      downloadUrl: json['download_url'] ?? '',
      releaseNotes: json['release_notes'] ?? '',
      forceUpdate: json['force_update'] ?? false,
    );
  }
}

class UpdateService {
  // GitHub raw URL for version check
  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json';

  /// Check if a newer version is available.
  /// Returns [UpdateInfo] if update available, null otherwise.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final updateInfo = UpdateInfo.fromJson(data);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isNewer(updateInfo.latestVersion, currentVersion)) {
        return updateInfo;
      }
      return null;
    } catch (e) {
      // Network error, timeout, parse error — silently ignore
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Compare two semantic version strings.
  /// Returns true if [remote] is newer than [local].
  static bool _isNewer(String remote, String local) {
    final remoteParts = remote.split('.').map(int.parse).toList();
    final localParts = local.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final l = i < localParts.length ? localParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  /// Download APK and trigger install.
  /// [onProgress] callback receives 0.0 - 1.0 progress.
  static Future<void> downloadAndInstall(
    String url, {
    Function(double)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/ridewind_update.apk';

    final dio = Dio();
    await dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total);
        }
      },
    );

    // Trigger system installer
    await OpenFilex.open(filePath);
  }

  /// Show update dialog.
  /// Call this from your main page's initState or after BLE connection.
  static Future<void> showUpdateDialogIfNeeded(BuildContext context) async {
    final updateInfo = await checkForUpdate();
    if (updateInfo == null) return;
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (ctx) => _UpdateDialog(updateInfo: updateInfo),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  const _UpdateDialog({required this.updateInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 v${widget.updateInfo.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '更新内容：',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            widget.updateInfo.releaseNotes,
            style: const TextStyle(fontSize: 13),
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text(
              '下载中 ${(_progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (!widget.updateInfo.forceUpdate && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后提醒'),
          ),
        if (!_downloading)
          ElevatedButton(
            onPressed: _startDownload,
            child: const Text('立即更新'),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _error = '下载地址未配置');
      return;
    }

    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      await UpdateService.downloadAndInstall(
        widget.updateInfo.downloadUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载失败: $e';
        });
      }
    }
  }
}
