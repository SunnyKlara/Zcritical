import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 固件更新检测服务
///
/// 通过对比设备当前固件版本与 firmware.json 中的最新版本，
/// 判断是否有可用更新。BLE 连接时即可检测，无需配网。
///
/// 流程：
///   1. BLE 连接后 BluetoothProvider 自动获取 firmwareInfo.version
///   2. 本服务加载 firmware.json 获取最新版本号
///   3. 对比两者，返回更新状态
class FirmwareUpdateChecker {
  static FirmwareUpdateChecker? _instance;
  static FirmwareUpdateChecker get instance =>
      _instance ??= FirmwareUpdateChecker._();

  FirmwareUpdateChecker._();

  /// 缓存的最新固件信息
  LatestFirmwareInfo? _latestInfo;

  /// 加载 firmware.json（从 assets 或网络）
  Future<LatestFirmwareInfo?> getLatestFirmwareInfo() async {
    if (_latestInfo != null) return _latestInfo;

    try {
      final jsonStr = await rootBundle.loadString('assets/firmware.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      _latestInfo = LatestFirmwareInfo.fromJson(json);
      return _latestInfo;
    } catch (e) {
      debugPrint('⚠️ 加载 firmware.json 失败: $e');
      return null;
    }
  }

  /// 强制刷新（下次调用 getLatestFirmwareInfo 会重新加载）
  void invalidateCache() {
    _latestInfo = null;
  }

  /// 检查设备是否有可用的固件更新
  ///
  /// [deviceFirmwareVersion] 从 BLE 连接获取的当前固件版本（如 "1.0.0"）
  /// 返回 [FirmwareUpdateStatus]
  Future<FirmwareUpdateStatus> checkForUpdate(
      String? deviceFirmwareVersion) async {
    if (deviceFirmwareVersion == null || deviceFirmwareVersion.isEmpty) {
      return FirmwareUpdateStatus.unknown;
    }

    final latest = await getLatestFirmwareInfo();
    if (latest == null) {
      return FirmwareUpdateStatus.unknown;
    }

    if (_isVersionLessThan(deviceFirmwareVersion, latest.version)) {
      return FirmwareUpdateStatus.updateAvailable;
    }

    return FirmwareUpdateStatus.upToDate;
  }

  /// 获取更新详情（版本号 + changelog）
  Future<FirmwareUpdateDetail?> getUpdateDetail(
      String? deviceFirmwareVersion) async {
    if (deviceFirmwareVersion == null) return null;

    final latest = await getLatestFirmwareInfo();
    if (latest == null) return null;

    if (!_isVersionLessThan(deviceFirmwareVersion, latest.version)) {
      return null; // 已是最新
    }

    return FirmwareUpdateDetail(
      currentVersion: deviceFirmwareVersion,
      latestVersion: latest.version,
      changelog: latest.changelog,
      downloadUrl: latest.downloadUrl,
    );
  }

  /// 版本比较：a < b ?
  static bool _isVersionLessThan(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }
}

/// 固件更新状态
enum FirmwareUpdateStatus {
  upToDate,        // 已是最新版本
  updateAvailable, // 有可用更新
  unknown,         // 无法判断（旧固件不上报版本 / firmware.json 加载失败）
}

/// firmware.json 中的最新固件信息
class LatestFirmwareInfo {
  final String version;
  final int size;
  final String downloadUrl;
  final String changelog;
  final String hwModel;

  const LatestFirmwareInfo({
    required this.version,
    required this.size,
    required this.downloadUrl,
    required this.changelog,
    required this.hwModel,
  });

  factory LatestFirmwareInfo.fromJson(Map<String, dynamic> json) {
    return LatestFirmwareInfo(
      version: json['version'] as String? ?? '0.0.0',
      size: json['size'] as int? ?? 0,
      downloadUrl: json['download_url'] as String? ?? '',
      changelog: json['changelog'] as String? ?? '',
      hwModel: json['hw_model'] as String? ?? 'T1',
    );
  }
}

/// 固件更新详情
class FirmwareUpdateDetail {
  final String currentVersion;
  final String latestVersion;
  final String changelog;
  final String downloadUrl;

  const FirmwareUpdateDetail({
    required this.currentVersion,
    required this.latestVersion,
    required this.changelog,
    required this.downloadUrl,
  });
}
