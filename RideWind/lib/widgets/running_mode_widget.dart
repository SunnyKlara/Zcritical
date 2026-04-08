import 'dart:async';
import 'dart:math'; // 🚀 用于乱序加速
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart'; // ✅ 导入音频插件
import '../utils/responsive_utils.dart'; // ✅ 添加响应式工具类
import '../utils/throttle_accelerator.dart'; // 🚀 乱序加速器
import '../utils/speed_bounce_animation.dart'; // 🎯 弹跳动画
import '../models/speed_report.dart'; // 🏎️ 速度报告模型

/// 📱 响应式布局配置类
///
/// 统一管理 RunningModeWidget 的所有位置和尺寸参数
/// 🔑 注意：现在 RunningModeWidget 被放在下半部分容器中，
/// 所以位置计算应该相对于容器，而不是整个屏幕
class _RunningModeConfig {
  final BuildContext context;

  _RunningModeConfig(this.context);

  // ========== 屏幕信息 ==========
  double get _screenWidth => MediaQuery.of(context).size.width;
  double get _screenHeight => MediaQuery.of(context).size.height;
  double get _safeAreaBottom => MediaQuery.of(context).padding.bottom;

  bool get _isSmallScreen => _screenHeight < 700 || _screenWidth < 375;
  bool get _isLargeScreen => _screenHeight > 900 || _screenWidth > 428;

  /// 下半部分容器高度（从分界线到屏幕底部）
  double get containerHeight => _screenHeight * 0.55;

  // ========== 紧急停止按钮 ==========

  /// 紧急停止按钮底部位置（相对于容器底部，考虑安全区域）
  double get emergencyStopBottom {
    final base = _safeAreaBottom + 25.0;
    if (_isSmallScreen) return base;
    if (_isLargeScreen) return base + 15.0;
    return base + 10.0;
  }

  /// 紧急停止按钮左边距
  double get emergencyStopLeft =>
      ResponsiveUtils.width(context, _isSmallScreen ? 10 : 14);

  /// 紧急停止按钮右边距
  double get emergencyStopRight =>
      ResponsiveUtils.width(context, _isSmallScreen ? 25 : 30);

  /// 紧急停止按钮高度
  double get emergencyStopHeight {
    if (_isSmallScreen) return 42.0;
    if (_isLargeScreen) return 56.0;
    return 50.0;
  }

  /// 底部按钮区域总高度（紧急停止按钮 + 底部边距）
  /// 🔑 增加底部区域高度，确保按钮不被遮挡
  double get bottomButtonAreaHeight =>
      emergencyStopBottom + emergencyStopHeight + 20.0;

  // ========== 油门加速按钮 ==========

  /// 油门按钮底部位置（相对于容器底部，考虑安全区域）
  double get quickArrowBottom {
    final base = _safeAreaBottom + 20.0;
    if (_isSmallScreen) return base;
    if (_isLargeScreen) return base + 12.0;
    return base + 8.0;
  }

  /// 油门按钮右边距
  double get quickArrowRight =>
      ResponsiveUtils.width(context, _isSmallScreen ? 3 : 5);

  /// 油门按钮尺寸
  double get quickArrowSize {
    if (_isSmallScreen) return 50.0;
    if (_isLargeScreen) return 75.0;
    return 65.0;
  }

  // ========== 滚轮参数 ==========

  /// 速度刻度左边距
  double get scaleLeftMargin =>
      ResponsiveUtils.width(context, _isSmallScreen ? 14 : 19);

  /// 🔑 滚轮可用高度（容器高度 - 底部按钮区域）
  double get wheelAvailableHeight {
    final available = containerHeight - bottomButtonAreaHeight;
    // 🔧 保护措施：确保可用高度至少为 200
    return available > 200 ? available : 200.0;
  }

  /// 🔑 滚轮项目高度 - 动态计算确保始终显示5个数字
  double get wheelItemExtent {
    // 可用高度 / 5 = 每个数字的高度（包含间隙）
    final calculated = wheelAvailableHeight / 5.0;
    // 🔧 减小上限，让数字更紧凑，给底部按钮留空间
    // 🔧 确保最小值为 40，防止数字太小
    return calculated.clamp(40.0, 75.0);
  }

  /// 单位标签右边距
  double get unitLabelRight =>
      ResponsiveUtils.width(context, _isSmallScreen ? 5 : 8);

  /// 非选中数字字体大小 - 根据项目高度动态计算
  double get speedFontSize {
    final baseSize = wheelItemExtent * 0.5;
    return baseSize.clamp(32.0, 50.0);
  }

  /// 🔑 选中数字的字体大小（更大更突出）
  double get selectedSpeedFontSize {
    final baseSize = wheelItemExtent * 1.1;
    return baseSize.clamp(65.0, 100.0);
  }

  /// 刻度指示器宽度
  double get scaleIndicatorWidth =>
      ResponsiveUtils.width(context, _isSmallScreen ? 18 : 23);

  /// 速度数字容器宽度
  double get speedNumberWidth =>
      ResponsiveUtils.width(context, 43); // 43% of width
}

/// Running Mode 完整组件
///
/// 包含：
/// - 调速滚轮界面
/// - 紧急停止按钮
/// - 油门加速按钮
/// - 长按显示调速界面的区域
/// - 🏎️ 外部速度流支持（硬件旋钮同步）
/// - 🔥 外部油门流支持（硬件三击油门模式同步）
/// - 🔗 连接状态显示
class RunningModeWidget extends StatefulWidget {
  final int initialSpeed; // ✅ 增加字段定义
  final int maxSpeed; // ✅ 增加字段定义
  final bool initialShowSpeedControl; // 🆕 初始是否显示调速界面
  final Function(int speed) onSpeedChanged;
  final Function(bool isMetric)? onUnitChanged;
  final Function(bool isThrottling)? onThrottleStatusChanged; // ✅ 增加油门状态回调
  final VoidCallback onEmergencyStop;
  final Function(bool isShowing)?
  onSpeedControlVisibilityChanged; // 调速界面显示/隐藏回调
  final bool debugMode;

