import 'dart:async';
import 'package:flutter/material.dart';
import '../data/led_presets.dart';
import '../providers/bluetooth_provider.dart';
import '../services/preference_service.dart';

/// Colorize 子模式枚举
enum ColorizeState {
  preset, // 对应配色预设界面 (hardware ui=2)
  rgbDetail, // 对应 RGB 调色界面 (hardware ui=3)
}

/// Colorize 模式状态控制器
///
/// 管理 LED 预设选择、RGB 调色、流水灯循环、亮度等状态。
/// 从 DeviceConnectScreen 提取，通过 get_it 注入。
class ColorizeController extends ChangeNotifier {
  final BluetoothProvider _btProvider;
  final PreferenceService _preferenceService = PreferenceService();

  // ── 核心状态 ──
  ColorizeState _colorizeState = ColorizeState.preset;
  int _selectedColorIndex = 0;
  bool _hasCustomColors = false;
  String _selectedLightPosition = 'B';
  double _brightnessValue = 1.0;
  bool _showDetailedTuning = false;

  // ── RGB 四区颜色值 ──
  final Map<String, int> _redValues = {'L': 150, 'M': 150, 'R': 150, 'B': 200};
  final Map<String, int> _greenValues = {'L': 20, 'M': 20, 'R': 20, 'B': 50};
  final Map<String, int> _blueValues = {'L': 0, 'M': 0, 'R': 0, 'B': 0};

  // ── 流水灯 ──
  Timer? _cycleTimer;
  bool _isCycling = false;
  int _cycleColorIndex = 0;
  int _cyclePositionIndex = 0;
  double _cycleSpeed = 0.5;
  final List<String> _cyclePositions = ['L', 'M', 'R', 'B'];

  // ── 转盘动画 ──
  bool _isSpinning = false;
  double _indicatorOffset = 0.0;
  double _bounceOffset = 0.0;
  double _bounceScale = 1.0;

  // ── RGB 手动输入 ──
  String? _editingRGBChannel;
  final TextEditingController rgbValueController = TextEditingController();
  final FocusNode rgbValueFocusNode = FocusNode();

  // ── 硬件同步节流 ──
  int _lastSentHardwareUI = -1;
  DateTime _lastColorSyncTime = DateTime.now();
  DateTime _lastPresetSyncTime = DateTime.now();
  bool _isReceivingPresetReport = false;

  // ── 预设数据 ──
  List<Map<String, dynamic>> get ledColorCapsules => ledPresetMaps;

  // ── Getters ──
  ColorizeState get colorizeState => _colorizeState;
  int get selectedColorIndex => _selectedColorIndex;
  bool get hasCustomColors => _hasCustomColors;
  String get selectedLightPosition => _selectedLightPosition;
  double get brightnessValue => _brightnessValue;
  bool get showDetailedTuning => _showDetailedTuning;
  bool get isCycling => _isCycling;
  double get cycleSpeed => _cycleSpeed;
  bool get isSpinning => _isSpinning;
  double get indicatorOffset => _indicatorOffset;
  double get bounceOffset => _bounceOffset;
  double get bounceScale => _bounceScale;
  String? get editingRGBChannel => _editingRGBChannel;
  bool get isReceivingPresetReport => _isReceivingPresetReport;
  int get lastSentHardwareUI => _lastSentHardwareUI;
  set lastSentHardwareUI(int value) => _lastSentHardwareUI = value;

  Map<String, int> get redValues => _redValues;
  Map<String, int> get greenValues => _greenValues;
  Map<String, int> get blueValues => _blueValues;

  ColorizeController(this._btProvider) {
    rgbValueFocusNode.addListener(_onRGBValueFocusChanged);
  }

  // ═══════════════════════════════════════════════════════════════
  //  状态切换
  // ═══════════════════════════════════════════════════════════════

  void setColorizeState(ColorizeState state) {
    _colorizeState = state;
    notifyListeners();
  }

  void setSelectedColorIndex(int index) {
    _selectedColorIndex = index;
    notifyListeners();
  }

  void setSelectedLightPosition(String pos) {
    _selectedLightPosition = pos;
    notifyListeners();
  }

  void setShowDetailedTuning(bool show) {
    _showDetailedTuning = show;
    notifyListeners();
  }

  void setSpinning(bool spinning) {
    _isSpinning = spinning;
    if (!spinning) {
      _indicatorOffset = 0;
      _bounceOffset = 0;
      _bounceScale = 1.0;
    }
    notifyListeners();
  }

