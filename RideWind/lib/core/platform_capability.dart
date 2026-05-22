/// 平台能力注册与降级机制
///
/// 运行时检测平台能力，自动隐藏不支持的功能入口。
/// 新平台接入时只需实现 [PlatformCapabilityProvider] 接口。
///
/// 使用方式：
///   final caps = PlatformCapabilities.instance;
///   if (caps.supports(PlatformFeature.audioCapture)) { ... }
///   caps.getUnavailableReason(PlatformFeature.audioCapture); // "iOS 不支持系统音频捕获"
library;

import 'dart:io' show Platform;

/// 平台特有功能枚举
enum PlatformFeature {
  /// 系统音频捕获（Android MediaProjection）
  audioCapture,

  /// WiFi SSID 自动获取
  wifiSsidAutoDetect,

  /// APK 下载安装（应用内更新）
  inAppUpdate,

  /// 后台 BLE 通信
  backgroundBle,

  /// WiFi 扫描（原生 API）
  wifiScan,

  /// 文件系统自由访问（非沙盒）
  fileSystemFreeAccess,

  /// 通知渠道管理
  notificationChannels,

  /// NFC 通信
  nfc,
}

/// 平台能力描述
class FeatureCapability {
  final PlatformFeature feature;
  final bool isSupported;
  final String? unavailableReason;
  final String? fallbackDescription;

  const FeatureCapability({
    required this.feature,
    required this.isSupported,
    this.unavailableReason,
    this.fallbackDescription,
  });
}

/// 平台能力提供者接口 — 每个平台实现一个
abstract class PlatformCapabilityProvider {
  /// 平台标识符
  String get platformId;

  /// 平台显示名称
  String get platformDisplayName;

  /// 查询某功能是否支持
  FeatureCapability getCapability(PlatformFeature feature);

  /// 获取所有能力列表
  List<FeatureCapability> getAllCapabilities();
}

/// Android 平台能力
class AndroidCapabilityProvider implements PlatformCapabilityProvider {
  @override
  String get platformId => 'android';

  @override
  String get platformDisplayName => 'Android';

  @override
  FeatureCapability getCapability(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.audioCapture:
        return const FeatureCapability(
          feature: PlatformFeature.audioCapture,
          isSupported: true,
        );
      case PlatformFeature.wifiSsidAutoDetect:
        return const FeatureCapability(
          feature: PlatformFeature.wifiSsidAutoDetect,
          isSupported: true,
        );
      case PlatformFeature.inAppUpdate:
        return const FeatureCapability(
          feature: PlatformFeature.inAppUpdate,
          isSupported: true,
        );
      case PlatformFeature.backgroundBle:
        return const FeatureCapability(
          feature: PlatformFeature.backgroundBle,
          isSupported: true,
        );
      case PlatformFeature.wifiScan:
        return const FeatureCapability(
          feature: PlatformFeature.wifiScan,
          isSupported: true,
        );
      case PlatformFeature.fileSystemFreeAccess:
        return const FeatureCapability(
          feature: PlatformFeature.fileSystemFreeAccess,
          isSupported: true,
        );
      case PlatformFeature.notificationChannels:
        return const FeatureCapability(
          feature: PlatformFeature.notificationChannels,
          isSupported: true,
        );
      case PlatformFeature.nfc:
        return const FeatureCapability(
          feature: PlatformFeature.nfc,
          isSupported: true,
        );
    }
  }

  @override
  List<FeatureCapability> getAllCapabilities() {
    return PlatformFeature.values.map(getCapability).toList();
  }
}

/// iOS 平台能力
class IOSCapabilityProvider implements PlatformCapabilityProvider {
  @override
  String get platformId => 'ios';

  @override
  String get platformDisplayName => 'iOS';

