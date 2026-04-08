import 'dart:async';
import 'package:flutter/foundation.dart';
import 'engine_audio_controller.dart';
import '../providers/bluetooth_provider.dart';

/// 🚗 引擎音效管理器 (全局单例)
/// 
/// 功能：
/// - 监听蓝牙引擎通知 (ENGINE_START / ENGINE_READY)
/// - 自动播放专业赛车引擎启动音效
/// - 与硬件端开机双闪同步
class EngineAudioManager {
  static final EngineAudioManager _instance = EngineAudioManager._internal();
  factory EngineAudioManager() => _instance;
  EngineAudioManager._internal();

  final EngineAudioController _audioController = EngineAudioController();
  StreamSubscription<String>? _engineNotificationSubscription;
  BluetoothProvider? _bluetoothProvider;
  bool _isInitialized = false;

  /// 获取音频控制器实例
  EngineAudioController get audioController => _audioController;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化引擎音效管理器
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚗 [EngineAudioManager] 初始化中...');
      await _audioController.initialize();
      _isInitialized = true;
      debugPrint('🚗 [EngineAudioManager] 初始化成功');
    } catch (e) {
      debugPrint('❌ [EngineAudioManager] 初始化失败: $e');
    }
  }

  /// 绑定蓝牙提供者，开始监听引擎通知
  void bindBluetoothProvider(BluetoothProvider provider) {
    if (_bluetoothProvider == provider) return;

    // 取消之前的订阅
    _engineNotificationSubscription?.cancel();

    _bluetoothProvider = provider;

    // 订阅引擎通知流
    _engineNotificationSubscription = provider.engineNotificationStream.listen(
      _handleEngineNotification,
      onError: (e) {
        debugPrint('❌ [EngineAudioManager] 引擎通知流错误: $e');
      },
    );

    debugPrint('🚗 [EngineAudioManager] 已绑定蓝牙提供者');
  }

  /// 处理引擎通知
  void _handleEngineNotification(String notification) {
    debugPrint('🚗 [EngineAudioManager] 收到引擎通知: $notification');

    switch (notification) {
      case 'ENGINE_START':
        // 硬件开机，播放启动音效
        _playStartupSound();
        break;
      case 'ENGINE_READY':
        // 硬件启动完成
        debugPrint('🚗 [EngineAudioManager] 硬件启动完成');
        break;
      default:
        debugPrint('⚠️ [EngineAudioManager] 未知引擎通知: $notification');
    }
  }

  /// 播放启动音效
  Future<void> _playStartupSound() async {
    if (!_isInitialized) {
      debugPrint('⚠️ [EngineAudioManager] 未初始化，无法播放启动音效');
      return;
    }

    try {
      debugPrint('🚗 [EngineAudioManager] 播放启动音效...');
      await _audioController.playStartupSound();
    } catch (e) {
      debugPrint('❌ [EngineAudioManager] 播放启动音效失败: $e');
    }
  }

  /// 手动播放启动音效（用于测试）
  Future<void> playStartupSound() async {
    await _playStartupSound();
  }

  /// 释放资源
  Future<void> dispose() async {
    _engineNotificationSubscription?.cancel();
    await _audioController.dispose();
    _isInitialized = false;
    debugPrint('🚗 [EngineAudioManager] 已释放资源');
  }
}