  void updateSpinAnimationFrame({
    required double indicatorOffset,
    required double bounceOffset,
    required double bounceScale,
    required int selectedIndex,
  }) {
    _indicatorOffset = indicatorOffset;
    _bounceOffset = bounceOffset;
    _bounceScale = bounceScale;
    _selectedColorIndex = selectedIndex;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  //  预设同步
  // ═══════════════════════════════════════════════════════════════

  /// 硬件预设报告回调（由 presetReportStream 驱动）
  void onPresetReport(int preset) {
    final appIndex = preset - 1;
    if (appIndex >= 0 && appIndex < ledColorCapsules.length) {
      debugPrint('🎨 收到硬件预设报告: $preset -> APP索引: $appIndex');
      _isReceivingPresetReport = true;
      _selectedColorIndex = appIndex;
      applyPresetToLocalColors(appIndex);
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 150), () {
        _isReceivingPresetReport = false;
      });
    }
  }

  /// 硬件流水灯状态报告回调
  void onStreamlightReport(bool isEnabled) {
    debugPrint('🔄 收到硬件流水灯状态: ${isEnabled ? "开启" : "关闭"}');
    _isCycling = isEnabled;
    notifyListeners();
  }

  Future<void> syncPresetToHardware(int index) async {
    if (_isReceivingPresetReport) {
      debugPrint('🔄 跳过发送预设（正在接收硬件报告）');
      return;
    }

    _hasCustomColors = false;
    _preferenceService.clearCustomRGBColors();

    applyPresetToLocalColors(index);
    if (!_btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastPresetSyncTime).inMilliseconds < 80) return;
    _lastPresetSyncTime = now;

    if (_lastSentHardwareUI != 2) {
      await _btProvider.setHardwareUI(2);
      _lastSentHardwareUI = 2;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    int presetCommandValue = index + 1;
    await _btProvider.setLEDPreset(presetCommandValue);
    debugPrint('📤 发送预设指令: PRESET:$presetCommandValue');
  }

  void applyPresetToLocalColors(int index) {
    if (index < 0 || index >= ledColorCapsules.length) return;

    final preset = ledColorCapsules[index];
    final led2 = preset['led2'] as Map<String, int>?;
    final led3 = preset['led3'] as Map<String, int>?;

    if (led2 != null && led3 != null) {
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
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  RGB 调色
  // ═══════════════════════════════════════════════════════════════

  void setRedValue(String pos, int value) {
    _redValues[pos] = value;
    notifyListeners();
  }

  void setGreenValue(String pos, int value) {
    _greenValues[pos] = value;
    notifyListeners();
  }

  void setBlueValue(String pos, int value) {
    _blueValues[pos] = value;
    notifyListeners();
  }

  void setBrightnessValue(double value) {
    _brightnessValue = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void markCustomColors() {
    _hasCustomColors = true;
    _preferenceService.saveHasCustomColors(true);
    _preferenceService.saveCustomRGBColors({
      'L': {'r': _redValues['L']!, 'g': _greenValues['L']!, 'b': _blueValues['L']!},
      'M': {'r': _redValues['M']!, 'g': _greenValues['M']!, 'b': _blueValues['M']!},
      'R': {'r': _redValues['R']!, 'g': _greenValues['R']!, 'b': _blueValues['R']!},
      'B': {'r': _redValues['B']!, 'g': _greenValues['B']!, 'b': _blueValues['B']!},
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  硬件同步
  // ═══════════════════════════════════════════════════════════════

  Future<void> syncLEDColor() async {
    if (!_btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastColorSyncTime).inMilliseconds < 80) return;
    _lastColorSyncTime = now;

    if (_lastSentHardwareUI != 3) {
      await _btProvider.setHardwareUI(3);
      _lastSentHardwareUI = 3;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final posMap = {'M': 1, 'L': 2, 'R': 3, 'B': 4};
    final strip = posMap[_selectedLightPosition]!;
    final pos = _selectedLightPosition;

    final r = _redValues[pos]!.clamp(0, 255);
    final g = _greenValues[pos]!.clamp(0, 255);
    final b = _blueValues[pos]!.clamp(0, 255);

    await _btProvider.setLEDColor(strip, r, g, b);
  }

  Future<void> syncBrightness() async {
    if (!_btProvider.isConnected) return;

    final now = DateTime.now();
    if (now.difference(_lastColorSyncTime).inMilliseconds < 80) return;
    _lastColorSyncTime = now;

    // 不切换硬件 LCD 页面 — 直接发送亮度命令
    // 避免用户在 RGB 调色面板拖动亮度时 LCD 跳到亮度页面
    await _btProvider.setBrightness((_brightnessValue * 100).toInt());
  }

  // ═══════════════════════════════════════════════════════════════
  //  流水灯
  // ═══════════════════════════════════════════════════════════════

  void startCycleAnimation() {
    if (_isCycling) return;
    _isCycling = true;
    notifyListeners();

    // 流水灯完全由硬件端控制，APP 只发开关命令
    if (_btProvider.isConnected) {
      _btProvider.setStreamlightMode(true);
      debugPrint('🔄 流水灯启动 - 已发送硬件命令 STREAMLIGHT:1');
    }
  }

  void stopCycleAnimation({bool sendCommand = true}) {
    _cycleTimer?.cancel();
    _cycleTimer = null;

    if (sendCommand && _btProvider.isConnected) {
      _btProvider.setStreamlightMode(false);
      debugPrint('⏹️ 流水灯停止 - 已发送硬件命令 STREAMLIGHT:0');
    }

    _isCycling = false;
    notifyListeners();
  }

  void updateCycleSpeed(double newSpeed) {
    _cycleSpeed = newSpeed;
    notifyListeners();
    // TODO: 如果硬件端支持流水灯速度命令，在这里发送
    // 目前硬件端流水灯速度是固定的
    debugPrint('🔄 流水灯速度更新: $newSpeed（本地 UI 更新，硬件端暂不支持速度调节）');
  }

  // _onCycleTick 已移除 — 流水灯完全由硬件端控制，APP 不再发 LED 命令

  // ═══════════════════════════════════════════════════════════════
  //  RGB 数值手动输入
  // ═══════════════════════════════════════════════════════════════

  void startRGBValueEdit(String channel, int currentValue) {
    _editingRGBChannel = channel;
    rgbValueController.text = currentValue.toString();
    notifyListeners();
  }

  void commitRGBValueEdit() {
    if (_editingRGBChannel == null) return;
    final channel = _editingRGBChannel!;
    final pos = _selectedLightPosition;
    final text = rgbValueController.text;

    if (text.isNotEmpty) {
      final parsed = int.tryParse(text) ?? 0;
      final clamped = parsed.clamp(0, 255);
      switch (channel) {
        case 'R': _redValues[pos] = clamped; break;
        case 'G': _greenValues[pos] = clamped; break;
        case 'B': _blueValues[pos] = clamped; break;
      }
      _editingRGBChannel = null;
      notifyListeners();
      syncLEDColor();
      markCustomColors();
    } else {
      _editingRGBChannel = null;
      notifyListeners();
    }
  }

  void _onRGBValueFocusChanged() {
    if (!rgbValueFocusNode.hasFocus && _editingRGBChannel != null) {
      commitRGBValueEdit();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  偏好恢复
  // ═══════════════════════════════════════════════════════════════

  void saveColorPreset(int index) {
    _preferenceService.saveColorPreset(index);
  }

  // ═══════════════════════════════════════════════════════════════
  //  重置（切换设备时调用）
  // ═══════════════════════════════════════════════════════════════

  /// 重置所有状态到默认值（连接新设备时调用）
  void resetToDefaults() {
    _cycleTimer?.cancel();
    _cycleTimer = null;

    _colorizeState = ColorizeState.preset;
    _selectedColorIndex = 0;
    _hasCustomColors = false;
    _selectedLightPosition = 'B';
    _brightnessValue = 1.0;
    _showDetailedTuning = false;

    _redValues['L'] = 150; _redValues['M'] = 150; _redValues['R'] = 150; _redValues['B'] = 200;
    _greenValues['L'] = 20; _greenValues['M'] = 20; _greenValues['R'] = 20; _greenValues['B'] = 50;
    _blueValues['L'] = 0; _blueValues['M'] = 0; _blueValues['R'] = 0; _blueValues['B'] = 0;

    _isCycling = false;
    _cycleColorIndex = 0;
    _cyclePositionIndex = 0;
    _cycleSpeed = 0.5;
    _isSpinning = false;
    _indicatorOffset = 0;
    _bounceOffset = 0;
    _bounceScale = 1.0;
    _editingRGBChannel = null;
    _lastSentHardwareUI = -1;
    _isReceivingPresetReport = false;

    notifyListeners();
    debugPrint('🎨 ColorizeController 已重置');
  }

  // ═══════════════════════════════════════════════════════════════
  //  清理
  // ═══════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _cycleTimer?.cancel();
    rgbValueController.dispose();
    rgbValueFocusNode.dispose();
    super.dispose();
  }
}
