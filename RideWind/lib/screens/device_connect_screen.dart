// Device Connect Screen - refactored to delegate business logic
// to DeviceSessionController (Phase 2).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../controllers/airflow_indicator_controller.dart';
import '../controllers/device_session_controller.dart';
import '../widgets/running_mode_widget.dart';
import '../widgets/enhanced_guide_overlay.dart';
import '../widgets/guide_tooltip_styles.dart';
import '../widgets/device_connect_helpers.dart';
import '../models/guide_models.dart';
import '../services/feature_guide_service.dart';
import '../configs/device_connect_config.dart';
import '../controllers/colorize_controller.dart';
import '../core/service_locator.dart';
import '../services/ble_connection_manager.dart';
import '../widgets/colorize_preset_view.dart';
import '../widgets/colorize_rgb_detail_view.dart';
import 'no_device_screen.dart';
import 'dialogs/device_dialogs.dart' as device_dialogs;

enum ControlMode { running, colorize, rgb }

typedef _DeviceConnectConfig = DeviceConnectConfig;

class DeviceConnectScreen extends StatefulWidget {
  final DeviceModel device;
  const DeviceConnectScreen({super.key, required this.device});
  @override
  State<DeviceConnectScreen> createState() => _DeviceConnectScreenState();
}

class _DeviceConnectScreenState extends State<DeviceConnectScreen>
    with WidgetsBindingObserver {
  // ==================================================================
  //  Controller (business logic)
  // ==================================================================
  late final DeviceSessionController _session;

  // ==================================================================
  //  UI-only state
  // ==================================================================
  late PageController _modePageController;
  late PageController _colorPageController;
  Key _colorPageViewKey = UniqueKey();

  final AirflowIndicatorController _airflowController =
      AirflowIndicatorController();

  // Guide system
  final FeatureGuideService _featureGuideService = FeatureGuideService();
  OverlayEntry? _guideOverlayEntry;
  bool _hasCheckedRunningModeGuide = false;
  bool _hasCheckedColorizeModeGuide = false;

  // Guide target keys
  final GlobalKey _carImageKey = GlobalKey(debugLabel: 'carImage');
  final GlobalKey _lowerHalfKey = GlobalKey(debugLabel: 'lowerHalf');
  final GlobalKey _colorCapsuleStripKey =
      GlobalKey(debugLabel: 'colorCapsuleStrip');
  final GlobalKey _startColoringButtonKey =
      GlobalKey(debugLabel: 'startColoringButton');
  final GlobalKey _paletteButtonKey = GlobalKey(debugLabel: 'paletteButton');
  final GlobalKey _lmrbCapsulesKey = GlobalKey(debugLabel: 'lmrbCapsules');
  final GlobalKey _rgbSlidersKey = GlobalKey(debugLabel: 'rgbSliders');
  final GlobalKey _brightnessBarKey = GlobalKey(debugLabel: 'brightnessBar');
  Map<String, GlobalKey> _runningModeKeys = {};
  final GlobalKey<RunningModeWidgetState> _runningModeStateKey =
      GlobalKey<RunningModeWidgetState>(debugLabel: 'runningModeState');

  // Event subscriptions from controller
  StreamSubscription<int>? _presetPageSub;

  ControlMode get _currentMode {
    switch (_session.currentModeIndex) {
      case 0: return ControlMode.running;
      case 1: return ControlMode.colorize;
      case 2: return ControlMode.rgb;
      default: return ControlMode.running;
    }
  }

  static const bool _debugMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _session = createDeviceSessionController(widget.device);

    _modePageController = PageController(initialPage: 0);
    _colorPageController = PageController(
      initialPage: 0,
      viewportFraction: 0.155,
    );

    // Listen to BLE state machine for disconnect (only fires on BleState.failed)
    final bleMgr = sl<BleConnectionManager>();
    bleMgr.addListener(_onBleManagerStateChanged);

    _presetPageSub = _session.onPresetPageChanged.listen((appIndex) {
      if (mounted && _colorPageController.hasClients) {
        _colorPageController.animateToPage(
          appIndex,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    _session.addListener(_onSessionChanged);
    _session.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowRunningModeGuide();
      _restorePreferencesAndRebuildPageController();
    });
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onBleManagerStateChanged() {
    if (!mounted) return;
    final bleMgr = sl<BleConnectionManager>();
    if (bleMgr.state == BleState.failed) {
      _showDisconnectDialog();
    }
  }

  Future<void> _restorePreferencesAndRebuildPageController() async {
    final restoredIndex = await _session.restorePreferences();
    if (restoredIndex > 0 && mounted) {
      _colorPageController.dispose();
      _colorPageController = PageController(
        initialPage: restoredIndex,
        viewportFraction: 0.155,
      );
      _colorPageViewKey = UniqueKey();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    sl<BleConnectionManager>().removeListener(_onBleManagerStateChanged);
    _presetPageSub?.cancel();
    _modePageController.dispose();
    _colorPageController.dispose();
    _airflowController.dispose();
    _guideOverlayEntry?.remove();
    _guideOverlayEntry = null;
    _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _session.onAppResumed();
    } else if (state == AppLifecycleState.paused) {
      _session.onAppPaused();
    }
  }

  // ==================================================================
  //  Dialogs
  // ==================================================================

  void _showDisconnectDialog() {
    device_dialogs.showDisconnectDialog(
      context,
      onReturnToList: () {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
      onReconnect: () => _attemptReconnect(),
    );
  }

  Future<void> _attemptReconnect() async {
    final success = await _session.attemptReconnect();
    if (mounted && !success) {
      _showReconnectFailedDialog();
    }
  }

  void _showReconnectFailedDialog() {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    device_dialogs.showReconnectFailedDialog(
      context,
      btProvider: btProvider,
      onReturnToList: () {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
    );
  }

  void _showDeviceMenu(BuildContext context) {
    device_dialogs.showDeviceMenu(
      context,
      onLogoUpload: () { if (mounted) _showLogoUploadScreen(context); },
      onOtaUpgrade: () { if (mounted) _navigateToOtaUpgrade(context); },
      onWifiProvisioning: () { if (mounted) _showWifiProvisioningDialog(context); },
      onRemoveDevice: () { if (mounted) _showRemoveDeviceDialog(context); },
    );
  }

  void _showLogoUploadScreen(BuildContext parentContext) {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    device_dialogs.navigateToLogoUpload(
      context,
      btProvider: btProvider,
      lastSentHardwareUI: _session.lastSentHardwareUI,
      currentModeIndex: _session.currentModeIndex,
      onHardwareUIChanged: (val) { _session.lastSentHardwareUI = val; },
    );
  }

  void _navigateToOtaUpgrade(BuildContext parentContext) {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    device_dialogs.navigateToOtaUpgrade(context, btProvider: btProvider);
  }

  void _showWifiProvisioningDialog(BuildContext parentContext) {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    device_dialogs.showWifiProvisioningDialog(context, btProvider: btProvider);
  }

  void _showRemoveDeviceDialog(BuildContext context) {
    device_dialogs.showRemoveDeviceDialog(
      context,
      device: widget.device,
      onDeviceRemoved: () { Navigator.of(this.context).pop(); },
    );
  }

  void _showPowerDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PowerDialog',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: PowerSliderDialog(
            onShutdown: () async {
              Navigator.of(ctx).pop();
              HapticFeedback.heavyImpact();
              await _session.performShutdown();
            },
            onReboot: () async {
              Navigator.of(ctx).pop();
              HapticFeedback.heavyImpact();
              await _session.performReboot();
            },
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
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

  // ==================================================================
  //  Back Navigation
  // ==================================================================

  Future<void> _handleBackNavigation() async {
    if (_currentMode == ControlMode.rgb) {
      HapticFeedback.lightImpact();
      _modePageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
      _session.colorize.syncCapsuleToHardware(
          _session.colorize.selectedColorIndex);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NoDeviceScreen()),
      );
    }
  }

  // ==================================================================
  //  Build
  // ==================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
          backgroundColor: Colors.black, body: _buildMainUIFixed()),
    );
  }

  Widget _buildMainUIFixed() {
    final config = _DeviceConnectConfig(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final dividerPosition = screenHeight * 0.45;

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            _getBackgroundImage(),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: Colors.black);
            },
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          height: config.topGradientHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black, Colors.black,
                    Colors.black.withAlpha(200), Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Car image area (tap=atomizer, long press=power)
        Positioned(
          key: _carImageKey,
          top: config.carImageTop,
          bottom: screenHeight - dividerPosition,
          left: config.carImageLeft,
          right: config.carImageRight,
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              final success = await _session.toggleAirflow();
              if (success) {
                if (_session.isAirflowOn) {
                  _airflowController.showOnIndicator();
                } else {
                  _airflowController.showOffIndicator();
                }
              }
            },
            onLongPress: () => _showPowerDialog(context),
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          key: _lowerHalfKey,
          top: dividerPosition, left: 0, right: 0, bottom: 0,
          child: ClipRect(child: _buildModeContentArea(config)),
        ),
        Positioned(
          top: config.backButtonTop, left: config.backButtonLeft,
          child: GestureDetector(
            onTap: _handleBackNavigation,
            child: Container(
              width: config.backButtonSize,
              height: config.backButtonSize,
              color: Colors.transparent,
            ),
          ),
        ),
        if (_currentMode != ControlMode.rgb)
          Positioned(
            top: config.menuButtonTop, right: config.menuButtonRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showDeviceMenu(context),
              child: Container(
                width: config.menuButtonSize,
                height: config.menuButtonSize,
                color: Colors.transparent,
              ),
            ),
          ),
        // Atomizer indicator
        Positioned(
          top: config.topButtonTop + 60, left: 0, right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: _airflowController.isVisible,
            builder: (context, isVisible, child) {
              if (!isVisible) return const SizedBox.shrink();
              return ValueListenableBuilder<bool>(
                valueListenable: _airflowController.isOn,
                builder: (context, isOn, _) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(230),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 12, offset: const Offset(0, 4),
                        )],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(isOn ? Icons.water_drop : Icons.water_drop_outlined,
                            color: Colors.black87, size: 16),
                        const SizedBox(width: 8),
                        Text(isOn ? '雾化器已开启' : '雾化器已关闭',
                          style: const TextStyle(color: Colors.black87,
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_currentMode == ControlMode.rgb)
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _session.colorize,
              builder: (context, _) {
                if (!_session.colorize.showDetailedTuning) {
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

  String _getBackgroundImage() {
    switch (_currentMode) {
      case ControlMode.running:
        return 'assets/images/running_mode_no_text.png';
      case ControlMode.colorize:
        return 'assets/images/colorize_mode_no_text.png';
      case ControlMode.rgb:
        return 'assets/images/rgb_settings_clean.png';
    }
  }

  Widget _buildModeContentArea(_DeviceConnectConfig config) {
    return PageView(
      controller: _modePageController,
      physics: const PageScrollPhysics(),
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        _session.setModeIndex(index);
        if (index == 1) {
          _session.colorize.setColorizeState(ColorizeState.preset);
          _colorPageController.dispose();
          _colorPageController = PageController(
            initialPage: _session.colorize.selectedColorIndex,
            viewportFraction: 0.155,
          );
          _colorPageViewKey = UniqueKey();
        }
        _session.syncHardwareUIOnModeChange(index);
        if (index == 1) _checkAndShowColorizeModeGuide();
      },
      children: [
        _buildRunningModeContent(config),
        _buildColorizeModeContent(config),
        _buildRGBContent(config),
      ],
    );
  }

  Widget _buildRGBContent(_DeviceConnectConfig config) {
    try {
      return ColorizeRGBDetailView(
        lmrbCapsulesKey: _lmrbCapsulesKey,
        rgbSlidersKey: _rgbSlidersKey,
        brightnessBarKey: _brightnessBarKey,
        debugMode: _debugMode,
      );
    } catch (e) {
      return const Center(
          child: Text('加载失败', style: TextStyle(color: Colors.white)));
    }
  }

  Widget _buildRunningModeContent(_DeviceConnectConfig config) {
    try {
      return Consumer<BluetoothProvider>(
        builder: (context, btProvider, child) {
          return RunningModeWidget(
            key: _runningModeStateKey,
            initialSpeed: _session.currentSpeed,
            maxSpeed: _session.maxSpeed,
            initialShowSpeedControl: true,
            externalSpeedStream: btProvider.speedReportStream,
            externalThrottleStream: btProvider.throttleReportStream,
            externalUnitStream: btProvider.unitReportStream,
            connectionStream: btProvider.connectionStream,
            isConnected: btProvider.isConnected,
            onKeysReady: (keys) { setState(() { _runningModeKeys = keys; }); },
            onSpeedChanged: (speed) => _session.setSpeed(speed),
            onUnitChanged: (isMetric) => _session.setSpeedUnit(isMetric),
            onThrottleStatusChanged: (isThrottling) =>
                _session.setThrottleMode(isThrottling),
            onEmergencyStop: () => _session.emergencyStop(),
            onSpeedControlVisibilityChanged: null,
            onGarageSettingsApplied: (settings) {
              _session.setMaxSpeed(settings.maxSpeed);
            },
          );
        },
      );
    } catch (e) {
      return Container(color: Colors.black, child: const Center(
        child: Text('Running Mode 加载失败',
            style: TextStyle(color: Colors.white))));
    }
  }

  Widget _buildColorizeModeContent(_DeviceConnectConfig config) {
    try {
      return ColorizePresetView(
        colorPageController: _colorPageController,
        colorPageViewKey: _colorPageViewKey,
        colorCapsuleStripKey: _colorCapsuleStripKey,
        startColoringButtonKey: _startColoringButtonKey,
        paletteButtonKey: _paletteButtonKey,
        debugMode: _debugMode,
        onPaletteTap: () {
          _modePageController.animateToPage(2,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut);
        },
      );
    } catch (e) {
      return const Center(
          child: Text('加载失败', style: TextStyle(color: Colors.white)));
    }
  }

  // ==================================================================
  //  Guide System
  // ==================================================================

  Future<void> _checkAndShowRunningModeGuide() async {
    if (_hasCheckedRunningModeGuide) return;
    _hasCheckedRunningModeGuide = true;
    final shouldShow = await _featureGuideService.shouldShowGuide(
        GuideType.runningMode);
    if (!shouldShow || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) _showRunningModeGuide();
  }

  Future<void> _checkAndShowColorizeModeGuide() async {
    if (_hasCheckedColorizeModeGuide) return;
    _hasCheckedColorizeModeGuide = true;
    final shouldShow = await _featureGuideService.shouldShowGuide(
        GuideType.colorizeMode);
    if (!shouldShow || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) _showColorizeModeGuide();
  }

  void _showRunningModeGuide() {
    final steps = [
      GuideStep(targetKey: _lowerHalfKey, title: '调速界面',
          description: '点击进入调速界面', icon: Icons.touch_app,
          gestureType: GestureType.tap),
      GuideStep(
          targetKey: _runningModeKeys['speedWheel'] ?? _lowerHalfKey,
          title: '速度调节', description: '上下滑动调节速度',
          icon: Icons.swap_vert, gestureType: GestureType.dragVertical,
          demoAction: () async {
            await _runningModeStateKey.currentState?.demoScrollSpeed();
          }),
      GuideStep(
          targetKey: _runningModeKeys['unitLabel'] ?? _lowerHalfKey,
          title: '单位切换', description: '点击切换 km/h 和 mph',
          icon: Icons.speed, gestureType: GestureType.tap,
          demoAction: () async {
            await _runningModeStateKey.currentState?.demoToggleUnit();
          }),
      GuideStep(
          targetKey: _runningModeKeys['throttleButton'] ?? _lowerHalfKey,
          title: '油门加速', description: '长按油门持续加速',
          icon: Icons.rocket_launch, gestureType: GestureType.longPress,
          demoAction: () async {
            await _runningModeStateKey.currentState?.demoThrottle();
          }),
      GuideStep(
          targetKey: _runningModeKeys['emergencyStop'] ?? _lowerHalfKey,
          title: '紧急停止', description: '点击紧急停止归零',
          icon: Icons.emergency, gestureType: GestureType.tap,
          demoAction: () async {
            await _runningModeStateKey.currentState?.demoEmergencyStop();
          }),
      GuideStep(targetKey: _carImageKey, title: '雾化器',
          description: '点击开关雾化器', icon: Icons.water_drop,
          gestureType: GestureType.tap),
      GuideStep(targetKey: _carImageKey, title: '关机 / 重启',
          description: '长按可关机或重启', icon: Icons.power_settings_new,
          gestureType: GestureType.longPress),
      GuideStep(targetKey: _lowerHalfKey, title: '切换模式',
          description: '向左滑动进入颜色模式', icon: Icons.swipe_left,
          gestureType: GestureType.swipeLeft),
    ];
    _guideOverlayEntry = showEnhancedGuideOverlay(
      context: context, steps: steps,
      tooltipStyle: GuideTooltipStyle.glassmorphism,
      onComplete: () async {
        await _featureGuideService.markGuideComplete(GuideType.runningMode);
        _guideOverlayEntry = null;
      },
      onSkip: () async {
        await _featureGuideService.markGuideComplete(GuideType.runningMode);
        _guideOverlayEntry = null;
      },
    );
  }

  void _showColorizeModeGuide() {
    final steps = [
      GuideStep(targetKey: _colorCapsuleStripKey, title: '颜色预设',
          description: '左右滑动选择预设颜色', icon: Icons.swipe,
          gestureType: GestureType.swipeRight),
      GuideStep(targetKey: _startColoringButtonKey, title: '颜色循环',
          description: '点击开始颜色循环动画', icon: Icons.play_circle,
          gestureType: GestureType.tap),
      GuideStep(targetKey: _paletteButtonKey, title: 'RGB 调色',
          description: '点击进入 RGB 详细调色', icon: Icons.palette,
          gestureType: GestureType.tap),
      GuideStep(targetKey: _lmrbCapsulesKey, title: '灯带区域',
          description: '点击选择灯带区域', icon: Icons.highlight,
          gestureType: GestureType.tap),
      GuideStep(targetKey: _lmrbCapsulesKey, title: '详细调色',
          description: '点击灯区打开详细调色面板', icon: Icons.color_lens,
          gestureType: GestureType.tap),
      GuideStep(targetKey: _rgbSlidersKey, title: 'RGB 滑条',
          description: '拖动调节颜色值', icon: Icons.tune,
          gestureType: GestureType.dragHorizontal),
      GuideStep(targetKey: _brightnessBarKey, title: '亮度调节',
          description: '上下拖动调节亮度', icon: Icons.wb_sunny,
          gestureType: GestureType.dragVertical),
    ];
    _guideOverlayEntry = showEnhancedGuideOverlay(
      context: context, steps: steps,
      tooltipStyle: GuideTooltipStyle.glowBorder,
      onComplete: () async {
        await _featureGuideService.markGuideComplete(GuideType.colorizeMode);
        _guideOverlayEntry = null;
      },
      onSkip: () async {
        await _featureGuideService.markGuideComplete(GuideType.colorizeMode);
        _guideOverlayEntry = null;
      },
    );
  }
}
