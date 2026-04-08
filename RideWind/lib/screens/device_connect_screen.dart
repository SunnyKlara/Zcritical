import 'dart:async'; // 用于 Timer
import 'dart:math'; // 用于随机数
import 'dart:ui'; // 用于 ImageFilter（毛玻璃效果）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于震动反馈
import 'package:provider/provider.dart'; // Provider 状态管理
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart'; // 蓝牙状态管理
import '../utils/debug_logger.dart'; // ✅ 导入日志工具
import '../utils/colorize_throttler.dart'; // 🔄 RGB调色节流器
import '../controllers/airflow_indicator_controller.dart'; // 🌫️ 雾化器指示器控制器
import '../widgets/running_mode_widget.dart'; // Running Mode 独立组件
import '../widgets/enhanced_guide_overlay.dart'; // ✅ 增强功能引导覆盖层
import '../widgets/guide_tooltip_styles.dart'; // ✅ 引导提示框样式
import '../models/guide_models.dart'; // ✅ 引导数据模型
import '../services/feature_guide_service.dart'; // ✅ 功能引导服务
import '../services/feedback_service.dart'; // ✅ 操作反馈服务
import '../services/preference_service.dart'; // ✅ 用户偏好存储服务
import 'device_scan_screen.dart'; // 扫描页面
import 'device_list_screen.dart'; // 设备列表页面
import 'no_device_screen.dart'; // 添加设备页面（APP主页）
import 'logo_upload_e2e_test_screen.dart'; // Logo上传界面（唯一可用的方案）
import 'dev_test_screen.dart'; // 🧪 开发测试界面
import 'color_ring_screen.dart'; // 🎨 色彩圆环界面
import 'ota_upgrade_screen.dart'; // 🔄 OTA 固件升级界面

// ╔══════════════════════════════════════════════════════════════╗
// ║          🔄 控制模式枚举（3个模式）                            ║
// ╚══════════════════════════════════════════════════════════════╝
enum ControlMode {
  devTest, // 🧪 开发测试模式（最左侧）
  running, // Running Mode - 速度/油门控制（默认）
  colorize, // Colorize Mode - LED颜色控制（右滑进入）
}

// 🎨 Colorize 子模式枚举
enum ColorizeState {
  preset, // 对应配色预设界面 (hardware ui=2)
  rgbDetail, // 对应 RGB 调色界面 (hardware ui=3)
}

/// 📱 响应式布局配置类
class _DeviceConnectConfig {
  final BuildContext context;

  _DeviceConnectConfig(this.context);

  // ========== 屏幕信息 ==========
  double get _screenWidth => MediaQuery.of(context).size.width;
  double get _screenHeight => MediaQuery.of(context).size.height;
  double get _safeAreaTop => MediaQuery.of(context).padding.top;
  double get _safeAreaBottom => MediaQuery.of(context).padding.bottom;

  bool get _isSmallScreen => _screenHeight < 700 || _screenWidth < 375;
  bool get _isLargeScreen => _screenHeight > 900 || _screenWidth > 428;
  bool get _isTablet => _screenWidth > 600;

  // ========== 顶部渐变遮罩 ==========
  double get topGradientHeight {
    if (_isSmallScreen) return 55.0;
    if (_isLargeScreen) return 80.0;
    return 70.0;
  }

  // ========== 顶部按钮 ==========
  double get topButtonTop {
    final base = _safeAreaTop + 8;
    if (_isSmallScreen) return base;
    if (_isLargeScreen) return base + 4;
    return base;
  }

  double get backButtonTop => topButtonTop;
  double get menuButtonTop => topButtonTop;

  double get backButtonLeft {
    if (_isSmallScreen) return 8;
    if (_isTablet) return 20;
    return _screenWidth * 0.02;
  }

  double get menuButtonRight {
    if (_isSmallScreen) return 8;
    if (_isTablet) return 20;
    return _screenWidth * 0.025;
  }

  double get topButtonSize {
    if (_isSmallScreen) return 40.0;
    if (_isLargeScreen) return 60.0;
    if (_isTablet) return 64.0;
    return 52.0;
  }

  double get backButtonSize => topButtonSize;
  double get menuButtonSize => topButtonSize;

  // ========== 双击区域（汽车图片）==========
  double get carImageTop {
    if (_isSmallScreen) return _screenHeight * 0.12;
    return _screenHeight * 0.15;
  }

  double get carImageBottom {
    if (_isSmallScreen) return _screenHeight * 0.50;
    return _screenHeight * 0.55;
  }

  double get carImageLeft => _screenWidth * 0.1;
  double get carImageRight => _screenWidth * 0.1;

  // ========== RGB 设置界面 ==========
  double get rgbSettingsTop => _screenHeight * 0.57;
  double get rgbSettingsLeft => _screenWidth * 0.1;
  double get rgbSettingsRight => _screenWidth * 0.1;

  double get rgbSettingsButtonBottom {
    final base = _safeAreaBottom + 10;
    if (_isSmallScreen) return base;
    if (_isLargeScreen) return base + 15;
    return base + 10;
  }

  double get rgbSettingsButtonRight => _screenWidth * 0.05;

  double get rgbSettingsButtonSize {
    if (_isSmallScreen) return 55.0;
    if (_isLargeScreen) return 90.0;
    return 80.0;
  }

  // ========== RGB 调色界面 (ui=3) 响应式布局 ==========
  double get cycleSpeedPanelBottom {
    final base = _safeAreaBottom + 80;
    if (_isSmallScreen) return base + 25;
    if (_isLargeScreen) return base + 45;
    return base + 35;
  }

  double get cycleSpeedSliderHeight {
    if (_isSmallScreen) return 36.0;
    if (_isLargeScreen) return 52.0;
    return 46.0;
  }

  double get _cycleSpeedPanelHeight {
    final titleFontSize = _screenWidth < 360
        ? 16.0
        : (_screenWidth > 414 ? 24.0 : 20.0);
    return titleFontSize + 15 + cycleSpeedSliderHeight + 10 + 7;
  }

  double get _cycleSpeedPanelTop {
    return _screenHeight - cycleSpeedPanelBottom - _cycleSpeedPanelHeight;
  }

  double get _availableSpaceForCapsules {
    final topBoundary = _screenHeight * 0.50;
    final bottomBoundary = _cycleSpeedPanelTop - 20;
    final available = bottomBoundary - topBoundary;
    // 🔧 确保返回正值，避免后续计算出错
    return available > 0 ? available : 200.0;
  }

  double get rgbCapsuleHeight {
    final availableForCapsule = _availableSpaceForCapsules - 40;
    double targetHeight;
    if (_isSmallScreen) {
      targetHeight = 140.0;
    } else if (_isLargeScreen) {
      targetHeight = 200.0;
    } else if (_isTablet) {
      targetHeight = 220.0;
    } else {
      targetHeight = 170.0;
    }
    // 🔧 修复：确保 max >= min，避免 clamp 参数错误
    final safeAvailable = availableForCapsule > 100
        ? availableForCapsule
        : 200.0;
    final maxHeight = safeAvailable * 0.85;
    return targetHeight.clamp(100.0, maxHeight > 100 ? maxHeight : 200.0);
  }

  double get rgbCapsuleWidth {
    final baseWidth = rgbCapsuleHeight * 0.38;
    if (_isSmallScreen) return baseWidth.clamp(45.0, 55.0);
    if (_isLargeScreen) return baseWidth.clamp(60.0, 75.0);
    if (_isTablet) return baseWidth.clamp(65.0, 80.0);
    return baseWidth.clamp(50.0, 65.0);
  }

  double get rgbCapsulesTop {
    final topBoundary = _screenHeight * 0.50;
    final bottomBoundary = _cycleSpeedPanelTop - 20;
    final totalCapsuleAreaHeight = rgbCapsuleHeight + 40;
    final centerY = (topBoundary + bottomBoundary) / 2;
    return centerY - totalCapsuleAreaHeight / 2;
  }