  // 🏎️ 外部速度流（来自硬件旋钮）
  final Stream<SpeedReport>? externalSpeedStream;

  // 🔥 外部油门流（来自硬件三击）
  final Stream<bool>? externalThrottleStream;

  // 📏 外部单位流（来自硬件单击切换）
  final Stream<bool>? externalUnitStream;

  // 🔗 连接状态流（用于显示断开指示器）
  final Stream<bool>? connectionStream;
  final bool isConnected;

  // 🐛 原始数据流（用于调试）
  final Stream<String>? rawDataStream;

  // 🎯 引导系统：GlobalKey 暴露回调
  final Function(Map<String, GlobalKey> keys)? onKeysReady;

  const RunningModeWidget({
    super.key,
    this.initialSpeed = 0, // ✅ 现在可以正确初始化了
    this.maxSpeed = 340,
    this.initialShowSpeedControl = false, // 🆕 默认不显示调速界面
    required this.onSpeedChanged,
    this.onUnitChanged,
    this.onThrottleStatusChanged, // ✅ 传入回调
    required this.onEmergencyStop,
    this.onSpeedControlVisibilityChanged,
    this.debugMode = false,
    this.externalSpeedStream, // 🏎️ 外部速度流
    this.externalThrottleStream, // 🔥 外部油门流
    this.externalUnitStream, // 📏 外部单位流
    this.connectionStream, // 🔗 连接状态流
    this.isConnected = true, // 🔗 初始连接状态
    this.rawDataStream, // 🐛 原始数据流
    this.onKeysReady, // 🎯 引导系统回调
  });

  @override
  State<RunningModeWidget> createState() => RunningModeWidgetState();
}

