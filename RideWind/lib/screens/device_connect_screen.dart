import 'dart:async'; // 用于 StreamSubscription
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于震动反馈
import 'package:provider/provider.dart'; // Provider 状态管理
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../utils/debug_logger.dart';
import '../controllers/airflow_indicator_controller.dart';
import '../widgets/running_mode_widget.dart';
import '../widgets/enhanced_guide_overlay.dart';
import '../widgets/guide_tooltip_styles.dart';
import '../widgets/device_connect_helpers.dart';
import '../models/guide_models.dart';
import '../services/feature_guide_service.dart';
import '../services/preference_service.dart';
import '../configs/device_connect_config.dart';
import '../data/led_presets.dart';
import '../controllers/colorize_controller.dart';
import '../core/service_locator.dart';
import '../widgets/colorize_preset_view.dart';
import '../widgets/colorize_rgb_detail_view.dart';
import 'no_device_screen.dart';
import 'logo_management_screen.dart';
import 'audio_management_screen.dart';
import 'ota_upgrade_screen.dart';
import 'audio_stream_screen.dart';

/// 核心控制页面 — 正在渐进式拆分中
///
/// 包含 2 个模式（PageView 左右滑动切换）：
///   index=0: Running Mode（速度/油门控制，默认）
///   index=1: Colorize Mode（LED预设/RGB调色/流水灯）
///
/// 已提取到独立文件：
///   - _DeviceConnectConfig → configs/device_connect_config.dart（typedef桥接）
///   - _ledColorCapsules → data/led_presets.dart（getter桥接）
///   - Painter/Dialog → widgets/device_connect_helpers.dart（底部旧副本待替换）
///
/// 下一步提取目标：Colorize 模式（~1100行，状态变量清单见 CONTINUATION_GUIDE.md）
///
/// 参考：CONTINUATION_GUIDE.md 第三节

// ╔══════════════════════════════════════════════════════════════╗
// ║          🔄 控制模式枚举（3个模式）                            ║
// ╚══════════════════════════════════════════════════════════════╝
enum ControlMode {
  running, // Running Mode - 速度/油门控制（默认）
  colorize, // Colorize Mode - LED颜色控制（右滑进入）
}

// 🎨 ColorizeState 枚举已移至 controllers/colorize_controller.dart

// 使用提取的 DeviceConnectConfig（从 configs/device_connect_config.dart 导入）
// 保留内部别名以最小化改动
typedef _DeviceConnectConfig = DeviceConnectConfig;

class DeviceConnectScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceConnectScreen({super.key, required this.device});

  @override
  State<DeviceConnectScreen> createState() => _DeviceConnectScreenState();
}

class _DeviceConnectScreenState extends State<DeviceConnectScreen> {
  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🔄 简化后的状态变量                                  ║
  // ╚══════════════════════════════════════════════════════════════╝

  // ========== 🏠 页面状态（简化：直接进入模式界面）==========
  int _currentModeIndex = 0; // 0=running(默认), 1=colorize
  late PageController _modePageController; // 模式页面滑动控制器

  // ========== 🌬️ 雾化器状态 ==========
  bool _isAirflowStarted = false;
  final AirflowIndicatorController _airflowController = AirflowIndicatorController();

  // ========== 🏃 Running Mode 专用状态 ==========
  int _currentSpeed = 0;
  final int _maxSpeed = 340;
  DateTime _lastCommandTime = DateTime.now();

  // ========== 🎨 Colorize Mode 专用状态 ==========
  int _lastSentHardwareUI = -1;
  
  late PageController _colorPageController;
  Key _colorPageViewKey = UniqueKey();

  // ========== 📚 功能引导状态 ==========
  final FeatureGuideService _featureGuideService = FeatureGuideService();
  OverlayEntry? _guideOverlayEntry;
  bool _hasCheckedRunningModeGuide = false;
  bool _hasCheckedColorizeModeGuide = false;

  // 🎯 引导目标 GlobalKey（绑定到实际 UI 元素）
  final GlobalKey _carImageKey = GlobalKey(debugLabel: 'carImage');
  final GlobalKey _lowerHalfKey = GlobalKey(debugLabel: 'lowerHalf');
  final GlobalKey _colorCapsuleStripKey = GlobalKey(debugLabel: 'colorCapsuleStrip');
  final GlobalKey _startColoringButtonKey = GlobalKey(debugLabel: 'startColoringButton');
  final GlobalKey _paletteButtonKey = GlobalKey(debugLabel: 'paletteButton');
  final GlobalKey _lmrbCapsulesKey = GlobalKey(debugLabel: 'lmrbCapsules');
  final GlobalKey _rgbSlidersKey = GlobalKey(debugLabel: 'rgbSliders');
  final GlobalKey _brightnessBarKey = GlobalKey(debugLabel: 'brightnessBar');