  /// 亮度调节条高度（基于屏幕高度的响应式计算，拉长一点）
  double get verticalBrightnessHeight {
    // 基于屏幕高度的 22%，拉长一点
    final baseHeight = _screenHeight * 0.22;
    return baseHeight.clamp(150.0, 220.0);
  }

  double get verticalBrightnessWidth {
    // 基于屏幕宽度的 14%，加粗
    final baseWidth = _screenWidth * 0.14;
    return baseWidth.clamp(50.0, 65.0);
  }

  /// 亮度调节条顶部位置（往下靠）
  double get verticalBrightnessTop {
    // 从屏幕顶部 15% 的位置开始
    final base = _screenHeight * 0.15;
    return base.clamp(100.0, 160.0);
  }

  double get metallicSliderHeight {
    if (_isSmallScreen) return 36.0;
    if (_isLargeScreen) return 52.0;
    return 46.0;
  }

  // ========== 颜色胶囊条 ==========
  double get colorCapsuleWidth {
    if (_isSmallScreen) return 42.0;
    if (_isLargeScreen) return 55.0;
    return 47.0;
  }

  double get colorCapsuleHeight {
    if (_isSmallScreen) return 135.0;
    if (_isLargeScreen) return 170.0;
    return 153.0;
  }

  double get colorCapsuleContainerHeight {
    if (_isSmallScreen) return 185.0;
    if (_isLargeScreen) return 240.0;
    return 220.0;
  }

  // ========== 对话框字体 ==========
  double get dialogTitleFontSize {
    if (_isSmallScreen) return 18.0;
    if (_isLargeScreen) return 24.0;
    return 22.0;
  }

  double get dialogContentFontSize {
    if (_isSmallScreen) return 14.0;
    if (_isLargeScreen) return 18.0;
    return 16.0;
  }

  double get dialogButtonFontSize {
    if (_isSmallScreen) return 14.0;
    if (_isLargeScreen) return 18.0;
    return 16.0;
  }

  /// 开始涂色按钮高度
  double get startColoringButtonTapHeight {
    if (_isSmallScreen) return 55.0;
    if (_isLargeScreen) return 70.0;
    return 62.0;
  }

  /// 调色盘按钮尺寸
  double get paletteButtonSize {
    if (_isSmallScreen) return 65.0;
    if (_isLargeScreen) return 90.0;
    return 78.0;
  }

