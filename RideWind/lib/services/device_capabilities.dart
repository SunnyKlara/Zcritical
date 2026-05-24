/// 设备能力矩阵 — 根据固件协议版本决定哪些功能可用
///
/// 核心原则：
///   - APP 永远不崩溃，只是功能多少不同
///   - 新 APP + 旧固件 = 旧功能正常，新功能隐藏
///   - 旧 APP + 新固件 = 旧功能正常，新功能不展示
///
/// 协议版本演进规则：
///   proto=1: 基础功能（风扇/LED/雾化器/Logo/OTA/音频/WiFi/油门灯效）
///   proto=2: 预留（车库联动/Colorize v2 等）
///   proto=3: 预留（跑步机/高级音频等）
///
/// 使用方式：
///   final caps = DeviceCapabilities.forProtocol(firmwareInfo?.protocolVersion);
///   if (caps.hasAudioCasting) { /* 显示音频投射入口 */ }

import 'firmware_compatibility.dart';

/// 设备能力集合
class DeviceCapabilities {
  /// 基础控制（风扇、LED 颜色、亮度、预设）
  final bool hasFanControl;

  /// LED 流水灯效果
  final bool hasStreamlight;

  /// LED 渐变效果
  final bool hasGradient;

  /// 雾化器控制
  final bool hasAtomizer;

  /// Logo 上传与管理
  final bool hasLogoUpload;

  /// OTA 固件升级
  final bool hasOTA;

  /// 音量控制
  final bool hasVolumeControl;

  /// 油门模式（硬件端模拟）
  final bool hasThrottleMode;

  /// 油门灯效（1-6 模式）
  final bool hasThrottleEffects;

  /// WiFi 音频投射
  final bool hasAudioCasting;

  /// WiFi 扫描
  final bool hasWifiScan;

  /// 自定义音频上传（引擎声浪）
  final bool hasCustomAudio;

  /// 速度显示最大值设置
  final bool hasSpeedMaxConfig;

  /// 风扇 PWM 范围设置
  final bool hasFanRangeConfig;

  /// 车库模式（选车联动）
  final bool hasGarageMode;

  /// Colorize v2（高级灯光编排）
  final bool hasColorizeV2;

  /// 跑步机模式
  final bool hasTreadmill;

  const DeviceCapabilities({
    this.hasFanControl = false,
    this.hasStreamlight = false,
    this.hasGradient = false,
    this.hasAtomizer = false,
    this.hasLogoUpload = false,
    this.hasOTA = false,
    this.hasVolumeControl = false,
    this.hasThrottleMode = false,
    this.hasThrottleEffects = false,
    this.hasAudioCasting = false,
    this.hasWifiScan = false,
    this.hasCustomAudio = false,
    this.hasSpeedMaxConfig = false,
    this.hasFanRangeConfig = false,
    this.hasGarageMode = false,
    this.hasColorizeV2 = false,
    this.hasTreadmill = false,
  });

  /// 根据协议版本生成能力集合
  ///
  /// [protocolVersion] 为 null 时表示旧固件（不支持 GET:VERSION），
  /// 按 proto=0 处理，只开放最基础的功能。
  factory DeviceCapabilities.forProtocol(int? protocolVersion) {
    final proto = protocolVersion ?? 0;

    return DeviceCapabilities(
      // proto >= 0: 基础功能（即使旧固件不响应版本查询也能用）
      hasFanControl: true,
      hasStreamlight: true,
      hasGradient: true,
      hasAtomizer: true,
      hasLogoUpload: proto >= 1,
      hasOTA: proto >= 1,
      hasVolumeControl: proto >= 1,
      hasThrottleMode: proto >= 1,
      hasThrottleEffects: proto >= 1,
      hasAudioCasting: proto >= 1,
      hasWifiScan: proto >= 1,
      hasCustomAudio: proto >= 1,
      hasSpeedMaxConfig: proto >= 1,
      hasFanRangeConfig: proto >= 1,

      // proto >= 2: 未来功能（当前固件还没实现）
      hasGarageMode: proto >= 2,
      hasColorizeV2: proto >= 2,

      // proto >= 3: 远期功能
      hasTreadmill: proto >= 3,
    );
  }

  /// 从 FirmwareInfo 生成（便捷方法）
  factory DeviceCapabilities.fromFirmwareInfo(FirmwareInfo? info) {
    return DeviceCapabilities.forProtocol(info?.protocolVersion);
  }

  /// 未连接时的空能力集（所有功能不可用）
  static const DeviceCapabilities disconnected = DeviceCapabilities();

  /// 所有功能可用（仅用于调试/测试）
  static const DeviceCapabilities all = DeviceCapabilities(
    hasFanControl: true,
    hasStreamlight: true,
    hasGradient: true,
    hasAtomizer: true,
    hasLogoUpload: true,
    hasOTA: true,
    hasVolumeControl: true,
    hasThrottleMode: true,
    hasThrottleEffects: true,
    hasAudioCasting: true,
    hasWifiScan: true,
    hasCustomAudio: true,
    hasSpeedMaxConfig: true,
    hasFanRangeConfig: true,
    hasGarageMode: true,
    hasColorizeV2: true,
    hasTreadmill: true,
  );

  @override
  String toString() {
    final enabled = <String>[];
    if (hasFanControl) enabled.add('fan');
    if (hasStreamlight) enabled.add('streamlight');
    if (hasGradient) enabled.add('gradient');
    if (hasAtomizer) enabled.add('atomizer');
    if (hasLogoUpload) enabled.add('logo');
    if (hasOTA) enabled.add('ota');
    if (hasVolumeControl) enabled.add('volume');
    if (hasThrottleMode) enabled.add('throttle');
    if (hasThrottleEffects) enabled.add('throttleFx');
    if (hasAudioCasting) enabled.add('audioCast');
    if (hasWifiScan) enabled.add('wifiScan');
    if (hasCustomAudio) enabled.add('customAudio');
    if (hasSpeedMaxConfig) enabled.add('speedMax');
    if (hasFanRangeConfig) enabled.add('fanRange');
    if (hasGarageMode) enabled.add('garage');
    if (hasColorizeV2) enabled.add('colorizeV2');
    if (hasTreadmill) enabled.add('treadmill');
    return 'DeviceCapabilities(${enabled.join(', ')})';
  }
}
