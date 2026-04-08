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
  final String releaseNotes;
  final bool forceUpdate;

  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] as String,
      buildNumber: json['buildNumber'] as int,
      downloadUrl: json['downloadUrl'] as String,
      releaseNotes: json['releaseNotes'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
    );
  }
}

/// APP自动更新服务
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._();
  factory AppUpdateService() => _instance;
  AppUpdateService._();

  /// GitHub 版本信息文件地址
  /// ⚠️ 发布前请替换为你的 GitHub 仓库地址
  static const String _versionUrl =
      'https://raw.githubusercontent.com/SunnyKlara/RideWind/main/version.json';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  CancelToken? _cancelToken;
  bool _isDownloading = false;

  /// 检查是否有新版本
  Future<AppVersionInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint('📱 当前版本: ${packageInfo.version}+$currentBuild');

      final response = await _dio.get(_versionUrl);
      final Map<String, dynamic> data;

      if (response.data is String) {
        data = jsonDecode(response.data as String);
      } else {
        data = response.data as Map<String, dynamic>;
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

  /// 下载并安装APK
  Future<void> downloadAndInstall(
    AppVersionInfo info, {
    ValueChanged<double>? onProgress,
    VoidCallback? onComplete,
    ValueChanged<String>? onError,
  }) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _cancelToken = CancelToken();

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

      final filePath = '${downloadDir.path}/RideWind-${info.version}.apk';

      // 如果已经下载过，直接安装
      final file = File(filePath);
      if (file.existsSync()) {
        file.deleteSync();
      }

      debugPrint('⬇️ 开始下载: ${info.downloadUrl}');

      await _dio.download(
        info.downloadUrl,
        filePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress?.call(received / total);
          }
        },
      );

      debugPrint('下载完成: $filePath');
      onComplete?.call();

      // 打开APK安装
      final result = await OpenFilex.open(filePath);
      debugPrint('安装结果: ${result.type} ${result.message}');
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        debugPrint('下载已取消');
      } else {
        debugPrint('下载失败: $e');
        onError?.call('下载失败: $e');
      }
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
