/// Platform Channel 统一抽象层
///
/// 定义平台特有功能的接口规范。新平台接入时只需实现对应接口，
/// 注册到 [PlatformChannelRegistry]，上层代码无需修改。
///
/// 架构：
///   Screen/Widget
///     → PlatformChannelRegistry.instance.audioCapture.startCapture()
///     → 实际调用 Android/iOS/macOS 的 MethodChannel 实现
///     → 不支持的平台返回安全默认值（graceful degradation）
///
/// 新平台接入步骤：
///   1. 实现 [AudioCaptureChannel] / [WifiChannel] 等接口
///   2. 在 [PlatformChannelRegistry.init()] 中注册
///   3. 原生端实现对应 MethodChannel handler
library;

import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 平台不支持异常
class PlatformUnsupportedException implements Exception {
  final String feature;
  final String platform;
  final String? fallback;

  PlatformUnsupportedException({
    required this.feature,
    required this.platform,
    this.fallback,
  });

  @override
  String toString() =>
      '$platform 不支持 $feature${fallback != null ? '（降级方案：$fallback）' : ''}';
}

// ═══════════════════════════════════════════════════════════════
//  接口定义 — 每个平台特有功能一个接口
// ═══════════════════════════════════════════════════════════════

/// 音频捕获通道接口
abstract class AudioCaptureChannel {
  /// 开始捕获系统音频并流式传输到指定 IP
  Future<bool> startCapture({String ip = '192.168.4.1'});

  /// 停止捕获
  Future<void> stopCapture();

  /// 是否正在捕获
  Future<bool> isCapturing();

  /// 获取当前状态描述
  Future<String> getStatus();
}

/// WiFi 通道接口
abstract class WifiChannel {
  /// 扫描附近 WiFi 网络
  /// 返回 [{ssid, rssi, secure}]
  Future<List<Map<String, dynamic>>> scanWifi();

  /// 获取当前连接的 WiFi 信息
  /// 返回 {ssid, frequency} 或 null
  Future<Map<String, dynamic>?> getConnectedWifi();
}

/// 应用更新通道接口
abstract class AppUpdateChannel {
  /// 执行更新（Android: 下载 APK，iOS: 跳转 App Store）
  Future<void> performUpdate(String downloadUrl);
}

// ═══════════════════════════════════════════════════════════════
//  空实现（不支持的平台使用，graceful degradation）
// ═══════════════════════════════════════════════════════════════

/// 不支持音频捕获的平台 — 所有方法返回安全默认值
class UnsupportedAudioCaptureChannel implements AudioCaptureChannel {
  @override
  Future<bool> startCapture({String ip = '192.168.4.1'}) async => false;

  @override
  Future<void> stopCapture() async {}

  @override
  Future<bool> isCapturing() async => false;

  @override
  Future<String> getStatus() async => '当前平台不支持音频捕获';
}

/// 不支持 WiFi 扫描的平台 — 返回空列表
class UnsupportedWifiChannel implements WifiChannel {
  @override
  Future<List<Map<String, dynamic>>> scanWifi() async => [];

  @override
  Future<Map<String, dynamic>?> getConnectedWifi() async => null;
}

// ═══════════════════════════════════════════════════════════════
//  Android 实现（桥接现有 MethodChannel）
// ═══════════════════════════════════════════════════════════════

const _channel = MethodChannel('com.example.ridewind/audio_capture');

class AndroidAudioCaptureChannel implements AudioCaptureChannel {
  @override
  Future<bool> startCapture({String ip = '192.168.4.1'}) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('startCapture', {'ip': ip});
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        throw UnsupportedError('音频投射需要 Android 10 或更高版本');
      }
      rethrow;
    }
  }

  @override
  Future<void> stopCapture() async {
    await _channel.invokeMethod('stopCapture');
  }

  @override
  Future<bool> isCapturing() async {
    final result = await _channel.invokeMethod<bool>('isCapturing');
    return result ?? false;
  }

  @override
  Future<String> getStatus() async {
    final result = await _channel.invokeMethod<String>('getStatus');
    return result ?? '';
  }
}

class AndroidWifiChannel implements WifiChannel {
  @override
  Future<List<Map<String, dynamic>>> scanWifi() async {
    try {
      final result = await _channel.invokeMethod<List>('scanWifi');
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>?> getConnectedWifi() async {
    try {
      final result = await _channel.invokeMethod<Map>('getConnectedWifi');
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  注册中心
// ═══════════════════════════════════════════════════════════════

/// 平台通道注册中心 — 统一管理所有平台特有功能的实现
///
/// 初始化时根据当前平台注册对应实现，上层代码通过此单例访问。
/// 不支持的功能使用空实现（graceful degradation），不会抛异常。
class PlatformChannelRegistry {
  PlatformChannelRegistry._();

  static final PlatformChannelRegistry instance = PlatformChannelRegistry._();

  late AudioCaptureChannel _audioCapture;
  late WifiChannel _wifi;

  bool _initialized = false;

  /// 初始化注册中心（在 main.dart 中调用一次）
  ///
  /// 可传入自定义实现（测试或新平台），否则使用平台默认实现。
  void init({
    AudioCaptureChannel? audioCapture,
    WifiChannel? wifi,
  }) {
    if (_initialized) return;

    _audioCapture = audioCapture ?? _defaultAudioCapture();
    _wifi = wifi ?? _defaultWifi();

    _initialized = true;
  }

  /// 音频捕获通道
  AudioCaptureChannel get audioCapture {
    _ensureInitialized();
    return _audioCapture;
  }

  /// WiFi 通道
  WifiChannel get wifi {
    _ensureInitialized();
    return _wifi;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      init();
    }
  }

  AudioCaptureChannel _defaultAudioCapture() {
    if (Platform.isAndroid) {
      return AndroidAudioCaptureChannel();
    }
    return UnsupportedAudioCaptureChannel();
  }

  WifiChannel _defaultWifi() {
    if (Platform.isAndroid) {
      return AndroidWifiChannel();
    }
    return UnsupportedWifiChannel();
  }
}