  @override
  FeatureCapability getCapability(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.audioCapture:
        return const FeatureCapability(
          feature: PlatformFeature.audioCapture,
          isSupported: false,
          unavailableReason: 'iOS 不支持系统音频捕获',
          fallbackDescription: '请使用蓝牙音箱模式',
        );
      case PlatformFeature.wifiSsidAutoDetect:
        return const FeatureCapability(
          feature: PlatformFeature.wifiSsidAutoDetect,
          isSupported: false,
          unavailableReason: 'iOS 需要 NEHotspotHelper 权限（需 Apple 审批）',
          fallbackDescription: '手动输入 WiFi 名称',
        );
      case PlatformFeature.inAppUpdate:
        return const FeatureCapability(
          feature: PlatformFeature.inAppUpdate,
          isSupported: false,
          unavailableReason: 'iOS 不允许应用内安装更新',
          fallbackDescription: '跳转 App Store 更新',
        );
      case PlatformFeature.backgroundBle:
        return const FeatureCapability(
          feature: PlatformFeature.backgroundBle,
          isSupported: true,
        );
      case PlatformFeature.wifiScan:
        return const FeatureCapability(
          feature: PlatformFeature.wifiScan,
          isSupported: false,
          unavailableReason: 'iOS 不提供 WiFi 扫描 API',
          fallbackDescription: '手动输入 WiFi 信息',
        );
      case PlatformFeature.fileSystemFreeAccess:
        return const FeatureCapability(
          feature: PlatformFeature.fileSystemFreeAccess,
          isSupported: false,
          unavailableReason: 'iOS 沙盒限制',
          fallbackDescription: '使用 path_provider 沙盒路径',
        );
      case PlatformFeature.notificationChannels:
        return const FeatureCapability(
          feature: PlatformFeature.notificationChannels,
          isSupported: false,
          unavailableReason: 'iOS 使用 UNNotification 体系',
          fallbackDescription: '使用 iOS 通知分类',
        );
      case PlatformFeature.nfc:
        return const FeatureCapability(
          feature: PlatformFeature.nfc,
          isSupported: true,
        );
    }
  }

  @override
  List<FeatureCapability> getAllCapabilities() {
    return PlatformFeature.values.map(getCapability).toList();
  }
}

/// macOS 平台能力（预留）
class MacOSCapabilityProvider implements PlatformCapabilityProvider {
  @override
  String get platformId => 'macos';

  @override
  String get platformDisplayName => 'macOS';

  @override
  FeatureCapability getCapability(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.audioCapture:
        return const FeatureCapability(
          feature: PlatformFeature.audioCapture,
          isSupported: false,
          unavailableReason: 'macOS 音频捕获需要 ScreenCaptureKit（macOS 13+）',
          fallbackDescription: '未来版本支持',
        );
      case PlatformFeature.wifiSsidAutoDetect:
        return const FeatureCapability(
          feature: PlatformFeature.wifiSsidAutoDetect,
          isSupported: true,
        );
      case PlatformFeature.inAppUpdate:
        return const FeatureCapability(
          feature: PlatformFeature.inAppUpdate,
          isSupported: false,
          unavailableReason: 'macOS 通过 Sparkle 或 Mac App Store 更新',
          fallbackDescription: '跳转下载页面',
        );
      case PlatformFeature.backgroundBle:
        return const FeatureCapability(
          feature: PlatformFeature.backgroundBle,
          isSupported: true,
        );
      case PlatformFeature.wifiScan:
        return const FeatureCapability(
          feature: PlatformFeature.wifiScan,
          isSupported: true,
        );
      case PlatformFeature.fileSystemFreeAccess:
        return const FeatureCapability(
          feature: PlatformFeature.fileSystemFreeAccess,
          isSupported: true,
        );
      case PlatformFeature.notificationChannels:
        return const FeatureCapability(
          feature: PlatformFeature.notificationChannels,
          isSupported: false,
          unavailableReason: 'macOS 使用 UNNotification',
          fallbackDescription: '使用 macOS 通知中心',
        );
      case PlatformFeature.nfc:
        return const FeatureCapability(
          feature: PlatformFeature.nfc,
          isSupported: false,
          unavailableReason: 'macOS 不支持 NFC',
        );
    }
  }

  @override
  List<FeatureCapability> getAllCapabilities() {
    return PlatformFeature.values.map(getCapability).toList();
  }
}

