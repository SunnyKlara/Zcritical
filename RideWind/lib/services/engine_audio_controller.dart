import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart'; // debugPrint

/// 🚗 发动机音效控制器 (专业赛车引擎版)
/// 
/// 功能：
/// - 专业赛车引擎音效（启动、怠速、加速、高转速）
/// - 根据风速动态切换音效和调整音量/音调
/// - 平滑的音量/音调过渡
/// - 智能音效切换（怠速↔加速↔高转速）
/// - 资源管理和错误处理
class EngineAudioController {
  late final AudioPlayer _audioPlayer;
  late final AudioPlayer _brakePlayer;  // 🚗 刹车音效播放器（独立）
  late final AudioPlayer _startPlayer;  // 🚗 启动音效播放器
  
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isEnabled = true;
  int _currentSpeed = 0;
  bool _isBraking = false;  // 是否正在刹车
  String _currentEngineState = 'idle';  // idle, accel, high
  
  // 专业赛车引擎音效文件
  static const String _engineStart = 'sound/engine_start.mp3';  // 启动音效 (2.5s)
  static const String _engineIdle = 'sound/engine_idle.mp3';    // 怠速循环 (6s)
  static const String _engineAccel = 'sound/engine_accel.mp3';  // 加速音效 (4s)
  static const String _engineHigh = 'sound/engine_high.mp3';    // 高转速循环 (4s)
  static const String _brakeSound = 'sound/brake.mp3';          // 🔴 刹车音效
  
  // 音量和音调范围
  static const double _minVolume = 0.0;
  static const double _maxVolume = 0.85; // 最大音量85%
  static const double _minPlaybackRate = 0.95; // 最低音调
  static const double _maxPlaybackRate = 1.15; // 最高音调
  static const int _maxSpeed = 340; // 最大风速
  
  // 速度阈值（用于切换音效）
  static const int _idleThreshold = 30;    // 低于30: 怠速
  static const int _accelThreshold = 150;  // 30-150: 加速
  // 高于150: 高转速
  
  EngineAudioController() {
    _audioPlayer = AudioPlayer();
    _brakePlayer = AudioPlayer();
    _startPlayer = AudioPlayer();
    
    // 🎧 监听主播放器完成事件：实现循环播放
    _audioPlayer.onPlayerComplete.listen((_) {
      if (_isPlaying) {
        // 根据当前状态重新播放对应音效
        _playCurrentStateSound();
      }
    });
    
    // 🎧 监听刹车音效播放位置：循环5-10秒的刹车声
    _brakePlayer.onPositionChanged.listen((position) {
      if (_isBraking && position.inSeconds >= 10) {
        _brakePlayer.seek(const Duration(seconds: 5));
        debugPrint('🔄 刹车声循环: 10秒 → 5秒');
      }
    });
  }
  
  /// 播放当前状态对应的音效
  void _playCurrentStateSound() {
    String soundFile;
    switch (_currentEngineState) {
      case 'idle':
        soundFile = _engineIdle;
        break;
      case 'accel':
        soundFile = _engineAccel;
        break;
      case 'high':
        soundFile = _engineHigh;
        break;
      default:
        soundFile = _engineIdle;
    }
    _audioPlayer.play(AssetSource(soundFile));
    debugPrint('🔄 循环播放: $soundFile');
  }
  
  /// 初始化音效
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('🎵 正在初始化专业赛车引擎音效...');
      
      // 预加载所有引擎音效
      await _audioPlayer.setSource(AssetSource(_engineIdle));
      debugPrint('✅ 怠速音效已加载: $_engineIdle');
      
      // 初始化启动音效播放器
      try {
        await _startPlayer.setSource(AssetSource(_engineStart));
        debugPrint('✅ 启动音效已加载: $_engineStart');
      } catch (e) {
        debugPrint('⚠️ 启动音效未找到: $e');
      }
      
      // 初始化刹车音效
      try {
        await _brakePlayer.setSource(AssetSource(_brakeSound));
        debugPrint('✅ 刹车音效已加载: $_brakeSound');
      } catch (e) {
        debugPrint('⚠️ 刹车音效未找到: $e');
      }
      
      // 设置初始音量和播放速率
      await _audioPlayer.setVolume(0.6);
      await _audioPlayer.setPlaybackRate(1.0);
      await _startPlayer.setVolume(0.8);
      await _brakePlayer.setVolume(0.8);
      
