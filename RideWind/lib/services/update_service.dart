import 'dart:convert';
import 'dart:io';

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
  final String? fallbackDownloadUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final String? iosAppStoreUrl;

  UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.minVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    this.fallbackDownloadUrl,
    this.iosAppStoreUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: json['latest_version'] ?? '1.0.0',
      latestBuild: json['latest_build'] ?? 1,
      minVersion: json['min_version'] ?? '1.0.0',
      downloadUrl: json['download_url'] ?? '',
      fallbackDownloadUrl: json['fallback_download_url'],
      releaseNotes: json['release_notes'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      iosAppStoreUrl: json['ios_app_store_url'],
    );
  }

  /// 获取所有可用的下载地址（主地址 + fallback）
  List<String> get allDownloadUrls {
    final urls = <String>[];
    if (downloadUrl.isNotEmpty) urls.add(downloadUrl);
    if (fallbackDownloadUrl != null && fallbackDownloadUrl!.isNotEmpty) {
      urls.add(fallbackDownloadUrl!);
    }
    return urls;
  }
}

class UpdateService {
  // GitHub raw URL for version check（主）
  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json';

  // 备用版本检测 URL（jsdelivr CDN，国内更快）
  static const String _versionJsonFallbackUrl =
      'https://cdn.jsdelivr.net/gh/SunnyKlara/Zcritical@main/RideWind/app_version.json';

  /// Check if a newer version is available.
  /// 自动尝试主 URL 和备用 URL。
  static Future<UpdateInfo?> checkForUpdate() async {
    Map<String, dynamic>? data;

    // 尝试主 URL
    data = await _fetchVersionJson(_versionJsonUrl);

    // 主 URL 失败，尝试 CDN 备用
    if (data == null) {
      debugPrint('Primary version check failed, trying fallback CDN...');
      data = await _fetchVersionJson(_versionJsonFallbackUrl);
    }

    if (data == null) {
      debugPrint('All version check URLs failed');
      return null;
    }

    try {
      final updateInfo = UpdateInfo.fromJson(data);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isNewer(updateInfo.latestVersion, currentVersion)) {
        return updateInfo;
      }
      return null;
    } catch (e) {
      debugPrint('Version parse error: $e');
      return null;
    }
  }

  /// 从指定 URL 获取版本 JSON，失败返回 null
  static Future<Map<String, dynamic>?> _fetchVersionJson(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Fetch $url failed: $e');
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
  /// 自动尝试多个下载地址（主地址失败自动 fallback 到 GitHub Release）。
  static Future<void> downloadAndInstall(
    String url, {
    Function(double)? onProgress,
    String? fallbackUrl,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/ridewind_update.apk';

    final urls = [url, if (fallbackUrl != null) fallbackUrl];
    Exception? lastError;

    for (final downloadUrl in urls) {
      try {
        debugPrint('Attempting download from: $downloadUrl');
        final dio = Dio();
        dio.options.connectTimeout = const Duration(seconds: 15);
        dio.options.receiveTimeout = const Duration(minutes: 10);

        await dio.download(
          downloadUrl,
          filePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              onProgress?.call(received / total);
            }
          },
        );

        // 验证文件大小（APK 至少 1MB）
        final file = File(filePath);
        if (await file.length() < 1024 * 1024) {
          throw Exception('下载文件异常（体积过小），可能不是有效 APK');
        }

        // 下载成功，触发安装
        await OpenFilex.open(filePath);
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('Download failed from $downloadUrl: $e');
        // 重置进度，准备尝试下一个 URL
        onProgress?.call(0);
      }
    }

    // 所有 URL 都失败
    throw lastError ?? Exception('所有下载地址均不可用');
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
  int _retryCount = 0;

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
            child: Text(_retryCount > 0 ? '重试下载' : '立即更新'),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    // iOS: 跳转 App Store
    if (Platform.isIOS) {
      final url = widget.updateInfo.iosAppStoreUrl;
      if (url == null || url.isEmpty) {
        setState(() => _error = 'App Store 链接未配置');
        return;
      }
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Android: 下载 APK 并安装
    final urls = widget.updateInfo.allDownloadUrls;
    if (urls.isEmpty) {
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
        urls.first,
        fallbackUrl: urls.length > 1 ? urls[1] : null,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _retryCount++;
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载失败，请检查网络后重试\n($e)';
        });
      }
    }
  }
}