/// Windows 平台能力（预留）
class WindowsCapabilityProvider implements PlatformCapabilityProvider {
  @override
  String get platformId => 'windows';

  @override
  String get platformDisplayName => 'Windows';

  @override
  FeatureCapability getCapability(PlatformFeature feature) {
    switch (feature) {
      case PlatformFeature.audioCapture:
        return const FeatureCapability(
          feature: PlatformFeature.audioCapture,
          isSupported: false,
          unavailableReason: 'Windows 音频捕获需要 WASAPI loopback',
          fallbackDescription: '未来版本支持',
        );
      case PlatformFeature.wifiSsidAutoDetect:
        return const FeatureCapability(
          feature: PlatformFeature.wifiSsidAutoDetect,
          isSupported: true,
        );
      case PlatformFeature.inAppUpdate:
        return const FeatureCapability(
          feature: PlatformFeature.inAppUpdate,
          isSupported: true,
        );
      case PlatformFeature.backgroundBle:
        return const FeatureCapability(
          feature: PlatformFeature.backgroundBle,
          isSupported: false,
          unavailableReason: 'Windows BLE 需要 win_ble 插件',
          fallbackDescription: 'flutter_blue_plus 不支持 Windows',
        );
      case PlatformFeature.wifiScan:
        return const FeatureCapability(
          feature: PlatformFeature.wifiScan,
          isSupported: true,
        );
      case PlatformFeature.fileSystemFreeAccess:
        return const FeatureCapability(
          feature: PlatformFeature.fileSystemFreeAccess,
          isSupported: true,
        );
      case PlatformFeature.notificationChannels:
        return const FeatureCapability(
          feature: PlatformFeature.notificationChannels,
          isSupported: true,
        );
      case PlatformFeature.nfc:
        return const FeatureCapability(
          feature: PlatformFeature.nfc,
          isSupported: false,
          unavailableReason: 'Windows NFC 支持有限',
        );
    }
  }

  @override
  List<FeatureCapability> getAllCapabilities() {
    return PlatformFeature.values.map(getCapability).toList();
  }
}

/// 全局平台能力单例
class PlatformCapabilities {
  PlatformCapabilities._();

  static final PlatformCapabilities instance = PlatformCapabilities._();

  late final PlatformCapabilityProvider _provider = _detectProvider();

  PlatformCapabilityProvider _detectProvider() {
    if (Platform.isAndroid) return AndroidCapabilityProvider();
    if (Platform.isIOS) return IOSCapabilityProvider();
    if (Platform.isMacOS) return MacOSCapabilityProvider();
    if (Platform.isWindows) return WindowsCapabilityProvider();
    // 默认降级到最保守的能力集
    return IOSCapabilityProvider();
  }

  /// 当前平台标识
  String get platformId => _provider.platformId;

  /// 当前平台显示名
  String get platformDisplayName => _provider.platformDisplayName;

  /// 查询功能是否支持
  bool supports(PlatformFeature feature) {
    return _provider.getCapability(feature).isSupported;
  }

  /// 获取不可用原因
  String? getUnavailableReason(PlatformFeature feature) {
    return _provider.getCapability(feature).unavailableReason;
  }

  /// 获取降级方案描述
  String? getFallbackDescription(PlatformFeature feature) {
    return _provider.getCapability(feature).fallbackDescription;
  }

  /// 获取完整能力信息
  FeatureCapability getCapability(PlatformFeature feature) {
    return _provider.getCapability(feature);
  }

  /// 获取所有能力
  List<FeatureCapability> getAllCapabilities() {
    return _provider.getAllCapabilities();
  }

  /// 获取所有不支持的功能
  List<FeatureCapability> getUnsupportedFeatures() {
    return _provider.getAllCapabilities().where((c) => !c.isSupported).toList();
  }
}