  // 🎯 存储 RunningModeWidget 通过 onKeysReady 回调传递的 key
  Map<String, GlobalKey> _runningModeKeys = {};

  // 🎯 RunningModeWidget 的 GlobalKey，用于引导演示调用
  final GlobalKey<RunningModeWidgetState> _runningModeStateKey =
      GlobalKey<RunningModeWidgetState>(debugLabel: 'runningModeState');

  // ========== 💾 用户偏好服务 ==========
  final PreferenceService _preferenceService = PreferenceService();

  // ========== 🎨 Colorize 控制器（通过 get_it 注入）==========
  late final ColorizeController _colorize;

  // ========== 🔗 蓝牙连接监听 ==========
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<int>? _presetReportSub;
  StreamSubscription<bool>? _streamlightReportSub; // 🔄 流水灯状态订阅
  bool _navigatedOnDisconnect = false;

  // ========== 🐛 调试模式 ==========
  static const bool _debugMode = false; // 🔧 调试模式已关闭

  // 🎨 LED 预设配置 — 使用 data/led_presets.dart 中的 ledPresetMaps
  List<Map<String, dynamic>> get _ledColorCapsules => ledPresetMaps;

  // 获取当前模式
  ControlMode get _currentMode {
    switch (_currentModeIndex) {
      case 0:
        return ControlMode.running;
      case 1:
        return ControlMode.colorize;
      default:
        return ControlMode.running;
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🚀🚀🚀 DeviceConnectScreen initState 开始');
    
    // 🎨 初始化 Colorize 控制器
    _colorize = sl<ColorizeController>();
    // 重置状态（防止上一个设备的状态残留）
    _colorize.resetToDefaults();

    // 初始化模式页面控制器
    _modePageController = PageController(initialPage: _currentModeIndex);
    debugPrint('🚀 [1/5] PageController 初始化完成');

    // 初始化颜色条PageView控制器（先用临时值，恢复偏好后会重建）
    _colorPageController = PageController(
      initialPage: 0,
      viewportFraction: 0.155,
    );
    debugPrint('🚀 [2/5] ColorPageController 初始化完成');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🚀 [3/5] PostFrameCallback 开始执行');
        // 🔑 连接后同步硬件UI到Running Mode
        debugPrint('🚀 [3a] 准备调用 _syncHardwareUIOnInit');
        _syncHardwareUIOnInit();
        // 📚 检查并显示 Running Mode 引导（首次进入时）
        debugPrint('🚀 [3b] 准备调用 _checkAndShowRunningModeGuide');
        _checkAndShowRunningModeGuide();
        // 💾 恢复用户偏好设置（会重建 _colorPageController）
        debugPrint('🚀 [3c] 准备调用 _restoreUserPreferences');
        _restoreUserPreferences();
        debugPrint('🚀 [3/5] PostFrameCallback 执行完成');
    });

    // 监听蓝牙连接状态
    debugPrint('🚀 [4/5] 准备设置蓝牙监听');
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    _connectionSub = btProvider.connectionStream.listen((connected) {
      debugPrint('🔗 蓝牙连接状态变化: $connected');
      if (!connected && mounted && !_navigatedOnDisconnect) {
        // 💾 保存设备设置（断连前）
        _saveDeviceSettings();
        _navigatedOnDisconnect = true;
        _showDisconnectDialog();
      }
    });

