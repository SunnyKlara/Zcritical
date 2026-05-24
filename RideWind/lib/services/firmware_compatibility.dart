/// 固件兼容性检查服务
///
/// BLE 连接后通过 GET:VERSION 获取固件信息，
/// 判断 APP 与固件版本是否兼容。
///
/// 协议格式：
///   APP → FW: GET:VERSION
///   FW → APP: VERSION:fw_ver:proto_ver:hw_model
///
/// 兼容性规则：
///   - APP 维护 minFirmwareVersion（最低兼容固件版本）
///   - APP 维护 supportedProtocolVersions（支持的协议版本范围）
///   - 固件版本过低 → 提示用户升级固件
///   - 协议版本不兼容 → 降级模式或提示升级

import 'package:flutter/material.dart';

/// 固件版本信息（从 GET:VERSION 响应解析）
class FirmwareInfo {
  final String version;       // e.g. "1.1.1"
  final int protocolVersion;  // e.g. 3
  final String hwModel;       // e.g. "T1"

  const FirmwareInfo({
    required this.version,
    required this.protocolVersion,
    required this.hwModel,
  });

  /// 从 "VERSION:1.1.1:3:T1" 格式解析
  static FirmwareInfo? parse(String response) {
    // 支持 "VERSION:x.y.z:proto:model" 格式
    final match = RegExp(r'^VERSION:([^:]+):(\d+):(.+)$').firstMatch(response.trim());
    if (match == null) return null;

    return FirmwareInfo(
      version: match.group(1)!,
      protocolVersion: int.tryParse(match.group(2)!) ?? 0,
      hwModel: match.group(3)!,
    );
  }

  @override
  String toString() => 'FW $version (proto=$protocolVersion, hw=$hwModel)';
}

/// 兼容性检查结果
enum CompatibilityStatus {
  compatible,           // 完全兼容
  firmwareTooOld,       // 固件版本过低，需要升级固件
  appTooOld,           // APP 版本过低，需要升级 APP（固件比 APP 新太多）
  protocolMismatch,    // 协议版本不兼容
  unknown,             // 无法获取版本信息（旧固件不支持 GET:VERSION）
}

/// 兼容性检查详情
class CompatibilityResult {
  final CompatibilityStatus status;
  final FirmwareInfo? firmwareInfo;
  final String message;

  const CompatibilityResult({
    required this.status,
    this.firmwareInfo,
    required this.message,
  });
}

/// 固件兼容性服务
class FirmwareCompatibility {
  // ── APP 端兼容性配置 ──
  // 当前 APP 支持的协议版本范围
  static const int minProtocolVersion = 1;
  static const int maxProtocolVersion = 3;

  // 最低兼容固件版本（低于此版本的固件功能可能不正常）
  static const String minFirmwareVersion = '1.0.0';

  // 当前 APP 版本要求的最低固件版本（推荐升级）
  static const String recommendedFirmwareVersion = '1.1.0';

  /// 检查兼容性
  static CompatibilityResult check(FirmwareInfo? info) {
    if (info == null) {
      // 旧固件不支持 GET:VERSION，按兼容处理但记录警告
      return const CompatibilityResult(
        status: CompatibilityStatus.unknown,
        message: '无法获取固件版本信息（旧固件），按兼容模式运行',
      );
    }

    // 检查协议版本
    if (info.protocolVersion < minProtocolVersion) {
      return CompatibilityResult(
        status: CompatibilityStatus.firmwareTooOld,
        firmwareInfo: info,
        message: '固件协议版本过低 (v${info.protocolVersion})，请升级固件到最新版本',
      );
    }
    if (info.protocolVersion > maxProtocolVersion) {
      return CompatibilityResult(
        status: CompatibilityStatus.appTooOld,
        firmwareInfo: info,
        message: '固件协议版本 (v${info.protocolVersion}) 高于 APP 支持范围，请升级 APP',
      );
    }

    // 检查固件版本
    if (_isVersionLessThan(info.version, minFirmwareVersion)) {
      return CompatibilityResult(
        status: CompatibilityStatus.firmwareTooOld,
        firmwareInfo: info,
        message: '固件版本 ${info.version} 过低，最低要求 $minFirmwareVersion，请升级固件',
      );
    }

    // 兼容
    return CompatibilityResult(
      status: CompatibilityStatus.compatible,
      firmwareInfo: info,
      message: '固件 ${info.version} 兼容',
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
    return false; // equal
  }

  /// 显示兼容性警告对话框（仅在不兼容时调用）
  static void showWarningIfNeeded(BuildContext context, CompatibilityResult result) {
    if (result.status == CompatibilityStatus.compatible ||
        result.status == CompatibilityStatus.unknown) {
      // 兼容或未知（旧固件），不弹窗
      if (result.status == CompatibilityStatus.unknown) {
        debugPrint('⚠️ ${result.message}');
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.status == CompatibilityStatus.firmwareTooOld
                  ? Icons.system_update
                  : Icons.phone_android,
              color: Colors.orange,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('版本不兼容', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.message,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (result.firmwareInfo != null) ...[
              const SizedBox(height: 12),
              Text(
                '当前固件: ${result.firmwareInfo!.version}\n'
                '协议版本: ${result.firmwareInfo!.protocolVersion}\n'
                '硬件型号: ${result.firmwareInfo!.hwModel}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              result.status == CompatibilityStatus.firmwareTooOld
                  ? '部分功能可能无法正常使用，建议通过 OTA 升级固件。'
                  : '部分功能可能无法正常使用，建议升级 APP 到最新版本。',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我知道了', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}