class RunningModeWidgetState extends State<RunningModeWidget>
    with TickerProviderStateMixin {
  // 🎯 引导系统 GlobalKey
  final GlobalKey _speedWheelKey = GlobalKey(debugLabel: 'speedWheel');
  final GlobalKey _unitLabelKey = GlobalKey(debugLabel: 'unitLabel');
  final GlobalKey _throttleButtonKey = GlobalKey(debugLabel: 'throttleButton');
  final GlobalKey _emergencyStopKey = GlobalKey(debugLabel: 'emergencyStop');

  // ========== 状态变量 ==========
  late bool _showSpeedControl; // 🔑 改为 late，在 initState 中初始化
  late int _currentSpeed;
  int? _speedBeforeAcceleration; // 开始加速前的速度（用于减速回到原位）
  FixedExtentScrollController? _speedScrollController;
  Timer? _accelerationTimer;
  bool _isAccelerating = false; // 是否正在加速（用于优化性能）

  // 🎯 弹跳动画控制器
  late AnimationController _bounceController;
  late Animation<double> _bounceScale;
  late Animation<double> _bounceOffset;

  // 🔊 音频播放器
  final AudioPlayer _enginePlayer = AudioPlayer();
  bool _isAudioInitialized = false;

  // 单位切换
  bool _isMetric = true; // true = km/h, false = mph

  // ✅ 优化动力方案：80ms 间隔 + 乱序步长，更有节奏感
  final int _accelerationInterval = 80;
  final ThrottleAccelerator _throttleAccelerator = ThrottleAccelerator(); // 🚀 乱序加速器
  int _accelerationCount = 0; // 加速次数计数器（用于震动节奏）

  // 🏎️ 外部速度流订阅
  StreamSubscription<SpeedReport>? _externalSpeedSubscription;
  bool _isReceivingExternalSpeed = false; // 防止循环更新

  // 🔥 外部油门流订阅
  StreamSubscription<bool>? _externalThrottleSubscription;

  // 📏 外部单位流订阅
  StreamSubscription<bool>? _externalUnitSubscription;

  // 🔗 连接状态
  StreamSubscription<bool>? _connectionSubscription;
  bool _isConnected = true; // UI刷新优化参数
  int _uiUpdateCounter = 0; // UI更新计数器
  static const int _audioUpdateInterval = 6; // ✅ 进一步降低频率 (约300ms更新一次)，确保音频驱动稳定
  static const int _uiUpdateInterval = 2; // 每2次加速才更新一次UI

  int _lastAudioSpeed = -1; // 记录上次更新音频时的速度，用于节流控制

  // 🐛 原始数据流订阅
  StreamSubscription<String>? _rawDataSubscription;

  // 🐛 调试日志
  final List<String> _debugLogs = [];
  static const int _maxDebugLogs = 15; // 最多显示15条日志

  void _addDebugLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19); // HH:mm:ss
    // 🔧 修复：确保在 mounted 状态下才调用 setState
    if (!mounted) {
      debugPrint('[$timestamp] $message (widget not mounted)');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _debugLogs.insert(0, '[$timestamp] $message');
          if (_debugLogs.length > _maxDebugLogs) {
            _debugLogs.removeLast();
          }
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _currentSpeed = widget.initialSpeed;
    _showSpeedControl = widget.initialShowSpeedControl; // 🔑 使用传入的初始值
    _isConnected = widget.isConnected;
    
    // 🎯 初始化弹跳动画控制器
    _bounceController = SpeedBounceAnimation.createBounceController(this);
    _bounceScale = SpeedBounceAnimation.createScaleAnimation(_bounceController);
    _bounceOffset = SpeedBounceAnimation.createOffsetAnimation(_bounceController);
    
    // 🔧 使用 WidgetsBinding.instance.addPostFrameCallback 延迟调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addDebugLog('🚀 Widget 初始化');
      _addDebugLog(
        'externalSpeedStream: ${widget.externalSpeedStream != null ? "有" : "无"}',
      );
      _addDebugLog('rawDataStream: ${widget.rawDataStream != null ? "有" : "无"}');
    });
    
    _initAudio();
    _subscribeToExternalSpeedStream();
    _subscribeToExternalThrottleStream(); // 🔥 订阅外部油门流
    _subscribeToExternalUnitStream(); // 📏 订阅外部单位流
    _subscribeToConnectionStream();
    _subscribeToRawDataStream(); // 🐛 订阅原始数据流

    // 🎯 引导系统：在首帧渲染后将 GlobalKey 传递给父组件
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onKeysReady?.call({
        'speedWheel': _speedWheelKey,
        'unitLabel': _unitLabelKey,
        'throttleButton': _throttleButtonKey,
        'emergencyStop': _emergencyStopKey,
      });
    });
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║              🎯 引导演示方法（供外部调用）                     ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 演示：滚动速度滚轮（从当前速度滚到目标速度再滚回来）
  Future<void> demoScrollSpeed() async {
    if (_speedScrollController == null || !_speedScrollController!.hasClients) {
      return;
    }
    final originalSpeed = _currentSpeed;
    final targetSpeed = (originalSpeed + 80).clamp(0, widget.maxSpeed);
    // 缓慢滚到目标速度
    _speedScrollController!.animateToItem(
      targetSpeed,
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
    );
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    // 停顿一下让用户看清
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    // 缓慢滚回原位
    _speedScrollController!.animateToItem(
      originalSpeed,
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOut,
    );
    await Future.delayed(const Duration(milliseconds: 1400));
  }

  /// 演示：切换单位（km/h ↔ mph，切换后再切回来）
  Future<void> demoToggleUnit() async {
    if (!mounted) return;
    setState(() => _isMetric = !_isMetric);
    widget.onUnitChanged?.call(_isMetric);
    // 停留久一点让用户看到变化
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _isMetric = !_isMetric);
    widget.onUnitChanged?.call(_isMetric);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// 演示：短暂加速（加速一小段再减速回来）
  Future<void> demoThrottle() async {
    _startAcceleration();
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    _startDeceleration();
    await Future.delayed(const Duration(milliseconds: 2000));
  }

  /// 演示：紧急停止（先加速到一个值，然后急停归零）
  Future<void> demoEmergencyStop() async {
    if (_speedScrollController == null || !_speedScrollController!.hasClients) {
      return;
    }
    // 先缓慢滚到一个速度
    _speedScrollController!.animateToItem(
      80,
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeIn,
    );
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    // 停顿一下
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    // 急停归零
    _speedScrollController!.animateToItem(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// 🐛 订阅原始数据流（用于调试）
  void _subscribeToRawDataStream() {
    if (widget.rawDataStream != null) {
      _rawDataSubscription = widget.rawDataStream!.listen((data) {
        final trimmed = data.trim();
        _addDebugLog('📡 原始: $trimmed');

        // 🐛 尝试手动解析，看看是否能匹配
        final regex = RegExp(r'SPEED_REPORT:(\d+)(?::(\d+))?');
        final match = regex.firstMatch(trimmed);
        if (match != null) {
          _addDebugLog('✅ 正则匹配成功!');
          _addDebugLog('   速度: ${match.group(1)}, 单位: ${match.group(2)}');
        } else if (trimmed.contains('SPEED')) {
          _addDebugLog('⚠️ 包含SPEED但正则不匹配');
        }
      });
      _addDebugLog('✅ 已订阅原始数据流');
    }
  }

  /// 🏎️ 订阅外部速度流（硬件旋钮同步）
  void _subscribeToExternalSpeedStream() {
    if (widget.externalSpeedStream != null) {
      _addDebugLog('📡 订阅外部速度流...');
      _externalSpeedSubscription = widget.externalSpeedStream!.listen(
        _handleExternalSpeedReport,
        onError: (error) {
          _addDebugLog('❌ 速度流错误: $error');
        },
        onDone: () {
          _addDebugLog('⚠️ 速度流已关闭');
        },
      );
      _addDebugLog('✅ 已订阅外部速度流');
      debugPrint('🏎️ 已订阅外部速度流');
    } else {
      _addDebugLog('⚠️ externalSpeedStream 为 null!');
    }
  }

  /// 🔥 订阅外部油门流（硬件三击进入油门模式）
  void _subscribeToExternalThrottleStream() {
    if (widget.externalThrottleStream != null) {
      _externalThrottleSubscription = widget.externalThrottleStream!.listen(
        _handleExternalThrottleReport,
        onError: (error) {
          _addDebugLog('❌ 油门流错误: $error');
        },
      );
      _addDebugLog('✅ 已订阅外部油门流');
      debugPrint('🔥 已订阅外部油门流');
    }
  }

  /// 🔥 处理外部油门报告(来自硬件三击)
  void _handleExternalThrottleReport(bool isThrottle) {
    _addDebugLog('🔥 收到油门报告: ${isThrottle ? "开启" : "关闭"}');

    if (isThrottle) {
      // 硬件端进入油门模式 → APP 自动显示调速界面
      if (!_showSpeedControl && mounted) {
        setState(() {
          _showSpeedControl = true;
        });
        widget.onSpeedControlVisibilityChanged?.call(true);
        _addDebugLog('📱 自动显示调速界面');
      }
      // 播放引擎音效
      _playEngineSound();
    } else {
      // 硬件端退出油门模式 → 停止音效
      _stopEngineSound();
      _addDebugLog('📱 硬件退出油门模式');
    }
  }

  /// 📏 订阅外部单位流（硬件单击切换单位）
  void _subscribeToExternalUnitStream() {
    if (widget.externalUnitStream != null) {
      _externalUnitSubscription = widget.externalUnitStream!.listen(
        (isMetric) {
          _addDebugLog('📏 收到单位报告: ${isMetric ? "km/h" : "mph"}');
          if (mounted) {
            setState(() {
              _isMetric = isMetric;
            });
          }
          debugPrint('📏 单位已同步: ${isMetric ? "km/h" : "mph"}');
        },
        onError: (error) {
          _addDebugLog('❌ 单位流错误: $error');
        },
      );
      _addDebugLog('✅ 已订阅外部单位流');
      debugPrint('📏 已订阅外部单位流');
    }
  }

  /// 🔗 订阅连接状态流
  void _subscribeToConnectionStream() {
    if (widget.connectionStream != null) {
      _connectionSubscription = widget.connectionStream!.listen((connected) {
        if (mounted) {
          setState(() {
            _isConnected = connected;
          });
        }
        if (connected) {
          debugPrint('🔗 连接已恢复');
        } else {
          debugPrint('🔗 连接已断开');
        }
      });
      debugPrint('🔗 已订阅连接状态流');
    }
  }

  /// 🏎️ 处理外部速度报告（来自硬件旋钮）
  void _handleExternalSpeedReport(SpeedReport report) {
    _addDebugLog('📥 收到速度报告: ${report.speed} ${report.unitString}');

    // 如果正在加速中，忽略外部速度报告
    if (_isAccelerating) {
      _addDebugLog('⏸️ 忽略 (正在加速中)');
      debugPrint('🏎️ 忽略外部速度报告 (正在加速中)');
      return;
    }

    // 🔧 修复：确保 mounted 状态
    if (!mounted) return;

    // 设置标志，防止循环更新
    _isReceivingExternalSpeed = true;

    final targetSpeed = report.speed.clamp(0, widget.maxSpeed);

    // 更新速度状态
    setState(() {
      _currentSpeed = targetSpeed;

      // 同步单位（如果报告中包含单位信息）
      if (report.unit == 0) {
        _isMetric = true;
      } else if (report.unit == 1) {
        _isMetric = false;
      }
    });

    // 同步滚轮位置（使用 jumpToItem 而不是 animateToItem，避免动画期间多次触发回调）
    if (_speedScrollController != null && _speedScrollController!.hasClients) {
      // ✅ 使用 jumpToItem 直接跳转，不触发中间的 onSelectedItemChanged
      _speedScrollController!.jumpToItem(targetSpeed);
    }

    _addDebugLog('✅ 速度已同步: $_currentSpeed');
    debugPrint('🏎️ 外部速度同步: ${report.speed} ${report.unitString}');

    // ✅ 延长标志保持时间到 300ms，确保不会误触发回传
    Future.delayed(const Duration(milliseconds: 300), () {
      _isReceivingExternalSpeed = false;
    });

    // 注意：不触发 onSpeedChanged 回调，避免循环
  }

  Future<void> _initAudio() async {
    try {
      await _enginePlayer.setReleaseMode(ReleaseMode.loop);
      // ✅ 强制低延迟模式 (适用于音效)
      await _enginePlayer.setPlayerMode(PlayerMode.lowLatency);
      // 预加载音频
      await _enginePlayer.setSource(AssetSource('sound/engine.mp3'));
      // ✅ 关键：设置音量后先启动再停止，确保音频轨道预热，彻底解决首次不响的问题
      await _enginePlayer.setVolume(0.0);
      await _enginePlayer.resume();
      await Future.delayed(const Duration(milliseconds: 100));
      await _enginePlayer.stop(); // ← 修复：使用stop()而不是pause()

      // 设置正常工作音量
      await _enginePlayer.setVolume(0.6);
      await _enginePlayer.setPlaybackRate(1.0);
      _isAudioInitialized = true;
      debugPrint('🔊 引擎音效预热及初始化成功（已停止）');
    } catch (e) {
      debugPrint('❌ 引擎音效初始化失败: $e');
    }
  }

  @override
  void dispose() {
    _speedScrollController?.dispose();
    _accelerationTimer?.cancel();
    _bounceController.dispose(); // 🎯 释放弹跳动画控制器
    _externalSpeedSubscription?.cancel(); // 🏎️ 取消外部速度流订阅
    _externalThrottleSubscription?.cancel(); // 🔥 取消外部油门流订阅
    _externalUnitSubscription?.cancel(); // 📏 取消外部单位流订阅
    _connectionSubscription?.cancel(); // 🔗 取消连接状态流订阅
    _rawDataSubscription?.cancel(); // 🐛 取消原始数据流订阅
    _enginePlayer.dispose(); // ✅ 释放音频资源
    super.dispose();
  }

  // 🔊 播放引擎声
  void _playEngineSound() {
    if (_isAudioInitialized) {
      _enginePlayer.resume();
      _updateEngineSoundProperties();
    }
  }

  // 🔊 停止引擎声
  void _stopEngineSound() {
    if (_isAudioInitialized) {
      _enginePlayer.pause();
    }
  }

  // 🔊 根据速度更新音量和音调（模拟转速）
  void _updateEngineSoundProperties() {
    if (!_isAudioInitialized) return;

    // ✅ 增加速度变化阈值：速度变化不到 15km/h 不更新音频，极致减少指令发送次数，防止产生呲呲声
    if (_lastAudioSpeed != -1 &&
        (_currentSpeed - _lastAudioSpeed).abs() < 15 &&
        _currentSpeed != widget.maxSpeed &&
        _currentSpeed != 0) {
      return;
    }
    _lastAudioSpeed = _currentSpeed;

    // 映射音量：0-340 km/h -> 0.6-1.0
    double volume = 0.6 + (_currentSpeed / widget.maxSpeed) * 0.4;
    _enginePlayer.setVolume(volume.clamp(0.0, 1.0));

    // 映射播放速率：0-340 km/h -> 1.0-1.8
    // ✅ 调低上限：某些安卓设备在 playbackRate > 2.0 时会产生采样失真（呲呲声）
    double playbackRate = 1.0 + (_currentSpeed / widget.maxSpeed) * 0.8;
    _enginePlayer.setPlaybackRate(playbackRate.clamp(0.5, 1.8));
  }

  @override
  Widget build(BuildContext context) {
    // 🔧 添加try-catch防止渲染错误导致黑屏
    try {
      // ✅ 创建响应式配置实例
      final config = _RunningModeConfig(context);
      debugPrint('🏃 RunningModeWidget build... showSpeedControl=$_showSpeedControl, speed=$_currentSpeed');
      debugPrint('🏃 containerHeight=${config.containerHeight}, wheelItemExtent=${config.wheelItemExtent}');

      return Container(
        // 🔧 修复黑屏问题：始终使用透明背景，让父组件的背景图片显示
        // 调试模式下使用绿色背景便于确认组件渲染
        color: widget.debugMode ? Colors.green.withAlpha(179) : Colors.transparent,
        child: Stack(
        children: [
          // 🔴 临时添加一个明显的测试文本，确认组件被渲染
          if (widget.debugMode)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.yellow,
                  child: const Text(
                    '🔴 RunningModeWidget 已渲染！',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          
          // 🔗 断开连接指示器（显示在最上层）
          if (!_isConnected)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(204),
                    borderRadius: BorderRadius.circular(20),
                  ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '连接已断开',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 🔑 移除了下半部分的退出覆盖层
        // 退出调速界面只能通过：返回按钮、手机返回键、或点击屏幕上半部分（在父组件中处理）

        // ========== 调速界面/单击区域 ==========
        // ⚠️ 必须在覆盖层之后，这样才能接收滚动事件
        Positioned.fill(
          // 🔑 改为填满整个容器
          child: _showSpeedControl
              ? _buildSpeedControlInline(config) // 显示调速界面
              : GestureDetector(
                  behavior: HitTestBehavior.opaque, // 🔑 关键：让透明区域也响应点击
                  onTap: () {
                    debugPrint('👆 单击 Running Mode 区域 → 显示调速界面');
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _showSpeedControl = true;
                    });
                    // 通知父组件
                    widget.onSpeedControlVisibilityChanged?.call(true);
                  },
                  child: Container(
                    color: widget.debugMode
                        ? Colors.orange.withAlpha(77)
                        : Colors.transparent,
                    child: widget.debugMode
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  '单击这里\n显示调速界面',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),
        ),

        // ========== 紧急停止按钮 ==========
        // ✅ 核心修复：只有调速界面显示时，紧急停止按钮才响应点击事件
        if (_showSpeedControl)
          Positioned(
            bottom: config.emergencyStopBottom,
            left: config.emergencyStopLeft,
            right: config.emergencyStopRight,
            child: GestureDetector(
              key: _emergencyStopKey,
              behavior: HitTestBehavior.opaque, // ✅ 阻止事件穿透到覆盖层
              onTap: () {
                debugPrint('🚨 紧急停止！速度急速滚动至零（保持调速界面开启）');
                HapticFeedback.heavyImpact();

                // 使用快速动画滚动到0（模拟紧急刹车）
                if (_speedScrollController != null &&
                    _speedScrollController!.hasClients) {
                  final currentSpeed = _currentSpeed;
                  _speedScrollController!.animateToItem(
                    0,
                    duration: Duration(
                      milliseconds: (currentSpeed * 2).clamp(200, 800),
                    ), // 更快的刹车速度
                    curve: Curves.easeOut, // 刹车曲线
                  );
                }

                setState(() {
                  _currentSpeed = 0;
                  // 不关闭调速界面，保持 _showSpeedControl 不变
                });
                _stopEngineSound(); // ✅ 紧急停止音效
                widget.onEmergencyStop();
              },
              child: Container(
                height: config.emergencyStopHeight,
                decoration: BoxDecoration(
                  color: widget.debugMode
                      ? Colors.red.withAlpha(50)
                      : Colors.transparent,
                  border: widget.debugMode
                      ? Border.all(color: Colors.red, width: 3)
                      : null,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: widget.debugMode
                    ? const Center(
                        child: Text(
                          '紧急停止\n(透明点击)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),

        // ========== 油门加速按钮 ==========
        // ✅ 核心修复：只有调速界面显示时，油门按钮才响应长按事件
        // 解决误触油门导致退出 Running Mode 的问题
        if (_showSpeedControl)
          Positioned(
            bottom: config.quickArrowBottom,
            right: config.quickArrowRight,
            child: GestureDetector(
              key: _throttleButtonKey,
              behavior: HitTestBehavior.opaque,
              // ✅ 添加 onTap 处理，阻止事件穿透到下层覆盖层
              onTap: () {
                debugPrint('🚀 油门按钮 - 轻触（需要长按才能加速）');
                // 不做任何操作，只是阻止事件穿透
              },
              onLongPressStart: (_) {
                debugPrint('🚀🚀🚀 油门按钮 - 长按开始');
                _startAcceleration();
              },
              onLongPressEnd: (_) {
                debugPrint('🔽🔽🔽 油门按钮 - 松开，开始减速');
                _startDeceleration();
              },
              onLongPressCancel: () {
                debugPrint('❌ 油门按钮 - 取消');
                _startDeceleration();
              },
              child: Container(
                width: config.quickArrowSize,
                height: config.quickArrowSize,
                decoration: BoxDecoration(
                  color: widget.debugMode
                      ? Colors.green.withAlpha(50)
                      : Colors.transparent,
                  border: widget.debugMode
                      ? Border.all(color: Colors.green, width: 3)
                      : null,
                  shape: BoxShape.circle,
                ),
                child: widget.debugMode
                    ? const Center(
                        child: Text(
                          '油门\n加速',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),

        // ========== 🐛 调试日志面板（左下角）- 仅调试模式显示 ==========
        if (widget.debugMode)
          Positioned(
            left: 10,
            bottom: 120,
            child: Container(
              width: 280,
              height: 200,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(217),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withAlpha(128),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🐛 调试日志',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _debugLogs.clear();
                            _debugLogs.add('日志已清空');
                          });
                        },
                        child: const Text(
                          '清空',
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _debugLogs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          _debugLogs[index],
                          style: TextStyle(
                            color: _debugLogs[index].contains('❌')
                                ? Colors.red
                                : _debugLogs[index].contains('✅')
                                ? Colors.green
                                : _debugLogs[index].contains('📥')
                                ? Colors.cyan
                                : Colors.white70,
                            fontSize: 9,
                            height: 1.3,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
    );  // 🔧 Container 结束括号
    } catch (e, stackTrace) {
      debugPrint('❌ RunningModeWidget 渲染错误: $e');
      debugPrint('📍 堆栈跟踪: $stackTrace');
      return Container(
        color: Colors.orange.withAlpha(77),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'RunningModeWidget 加载失败',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$e',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║                  调速界面（滚轮选择器）                        ║
  // ╚══════════════════════════════════════════════════════════════╝

  Widget _buildSpeedControlInline(_RunningModeConfig config) {
    // 🔑 计算滚轮高度，严格显示5个数字
    final wheelHeight = config.wheelItemExtent * 5;
    
    // 🔧 调试信息：打印布局参数
    debugPrint('🎡 _buildSpeedControlInline: wheelHeight=$wheelHeight, bottomButtonAreaHeight=${config.bottomButtonAreaHeight}');
    debugPrint('🎡 wheelItemExtent=${config.wheelItemExtent}, wheelAvailableHeight=${config.wheelAvailableHeight}');

    return Stack(
      clipBehavior: Clip.none, // 允许子组件超出
      children: [
        // 🔧 调试：添加一个可见的背景来确认Stack被渲染
        if (widget.debugMode)
          Positioned.fill(
            child: Container(
              color: Colors.purple.withAlpha(77),
              child: const Center(
                child: Text(
                  '🎡 Speed Control Stack',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        
        // ========== 主滚轮区域 ==========
        Positioned(
          key: _speedWheelKey,
          top: 0,
          left: 0,
          right: 0,
          bottom: config.bottomButtonAreaHeight,
          child: Center(
            child: SizedBox(
              height: wheelHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge, // 🔧 关键：裁剪滚轮内部内容，防止遮罩超出
                children: [
                  // 滚轮本体
                  ListWheelScrollView.useDelegate(
                    controller: _speedScrollController ??=
                        FixedExtentScrollController(initialItem: _currentSpeed),
                    itemExtent: config.wheelItemExtent,
                    diameterRatio: 1.8,
                    perspective: 0.002,
                    clipBehavior: Clip.hardEdge,
                    physics: const BouncingScrollPhysics(
                      parent: FixedExtentScrollPhysics(),
                    ),
                    onSelectedItemChanged: (index) {
                      if (index == _currentSpeed) return;
                      if (_isReceivingExternalSpeed) return;

                      if (!_isAccelerating) {
                        setState(() {
                          _currentSpeed = index;
                        });
                        widget.onSpeedChanged(index);

                        HapticFeedback.selectionClick();
                      } else {
                        _currentSpeed = index;
                      }
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (context, index) {
                        if (index < 0 || index > widget.maxSpeed) return null;
                        return _buildSpeedItemWithIndicator(index, config);
                      },
                      childCount: widget.maxSpeed + 1,
                    ),
                  ),
                  // 🔧 顶部渐变遮罩 - 柔和过渡，不遮挡数字
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: config.wheelItemExtent * 0.6,
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF0D0D0D), Color(0x000D0D0D)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 🔧 底部渐变遮罩 - 柔和过渡，不遮挡数字
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: config.wheelItemExtent * 0.6,
                    child: IgnorePointer(
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xFF0D0D0D), Color(0x000D0D0D)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 单个速度项（优化版：红点+横线融合组件 + 数字居中放大）
  Widget _buildSpeedItemWithIndicator(int speed, _RunningModeConfig config) {
    // ✅ 关键改进：使用逻辑速度 _currentSpeed 判断，而不是依赖滚轮当前的 selectedItem
    // 这样在极速动画过程中，中间的数字依然能保持高亮和单位显示
    final bool isCurrent = speed == _currentSpeed;

    // 计算与当前速度的距离，用于淡出效果
    final int distance = (speed - _currentSpeed).abs();
    final double opacity = distance == 0
        ? 1.0
        : distance == 1
        ? 0.7
        : distance == 2
        ? 0.4
        : 0.2;

    // 生成横线刻度（当前速度显示红点+7根横线，其他速度只显示横线）
    Widget buildScaleIndicator() {
      List<Widget> scaleItems = [];

      if (isCurrent) {
        // ========== 当前速度：只显示红点 ==========
        scaleItems.add(
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: Color(0xFFFF0000), // 纯红色
              shape: BoxShape.circle,
            ),
          ),
        );
      } else {
        // ========== 其他速度：只显示横线（长短循环）==========
        // 基于速度值的偏移量，让横线随着滑动循环变化
        int offset = (speed - _currentSpeed) % 7;
        if (offset < 0) offset += 7;

        // 横线模式（7种长度循环）
        List<double> lineLengths = [
          22.0, // 长
          12.0, // 短
          12.0, // 短
          22.0, // 长
          12.0, // 短
          22.0, // 长
          12.0, // 短
        ];

        // 显示对应偏移量的横线
        double lineLength = lineLengths[offset];
        double lineOpacity = distance > 2 ? 0.3 : 0.5;

        scaleItems.add(
          Container(
            width: lineLength,
            height: 2.5,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((lineOpacity * 255).round()),
              borderRadius: BorderRadius.circular(1.25),
            ),
          ),
        );
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: scaleItems,
      );
    }

    return Stack(
      children: [
        Row(
          children: [
            // ========== 左侧刻度指示器（红点+横线融合）==========
            SizedBox(
              width:
                  config.scaleIndicatorWidth +
                  config.scaleLeftMargin, // 增加宽度包含左边距
              child: Padding(
                padding: EdgeInsets.only(
                  left: config.scaleLeftMargin,
                ), // 恢复刻度线的视觉位置
                child: buildScaleIndicator(),
              ),
            ),

            // ========== 数字容器（居中显示）==========
            Expanded(
              child: Container(
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: isCurrent
                      ? () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _isMetric = !_isMetric;
                          });
                          widget.onUnitChanged?.call(_isMetric);
                          debugPrint('🔄 单位切换: ${_isMetric ? "km/h" : "mph"}');
                        }
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // 数字部分 - 🎯 当前速度（暂时移除弹跳动画以排查黑屏问题）
                      Text(
                        _convertSpeedForDisplay(speed).toString(),
                        style: TextStyle(
                          color: isCurrent ? Colors.white : const Color(0xFFC94A4A).withAlpha((opacity * 0.7 * 255).round()),
                          fontSize: isCurrent ? config.selectedSpeedFontSize : config.speedFontSize,
                          fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w800,
                          letterSpacing: isCurrent ? 4 : 2,
                          height: 1.0,
                          shadows: isCurrent ? [
                            // 🔑 纯黑色阴影，无白色高光，干净的金属感
                            Shadow(
                              color: Colors.black,
                              offset: const Offset(0, 4),
                              blurRadius: 8,
                            ),
                            Shadow(
                              color: Colors.black.withAlpha(204),
                              offset: const Offset(2, 6),
                              blurRadius: 12,
                            ),
                          ] : null,
                        ),
                      ),

                      // 单位部分（仅选中显示，紧跟在数字后）
                      // 🎯 key 绑定在单位文本容器上，确保引导高亮精确对齐 km/h 位置
                      if (isCurrent)
                        Container(
                          key: _unitLabelKey,
                          padding: const EdgeInsets.only(left: 10.0, top: 4.0, bottom: 4.0, right: 4.0),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: _isMetric ? 'km' : 'mp',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: '/',
                                  style: TextStyle(
                                    color: const Color(0xFFC94A4A),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: 'h',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 将内部速度值（km/h）转换为显示值（根据当前单位）
  int _convertSpeedForDisplay(int speedKmh) {
    if (_isMetric) {
      return speedKmh; // 公制：直接返回 km/h
    } else {
      return (speedKmh * 0.621371).round(); // 英制：转换为 mph
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║                  油门加速功能（长按持续加速）                  ║
  // ╚══════════════════════════════════════════════════════════════╝

  // 开始加速（长按油门按钮）- 赛车引擎体验
  void _startAcceleration() {
    _accelerationTimer?.cancel();
    _accelerationCount = 0; // 重置计数器

    // 强烈震动（引擎启动）
    HapticFeedback.heavyImpact();

    // ✅ 修复：只有在非加速状态下才记录起始速度
    // 避免连续加速时覆盖原始起始速度
    if (!_isAccelerating && _speedBeforeAcceleration == null) {
      _speedBeforeAcceleration = _currentSpeed;
      debugPrint('🏎️ 引擎启动！起始速度: $_speedBeforeAcceleration km/h');
    } else {
      debugPrint('🏎️ 继续加速！保持起始速度: $_speedBeforeAcceleration km/h');
    }

    setState(() {
      _isAccelerating = true; // 标记为加速状态
    });

    // ✅ 通知外部：油门模式启动，触发硬件远程模式同步
    widget.onThrottleStatusChanged?.call(true);

    _playEngineSound(); // ✅ 开始播放音效
    _accelerate();
    _accelerationTimer = Timer.periodic(
      Duration(milliseconds: _accelerationInterval),
      (timer) {
        _accelerate();
      },
    );
  }

  // 开始减速（松开油门按钮）- 引擎制动
  void _startDeceleration() {
    _accelerationTimer?.cancel();
    _accelerationCount = 0; // 重置计数器

    // 松开油门震动反馈
    HapticFeedback.mediumImpact();
    _stopEngineSound(); // ✅ 松手立即停止引擎音效

    // 如果有记录的起始速度，则减速回到起始位置
    final targetSpeed = _speedBeforeAcceleration ?? 0;
    debugPrint('🔽 引擎制动！当前速度: $_currentSpeed km/h，目标速度: $targetSpeed km/h');

    if (_currentSpeed <= targetSpeed) {
      // 如果当前速度已经低于或等于目标速度，直接停止
      _stopAcceleration();
      return;
    }

    setState(() {
      _isAccelerating = true; // 减速也标记为加速状态（避免卡顿）
    });

    _decelerate();
    _accelerationTimer = Timer.periodic(
      Duration(milliseconds: _accelerationInterval),
      (timer) {
        _decelerate();
      },
    );
  }

  // 停止加速/减速（完全停止定时器）
  void _stopAcceleration() {
    if (_accelerationTimer != null) {
      _accelerationTimer!.cancel();
      _accelerationTimer = null;
      HapticFeedback.lightImpact();
      _stopEngineSound(); // ✅ 停止播放音效
      debugPrint('🛑 停止操作。当前速度: $_currentSpeed km/h');

      if (mounted) {
        setState(() {
          _isAccelerating = false; // 恢复正常状态
        });
      }

      // ✅ 修复：减速完成后清空起始速度记录，下次加速重新记录
      _speedBeforeAcceleration = null;

      // ✅ 通知外部：油门模式关闭
      widget.onThrottleStatusChanged?.call(false);

      // 同步滚轮位置到当前速度
      if (_speedScrollController != null &&
          _speedScrollController!.hasClients) {
        _speedScrollController!.animateToItem(
          _currentSpeed,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // 执行加速（增加速度）- 🚀 使用乱序递增，更有节奏感
  void _accelerate() {
    if (!mounted) return; // 🔧 修复：确保 mounted 状态
    
    if (_currentSpeed < widget.maxSpeed) {
      _accelerationCount++;

      // 🚀 使用乱序加速器获取步长（1-3随机）
      final step = _throttleAccelerator.getNextStep();
      final newSpeed = (_currentSpeed + step)
          .clamp(0, widget.maxSpeed)
          .toInt();

      // ✅ 核心修复：先更新状态再触发动画，确保白色高亮正确显示
      setState(() {
        _currentSpeed = newSpeed;
      });

      // 🎯 触发弹跳动画 - 数字跳出屏幕效果
      SpeedBounceAnimation.triggerBounce(_bounceController);

      // ✅ 关键改进：使用 animateToItem 替代 jumpToItem
      // 动画时间设为 40ms，配合 80ms 的循环，产生"跳跃式"滚动视觉
      if (_speedScrollController != null &&
          _speedScrollController!.hasClients) {
        _speedScrollController!.animateToItem(
          _currentSpeed,
          duration: const Duration(milliseconds: 40),
          curve: Curves.easeOutCubic,
        );
      }

      // 🚀 根据步长调整震动强度，增强节奏感
      if (step >= 3) {
        HapticFeedback.heavyImpact();
      } else if (step >= 2) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }

      // ✅ 增加音频指令节流：彻底消除呲呲声
      if (_accelerationCount % _audioUpdateInterval == 0) {
        _updateEngineSoundProperties();
      }

      // 🎯 优化：蓝牙命令发送频率控制
      _uiUpdateCounter++;
      if (_uiUpdateCounter % _uiUpdateInterval == 0) {
        widget.onSpeedChanged(_currentSpeed);
      }
    } else {
      // 达到最大速度：保持选中状态并维持音效
      // ✅ 修复：强制锁定 _currentSpeed 为最大值，防止被滚轮回调覆盖
      setState(() {
        _currentSpeed = widget.maxSpeed;
      });

      // ✅ 修复：使用 jumpToItem 立即跳转，避免动画延迟导致的不同步
      if (_speedScrollController != null &&
          _speedScrollController!.hasClients) {
        _speedScrollController!.jumpToItem(widget.maxSpeed);
      }

      // ✅ 极速状态下也要节流更新音频，防止产生呲呲声
      if (_accelerationCount % _audioUpdateInterval == 0) {
        _updateEngineSoundProperties();
      }
      if (_accelerationCount % 5 == 0) {
        HapticFeedback.heavyImpact();
      }
    }
  }

  // 执行减速（降低速度）- 减速回到起始位置
  void _decelerate() {
    if (!mounted) return; // 🔧 修复：确保 mounted 状态
    
    final targetSpeed = _speedBeforeAcceleration ?? 0;

    if (_currentSpeed > targetSpeed) {
      _accelerationCount++;

      // 减速步长增加，让动力回收也更快
      final decelerateStep = 6;
      final newSpeed = (_currentSpeed - decelerateStep)
          .clamp(targetSpeed, widget.maxSpeed)
          .toInt();

      // ✅ 核心修复：先更新状态再触发动画，确保白色高亮正确显示
      setState(() {
        _currentSpeed = newSpeed;
      });

      // 使用超快动画
      if (_speedScrollController != null &&
          _speedScrollController!.hasClients) {
        _speedScrollController!.animateToItem(
          _currentSpeed,
          duration: const Duration(milliseconds: 40),
          curve: Curves.easeOutCubic,
        );
      }

      // 🎯 优化：减速时也控制蓝牙命令发送频率
      _uiUpdateCounter++;
      if (_uiUpdateCounter % _uiUpdateInterval == 0) {
        widget.onSpeedChanged(_currentSpeed);
      }

      // 减速时的轻微震动反馈（每3次）
      if (_accelerationCount % 3 == 0) {
        HapticFeedback.lightImpact();
      }

      // 🎯 优化：减速时也更新滚轮UI
      if (_uiUpdateCounter % _uiUpdateInterval == 0) {
        if (_speedScrollController != null &&
            _speedScrollController!.hasClients) {
          _speedScrollController!.animateToItem(
            _currentSpeed,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          );
        }
      }

      debugPrint('🔽 减速中: $_currentSpeed km/h → 目标: $targetSpeed km/h');
    } else {
      _stopAcceleration();
      HapticFeedback.mediumImpact();
      debugPrint('✅ 已回到起始速度: $targetSpeed km/h');
    }
  }
}