      _isInitialized = true;
      _isEnabled = true;
      debugPrint('🎵 专业赛车引擎音效初始化成功');
    } catch (e) {
      debugPrint('❌ 初始化音效失败: $e');
      _isEnabled = false;
      _isInitialized = false;
    }
  }
  
  /// 🚗 播放启动音效（开机双闪时调用）
  Future<void> playStartupSound() async {
    if (!_isInitialized || !_isEnabled) {
      debugPrint('⚠️ 音效未初始化，无法播放启动音效');
      return;
    }
    
    try {
      await _startPlayer.setVolume(0.85);
      await _startPlayer.play(AssetSource(_engineStart));
      debugPrint('🚗 播放启动音效: $_engineStart');
    } catch (e) {
      debugPrint('❌ 播放启动音效失败: $e');
    }
  }
  
  /// 🚗 真实开车体验：专业赛车引擎音效（智能切换版）
  /// [speed] 当前速度
  /// [isDragging] 是否正在拖动（true=播放，false=暂停）
  /// [isBraking] 是否正在刹车（可选）
  void updateSpeed(int speed, {required bool isDragging, bool isBraking = false}) {
    debugPrint('🎵 updateSpeed: speed=$speed, isDragging=$isDragging, isBraking=$isBraking');
    
    if (!_isInitialized || !_isEnabled) {
      debugPrint('❌ 音效未初始化或已禁用');
      return;
    }
    
    final previousSpeed = _currentSpeed;
    _currentSpeed = speed.clamp(0, _maxSpeed);
    
    try {
      if (isDragging && _currentSpeed > 0) {
        // 🎵 确定当前应该播放的音效状态
        String targetState;
        if (_currentSpeed < _idleThreshold) {
          targetState = 'idle';
        } else if (_currentSpeed < _accelThreshold) {
          targetState = 'accel';
        } else {
          targetState = 'high';
        }
        
        // 🎵 如果状态改变，切换音效
        if (targetState != _currentEngineState || !_isPlaying) {
          _currentEngineState = targetState;
          
          String soundFile;
          switch (targetState) {
            case 'idle':
              soundFile = _engineIdle;
              break;
            case 'accel':
              soundFile = _engineAccel;
              break;
            case 'high':
              soundFile = _engineHigh;
              break;
            default:
              soundFile = _engineIdle;
          }
          
          _audioPlayer.play(AssetSource(soundFile));
          _isPlaying = true;
          debugPrint('🚗 切换引擎音效: $targetState ($soundFile)');
        }
        
        // 🎵 动态调整音量和音调
        final effectiveMaxSpeed = 200.0;
        final normalizedSpeed = (_currentSpeed / effectiveMaxSpeed).clamp(0.0, 1.0);
        
        // 音量：使用平方根曲线，低速时更敏感
        final sqrtSpeed = normalizedSpeed * normalizedSpeed;
        final targetVolume = (0.5 + sqrtSpeed * 0.45).clamp(0.45, 0.95);
        _audioPlayer.setVolume(targetVolume);
        
        // 播放速率：根据速度变化调整
        final speedDelta = _currentSpeed - previousSpeed;
        double playbackRate = 1.0;
        
        if (speedDelta > 2) {
          // 加速中：音调升高
          playbackRate = 1.0 + normalizedSpeed * 0.12;
        } else if (speedDelta < -2) {
          // 减速中：音调降低
          playbackRate = 0.95 + normalizedSpeed * 0.05;
        } else {
          // 匀速：基础音调
          playbackRate = 0.98 + normalizedSpeed * 0.08;
        }
        _audioPlayer.setPlaybackRate(playbackRate.clamp(0.95, 1.12));
        
        debugPrint('🎵 引擎: 状态=$_currentEngineState, 速度=$_currentSpeed, 音量=${targetVolume.toStringAsFixed(2)}, 速率=${playbackRate.toStringAsFixed(2)}');
        
      } else {
        // 停止引擎声
        if (_isPlaying) {
          _audioPlayer.pause();
          _audioPlayer.setPlaybackRate(1.0);
          _isPlaying = false;
          _currentEngineState = 'idle';
          debugPrint('⏸️ 引擎声暂停');
        }
      }
    } catch (e) {
      debugPrint('❌ 引擎控制失败: $e');
    }
  }
  
  /// 🔴 播放刹车音效（尖锐的刹车声）
  /// [speed] 当前速度（用于调整音调）
  void playBrakeSound({int speed = 0}) {
    if (!_isInitialized || !_isEnabled) return;
    
    try {
      if (!_isBraking) {
        _brakePlayer.play(AssetSource(_brakeSound));
        // 🎵 跳转到5秒位置（跳过前面的无声部分）
        Future.delayed(const Duration(milliseconds: 100), () {
          _brakePlayer.seek(const Duration(seconds: 5));
          debugPrint('🎵 刹车音效已跳转到5秒位置（有效刹车声）');
        });
        _isBraking = true;
        debugPrint('🔴 刹车音效: 尖锐的轮胎摩擦声（从5秒开始）');
      }
    } catch (e) {
      debugPrint('⚠️ 刹车音效播放失败（可能文件不存在）: $e');
    }
  }
  
  /// 🔴 更新刹车音效音调（优化版：从高速到低速都有明显音效）
  void updateBrakeSound(int speed) {
    if (!_isInitialized || !_isEnabled || !_isBraking) return;
    
    try {
      // 🏎️ 智能刹车音效：速度越低，音调越高（越尖锐），音量越大
      // 实际使用速度范围：0-200
      
      if (speed > 0) {
        final effectiveMaxSpeed = 200.0; // 实际最大速度
        final normalizedSpeed = (speed / effectiveMaxSpeed).clamp(0.0, 1.0);
        
        // 🔴 反转逻辑：速度降低 → 音调升高、音量增大
        final inversedSpeed = 1.0 - normalizedSpeed;  // 速度200→0时，inversedSpeed从0→1
        
        // 音调（播放速率）：使用立方曲线，让低速时变化更剧烈
        // 速度200: inversedSpeed=0 → rate=1.0（正常）
        // 速度100: inversedSpeed=0.5 → rate≈1.15（稍高）
        // 速度50: inversedSpeed=0.75 → rate≈1.34（很尖锐）
        // 速度10: inversedSpeed=0.95 → rate≈1.54（最尖锐）
        final cubicInversed = inversedSpeed * inversedSpeed * inversedSpeed; // 立方曲线
        final playbackRate = 1.0 + cubicInversed * 0.6;  // 1.0 → 1.6
        _brakePlayer.setPlaybackRate(playbackRate.clamp(1.0, 1.6));
        
        // 音量：使用平方曲线，从刹车开始就很明显
        // 速度200: inversedSpeed=0 → volume=0.6（起始就明显）
        // 速度100: inversedSpeed=0.5 → volume≈0.75
        // 速度50: inversedSpeed=0.75 → volume≈0.92
        // 速度10: inversedSpeed=0.95 → volume≈0.99（最响亮）
        final squaredInversed = inversedSpeed * inversedSpeed; // 平方曲线
        final targetVolume = 0.6 + squaredInversed * 0.39;  // 0.6 → 0.99
        _brakePlayer.setVolume(targetVolume.clamp(0.6, 0.99));
        
        debugPrint('🔴 刹车音效: 速度=$speed km/h, 音调=${playbackRate.toStringAsFixed(2)}x, 音量=${targetVolume.toStringAsFixed(2)}');
      } else {
        // 速度为0，最后一刻的尖锐音效
        _brakePlayer.setPlaybackRate(1.6);  // 最尖锐
        _brakePlayer.setVolume(0.99);  // 最响亮
        debugPrint('🔴 速度为0，刹车声最尖锐的瞬间！');
      }
    } catch (e) {
      debugPrint('⚠️ 更新刹车音效失败: $e');
    }
  }
  
  /// 🔴 停止刹车音效
  void stopBrakeSound() {
    if (!_isInitialized || !_isEnabled) return;
    
    try {
      if (_isBraking) {
        _brakePlayer.stop();
        _isBraking = false;
        debugPrint('⏸️ 刹车音效停止');
      }
    } catch (e) {
      debugPrint('⚠️ 停止刹车音效失败: $e');
    }
  }
  
  /// 启用/禁用音效
  Future<void> setEnabled(bool enabled) async {
    if (!_isInitialized) return;
    
    _isEnabled = enabled;
    
    if (!enabled && _isPlaying) {
      await _audioPlayer.pause();
      _isPlaying = false;
      debugPrint('🔇 音效已禁用');
    } else if (enabled && _currentSpeed > 0) {
      updateSpeed(_currentSpeed, isDragging: false);
      debugPrint('🔊 音效已启用');
    }
  }
  
  /// 获取当前状态
  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  int get currentSpeed => _currentSpeed;
  
  /// 获取当前音量（用于调试）
  double getCurrentVolume() {
    if (!_isInitialized || !_isEnabled || _currentSpeed == 0) return 0.0;
    final normalizedSpeed = _currentSpeed / _maxSpeed;
    return _minVolume + (_maxVolume - _minVolume) * normalizedSpeed;
  }
  
  /// 获取当前音调（用于调试）
  double getCurrentPlaybackRate() {
    if (!_isInitialized || !_isEnabled) return _minPlaybackRate;
    final normalizedSpeed = _currentSpeed / _maxSpeed;
    return _minPlaybackRate + (_maxPlaybackRate - _minPlaybackRate) * normalizedSpeed;
  }
  
  /// 释放资源
  Future<void> dispose() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
      await _brakePlayer.stop();
      await _brakePlayer.dispose();
      await _startPlayer.stop();
      await _startPlayer.dispose();
      _isPlaying = false;
      _isBraking = false;
      _isInitialized = false;
      _currentEngineState = 'idle';
      debugPrint('🎵 音效控制器已释放');
    } catch (e) {
      debugPrint('❌ 释放音效资源失败: $e');
    }
  }
}

