import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// APP版本信息（从GitHub获取）
class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? fallbackDownloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.fallbackDownloadUrl,
    this.forceUpdate = false,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String,
      buildNumber: json['buildNumber'] as int,
      downloadUrl: json['downloadUrl'] as String,
      fallbackDownloadUrl: json['fallbackDownloadUrl'] as String?,
      releaseNotes: json['releaseNotes'] as String? ?? json['changelog'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
    );
  }
}

/// APP自动更新服务
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._();
  factory AppUpdateService() => _instance;
  AppUpdateService._();

  /// 版本信息文件地址（主）
  static const String _versionUrl =
      'https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json';

  /// 版本信息文件地址（备用 CDN，国内更快）
  static const String _versionUrlFallback =
      'https://cdn.jsdelivr.net/gh/SunnyKlara/Zcritical@main/RideWind/app_version.json';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  CancelToken? _cancelToken;
  bool _isDownloading = false;

  /// 检查是否有新版本（自动尝试主 URL 和备用 URL）
  Future<AppVersionInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint('📱 当前版本: ${packageInfo.version}+$currentBuild');

      Map<String, dynamic>? data;
      data = await _fetchVersionJson(_versionUrl);
      if (data == null) {
        debugPrint('主 URL 失败，尝试 CDN 备用...');
        data = await _fetchVersionJson(_versionUrlFallback);
      }
      if (data == null) {
        debugPrint('⚠️ 所有版本检测 URL 均失败');
        return null;
      }

      final remoteInfo = AppVersionInfo.fromJson(data);
      debugPrint('🌐 远程版本: ${remoteInfo.version}+${remoteInfo.buildNumber}');

      if (remoteInfo.buildNumber > currentBuild) {
        return remoteInfo;
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ 检查更新失败: $e');
      return null;
    }
  }

  /// 从指定 URL 获取版本 JSON
  Future<Map<String, dynamic>?> _fetchVersionJson(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );

      if (response.statusCode != 200) return null;

      if (response.data is String) {
        return jsonDecode(response.data as String) as Map<String, dynamic>;
      }
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Fetch $url failed: $e');
      return null;
    }
  }

  /// 下载并安装APK（仅 Android）
  /// 自动尝试主地址和 fallback 地址
  Future<void> downloadAndInstall(
    AppVersionInfo info, {
    ValueChanged<double>? onProgress,
    VoidCallback? onComplete,
    ValueChanged<String>? onError,
  }) async {
    // iOS 不支持 APK 下载安装
    if (Platform.isIOS) {
      onError?.call('iOS 请通过 App Store 更新');
      return;
    }

    if (_isDownloading) return;
    _isDownloading = true;
    _cancelToken = CancelToken();

    final urls = [
      info.downloadUrl,
      if (info.fallbackDownloadUrl != null && info.fallbackDownloadUrl!.isNotEmpty)
        info.fallbackDownloadUrl!,
    ];

    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) {
        onError?.call('无法获取存储目录');
        return;
      }

      final downloadDir = Directory('${dir.path}/Download');
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }

      final filePath = '${downloadDir.path}/Critical-${info.version}.apk';

      // 如果已经下载过，删除重新下载
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }

      String? lastErrorMsg;

      for (final url in urls) {
        try {
          debugPrint('⬇️ 尝试下载: $url');
          onProgress?.call(0);

          await _dio.download(
            url,
            filePath,
            cancelToken: _cancelToken,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                onProgress?.call(received / total);
              }
            },
          );

          // 验证文件大小（APK 至少 1MB）
          final downloadedFile = File(filePath);
          if (downloadedFile.existsSync() && downloadedFile.lengthSync() < 1024 * 1024) {
            downloadedFile.deleteSync();
            throw Exception('下载文件异常（体积过小）');
          }

          debugPrint('✅ 下载完成: $filePath');
          onComplete?.call();

          // 打开APK安装
          final result = await OpenFilex.open(filePath);
          debugPrint('安装结果: ${result.type} ${result.message}');
          return; // 成功，退出
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) {
            debugPrint('下载已取消');
            return;
          }
          lastErrorMsg = '$e';
          debugPrint('⚠️ 从 $url 下载失败: $e，尝试下一个地址...');
        }
      }

      // 所有 URL 都失败
      onError?.call('下载失败，请检查网络后重试\n($lastErrorMsg)');
    } finally {
      _isDownloading = false;
      _cancelToken = null;
    }
  }

  /// 取消下载
  void cancelDownload() {
    _cancelToken?.cancel();
  }

  bool get isDownloading => _isDownloading;
}