    // 监听硬件预设报告流
    _presetReportSub = btProvider.presetReportStream.listen((preset) {
      if (!mounted) return;
      final appIndex = preset - 1;
      if (appIndex >= 0 && appIndex < _ledColorCapsules.length) {
        // 委托给 Controller 处理状态更新
        _colorize.onPresetReport(preset);
        // Screen 只负责 PageView 动画
        if (_colorPageController.hasClients) {
          _colorPageController.animateToPage(
            appIndex,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });

    // 🔄 监听硬件流水灯状态报告流
    _streamlightReportSub = btProvider.streamlightReportStream.listen((isEnabled) {
      if (!mounted) return;
      _colorize.onStreamlightReport(isEnabled);
    });
    debugPrint('🚀 [5/5] 所有监听设置完成');
    debugPrint('🚀🚀🚀 DeviceConnectScreen initState 结束');
  }

  /// 🔑 连接后同步硬件UI
  Future<void> _syncHardwareUIOnInit() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (btProvider.isConnected) {
      await btProvider.setHardwareUI(1); // Running Mode UI
      _lastSentHardwareUI = 1;
      debugPrint('🔄 初始化同步硬件UI到Running Mode');
    }
  }

  /// 💾 恢复用户偏好设置
  Future<void> _restoreUserPreferences() async {
    try {
      // 首先尝试恢复设备特定设置
      final deviceSettings = await _preferenceService.getDeviceSettings(widget.device.id);
      
      if (deviceSettings != null) {
        // 使用设备特定设置
        if (mounted) {
          setState(() {
            _colorize.setSelectedColorIndex((deviceSettings['colorPreset'] as int? ?? 0).clamp(0, _ledColorCapsules.length - 1));
            _currentSpeed = (deviceSettings['speed'] as int? ?? 0).clamp(0, _maxSpeed);
            _isAirflowStarted = deviceSettings['atomizer'] as bool? ?? false;
            _colorize.setBrightnessValue((deviceSettings['brightness'] as double? ?? 1.0).clamp(0.0, 1.0));
          });
          debugPrint('💾 设备特定设置已恢复: ${widget.device.id}');
        }
      } else {
        // 回退到全局偏好设置
        final colorPreset = await _preferenceService.getColorPreset();
        final speedValue = await _preferenceService.getSpeedValue();
        final atomizerState = await _preferenceService.getAtomizerState();

        if (mounted) {
          setState(() {
            _colorize.setSelectedColorIndex(colorPreset.clamp(0, _ledColorCapsules.length - 1));
            _currentSpeed = speedValue.clamp(0, _maxSpeed);
            _isAirflowStarted = atomizerState;
          });
          debugPrint('💾 全局偏好已恢复: 颜色=${_colorize.selectedColorIndex}, 速度=$_currentSpeed, 雾化器=$_isAirflowStarted');
        }
      }

      // 用正确的 initialPage 重建 PageController，确保 PageView 从一开始就定位在保存的索引
      if (_colorize.selectedColorIndex > 0) {
        _colorPageController.dispose();
        _colorPageController = PageController(
          initialPage: _colorize.selectedColorIndex,
          viewportFraction: 0.155,
        );
        _colorPageViewKey = UniqueKey();
        setState(() {}); // 触发重建，让 PageView 使用新的 controller 和 key
        debugPrint('💾 重建 ColorPageController: initialPage=${_colorize.selectedColorIndex}');
      }

      // 🎨 恢复自定义 RGB 颜色状态
      final hasCustom = await _preferenceService.getHasCustomColors();
      if (hasCustom) {
        final savedColors = await _preferenceService.getCustomRGBColors();
        if (savedColors != null && mounted) {
          for (final zone in ['L', 'M', 'R', 'B']) {
            if (savedColors.containsKey(zone)) {
              _colorize.setRedValue(zone, savedColors[zone]!['r']!);
              _colorize.setGreenValue(zone, savedColors[zone]!['g']!);
              _colorize.setBlueValue(zone, savedColors[zone]!['b']!);
            }
          }
          _colorize.markCustomColors();
          debugPrint('💾 自定义 RGB 颜色已恢复: $savedColors');
        }
      }
    } catch (e) {
      debugPrint('❌ 恢复用户偏好失败: $e');
    }
  }

  /// 💾 保存设备特定设置
  Future<void> _saveDeviceSettings() async {
    try {
      final settings = {
        'colorPreset': _colorize.selectedColorIndex,
        'speed': _currentSpeed,
        'atomizer': _isAirflowStarted,
        'brightness': _colorize.brightnessValue,
      };
      await _preferenceService.saveDeviceSettings(widget.device.id, settings);
      // 同时更新全局偏好（作为无设备特定设置时的回退）
      _preferenceService.saveSpeedValue(_currentSpeed);
      _preferenceService.saveColorPreset(_colorize.selectedColorIndex);
      debugPrint('💾 设备特定设置已保存: ${widget.device.id}');
    } catch (e) {
      debugPrint('❌ 保存设备特定设置失败: $e');
    }
  }

  /// 显示蓝牙断开连接提示对话框
  void _showDisconnectDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text('设备已断开', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          '蓝牙连接已断开，请选择操作：',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // pop 回到 DeviceListScreen（栈: NoDevice → DeviceList → Connect）
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('返回设备列表', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _attemptReconnect();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25C485)),
            child: const Text('重新连接'),
          ),
        ],
      ),
    );
  }

  /// 尝试重新连接设备
  Future<void> _attemptReconnect() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    final success = await btProvider.connectToDevice(widget.device);
    if (mounted) {
      if (success) {
        _navigatedOnDisconnect = false;
      } else {
        _showReconnectFailedDialog();
      }
    }
  }

  /// 显示重连失败提示
  void _showReconnectFailedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('连接失败', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          '无法重新连接到设备，请检查设备状态后重试。',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // pop 回到 DeviceListScreen
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('返回设备列表'),
          ),
        ],
      ),
    );
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  📚 功能引导逻辑                                                        ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  /// 🧪 调试用：重置引导状态并重新触发指定引导
  Future<void> _debugResetAndShowGuide(GuideType type) async {
    // 先移除已有的引导覆盖层
    _guideOverlayEntry?.remove();
    _guideOverlayEntry = null;

    await _featureGuideService.resetAllGuides();
    _hasCheckedRunningModeGuide = false;
    _hasCheckedColorizeModeGuide = false;

    if (!mounted) return;

    if (type == GuideType.runningMode) {
      // 先切到 Running Mode 页面
      _modePageController.animateToPage(1,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _showRunningModeGuide();
    } else if (type == GuideType.colorizeMode) {
      // 先切到 Colorize Mode 页面
      _modePageController.animateToPage(2,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _showColorizeModeGuide();
    }
  }

  /// 🧪 调试用：构建引导触发按钮
  Widget _buildDebugGuideButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(
              color: Colors.white70, fontSize: 13,
              decoration: TextDecoration.none,
            )),
          ],
        ),
      ),
    );
  }

  /// 检查并显示 Running Mode 引导
  Future<void> _checkAndShowRunningModeGuide() async {
    if (_hasCheckedRunningModeGuide) return;
    _hasCheckedRunningModeGuide = true;

    final shouldShow = await _featureGuideService.shouldShowGuide(GuideType.runningMode);
    if (!shouldShow) return;
    if (mounted) {
      // 延迟一点显示引导，让界面先渲染完成
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showRunningModeGuide();
      }
    }
  }

  /// 检查并显示 Colorize Mode 引导
  Future<void> _checkAndShowColorizeModeGuide() async {
    if (_hasCheckedColorizeModeGuide) return;
    _hasCheckedColorizeModeGuide = true;

    final shouldShow = await _featureGuideService.shouldShowGuide(GuideType.colorizeMode);
    if (!shouldShow) return;
    if (mounted) {
      // 延迟一点显示引导，让界面先渲染完成
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showColorizeModeGuide();
      }
    }
  }

  /// 显示 Running Mode 引导覆盖层
  void _showRunningModeGuide() {
    final steps = [
      // Step 1: 点击下半部分进入调速界面
      GuideStep(
        targetKey: _lowerHalfKey,
        title: '调速界面',
        description: '点击进入调速界面',
        icon: Icons.touch_app,
        gestureType: GestureType.tap,
        // 调速界面已经显示，无需演示动作
      ),
      // Step 2: 上下滑动速度滚轮
      GuideStep(
        targetKey: _runningModeKeys['speedWheel'] ?? _lowerHalfKey,
        title: '速度调节',
        description: '上下滑动调节速度',
        icon: Icons.swap_vert,
        gestureType: GestureType.dragVertical,
        demoAction: () async {
          await _runningModeStateKey.currentState?.demoScrollSpeed();
        },
      ),
      // Step 3: 点击单位标签切换
      GuideStep(
        targetKey: _runningModeKeys['unitLabel'] ?? _lowerHalfKey,
        title: '单位切换',
        description: '点击切换 km/h 和 mph',
        icon: Icons.speed,
        gestureType: GestureType.tap,
        demoAction: () async {
          await _runningModeStateKey.currentState?.demoToggleUnit();
        },
      ),
      // Step 4: 长按油门按钮
      GuideStep(
        targetKey: _runningModeKeys['throttleButton'] ?? _lowerHalfKey,
        title: '油门加速',
        description: '长按油门持续加速',
        icon: Icons.rocket_launch,
        gestureType: GestureType.longPress,
        demoAction: () async {
          await _runningModeStateKey.currentState?.demoThrottle();
        },
      ),
      // Step 5: 点击紧急停止
      GuideStep(
        targetKey: _runningModeKeys['emergencyStop'] ?? _lowerHalfKey,
        title: '紧急停止',
        description: '点击紧急停止归零',
        icon: Icons.emergency,
        gestureType: GestureType.tap,
        demoAction: () async {
          await _runningModeStateKey.currentState?.demoEmergencyStop();
        },
      ),
      // Step 6: 点击汽车图片开关雾化器
      GuideStep(
        targetKey: _carImageKey,
        title: '雾化器',
        description: '点击开关雾化器',
        icon: Icons.water_drop,
        gestureType: GestureType.tap,
      ),
      // Step 7: 长按汽车图片关机或重启
      GuideStep(
        targetKey: _carImageKey,
        title: '关机 / 重启',
        description: '长按可关机或重启',
        icon: Icons.power_settings_new,
        gestureType: GestureType.longPress,
      ),
      // Step 8: 向左滑动进入颜色模式
      GuideStep(
        targetKey: _lowerHalfKey,
        title: '切换模式',
        description: '向左滑动进入颜色模式',
        icon: Icons.swipe_left,
        gestureType: GestureType.swipeLeft,
      ),
    ];

    _guideOverlayEntry = showEnhancedGuideOverlay(
      context: context,
      steps: steps,
      tooltipStyle: GuideTooltipStyle.glassmorphism,
      onComplete: () async {
        await _featureGuideService.markGuideComplete(GuideType.runningMode);
        _guideOverlayEntry = null;
        debugPrint('📚 Running Mode 引导完成');
      },
      onSkip: () async {
        await _featureGuideService.markGuideComplete(GuideType.runningMode);
        _guideOverlayEntry = null;
        debugPrint('📚 Running Mode 引导跳过');
      },
    );
  }

  /// 显示 Colorize Mode 引导覆盖层
  void _showColorizeModeGuide() {
    final steps = [
      // Step 1: 左右滑动选择预设颜色
      GuideStep(
        targetKey: _colorCapsuleStripKey,
        title: '颜色预设',
        description: '左右滑动选择预设颜色',
        icon: Icons.swipe,
        gestureType: GestureType.swipeRight,
      ),
      // Step 2: 点击开始颜色循环动画
      GuideStep(
        targetKey: _startColoringButtonKey,
        title: '颜色循环',
        description: '点击开始颜色循环动画',
        icon: Icons.play_circle,
        gestureType: GestureType.tap,
      ),
      // Step 3: 点击进入 RGB 详细调色
      GuideStep(
        targetKey: _paletteButtonKey,
        title: 'RGB 调色',
        description: '点击进入 RGB 详细调色',
        icon: Icons.palette,
        gestureType: GestureType.tap,
      ),
      // Step 4: 点击选择灯带区域
      GuideStep(
        targetKey: _lmrbCapsulesKey,
        title: '灯带区域',
        description: '点击选择灯带区域',
        icon: Icons.highlight,
        gestureType: GestureType.tap,
      ),
      // Step 5: 长按打开详细调色面板
      GuideStep(
        targetKey: _lmrbCapsulesKey,
        title: '详细调色',
        description: '长按打开详细调色面板',
        icon: Icons.color_lens,
        gestureType: GestureType.longPress,
      ),
      // Step 6: 拖动调节颜色值
      GuideStep(
        targetKey: _rgbSlidersKey,
        title: 'RGB 滑条',
        description: '拖动调节颜色值',
        icon: Icons.tune,
        gestureType: GestureType.dragHorizontal,
      ),
      // Step 7: 上下拖动调节亮度
      GuideStep(
        targetKey: _brightnessBarKey,
        title: '亮度调节',
        description: '上下拖动调节亮度',
        icon: Icons.wb_sunny,
        gestureType: GestureType.dragVertical,
      ),
    ];

    _guideOverlayEntry = showEnhancedGuideOverlay(
      context: context,
      steps: steps,
      tooltipStyle: GuideTooltipStyle.glowBorder,
      onComplete: () async {
        await _featureGuideService.markGuideComplete(GuideType.colorizeMode);
        _guideOverlayEntry = null;
        debugPrint('📚 Colorize Mode 引导完成');
      },
      onSkip: () async {
        await _featureGuideService.markGuideComplete(GuideType.colorizeMode);
        _guideOverlayEntry = null;
        debugPrint('📚 Colorize Mode 引导跳过');
      },
    );
  }

  @override
  void dispose() {
    // 🔧 先停止流水灯动画（不发送命令）
    _colorize.stopCycleAnimation(sendCommand: false);
    
    // 💾 保存设备特定设置（在离开页面时）- 需要在 super.dispose() 之前
    _saveDeviceSettings();
    
    _modePageController.dispose();
    _colorPageController.dispose();
    _connectionSub?.cancel();
    _presetReportSub?.cancel();
    _streamlightReportSub?.cancel(); // 🔄 取消流水灯订阅
    _airflowController.dispose(); // 🌫️ 释放雾化器控制器
    // 📚 清理引导覆盖层
    _guideOverlayEntry?.remove();
    _guideOverlayEntry = null;
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔄 流水灯循环播放逻辑 — 已迁移到 ColorizeController
  // ═══════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════
  // 📱 菜单和对话框
  // ════════════════════════════════════════════════════════════════════

  void _showDeviceMenu(BuildContext context) {
    final parentContext = context; // 保存父级 context
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        100,
        20,
        0,
      ),
      items: [
        // Logo 设置选项
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.image_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                'Logo 设置',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            // 使用 WidgetsBinding 确保在菜单关闭后执行
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showLogoUploadScreen(parentContext);
              }
            });
          },
        ),
        // OTA 固件升级选项
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.system_update_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                'OTA 升级',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _navigateToOtaUpgrade(parentContext);
              }
            });
          },
        ),
        // 音频投射选项
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.speaker_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                '音频投射',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.push(
                  parentContext,
                  MaterialPageRoute(builder: (_) => const AudioStreamScreen()),
                );
              }
            });
          },
        ),
        // 引擎音频管理选项
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.music_note_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                '引擎音效',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.push(
                  parentContext,
                  MaterialPageRoute(builder: (_) => const AudioManagementScreen()),
                );
              }
            });
          },
        ),
        // 移除设备选项
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text('移除设备', style: TextStyle(color: Colors.red, fontSize: 16)),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _showRemoveDeviceDialog(parentContext);
              }
            });
          },
        ),
      ],
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  /// 显示 Logo 上传界面
  void _showLogoUploadScreen(BuildContext parentContext) {
    // 同步硬件UI到Logo模式
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (btProvider.isConnected) {
      btProvider.setHardwareUI(6);
      _lastSentHardwareUI = 6;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LogoManagementScreen()),
    ).then((_) {
      // 返回后恢复硬件UI
      if (mounted && btProvider.isConnected && _lastSentHardwareUI == 6) {
        // 0=running(UI=1), 1=colorize(UI=2)
        final targetUI = _currentModeIndex == 0 ? 1 : 2;
        if (targetUI != 6) {
          btProvider.setHardwareUI(targetUI);
          _lastSentHardwareUI = targetUI;
        }
      }
    });
  }

  /// 导航到 OTA 固件升级页面（仅蓝牙已连接时允许）
  void _navigateToOtaUpgrade(BuildContext parentContext) {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先连接蓝牙设备'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OtaUpgradeScreen()),
    );
  }

  void _showRemoveDeviceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            '移除设备',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            '确定要移除设备"${widget.device.name}"吗？',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: Colors.blue, fontSize: 16),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '移除',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🔙 返回按钮逻辑（简化后）                                              ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Future<void> _handleBackNavigation() async {
    debugPrint('\n🔘 ========== 返回按钮被点击！==========');

    // 优先级 1: Colorize 模式内的返回逻辑
    if (_currentMode == ControlMode.colorize) {
      if (_colorize.colorizeState == ColorizeState.rgbDetail) {
        HapticFeedback.lightImpact();
        _colorize.setColorizeState(ColorizeState.preset);
        setState(() {}); // 触发 UI 重建
        // 仅在没有自定义颜色时才同步预设到硬件，避免覆盖用户自定义的 RGB 值
        if (!_colorize.hasCustomColors) {
          _colorize.syncPresetToHardware(_colorize.selectedColorIndex);
        }
        return;
      }
    }

    // 优先级 2: 返回到已有的 NoDeviceScreen（pop 回栈中已有页面，避免栈累积）
    debugPrint('✅ 返回添加设备页');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // 兜底：栈底时替换为 NoDeviceScreen
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NoDeviceScreen()),
      );
    }
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🔌 关机/重启对话框                                                     ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  void _showPowerDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PowerDialog',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: PowerSliderDialog(
            onShutdown: () async {
              Navigator.of(context).pop();
              await _performShutdown();
            },
            onReboot: () async {
              Navigator.of(context).pop();
              await _performReboot();
            },
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: anim1.drive(Tween(begin: 0.9, end: 1.0)),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _performShutdown() async {
    final logger = DebugLogger();
    debugPrint('🔌 执行软关机...');
    logger.log('🔌 执行软关机...');
    HapticFeedback.heavyImpact();

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    await btProvider.setWuhuaqiStatus(false);
    await Future.delayed(const Duration(milliseconds: 100));

    await btProvider.setFanSpeed(0);
    await Future.delayed(const Duration(milliseconds: 100));

    for (int strip = 1; strip <= 4; strip++) {
      await btProvider.setLEDColor(strip, 0, 0, 0);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await btProvider.setLCDStatus(false);
    await Future.delayed(const Duration(milliseconds: 100));

    setState(() => _isAirflowStarted = false);
    debugPrint('✅ 软关机完成');
  }

  Future<void> _performReboot() async {
    debugPrint('🔄 执行重启...');
    HapticFeedback.heavyImpact();

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    await btProvider.setWuhuaqiStatus(false);
    await btProvider.setFanSpeed(0);
    for (int strip = 1; strip <= 4; strip++) {
      await btProvider.setLEDColor(strip, 0, 0, 0);
    }
    await btProvider.setLCDStatus(false);

    await Future.delayed(const Duration(milliseconds: 500));

    await btProvider.setLCDStatus(true);

    for (int strip = 1; strip <= 4; strip++) {
      await btProvider.setLEDColor(strip, 255, 255, 255);
    }

    setState(() {
      _isAirflowStarted = false;
    });

    debugPrint('✅ 重启完成');
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🏗️ 主界面构建（简化后：直接进入模式界面）                              ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️🏗️🏗️ DeviceConnectScreen build 开始');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(backgroundColor: Colors.black, body: _buildMainUIFixed()),
    );
  }
  
  // 🔧 修复后的主界面（简化背景图加载逻辑）
  Widget _buildMainUIFixed() {
    final config = _DeviceConnectConfig(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final dividerPosition = screenHeight * 0.45;

    return Stack(
      children: [
        // ========== 🖼️ 背景图（简化版，去掉 cacheWidth/cacheHeight）==========
        Positioned.fill(
          child: Image.asset(
            _getBackgroundImage(),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('❌ 背景图片加载失败: $error');
              return Container(color: Colors.black);
            },
          ),
        ),

        // 顶部渐变遮罩
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: config.topGradientHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.black.withAlpha(200),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ========== 🚗 汽车图片区域（单击雾化器、长按关机）==========
        Positioned(
          key: _carImageKey,
          top: config.carImageTop,
          bottom: screenHeight - dividerPosition,
          left: config.carImageLeft,
          right: config.carImageRight,
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              debugPrint('🚗 单击车模型 → 切换雾化器');
              final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
              bool newState = !_isAirflowStarted;
              bool success = await btProvider.setWuhuaqiStatus(newState);
              if (success) {
                setState(() => _isAirflowStarted = newState);
                debugPrint('✅ 雾化器${newState ? "开启" : "关闭"}');
              }
            },
            onLongPress: () {
              debugPrint('⏱️ 长按车模型 → 显示关机/重启对话框');
              _showPowerDialog(context);
            },
            child: Container(color: Colors.transparent),
          ),
        ),

        // ========== 📄 下半部分内容区域（左右滑动切换模式）==========
        Positioned(
          key: _lowerHalfKey,
          top: dividerPosition,
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRect(child: _buildModeContentArea(config)),
        ),

        // ========== 🔝 返回按钮 ==========
        Positioned(
          top: config.backButtonTop,
          left: config.backButtonLeft,
          child: GestureDetector(
            onTap: _handleBackNavigation,
            child: Container(
              width: config.backButtonSize,
              height: config.backButtonSize,
              color: Colors.transparent,
            ),
          ),
        ),

        // ========== 📋 菜单按钮 ==========
        if (!(_currentMode == ControlMode.colorize && _colorize.colorizeState == ColorizeState.rgbDetail))
          Positioned(
            top: config.menuButtonTop,
            right: config.menuButtonRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                debugPrint('📋 菜单按钮被点击');
                _showDeviceMenu(context);
              },
              child: Container(
                width: config.menuButtonSize,
                height: config.menuButtonSize,
                color: Colors.transparent,
              ),
            ),
          ),

        // ========== 🌫️ 雾化器状态指示器 ==========
        if (_isAirflowStarted)
          Positioned(
            top: config.topButtonTop + 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(204),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.water_drop, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('雾化器已开启', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

        // ========== 🎨 RGB 详细调节面板 ==========
        if (_currentMode == ControlMode.colorize &&
            _colorize.colorizeState == ColorizeState.rgbDetail)
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _colorize,
              builder: (context, _) {
                if (!_colorize.showDetailedTuning) {
                  return const SizedBox.shrink();
                }
                return ColorizeDetailedTuningOverlay(
                  rgbSlidersKey: _rgbSlidersKey,
                  brightnessBarKey: _brightnessBarKey,
                );
              },
            ),
          ),


      ],
    );
  }

  /// 获取背景图（根据当前模式和状态）
  String _getBackgroundImage() {
    switch (_currentMode) {
      case ControlMode.running:
        return 'assets/images/running_mode_no_text.png';
      case ControlMode.colorize:
        switch (_colorize.colorizeState) {
          case ColorizeState.preset:
            return 'assets/images/colorize_mode_no_text.png';
          case ColorizeState.rgbDetail:
            return 'assets/images/rgb_settings_clean.png';
        }
    }
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  📄 模式内容区域（下半部分，左右滑动切换）                               ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Widget _buildModeContentArea(_DeviceConnectConfig config) {
    debugPrint('📄 _buildModeContentArea 渲染中... currentModeIndex=$_currentModeIndex');
    
    return PageView(
      controller: _modePageController,
      physics: const PageScrollPhysics(),
      scrollDirection: Axis.horizontal,
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        setState(() {
          _currentModeIndex = index;
          if (index == 2) {
            _colorize.setColorizeState(ColorizeState.preset);
            // 重建 PageController 确保 initialPage 对齐当前选中的颜色索引
            _colorPageController.dispose();
            _colorPageController = PageController(
              initialPage: _colorize.selectedColorIndex,
              viewportFraction: 0.155,
            );
            _colorPageViewKey = UniqueKey();
          }
        });
        _syncHardwareUIOnModeChange(index);
        final modeNames = ['Dev Test', 'Running Mode', 'Colorize Mode'];
        debugPrint('📄 滑动切换到: ${modeNames[index]}');
        
        if (index == 2) {
          _checkAndShowColorizeModeGuide();
        }
      },
      children: [
        _buildRunningModeContent(config),
        _buildColorizeModeContent(config),
      ],
    );
  }

  /// 🔑 模式切换时同步硬件UI
  Future<void> _syncHardwareUIOnModeChange(int modeIndex) async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    switch (modeIndex) {
      case 0: // Dev Test Mode - 不改变硬件UI
        debugPrint('🧪 进入开发测试模式，保持当前硬件UI');
        break;
      case 1: // Running Mode
        if (_lastSentHardwareUI != 1) {
          await btProvider.setHardwareUI(1);
          _lastSentHardwareUI = 1;
        }
        break;
      case 2: // Colorize Mode
        if (_lastSentHardwareUI != 2) {
          await btProvider.setHardwareUI(2);
          _lastSentHardwareUI = 2;
          // 🎨 进入Colorize模式时，将本地保存的预设同步到硬件，而非从硬件查询
          // 这样可以保持用户上次选择的颜色预设
          if (!_colorize.hasCustomColors) {
            _colorize.syncPresetToHardware(_colorize.selectedColorIndex);
          }
        }
        break;
    }
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🏃 Running Mode 内容（调速界面）                                        ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Widget _buildRunningModeContent(_DeviceConnectConfig config) {
    // 🔧 添加try-catch防止渲染错误导致黑屏
    try {
      return Consumer<BluetoothProvider>(
        builder: (context, btProvider, child) {
          debugPrint('🏃 Running Mode 渲染中... isConnected=${btProvider.isConnected}');
          return RunningModeWidget(
        key: _runningModeStateKey,
        initialSpeed: _currentSpeed,
        maxSpeed: _maxSpeed,
        initialShowSpeedControl: true, // 🔑 直接显示调速界面
        externalSpeedStream: btProvider.speedReportStream,
        externalThrottleStream: btProvider.throttleReportStream,
        externalUnitStream: btProvider.unitReportStream,
        connectionStream: btProvider.connectionStream,
        isConnected: btProvider.isConnected,
        onKeysReady: (keys) {
          setState(() {
            _runningModeKeys = keys;
          });
        },
        onSpeedChanged: (speed) async {
          setState(() => _currentSpeed = speed);
          // 💾 保存速度值（边界值立即保存，其他值通过 _saveDeviceSettings 在离开时保存）
          if (speed == 0 || speed == _maxSpeed) {
            _preferenceService.saveSpeedValue(speed);
          }

          final btProvider = Provider.of<BluetoothProvider>(
            context,
            listen: false,
          );
          final now = DateTime.now();
          final timeSinceLastCommand = now
              .difference(_lastCommandTime)
              .inMilliseconds;

          bool shouldSend = false;
          if (speed == 0 || speed == _maxSpeed) {
            shouldSend = true;
          } else if (timeSinceLastCommand >= 100) {
            shouldSend = true;
          }

          if (shouldSend) {
            _lastCommandTime = now;
            await btProvider.setRunningSpeed(speed);
          }
        },
        onUnitChanged: (isMetric) async {
          final btProvider = Provider.of<BluetoothProvider>(
            context,
            listen: false,
          );
          await btProvider.setSpeedUnit(isMetric);
        },
        onThrottleStatusChanged: (isThrottling) async {
          final btProvider = Provider.of<BluetoothProvider>(
            context,
            listen: false,
          );
          await btProvider.setHardwareThrottleMode(isThrottling);
          await Future.delayed(const Duration(milliseconds: 30));
          debugPrint('🔥 油门模式: ${isThrottling ? "开启" : "关闭"}');
        },
        onEmergencyStop: () async {
          setState(() => _currentSpeed = 0);

          final btProvider = Provider.of<BluetoothProvider>(
            context,
            listen: false,
          );
          await btProvider.setHardwareThrottleMode(false);
          await Future.delayed(const Duration(milliseconds: 20));
          await btProvider.setRunningSpeed(0);
          await btProvider.setFanSpeed(0);
        },
        onSpeedControlVisibilityChanged: null, // 🔑 不需要这个回调了
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Running Mode 渲染错误: $e');
      debugPrint('📍 堆栈跟踪: $stackTrace');
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Running Mode 加载失败',
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

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🎨 Colorize Mode 内容（下半部分）                                       ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Widget _buildColorizeModeContent(_DeviceConnectConfig config) {
    try {
      switch (_colorize.colorizeState) {
        case ColorizeState.preset:
          return ColorizePresetView(
            colorPageController: _colorPageController,
            colorPageViewKey: _colorPageViewKey,
            colorCapsuleStripKey: _colorCapsuleStripKey,
            startColoringButtonKey: _startColoringButtonKey,
            paletteButtonKey: _paletteButtonKey,
            debugMode: _debugMode,
          );
        case ColorizeState.rgbDetail:
          return ColorizeRGBDetailView(
            lmrbCapsulesKey: _lmrbCapsulesKey,
            rgbSlidersKey: _rgbSlidersKey,
            brightnessBarKey: _brightnessBarKey,
            debugMode: _debugMode,
          );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Colorize Mode 渲染错误: $e');
      debugPrint('📍 堆栈跟踪: $stackTrace');
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                '加载失败',
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

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🎨 Colorize Mode 子组件 — 已提取到 widgets/colorize_rgb_detail_view.dart ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🔄 硬件同步方法（旧 Colorize 方法已迁移到 ColorizeController +           ║
  // ║      ColorizeRGBDetailView / ColorizeDetailedTuningOverlay）             ║
  // ╚════════════════════════════════════════════════════════════════════════╝

} // _DeviceConnectScreenState 类结束