  /// 底部按钮区域底部边距
  double get bottomButtonsMarginBottom {
    final base = _safeAreaBottom + 15; // 🔧 减小基础边距，让按钮更靠下
    if (_isSmallScreen) return base + 5;
    if (_isLargeScreen) return base + 15;
    return base + 10;
  }
}

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
  int _currentModeIndex = 1; // 0=devTest, 1=running(默认), 2=colorize
  late PageController _modePageController; // 模式页面滑动控制器

  // ========== 🌬️ 雾化器状态 ==========
  bool _isAirflowStarted = false;
  final AirflowIndicatorController _airflowController = AirflowIndicatorController();

  // ========== 🏃 Running Mode 专用状态 ==========
  int _currentSpeed = 0;
  final int _maxSpeed = 340;
  DateTime _lastCommandTime = DateTime.now();

  // ========== 🎨 Colorize Mode 专用状态 ==========
  ColorizeState _colorizeState = ColorizeState.preset;
  bool _hasCustomColors = false; // 🎨 颜色来源标志位：true=自定义RGB，false=预设
  int _lastSentHardwareUI = -1;
  DateTime _lastColorSyncTime = DateTime.now();
  DateTime _lastPresetSyncTime = DateTime.now();
  
  // 🔄 RGB调色节流器（50ms间隔）
  final ColorizeThrottler _colorizeThrottler = ColorizeThrottler();

  int _selectedColorIndex = 0;
  late PageController _colorPageController;
  Key _colorPageViewKey = UniqueKey();

  // ========== 🎰 转盘抽奖动画状态 ==========
  bool _isSpinning = false;

  String _selectedLightPosition = 'B';
  bool _showDetailedTuning = false;
  double _cycleSpeed = 0.5;

  final Map<String, int> _redValues = {'L': 150, 'M': 150, 'R': 150, 'B': 200};
  final Map<String, int> _greenValues = {'L': 20, 'M': 20, 'R': 20, 'B': 50};
  final Map<String, int> _blueValues = {'L': 0, 'M': 0, 'R': 0, 'B': 0};

  // 🎨 RGB 数值手动输入状态
  String? _editingRGBChannel; // null=无编辑, 'R'/'G'/'B'
  final TextEditingController _rgbValueController = TextEditingController();
  final FocusNode _rgbValueFocusNode = FocusNode();

  double _brightnessValue = 1.0;

  Timer? _cycleTimer;
  bool _isCycling = false;
  int _cycleColorIndex = 0;

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

  final List<String> _cyclePositions = ['L', 'M', 'R', 'B'];
  int _cyclePositionIndex = 0;

  // ========== 💾 用户偏好服务 ==========
  final PreferenceService _preferenceService = PreferenceService();

  // ========== 🔗 蓝牙连接监听 ==========
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<int>? _presetReportSub;
  StreamSubscription<bool>? _streamlightReportSub; // 🔄 流水灯状态订阅
  bool _navigatedOnDisconnect = false;
  bool _isReceivingPresetReport = false;

  // ========== 🐛 调试模式 ==========
  static const bool _debugMode = false; // 🔧 调试模式已关闭

  // 🎨 12条颜色预设配置
  static const List<Map<String, dynamic>> _ledColorCapsules = [
    {
      'type': 'gradient',
      'colors': [Color(0xFF8A2BE2), Color(0xFF00FF80)],
      'led2': {'r': 138, 'g': 43, 'b': 226},
      'led3': {'r': 0, 'g': 255, 'b': 128},
    },
    {
      'type': 'solid',
      'color': Color(0xFF00EAFF),
      'led2': {'r': 0, 'g': 234, 'b': 255},
      'led3': {'r': 0, 'g': 234, 'b': 255},
    },
    {
      'type': 'gradient',
      'colors': [Color(0xFFFF6400), Color(0xFF00C8FF)],
      'led2': {'r': 255, 'g': 100, 'b': 0},
      'led3': {'r': 0, 'g': 200, 'b': 255},
    },
    {
      'type': 'solid',
      'color': Color(0xFFFFD200),
      'led2': {'r': 255, 'g': 210, 'b': 0},
      'led3': {'r': 255, 'g': 210, 'b': 0},
    },
    {
      'type': 'solid',
      'color': Color(0xFFFF0000),
      'led2': {'r': 255, 'g': 0, 'b': 0},
      'led3': {'r': 255, 'g': 0, 'b': 0},
    },
    {
      'type': 'gradient',
      'colors': [Color(0xFFFF0000), Color(0xFF0050FF)],
      'led2': {'r': 255, 'g': 0, 'b': 0},
      'led3': {'r': 0, 'g': 80, 'b': 255},
    },
    {
      'type': 'gradient',
      'colors': [Color(0xFFFF69B4), Color(0xFFFF0050)],
      'led2': {'r': 255, 'g': 105, 'b': 180},
      'led3': {'r': 255, 'g': 0, 'b': 80},
    },
    {
      'type': 'gradient',
      'colors': [Color(0xFFB400FF), Color(0xFF00FFC8)],
      'led2': {'r': 180, 'g': 0, 'b': 255},
      'led3': {'r': 0, 'g': 255, 'b': 200},
    },
    {
      'type': 'solid',
      'color': Color(0xFF9400D3),
      'led2': {'r': 148, 'g': 0, 'b': 211},
      'led3': {'r': 148, 'g': 0, 'b': 211},
    },
    {
      'type': 'gradient',
      'colors': [Color(0xFF00FFB4), Color(0xFF64C8FF)],
      'led2': {'r': 0, 'g': 255, 'b': 180},
      'led3': {'r': 100, 'g': 200, 'b': 255},
    },
    {
      'type': 'solid',
      'color': Color(0xFF00FF41),
      'led2': {'r': 0, 'g': 255, 'b': 65},
      'led3': {'r': 0, 'g': 255, 'b': 65},
    },
    {
      'type': 'solid',
      'color': Color(0xFFE1E1E1),
      'led2': {'r': 225, 'g': 225, 'b': 225},
      'led3': {'r': 225, 'g': 225, 'b': 225},
    },
  ];

  // 获取当前模式
  ControlMode get _currentMode {
    switch (_currentModeIndex) {
      case 0:
        return ControlMode.devTest;
      case 1:
        return ControlMode.running;
      case 2:
        return ControlMode.colorize;
      default:
        return ControlMode.running;
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🚀🚀🚀 DeviceConnectScreen initState 开始');
    
    // 🎨 RGB 数值输入焦点监听
    _rgbValueFocusNode.addListener(_onRGBValueFocusChanged);

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
        debugPrint('🎨 收到硬件预设报告: $preset -> APP索引: $appIndex');
        _isReceivingPresetReport = true;
        setState(() {
          _selectedColorIndex = appIndex;
        });
        if (_colorPageController.hasClients) {
          _colorPageController.animateToPage(
            appIndex,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        _applyPresetToLocalColors(appIndex);
        Future.delayed(const Duration(milliseconds: 150), () {
          _isReceivingPresetReport = false;
        });
      }
    });

    // 🔄 监听硬件流水灯状态报告流
    _streamlightReportSub = btProvider.streamlightReportStream.listen((isEnabled) {
      if (!mounted) return;
      debugPrint('🔄 收到硬件流水灯状态: ${isEnabled ? "开启" : "关闭"}');
      setState(() {
        _isCycling = isEnabled;
      });
      // 如果硬件开启了流水灯，APP端也启动本地动画
      if (isEnabled && _cycleTimer == null) {
        _cycleTimer = Timer.periodic(_cycleInterval, _onCycleTick);
      } else if (!isEnabled && _cycleTimer != null) {
        _cycleTimer?.cancel();
        _cycleTimer = null;
      }
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
            _selectedColorIndex = (deviceSettings['colorPreset'] as int? ?? 0).clamp(0, _ledColorCapsules.length - 1);
            _currentSpeed = (deviceSettings['speed'] as int? ?? 0).clamp(0, _maxSpeed);
            _isAirflowStarted = deviceSettings['atomizer'] as bool? ?? false;
            _brightnessValue = (deviceSettings['brightness'] as double? ?? 1.0).clamp(0.0, 1.0);
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
            _selectedColorIndex = colorPreset.clamp(0, _ledColorCapsules.length - 1);
            _currentSpeed = speedValue.clamp(0, _maxSpeed);
            _isAirflowStarted = atomizerState;
          });
          debugPrint('💾 全局偏好已恢复: 颜色=$_selectedColorIndex, 速度=$_currentSpeed, 雾化器=$_isAirflowStarted');
        }
      }

      // 用正确的 initialPage 重建 PageController，确保 PageView 从一开始就定位在保存的索引
      if (_selectedColorIndex > 0) {
        _colorPageController.dispose();
        _colorPageController = PageController(
          initialPage: _selectedColorIndex,
          viewportFraction: 0.155,
        );
        _colorPageViewKey = UniqueKey();
        setState(() {}); // 触发重建，让 PageView 使用新的 controller 和 key
        debugPrint('💾 重建 ColorPageController: initialPage=$_selectedColorIndex');
      }

      // 🎨 恢复自定义 RGB 颜色状态
      final hasCustom = await _preferenceService.getHasCustomColors();
      if (hasCustom) {
        final savedColors = await _preferenceService.getCustomRGBColors();
        if (savedColors != null && mounted) {
          setState(() {
            for (final zone in ['L', 'M', 'R', 'B']) {
              if (savedColors.containsKey(zone)) {
                _redValues[zone] = savedColors[zone]!['r']!;
                _greenValues[zone] = savedColors[zone]!['g']!;
                _blueValues[zone] = savedColors[zone]!['b']!;
              }
            }
            _hasCustomColors = true;
          });
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
        'colorPreset': _selectedColorIndex,
        'speed': _currentSpeed,
        'atomizer': _isAirflowStarted,
        'brightness': _brightnessValue,
      };
      await _preferenceService.saveDeviceSettings(widget.device.id, settings);
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
    // 🔧 先停止动画（不发送命令，标记为 dispose 调用）
    _stopCycleAnimation(sendCommand: false, fromDispose: true);
    
    // 💾 保存设备特定设置（在离开页面时）- 需要在 super.dispose() 之前
    _saveDeviceSettings();
    
    _modePageController.dispose();
    _colorPageController.dispose();
    _connectionSub?.cancel();
    _presetReportSub?.cancel();
    _streamlightReportSub?.cancel(); // 🔄 取消流水灯订阅
    _airflowController.dispose(); // 🌫️ 释放雾化器控制器
    // 🎨 RGB 数值输入清理
    _rgbValueFocusNode.removeListener(_onRGBValueFocusChanged);
    _rgbValueController.dispose();
    _rgbValueFocusNode.dispose();
    // 📚 清理引导覆盖层
    _guideOverlayEntry?.remove();
    _guideOverlayEntry = null;
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🎰 转盘抽奖动画逻辑
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _startSpinAnimation() async {
    if (_isSpinning) return;

    setState(() {
      _isSpinning = true;
      _indicatorOffset = 0;
      _bounceOffset = 0;
      _bounceScale = 1.0;
    });
    HapticFeedback.heavyImpact();
    debugPrint('🎰 转盘测试开始');

    final totalItems = _ledColorCapsules.length;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxOffset = screenWidth * 0.5;

    int bounceFrame = 0;

    while (_isSpinning && mounted) {
      for (int i = 0; i <= totalItems - 1; i += 3) {
        if (!_isSpinning || !mounted || !_colorPageController.hasClients) {
          return;
        }

        final pos = i.clamp(0, totalItems - 1);
        final progress = pos / (totalItems - 1);
        final offset = maxOffset - progress * maxOffset * 2;

        bounceFrame++;
        final bounceY = sin(bounceFrame * 0.8) * 25;
        final bounceS = 1.0 + sin(bounceFrame * 0.6) * 0.15;

        setState(() {
          _indicatorOffset = offset;
          _bounceOffset = bounceY;
          _bounceScale = bounceS;
          _selectedColorIndex = pos;
        });

        _colorPageController.jumpToPage(pos);
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 35));
      }

      for (int i = totalItems - 1; i >= 0; i -= 3) {
        if (!_isSpinning || !mounted || !_colorPageController.hasClients) {
          return;
        }

        final pos = i.clamp(0, totalItems - 1);
        final progress = pos / (totalItems - 1);
        final offset = maxOffset - progress * maxOffset * 2;

        bounceFrame++;
        final bounceY = sin(bounceFrame * 0.8) * 25;
        final bounceS = 1.0 + sin(bounceFrame * 0.6) * 0.15;

        setState(() {
          _indicatorOffset = offset;
          _bounceOffset = bounceY;
          _bounceScale = bounceS;
          _selectedColorIndex = pos;
        });

        _colorPageController.jumpToPage(pos);
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(milliseconds: 35));
      }
    }

    setState(() {
      _bounceOffset = 0;
      _bounceScale = 1.0;
      _indicatorOffset = 0;
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // 🔄 流水灯循环播放逻辑
  // ═══════════════════════════════════════════════════════════════════

  Duration get _cycleInterval {
    const minInterval = 50;
    const maxInterval = 1000;
    final adjustedInterval =
        (maxInterval * (1 - _cycleSpeed * _cycleSpeed) +
                minInterval * _cycleSpeed * _cycleSpeed)
            .round();
    return Duration(
      milliseconds: adjustedInterval.clamp(minInterval, maxInterval),
    );
  }

  void _startCycleAnimation() {
    if (_isCycling) return;
    setState(() => _isCycling = true);
    
    // 🔄 发送流水灯开启命令到硬件端
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (btProvider.isConnected) {
      btProvider.setStreamlightMode(true);
      debugPrint('🔄 流水灯启动 - 已发送硬件命令');
    }
    
    // APP端本地动画（可选，用于UI反馈）
    _cycleTimer?.cancel();
    _cycleTimer = Timer.periodic(_cycleInterval, _onCycleTick);
    debugPrint('🔄 流水灯启动，间隔: ${_cycleInterval.inMilliseconds}ms');
  }

  void _stopCycleAnimation({bool sendCommand = true, bool fromDispose = false}) {
    _cycleTimer?.cancel();
    _cycleTimer = null;
    
    // 🔄 发送流水灯关闭命令到硬件端（仅在 mounted 时发送）
    if (sendCommand && mounted && !fromDispose) {
      try {
        final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
        if (btProvider.isConnected) {
          btProvider.setStreamlightMode(false);
          debugPrint('⏹️ 流水灯停止 - 已发送硬件命令');
        }
      } catch (e) {
        debugPrint('⚠️ 无法发送流水灯停止命令: $e');
      }
    }
    
    // ⚠️ 在 dispose 期间不能调用 setState，直接修改状态
    if (fromDispose) {
      _isCycling = false;
    } else if (mounted) {
      setState(() => _isCycling = false);
    }
    debugPrint('⏹️ 流水灯停止');
  }

  void _updateCycleSpeed(double newSpeed) {
    setState(() => _cycleSpeed = newSpeed);
    if (_isCycling) {
      _cycleTimer?.cancel();
      _cycleTimer = Timer.periodic(_cycleInterval, _onCycleTick);
      debugPrint('🔄 速度更新，新间隔: ${_cycleInterval.inMilliseconds}ms');
    }
  }

  void _onCycleTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }

    setState(() {
      for (int i = 0; i < 4; i++) {
        final pos = _cyclePositions[i];
        final preset = _ledColorCapsules[_cycleColorIndex];
        final led2 = preset['led2'] as Map<String, int>;
        final led3 = preset['led3'] as Map<String, int>;

        if (i == _cyclePositionIndex) {
          _redValues[pos] = led2['r']!;
          _greenValues[pos] = led2['g']!;
          _blueValues[pos] = led2['b']!;
        } else {
          _redValues[pos] = (led3['r']! * 0.4).toInt();
          _greenValues[pos] = (led3['g']! * 0.4).toInt();
          _blueValues[pos] = (led3['b']! * 0.4).toInt();
        }
      }

      _cyclePositionIndex = (_cyclePositionIndex + 1) % 4;
      if (_cyclePositionIndex == 0) {
        _cycleColorIndex = (_cycleColorIndex + 1) % _ledColorCapsules.length;
      }
    });

    _syncAllLEDColors();
  }

  void _syncAllLEDColors() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    // 🔄 使用节流器控制发送频率（50ms间隔）
    if (!_colorizeThrottler.canSend()) return;

    final posMap = {'M': 1, 'L': 2, 'R': 3, 'B': 4};
    final positions = ['M', 'L', 'R', 'B'];

    for (String pos in positions) {
      final strip = posMap[pos]!;
      final r = _redValues[pos]!.clamp(0, 255);
      final g = _greenValues[pos]!.clamp(0, 255);
      final b = _blueValues[pos]!.clamp(0, 255);

      await btProvider.setLEDColor(strip, r, g, b);
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 📱 菜单和对话框
  // ═══════════════════════════════════════════════════════════════════

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
      MaterialPageRoute(builder: (context) => const LogoUploadE2ETestScreen()),
    ).then((_) {
      // 返回后恢复硬件UI
      if (mounted && btProvider.isConnected && _lastSentHardwareUI == 6) {
        // 0=devTest(不改变), 1=running(UI=1), 2=colorize(UI=2)
        final targetUI = _currentModeIndex == 1 ? 1 : (_currentModeIndex == 2 ? 2 : _lastSentHardwareUI);
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
      if (_colorizeState == ColorizeState.rgbDetail) {
        HapticFeedback.lightImpact();
        setState(() => _colorizeState = ColorizeState.preset);
        // 仅在没有自定义颜色时才同步预设到硬件，避免覆盖用户自定义的 RGB 值
        if (!_hasCustomColors) {
          _syncPresetToHardware(_selectedColorIndex);
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
          child: _PowerSliderDialog(
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
        if (!(_currentMode == ControlMode.colorize && _colorizeState == ColorizeState.rgbDetail))
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
        if (_currentMode == ControlMode.colorize && _colorizeState == ColorizeState.rgbDetail && _showDetailedTuning)
          _buildDetailedTuningOverlay(config),

        // ========== 🧪 调试：引导系统触发按钮（仅 Dev Test 页面可见）==========
        if (_currentModeIndex == 0)
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDebugGuideButton('Running 引导', Icons.directions_car, () {
                  _debugResetAndShowGuide(GuideType.runningMode);
                }),
                const SizedBox(width: 12),
                _buildDebugGuideButton('Colorize 引导', Icons.palette, () {
                  _debugResetAndShowGuide(GuideType.colorizeMode);
                }),
              ],
            ),
          ),
      ],
    );
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🎛️ 主界面UI（简化后：上半部分固定，下半部分左右滑动）                   ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Widget _buildMainUI() {
    debugPrint('🏗️ _buildMainUI 开始构建');
    final config = _DeviceConnectConfig(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final dividerPosition = screenHeight * 0.45;
    
    // 🔧 获取屏幕尺寸用于图片缓存优化
    final screenSize = MediaQuery.of(context).size;
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    // 限制缓存尺寸，防止大图片导致内存问题
    final cacheWidth = (screenSize.width * devicePixelRatio).toInt().clamp(100, 1080);
    final cacheHeight = (screenSize.height * devicePixelRatio).toInt().clamp(100, 2400);
    
    debugPrint('🏗️ 屏幕尺寸: ${screenSize.width}x${screenSize.height}, 背景图: ${_getBackgroundImage()}');
    
    return Stack(
      children: [
        // ========== 🔧 纯色背景（后备方案，防止图片加载失败时黑屏）==========
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D0D0D),
                  Color(0xFF1A1A1A),
                  Color(0xFF0D0D0D),
                ],
              ),
            ),
          ),
        ),
        
        // ========== 🖼️ 背景图（使用 FadeInImage 确保加载过程可见）==========
        Positioned.fill(
          child: Builder(
            builder: (context) {
              final imagePath = _getBackgroundImage();
              return Image.asset(
                imagePath,
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                cacheHeight: cacheHeight,
                gaplessPlayback: true, // 防止切换时闪烁
                // 🔧 frameBuilder 确保即使图片未加载完成也能显示占位内容
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return child; // 图片已加载，显示图片
                  }
                  // 图片正在加载，显示渐变背景
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0D0D0D),
                          Color(0xFF1A1A1A),
                          Color(0xFF0D0D0D),
                        ],
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('❌ 背景图片加载失败: $error');
                  // 🔧 错误时显示渐变背景而不是红色，保持UI美观
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0D0D0D),
                          Color(0xFF1A1A1A),
                          Color(0xFF0D0D0D),
                        ],
                      ),
                    ),
                  );
                },
              );
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
          top: config.carImageTop,
          bottom: screenHeight - dividerPosition,
          left: config.carImageLeft,
          right: config.carImageRight,
          child: GestureDetector(
            onTap: () async {
              // 单击：切换雾化器
              HapticFeedback.mediumImpact();
              debugPrint('🚗 单击车模型 → 切换雾化器');

              final btProvider = Provider.of<BluetoothProvider>(
                context,
                listen: false,
              );
              bool newState = !_isAirflowStarted;
              bool success = await btProvider.setWuhuaqiStatus(newState);

              if (success) {
                setState(() => _isAirflowStarted = newState);
                // 🌫️ 使用控制器显示短暂指示器
                if (newState) {
                  _airflowController.showOnIndicator();
                } else {
                  _airflowController.showOffIndicator();
                }
                // 💾 保存雾化器状态
                _preferenceService.saveAtomizerState(newState);
                debugPrint('✅ 雾化器${newState ? "开启" : "关闭"}');
                if (mounted) {
                  FeedbackService.showSuccess(context, '雾化器${newState ? "已开启" : "已关闭"}');
                }
              } else {
                debugPrint('❌ 雾化器命令发送失败');
                if (mounted) {
                  FeedbackService.showError(
                    context,
                    '雾化器控制失败',
                    onRetry: () async {
                      bool retrySuccess = await btProvider.setWuhuaqiStatus(newState);
                      if (retrySuccess && mounted) {
                        setState(() => _isAirflowStarted = newState);
                        // 🌫️ 使用控制器显示短暂指示器
                        if (newState) {
                          _airflowController.showOnIndicator();
                        } else {
                          _airflowController.showOffIndicator();
                        }
                        // 💾 保存雾化器状态
                        _preferenceService.saveAtomizerState(newState);
                        FeedbackService.showSuccess(context, '雾化器${newState ? "已开启" : "已关闭"}');
                      }
                    },
                  );
                }
              }
            },
            onLongPress: () {
              // 长按：显示关机/重启对话框
              debugPrint('⏱️ 长按车模型 → 显示关机/重启对话框');
              _showPowerDialog(context);
            },
            child: Container(
              color: _debugMode
                  ? Colors.blue.withAlpha(51)
                  : Colors.transparent,
              child: _debugMode
                  ? const Center(
                      child: Text(
                        '单击:雾化器\n长按:关机',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    )
                  : null,
            ),
          ),
        ),

        // ========== 📄 下半部分内容区域（左右滑动切换模式）==========
        Positioned(
          top: dividerPosition,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            // 🔧 添加半透明深色背景，确保调速界面在任何背景图片上都能显示
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(77),
                  Colors.black.withAlpha(128),
                  Colors.black.withAlpha(179),
                ],
              ),
            ),
            child: ClipRect(child: _buildModeContentArea(config)),
          ),
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
              decoration: BoxDecoration(
                color: _debugMode
                    ? Colors.red.withAlpha(77)
                    : Colors.transparent,
                border: _debugMode
                    ? Border.all(color: Colors.red, width: 3)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        // ========== 📋 菜单按钮（RGB详细调节时隐藏）==========
        if (!(_currentMode == ControlMode.colorize &&
            _colorizeState == ColorizeState.rgbDetail))
          Positioned(
            top: config.menuButtonTop,
            right: config.menuButtonRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // 🔑 确保透明区域也能响应点击
              onTap: () {
                debugPrint('📋 菜单按钮被点击');
                _showDeviceMenu(context);
              },
              child: Container(
                width: config.menuButtonSize,
                height: config.menuButtonSize,
                decoration: BoxDecoration(
                  color: _debugMode
                      ? Colors.blue.withAlpha(77)
                      : Colors.transparent,
                  border: _debugMode
                      ? Border.all(color: Colors.blue, width: 3)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

        // ========== 🌫️ 雾化器状态指示器（短暂显示后自动隐藏）==========
        ValueListenableBuilder<bool>(
          valueListenable: _airflowController.isVisible,
          builder: (context, isVisible, child) {
            if (!isVisible) return const SizedBox.shrink();
            return ValueListenableBuilder<bool>(
              valueListenable: _airflowController.isOn,
              builder: (context, isOn, child) {
                return Positioned(
                  top: config.topButtonTop + 60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isOn 
                              ? Colors.green.withAlpha(204)
                              : Colors.grey.withAlpha(204),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOn ? Icons.water_drop : Icons.water_drop_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isOn ? '雾化器已开启' : '雾化器已关闭',
                              style: const TextStyle(
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
                );
              },
            );
          },
        ),

        // ========== 🎨 RGB 详细调节面板（全屏覆盖层）==========
        if (_currentMode == ControlMode.colorize &&
            _colorizeState == ColorizeState.rgbDetail &&
            _showDetailedTuning)
          _buildDetailedTuningOverlay(config),
      ],
    );
  }

  /// 获取背景图（根据当前模式和状态）
  String _getBackgroundImage() {
    switch (_currentMode) {
      case ControlMode.devTest:
        return 'assets/images/running_mode_no_text.png'; // 测试模式使用默认背景
      case ControlMode.running:
        return 'assets/images/running_mode_no_text.png';
      case ControlMode.colorize:
        switch (_colorizeState) {
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
            _colorizeState = ColorizeState.preset;
            // 重建 PageController 确保 initialPage 对齐当前选中的颜色索引
            _colorPageController.dispose();
            _colorPageController = PageController(
              initialPage: _selectedColorIndex,
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
        DevTestScreen(isVisible: _currentModeIndex == 0), // 🧪 开发测试界面（最左侧）
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
          if (!_hasCustomColors) {
            _syncPresetToHardware(_selectedColorIndex);
          }
        }
        break;
    }
  }

  /// 🎨 查询并同步当前预设到倒三角指示器
  Future<void> _queryAndSyncPreset() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;
    
    // 发送查询命令，响应会通过presetReportStream返回
    // 已在initState中订阅了presetReportStream，会自动更新_selectedColorIndex
    debugPrint('🎨 查询当前LED预设...');
    await btProvider.queryCurrentPreset();
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
        rawDataStream: btProvider.rawDataStream,
        onKeysReady: (keys) {
          setState(() {
            _runningModeKeys = keys;
          });
        },
        onSpeedChanged: (speed) async {
          setState(() => _currentSpeed = speed);
          // 💾 保存速度值（仅在速度稳定时保存，避免频繁写入）
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
        debugMode: _debugMode,
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
      switch (_colorizeState) {
        case ColorizeState.preset:
          return _buildPresetUI(config);
        case ColorizeState.rgbDetail:
          return _buildRGBDetailUI(config);
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

  // ========== Preset UI ==========
  Widget _buildPresetUI(_DeviceConnectConfig config) {
    return Stack(
      children: [
        // 上部分：颜色胶囊条（占据整个区域，但不遮挡底部按钮）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom:
              config.bottomButtonsMarginBottom +
              config.paletteButtonSize +
              20, // 为按钮区域留出空间
          child: Center(child: KeyedSubtree(key: _colorCapsuleStripKey, child: _buildColorCapsulesLayer())),
        ),
        // 底部：按钮区域（固定在底部）
        Positioned(
          left: config._isSmallScreen ? 15 : 20,
          right: config._isSmallScreen ? 10 : 15,
          bottom: config.bottomButtonsMarginBottom,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // "开始涂色" 按钮区域 - 点击开始/停止转盘
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    debugPrint('👆 点击开始涂色按钮，当前状态: $_isSpinning');
                    HapticFeedback.heavyImpact();
                    if (_isSpinning) {
                      debugPrint('🛑 停止转盘');
                      setState(() {
                        _isSpinning = false;
                        _indicatorOffset = 0;
                        _bounceOffset = 0;
                        _bounceScale = 1.0;
                      });
                    } else {
                      debugPrint('🎰 启动转盘');
                      _startSpinAnimation();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    key: _startColoringButtonKey,
                    height: config.startColoringButtonTapHeight,
                    decoration: BoxDecoration(
                      color: _debugMode
                          ? (_isSpinning
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.green.withValues(alpha: 0.3))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        config.startColoringButtonTapHeight / 2,
                      ),
                    ),
                    child: _debugMode
                        ? Center(
                            child: Text(
                              _isSpinning ? '点击停止' : '开始涂色',
                              style: const TextStyle(color: Colors.white),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              SizedBox(width: config._isSmallScreen ? 6 : 8),
              // "调色盘" 按钮区域
              GestureDetector(
                onTap: () async {
                  debugPrint('👆 点击调色盘按钮');
                  HapticFeedback.mediumImpact();
                  setState(() => _colorizeState = ColorizeState.rgbDetail);
                  final btProvider = Provider.of<BluetoothProvider>(
                    context,
                    listen: false,
                  );
                  await btProvider.setHardwareUI(3);
                  _lastSentHardwareUI = 3;
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  key: _paletteButtonKey,
                  width: config.paletteButtonSize,
                  height: config.paletteButtonSize,
                  decoration: BoxDecoration(
                    color: _debugMode
                        ? Colors.orange.withValues(alpha: 0.3)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: _debugMode
                      ? const Center(
                          child: Text(
                            '调色盘',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========== RGB Detail UI ==========
  Widget _buildRGBDetailUI(_DeviceConnectConfig config) {
    // 🔧 添加try-catch防止渲染错误导致白屏
    try {
      return Column(
        children: [
          // 上部分：LMRB 胶囊选择区
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: config._isSmallScreen ? 5 : 10),
              child: Center(child: KeyedSubtree(key: _lmrbCapsulesKey, child: _buildRGBPositionCapsulesNew(config))),
            ),
          ),
          // 底部：循环速度控制面板
          Padding(
            padding: EdgeInsets.only(
              bottom:
                  config._safeAreaBottom + (config._isSmallScreen ? 30 : 45),
            ),
            child: _buildCycleSpeedPanel(config),
          ),
        ],
      );
    } catch (e, stackTrace) {
      debugPrint('❌ RGB Detail UI 渲染错误: $e');
      debugPrint('📍 堆栈: $stackTrace');
      return Center(
        child: Text(
          '加载失败: $e',
          style: const TextStyle(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🎨 Colorize Mode 子组件                                                ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  Widget _buildDetailedTuningOverlay(_DeviceConnectConfig config) {
    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: () async {
              setState(() => _showDetailedTuning = false);
              _syncLEDColor();
            },
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),

          Positioned(
            top: config.verticalBrightnessTop,
            right: config.menuButtonRight,
            child: KeyedSubtree(key: _brightnessBarKey, child: _buildVerticalBrightnessSlider(config)),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: KeyedSubtree(key: _rgbSlidersKey, child: _buildHighQualityRGBPanel(config)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalBrightnessSlider(_DeviceConnectConfig config) {
    final fillHeight = config.verticalBrightnessHeight * _brightnessValue;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _brightnessValue -= details.delta.dy / 200;
          _brightnessValue = _brightnessValue.clamp(0.0, 1.0);
        });
        _syncBrightness();
      },
      child: Container(
        width: config.verticalBrightnessWidth,
        height: config.verticalBrightnessHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(
            config.verticalBrightnessWidth / 2,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
            // 🌟 亮度越高，外发光越强
            if (_brightnessValue > 0.5)
              BoxShadow(
                color: Colors.white.withValues(
                  alpha: (_brightnessValue - 0.5) * 0.4,
                ),
                blurRadius: 20 * _brightnessValue,
                spreadRadius: 2 * _brightnessValue,
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 亮度填充条
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: fillHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
            // 🔆 底部动态图标：随亮度变化
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 光晕层（亮度高时显示）
                    if (_brightnessValue > 0.5)
                      Container(
                        width: 28 + (_brightnessValue * 12),
                        height: 28 + (_brightnessValue * 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.amber.withValues(
                                alpha: (_brightnessValue - 0.5) * 0.5,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    // 图标本体：缩放 + 颜色 + 实心/空心切换
                    Transform.scale(
                      scale: 0.85 + (_brightnessValue * 0.35), // 0.85 ~ 1.2
                      child: Icon(
                        _brightnessValue > 0.5
                            ? Icons.wb_sunny
                            : Icons.wb_sunny_outlined,
                        color: _brightnessValue > 0.6
                            ? Colors.amber
                            : _brightnessValue > 0.3
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighQualityRGBPanel(_DeviceConnectConfig config) {
    final currentPos = _selectedLightPosition;
    final posName = {
      'L': '左侧灯带',
      'M': '中间灯带',
      'R': '右侧灯带',
      'B': '后部灯带',
    }[currentPos];

    return Container(
      padding: const EdgeInsets.fromLTRB(30, 35, 30, 50),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF151515), const Color(0xFF0A0A0A)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 40,
            offset: const Offset(0, -15),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 25),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🎨 传统色彩圆盘入口按钮
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  debugPrint('🎨 色环按钮被点击');
                  _openChineseColorWheel();
                },
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                    gradient: const SweepGradient(
                      colors: [
                        Color(0xFFFF4500),
                        Color(0xFFE2C100),
                        Color(0xFF2BAE66),
                        Color(0xFF1661AB),
                        Color(0xFF8B2671),
                        Color(0xFFFF4500),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.palette_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              Text(
                posName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          _buildMetallicColorSlider(
            config,
            'R',
            const Color(0xFFFF3D00),
            _redValues[currentPos]!,
            (val) {
              setState(() => _redValues[currentPos] = val.toInt());
              _syncLEDColor();
              _markCustomColors();
            },
          ),
          const SizedBox(height: 15),
          _buildMetallicColorSlider(
            config,
            'G',
            const Color(0xFF00E676),
            _greenValues[currentPos]!,
            (val) {
              setState(() => _greenValues[currentPos] = val.toInt());
              _syncLEDColor();
              _markCustomColors();
            },
          ),
          const SizedBox(height: 15),
          _buildMetallicColorSlider(
            config,
            'B',
            const Color(0xFF2979FF),
            _blueValues[currentPos]!,
            (val) {
              setState(() => _blueValues[currentPos] = val.toInt());
              _syncLEDColor();
              _markCustomColors();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetallicColorSlider(
    _DeviceConnectConfig config,
    String label,
    Color color,
    int value,
    ValueChanged<double> onChanged,
  ) {
    const int segments = 25;
    final int litSegments = (value / 255 * segments).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _editingRGBChannel == label ? Colors.white30 : Colors.white10),
              ),
              child: _editingRGBChannel == label
                  ? SizedBox(
                      width: 48,
                      height: 22,
                      child: TextField(
                        controller: _rgbValueController,
                        focusNode: _rgbValueFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _commitRGBValueEdit(),
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _startRGBValueEdit(label, value),
                      child: Text(
                        value.toString().padLeft(3, '0'),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: config.metallicSliderHeight,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(segments, (index) {
                  final isLit = index < litSegments;
                  return Container(
                    width: 6,
                    height: config.metallicSliderHeight / 2,
                    decoration: BoxDecoration(
                      color: isLit
                          ? color
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: isLit
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: config.metallicSliderHeight,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
                thumbShape: _MechanicalThumbShape(color: color),
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCycleSpeedPanel(_DeviceConnectConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final labelFontSize = screenWidth < 360
        ? 14.0
        : (screenWidth > 414 ? 18.0 : 16.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
          child: Row(
            children: [
              SizedBox(width: screenWidth * 0.02),
              Text(
                '慢',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Container(
                  height: config.cycleSpeedSliderHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(
                      config.cycleSpeedSliderHeight / 2,
                    ),
                    border: Border.all(
                      color: _isCycling
                          ? const Color(0xFFC62828).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: config.cycleSpeedSliderHeight,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: _isCycling
                          ? const Color(0xFFC62828)
                          : Colors.white,
                      thumbShape: _CustomSliderThumbShape(
                        radius: config.cycleSpeedSliderHeight / 2,
                        color: _isCycling
                            ? const Color(0xFFC62828)
                            : Colors.white,
                      ),
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _cycleSpeed,
                      onChanged: (val) {
                        _updateCycleSpeed(val);
                        if (!_isCycling) _startCycleAnimation();
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Text(
                '快',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: screenWidth * 0.02),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildRGBPositionCapsulesNew(_DeviceConnectConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final horizontalPadding = screenWidth * 0.035;
    final letterFontSize = screenWidth < 360
        ? 20.0
        : (screenWidth > 414 ? 30.0 : 24.0);
    final letterSpacing = screenHeight < 700 ? 8.0 : 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['L', 'M', 'R', 'B'].map((pos) {
        final isSelected = _selectedLightPosition == pos;
        return GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            _stopCycleAnimation();
            setState(() => _selectedLightPosition = pos);
            _syncLEDColor();
          },
          onLongPress: () async {
            HapticFeedback.mediumImpact();
            _stopCycleAnimation();
            setState(() {
              _selectedLightPosition = pos;
              _showDetailedTuning = true;
            });
            _syncLEDColor();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: config.rgbCapsuleWidth,
                  height: config.rgbCapsuleHeight,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFC62828) : Colors.white,
                    borderRadius: BorderRadius.circular(
                      config.rgbCapsuleWidth / 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFC62828,
                              ).withValues(alpha: 0.6),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                ),
                SizedBox(height: letterSpacing),
                Text(
                  pos,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: letterFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🎨 颜色胶囊条                                                          ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  // 🎰 转盘模式下的动画状态
  double _indicatorOffset = 0.0;
  double _bounceOffset = 0.0;
  double _bounceScale = 1.0;

  Widget _buildColorCapsulesLayer() {
    final config = _DeviceConnectConfig(context);
    final double capsuleWidth = config.colorCapsuleWidth;
    final double capsuleHeight = config.colorCapsuleHeight;
    final double containerHeight = config.colorCapsuleContainerHeight;
    final double triangleTopOffset = capsuleHeight + 35;
    final double screenWidth = MediaQuery.of(context).size.width;

    final double triangleLeftPosition = screenWidth / 2 - 14 + _indicatorOffset;

    return SizedBox(
      height: containerHeight,
      child: Stack(
        clipBehavior: Clip.none, // 允许三角形指示器超出边界
        children: [
          AnimatedPositioned(
            duration: _isSpinning
                ? const Duration(milliseconds: 30)
                : const Duration(milliseconds: 150),
            top: triangleTopOffset,
            left: triangleLeftPosition,
            child: CustomPaint(
              size: const Size(28, 12),
              painter: _TriangleIndicatorPainter(
                isActive: true,
                currentColor:
                    _ledColorCapsules[_selectedColorIndex]['type'] == 'solid'
                    ? _ledColorCapsules[_selectedColorIndex]['color'] as Color
                    : (_ledColorCapsules[_selectedColorIndex]['colors']
                              as List<Color>)
                          .first,
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: capsuleHeight + 30,
              child: PageView.builder(
                key: _colorPageViewKey,
                controller: _colorPageController,
                padEnds: true,
                physics: _isSpinning
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _selectedColorIndex = index);
                  HapticFeedback.selectionClick();
                  _syncPresetToHardware(index);
                  // 💾 保存颜色预设
                  _preferenceService.saveColorPreset(index);
                },
                itemCount: _ledColorCapsules.length,
                itemBuilder: (context, index) {
                  final capsule = _ledColorCapsules[index];
                  final isSolid = capsule['type'] == 'solid';
                  final distance = (index - _selectedColorIndex).abs();

                  double brightness;
                  if (distance == 0) {
                    brightness = 1.0;
                  } else if (distance == 1) {
                    brightness = 0.7;
                  } else if (distance == 2) {
                    brightness = 0.5;
                  } else {
                    brightness = 0.3;
                  }

                  final double scale = distance == 0 ? 1.15 : 1.0;
                  final double capsuleBorderRadius = capsuleWidth / 2;
                  final double capsuleMargin = config._isSmallScreen
                      ? 6.0
                      : 10.0;

                  return GestureDetector(
                    onTap: () {
                      if (distance != 0 && !_isSpinning) {
                        _colorPageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, _isSpinning ? _bounceOffset : 0),
                        child: Transform.scale(
                          scale: _isSpinning
                              ? (distance == 0
                                    ? _bounceScale * 1.15
                                    : _bounceScale)
                              : scale,
                          child: Container(
                            width: capsuleWidth,
                            height: capsuleHeight,
                            margin: EdgeInsets.symmetric(
                              horizontal: capsuleMargin,
                            ),
                            decoration: BoxDecoration(
                              color: isSolid ? capsule['color'] as Color : null,
                              gradient: !isSolid
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors:
                                          (capsule['colors'] as List<Color>),
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(
                                capsuleBorderRadius,
                              ),
                              boxShadow: distance == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(102),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                      BoxShadow(
                                        color:
                                            (isSolid
                                                    ? capsule['color'] as Color
                                                    : (capsule['colors']
                                                              as List<Color>)
                                                          .first)
                                                .withAlpha(89),
                                        blurRadius: 15,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(
                                      ((1.0 - brightness) * 255).round(),
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      capsuleBorderRadius,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ╔════════════════════════════════════════════════════════════════════════╗
  // ║  🔄 硬件同步方法                                                        ║
  // ╚════════════════════════════════════════════════════════════════════════╝

  void _syncPresetToHardware(int index) async {
    if (_isReceivingPresetReport) {
      debugPrint('🔄 跳过发送预设（正在接收硬件报告）');
      return;
    }

    // 用户主动选择预设时，清除自定义颜色标志和持久化数据
    _hasCustomColors = false;
    _preferenceService.clearCustomRGBColors();

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    _applyPresetToLocalColors(index);
    if (!btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastPresetSyncTime).inMilliseconds < 80) return;
    _lastPresetSyncTime = now;

    if (_lastSentHardwareUI != 2) {
      await btProvider.setHardwareUI(2);
      _lastSentHardwareUI = 2;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    int presetCommandValue = index + 1;
    await btProvider.setLEDPreset(presetCommandValue);
    debugPrint('📤 发送预设指令: PRESET:$presetCommandValue');
  }

  void _applyPresetToLocalColors(int index) {
    if (index < 0 || index >= _ledColorCapsules.length) return;
    if (!mounted) return; // 🔧 修复：确保 mounted 状态

    final preset = _ledColorCapsules[index];
    final led2 = preset['led2'] as Map<String, int>?;
    final led3 = preset['led3'] as Map<String, int>?;

    if (led2 != null && led3 != null) {
      setState(() {
        _redValues['L'] = led2['r']!;
        _greenValues['L'] = led2['g']!;
        _blueValues['L'] = led2['b']!;

        _redValues['M'] = led2['r']!;
        _greenValues['M'] = led2['g']!;
        _blueValues['M'] = led2['b']!;

        _redValues['R'] = led3['r']!;
        _greenValues['R'] = led3['g']!;
        _blueValues['R'] = led3['b']!;

        _redValues['B'] = led3['r']!;
        _greenValues['B'] = led3['g']!;
        _blueValues['B'] = led3['b']!;
      });
    }
  }

  /// 🎨 打开色彩圆环界面
  void _openChineseColorWheel() {
    debugPrint('🎨 _openChineseColorWheel 开始导航');
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            debugPrint('🎨 ColorRingScreen builder 被调用');
            return ColorRingScreen(
              onColorSelected: (r, g, b) {
                final pos = _selectedLightPosition;
                setState(() {
                  _redValues[pos] = r;
                  _greenValues[pos] = g;
                  _blueValues[pos] = b;
                });
                _syncLEDColor();
                _markCustomColors();
              },
            );
          },
        ),
      ).then((_) {
        debugPrint('🎨 导航返回');
      }).catchError((e, stack) {
        debugPrint('🎨 导航异常: $e');
        debugPrint('📍 堆栈: $stack');
      });
      debugPrint('🎨 Navigator.push 已调用');
    } catch (e, stack) {
      debugPrint('🎨 同步异常: $e');
      debugPrint('📍 堆栈: $stack');
    }
  }

  /// 🎨 RGB 数值输入：焦点变化回调
  void _onRGBValueFocusChanged() {
    if (!_rgbValueFocusNode.hasFocus && _editingRGBChannel != null) {
      _commitRGBValueEdit();
    }
  }

  /// 🎨 RGB 数值输入：开始编辑
  void _startRGBValueEdit(String channel, int currentValue) {
    setState(() {
      _editingRGBChannel = channel;
      _rgbValueController.text = currentValue.toString();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rgbValueFocusNode.requestFocus();
      _rgbValueController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _rgbValueController.text.length,
      );
    });
  }

  /// 🎨 RGB 数值输入：提交编辑
  void _commitRGBValueEdit() {
    if (_editingRGBChannel == null) return;
    final channel = _editingRGBChannel!;
    final pos = _selectedLightPosition;
    final text = _rgbValueController.text;
    
    if (text.isNotEmpty) {
      final parsed = int.tryParse(text) ?? 0;
      final clamped = parsed.clamp(0, 255);
      setState(() {
        switch (channel) {
          case 'R': _redValues[pos] = clamped; break;
          case 'G': _greenValues[pos] = clamped; break;
          case 'B': _blueValues[pos] = clamped; break;
        }
        _editingRGBChannel = null;
      });
      _syncLEDColor();
      _markCustomColors();
    } else {
      setState(() => _editingRGBChannel = null);
    }
  }

  /// 标记当前颜色为自定义颜色，并持久化保存
  void _markCustomColors() {
    _hasCustomColors = true;
    _preferenceService.saveHasCustomColors(true);
    _preferenceService.saveCustomRGBColors({
      'L': {'r': _redValues['L']!, 'g': _greenValues['L']!, 'b': _blueValues['L']!},
      'M': {'r': _redValues['M']!, 'g': _greenValues['M']!, 'b': _blueValues['M']!},
      'R': {'r': _redValues['R']!, 'g': _greenValues['R']!, 'b': _blueValues['R']!},
      'B': {'r': _redValues['B']!, 'g': _greenValues['B']!, 'b': _blueValues['B']!},
    });
  }

  void _syncBrightness() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastColorSyncTime).inMilliseconds < 80) return;
    _lastColorSyncTime = now;

    if (_lastSentHardwareUI != 4) {
      await btProvider.setHardwareUI(4);
      _lastSentHardwareUI = 4;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    await btProvider.setBrightness((_brightnessValue * 100).toInt());
  }

  void _syncLEDColor() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastColorSyncTime).inMilliseconds < 80) return;
    _lastColorSyncTime = now;

    if (_lastSentHardwareUI != 3) {
      await btProvider.setHardwareUI(3);
      _lastSentHardwareUI = 3;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final posMap = {'M': 1, 'L': 2, 'R': 3, 'B': 4};
    final strip = posMap[_selectedLightPosition]!;
    final pos = _selectedLightPosition;

    final r = _redValues[pos]!.clamp(0, 255);
    final g = _greenValues[pos]!.clamp(0, 255);
    final b = _blueValues[pos]!.clamp(0, 255);

    await btProvider.setLEDColor(strip, r, g, b);
  }
} // _DeviceConnectScreenState 类结束

// ╔══════════════════════════════════════════════════════════════╗
// ║      🔺 倒三角指示器                                          ║
// ╚══════════════════════════════════════════════════════════════╝

class _TriangleIndicatorPainter extends CustomPainter {
  final bool isActive;
  final Color currentColor;

  _TriangleIndicatorPainter({
    this.isActive = false,
    this.currentColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive ? currentColor : Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final scaleX = size.width / 26.5732421875;
    final scaleY = size.height / 9.5234375;

    final path = Path();
    path.moveTo(14.1659 * scaleX, 0.203846 * scaleY);
    path.lineTo(25.4495 * scaleX, 5.7271 * scaleY);
    path.cubicTo(
      27.3533 * scaleX,
      6.65898 * scaleY,
      26.6899 * scaleX,
      9.52344 * scaleY,
      24.5702 * scaleX,
      9.52344 * scaleY,
    );
    path.lineTo(2.003 * scaleX, 9.52344 * scaleY);
    path.cubicTo(
      -0.116619 * scaleX,
      9.52344 * scaleY,
      -0.780075 * scaleX,
      6.65898 * scaleY,
      1.1237 * scaleX,
      5.7271 * scaleY,
    );
    path.lineTo(12.4073 * scaleX, 0.203846 * scaleY);
    path.cubicTo(
      12.9621 * scaleX,
      -0.0676997 * scaleY,
      13.6112 * scaleX,
      -0.0676997 * scaleY,
      14.1659 * scaleX,
      0.203846 * scaleY,
    );
    path.close();

    if (isActive) {
      canvas.drawShadow(path, Colors.black.withAlpha(102), 4.0, true);

      final glowPaint1 = Paint()
        ..color = currentColor.withAlpha(102)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint1);

      final glowPaint2 = Paint()
        ..color = currentColor.withAlpha(153)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint2);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TriangleIndicatorPainter oldDelegate) {
    return oldDelegate.currentColor != currentColor ||
        oldDelegate.isActive != isActive;
  }
}

/// 自定义滑动条滑块样式
class _CustomSliderThumbShape extends SliderComponentShape {
  final double radius;
  final Color color;

  _CustomSliderThumbShape({this.radius = 24, this.color = Colors.white});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 6, true);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 0.5, borderPaint);
  }
}

// ╔════════════════════════════════════════════════════════════════════════╗
// ║  🎚️ 关机/重启滑动组件                                                  ║
// ╚════════════════════════════════════════════════════════════════════════╝

class _PowerSliderDialog extends StatefulWidget {
  final Future<void> Function() onShutdown;
  final Future<void> Function() onReboot;

  const _PowerSliderDialog({required this.onShutdown, required this.onReboot});

  @override
  State<_PowerSliderDialog> createState() => _PowerSliderDialogState();
}

class _PowerSliderDialogState extends State<_PowerSliderDialog> {
  double _sliderY = 0.0;
  bool _isDragging = false;

  static const double _capsuleWidth = 84.0;
  static const double _capsuleHeight = 320.0;
  static const double _sliderSize = 68.0;
  static const double _triggerThreshold = 60.0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _sliderY += details.delta.dy;
      double maxDrag = (_capsuleHeight - _sliderSize) / 2 - 10;
      _sliderY = _sliderY.clamp(-maxDrag, maxDrag);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) async {
    if (_sliderY <= -_triggerThreshold) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _sliderY = 0.0;
          _isDragging = false;
        });
      }
      await widget.onShutdown();
    } else if (_sliderY >= _triggerThreshold) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() {
          _sliderY = 0.0;
          _isDragging = false;
        });
      }
      await widget.onReboot();
    } else {
      if (mounted) {
        setState(() {
          _sliderY = 0.0;
          _isDragging = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isShutdownActive = _sliderY <= -_triggerThreshold;
    bool isRebootActive = _sliderY >= _triggerThreshold;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '关机',
            style: TextStyle(
              color: Colors.white.withAlpha(isShutdownActive ? 255 : 102),
              fontSize: 14,
              letterSpacing: 4.0,
              fontWeight: isShutdownActive ? FontWeight.bold : FontWeight.w300,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onVerticalDragStart: (_) => setState(() => _isDragging = true),
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            onVerticalDragCancel: () => setState(() {
              _sliderY = 0.0;
              _isDragging = false;
            }),
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(42),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: _capsuleWidth,
                  height: _capsuleHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(42),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 30,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: isShutdownActive ? 1.4 : 1.0,
                          child: Icon(
                            Icons.power_settings_new_rounded,
                            color: Colors.white.withAlpha(
                              isShutdownActive ? 255 : 102,
                            ),
                            size: 36,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: isRebootActive ? 1.4 : 1.0,
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Colors.white.withAlpha(
                              isRebootActive ? 255 : 102,
                            ),
                            size: 36,
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        top: (_capsuleHeight - _sliderSize) / 2 + _sliderY,
                        child: Container(
                          width: _sliderSize,
                          height: _sliderSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: 90 * 3.14159 / 180,
                            child: const Icon(
                              Icons.code_rounded,
                              color: Color(0xFF1A1A1A),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '重启',
            style: TextStyle(
              color: Colors.white.withAlpha(isRebootActive ? 255 : 102),
              fontSize: 14,
              letterSpacing: 4.0,
              fontWeight: isRebootActive ? FontWeight.bold : FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

class _MechanicalThumbShape extends SliderComponentShape {
  final Color color;
  const _MechanicalThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 30);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 14, height: 24),
        const Radius.circular(4),
      ),
      paint,
    );

    final innerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 8, height: 18),
        const Radius.circular(2),
      ),
      innerPaint,
    );
  }
}
