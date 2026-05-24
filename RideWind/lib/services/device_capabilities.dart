/// 设备能力矩阵 — 基于固件返回的 capabilities bitmap
///
/// 行业标准做法：
///   - 固件是真值源，通过 HELLO 握手返回 caps_bitmap
///   - APP 根据 bitmap 动态渲染 UI（不支持的功能隐藏/灰色）
///   - 运行时根据 ERR:UNKNOWN_CMD 动态降级
///
/// Bitmap 定义（与固件 board_config.h 保持同步）：
///   bit 0:  speed_control
///   bit 1:  led_preset
///   bit 2:  led_rgb
///   bit 3:  atomizer
///   bit 4:  fan_control
///   bit 5:  ota
///   bit 6:  wifi_provisioning
///   bit 7:  logo_upload
///   bit 8:  audio_engine
///   bit 9:  speed_max_config
///   bit 10: fan_range_config
///   bit 11: volume_control
///   bit 12: throttle_mode
///   bit 13: throttle_fx
///   bit 14: streamlight
///   bit 15: audio_upload
///   bit 16: wifi_audio
///   bit 17: led_gradient

import 'firmware_compatibility.dart';

/// Capability bit positions (must match firmware board_config.h)
class CapBit {
  static const int speedControl = 0;
  static const int ledPreset = 1;
  static const int ledRgb = 2;
  static const int atomizer = 3;
  static const int fanControl = 4;
  static const int ota = 5;
  static const int wifiProvision = 6;
  static const int logoUpload = 7;
  static const int audioEngine = 8;
  static const int speedMaxConfig = 9;
  static const int fanRangeConfig = 10;
  static const int volumeControl = 11;
  static const int throttleMode = 12;
  static const int throttleFx = 13;
  static const int streamlight = 14;
  static const int audioUpload = 15;
  static const int wifiAudio = 16;
  static const int ledGradient = 17;
}

/// 设备能力集合
class DeviceCapabilities {
  /// Raw bitmap from firmware (0 = unknown/disconnected)
  final int bitmap;

  const DeviceCapabilities(this.bitmap);

  // ── Feature queries ──

  bool get hasSpeedControl => _has(CapBit.speedControl);
  bool get hasLedPreset => _has(CapBit.ledPreset);
  bool get hasLedRgb => _has(CapBit.ledRgb);
  bool get hasAtomizer => _has(CapBit.atomizer);
  bool get hasFanControl => _has(CapBit.fanControl);
  bool get hasOTA => _has(CapBit.ota);
  bool get hasWifiProvision => _has(CapBit.wifiProvision);
  bool get hasLogoUpload => _has(CapBit.logoUpload);
  bool get hasAudioEngine => _has(CapBit.audioEngine);
  bool get hasSpeedMaxConfig => _has(CapBit.speedMaxConfig);
  bool get hasFanRangeConfig => _has(CapBit.fanRangeConfig);
  bool get hasVolumeControl => _has(CapBit.volumeControl);
  bool get hasThrottleMode => _has(CapBit.throttleMode);
  bool get hasThrottleFx => _has(CapBit.throttleFx);
  bool get hasStreamlight => _has(CapBit.streamlight);
  bool get hasAudioUpload => _has(CapBit.audioUpload);
  bool get hasWifiAudio => _has(CapBit.wifiAudio);
  bool get hasLedGradient => _has(CapBit.ledGradient);

  // ── Convenience groups ──

  /// Basic LED control (preset + RGB)
  bool get hasLedControl => hasLedPreset || hasLedRgb;

  /// Any audio feature
  bool get hasAnyAudio => hasAudioEngine || hasAudioUpload || hasWifiAudio;

  /// Garage mode (requires speed_max + fan_range + volume)
  bool get hasGarageMode =>
      hasSpeedMaxConfig && hasFanRangeConfig && hasVolumeControl;

  bool _has(int bit) => (bitmap >> bit) & 1 == 1;

  // ── Runtime degradation ──

  /// Create a new capabilities with a specific feature disabled
  /// (used when ERR:UNKNOWN_CMD is received for a command)
  DeviceCapabilities withoutFeature(int bit) {
    return DeviceCapabilities(bitmap & ~(1 << bit));
  }

  // ── Factory constructors ──

  /// From HELLO response bitmap (hex string → int)
  factory DeviceCapabilities.fromHexBitmap(String hex) {
    final value = int.tryParse(hex, radix: 16) ?? 0;
    return DeviceCapabilities(value);
  }

  /// From protocol version (fallback for old firmware without HELLO)
  /// Maps protocol version to a conservative bitmap
  factory DeviceCapabilities.forProtocol(int? protocolVersion) {
    final proto = protocolVersion ?? 0;

    int bitmap = 0;

    // proto >= 0: basic features (even old firmware without version query)
    bitmap |= (1 << CapBit.speedControl);
    bitmap |= (1 << CapBit.ledPreset);
    bitmap |= (1 << CapBit.ledRgb);
    bitmap |= (1 << CapBit.atomizer);
    bitmap |= (1 << CapBit.fanControl);
    bitmap |= (1 << CapBit.streamlight);
    bitmap |= (1 << CapBit.ledGradient);

    if (proto >= 1) {
      bitmap |= (1 << CapBit.ota);
      bitmap |= (1 << CapBit.wifiProvision);
      bitmap |= (1 << CapBit.logoUpload);
      bitmap |= (1 << CapBit.audioEngine);
      bitmap |= (1 << CapBit.speedMaxConfig);
      bitmap |= (1 << CapBit.fanRangeConfig);
      bitmap |= (1 << CapBit.volumeControl);
      bitmap |= (1 << CapBit.throttleMode);
      bitmap |= (1 << CapBit.throttleFx);
      bitmap |= (1 << CapBit.audioUpload);
      bitmap |= (1 << CapBit.wifiAudio);
    }

    return DeviceCapabilities(bitmap);
  }

  /// From FirmwareInfo (convenience)
  factory DeviceCapabilities.fromFirmwareInfo(FirmwareInfo? info) {
    return DeviceCapabilities.forProtocol(info?.protocolVersion);
  }

  /// Disconnected state — no capabilities
  static const DeviceCapabilities disconnected = DeviceCapabilities(0);

  /// All capabilities enabled (debug/test only)
  static const DeviceCapabilities all = DeviceCapabilities(0x3FFFF); // 18 bits

  @override
  String toString() {
    final features = <String>[];
    if (hasSpeedControl) features.add('speed');
    if (hasLedPreset) features.add('preset');
    if (hasLedRgb) features.add('rgb');
    if (hasAtomizer) features.add('atomizer');
    if (hasFanControl) features.add('fan');
    if (hasOTA) features.add('ota');
    if (hasWifiProvision) features.add('wifi');
    if (hasLogoUpload) features.add('logo');
    if (hasAudioEngine) features.add('audio');
    if (hasSpeedMaxConfig) features.add('speed_max');
    if (hasFanRangeConfig) features.add('fan_range');
    if (hasVolumeControl) features.add('volume');
    if (hasThrottleMode) features.add('throttle');
    if (hasThrottleFx) features.add('throttle_fx');
    if (hasStreamlight) features.add('streamlight');
    if (hasAudioUpload) features.add('audio_upload');
    if (hasWifiAudio) features.add('wifi_audio');
    if (hasLedGradient) features.add('gradient');
    return 'Caps(0x${bitmap.toRadixString(16)})[${features.join(",")}]';
  }
}
