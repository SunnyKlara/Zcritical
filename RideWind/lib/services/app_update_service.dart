import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// APP版本信息（从远程 JSON 获取）
class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? fallbackDownloadUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final int rolloutPercentage;

  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.fallbackDownloadUrl,
    this.forceUpdate = false,
    this.rolloutPercentage = 100,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    // 解析 rolloutPercentage，容错处理
    int rollout = 100;
    final rawRollout = json['rolloutPercentage'] ?? json['rollout_percentage'];
    if (rawRollout is int && rawRollout >= 0 && rawRollout <= 100) {
      rollout = rawRollout;
    } else if (rawRollout is double && rawRollout >= 0 && rawRollout <= 100) {
      rollout = rawRollout.toInt();
    }
    // 非法值视为 100（全量推送）

    return AppVersionInfo(
      version: json['version'] as String? ?? json['latest_version'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as int? ?? json['latest_build'] as int? ?? 1,
      downloadUrl: json['downloadUrl'] as String? ?? json['download_url'] as String? ?? '',
      fallbackDownloadUrl: json['fallbackDownloadUrl'] as String? ?? json['fallback_download_url'] as String?,
      releaseNotes: json['changelog'] as String? ?? json['release_notes'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? json['force_update'] as bool? ?? false,
      rolloutPercentage: rollout,
    );
  }
}

/// 灰度发布控制器
class GrayscaleController {
  static const String _deviceIdKey = 'grayscale_device_id';

  /// 获取或生成设备唯一标识
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      // 生成稳定的 UUID 并持久化
      deviceId = _generateUuid();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// 判断当前设备是否在灰度范围内
  /// 使用 SHA-256 哈希确保均匀分布和单调递增特性
  static Future<bool> isInRollout(int rolloutPercentage) async {
    if (rolloutPercentage >= 100) return true;
    if (rolloutPercentage <= 0) return false;

    final deviceId = await getDeviceId();
    final hash = sha256.convert(utf8.encode(deviceId));
    // 取前 4 字节作为 uint32，对 100 取模
    final bytes = hash.bytes;
    final value = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final bucket = value.abs() % 100; // 0-99
    return bucket < rolloutPercentage;
  }

  static String _generateUuid() {
    final random = DateTime.now().microsecondsSinceEpoch;
    return '${random.toRadixString(16)}-${Object().hashCode.toRadixString(16)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
  }
}

/// APP自动更新服务（单例）
/// 统一版本检测 + 下载安装 + 灰度控制
class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._();
  factory AppUpdateService() => _instance;
  AppUpdateService._();

  /// iOS App Store URL（从 app_version.json 获取，上架后填入）
  static String iosAppStoreUrl = '';

  /// 版本信息 URL（主）
  static const String _versionUrl =
      'https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json';

  /// 版本信息 URL（备用 CDN，国内更快）
  static const String _versionUrlFallback =
      'https://cdn.jsdelivr.net/gh/SunnyKlara/Zcritical@main/RideWind/app_version.json';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  CancelToken? _cancelToken;
  bool _isDownloading = false;

  /// 检查是否有新版本（含灰度判定）
  /// 返回 null 表示无需更新（无新版本或不在灰度范围内）
  Future<AppVersionInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint('📱 当前版本: ${packageInfo.version}+$currentBuild');

      // 双 URL 版本检测
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
      debugPrint('🌐 远程版本: ${remoteInfo.version}+${remoteInfo.buildNumber}, rollout: ${remoteInfo.rolloutPercentage}%');

      // 存储 iOS App Store URL（供升级弹窗使用）
      final storeUrl = data['ios_app_store_url'] as String? ?? '';
      if (storeUrl.isNotEmpty) {
        iosAppStoreUrl = storeUrl;
      }

      // 版本比较
      if (remoteInfo.buildNumber <= currentBuild) {
        return null;
      }

      // 灰度判定
      if (remoteInfo.rolloutPercentage < 100) {
        final inRollout = await GrayscaleController.isInRollout(remoteInfo.rolloutPercentage);
        if (!inRollout) {
          debugPrint('🎯 设备不在灰度范围内 (${remoteInfo.rolloutPercentage}%)，跳过更新');
          return null;
        }
        debugPrint('🎯 设备在灰度范围内，展示更新');
      }

      return remoteInfo;
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

      final filePath = '${downloadDir.path}/Zcritical-${info.version}.apk';

      // 删除旧文件
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
