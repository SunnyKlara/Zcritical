import 'dart:async';
import 'package:flutter/material.dart';
import '../data/custom_preset.dart';
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

  // ── 内置预设 + 用户自定义 ──
  /// 内置 14 个预设（与 ESP32 preset_colors.h 对齐）
  List<Map<String, dynamic>> get ledColorCapsules => ledPresetMaps;

  /// 用户自定义胶囊列表（运行时缓存，启动时从 SharedPreferences 恢复）
  final List<CustomPreset> _customPresets = [];
  List<CustomPreset> get customPresets => List.unmodifiable(_customPresets);

  /// 合并后的胶囊列表（UI 使用）：内置预设 + 自定义 + 末尾 "+" 占位
  ///
  /// 每个 item 多了一个 `kind` 字段:
  ///   - 'preset'  → 内置预设
  ///   - 'custom'  → 用户自定义（含 customId）
  ///   - 'plus'    → 末尾占位的"加号"按钮
  ///
  /// 索引语义:
  ///   [0 .. ledPresets.length-1]                       → 预设
  ///   [ledPresets.length .. ledPresets.length+customs-1] → 自定义
  ///   [last]                                            → "+" 加号
  List<Map<String, dynamic>> get allCapsules {
    final list = <Map<String, dynamic>>[];
    for (final m in ledColorCapsules) {
      list.add({...m, 'kind': 'preset'});
    }
    for (final c in _customPresets) {
      list.add(c.toCapsuleMap());
    }
    list.add({'kind': 'plus'});
    return list;
  }

  /// 内置预设数量（用于索引边界判断）
  int get presetCount => ledColorCapsules.length;

  /// "+" 按钮在 allCapsules 中的索引
  int get plusButtonIndex => presetCount + _customPresets.length;

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
  ///
  /// 🔒 守护逻辑：如果当前选中的是自定义胶囊（[_selectedColorIndex] >= presetCount），
  /// 说明用户的意图是自定义色，硬件刚才报告的预设值不该覆盖 app 状态。
  /// 此时反向同步：把当前自定义胶囊重新铺到硬件，让硬件回归用户的选择。
  void onPresetReport(int preset) {
    final appIndex = preset - 1;
    if (appIndex < 0 || appIndex >= ledColorCapsules.length) return;

    if (_selectedColorIndex >= presetCount &&
        _selectedColorIndex < presetCount + _customPresets.length) {
      // 当前选中的是自定义胶囊 → 不接受硬件预设覆盖，反过来把自定义色重发
      final customIndex = _selectedColorIndex - presetCount;
      final preset = _customPresets[customIndex];
      debugPrint(
          '🛡️ 硬件预设报告 $appIndex 与 app 自定义选择不符，反向同步自定义色到硬件');
      syncCustomToHardware(preset);
      return;
    }

    debugPrint('🎨 收到硬件预设报告: $preset -> APP索引: $appIndex');
    _isReceivingPresetReport = true;
    _selectedColorIndex = appIndex;
    applyPresetToLocalColors(appIndex);
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 150), () {
      _isReceivingPresetReport = false;
    });
  }

  /// 硬件流水灯状态报告回调
  void onStreamlightReport(bool isEnabled) {
    debugPrint('🔄 收到硬件流水灯状态: ${isEnabled ? "开启" : "关闭"}');
    _isCycling = isEnabled;
    notifyListeners();
  }

  /// 智能分发同步：根据 allCapsules[index] 的 kind 决定走哪条硬件链路
  ///
  /// - 'preset' → [syncPresetToHardware]
  /// - 'custom' → [syncCustomToHardware]
  /// - 'plus'   → 不发硬件指令
  Future<void> syncCapsuleToHardware(int index) async {
    final caps = allCapsules;
    if (index < 0 || index >= caps.length) return;
    final kind = caps[index]['kind'];
    if (kind == 'preset') {
      await syncPresetToHardware(index);
    } else if (kind == 'custom') {
      final customIndex = index - presetCount;
      if (customIndex >= 0 && customIndex < _customPresets.length) {
        await syncCustomToHardware(_customPresets[customIndex]);
      }
    }
    // 'plus' → no-op
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

  /// 把用户自定义胶囊的颜色铺到 4 条灯带
  ///
  /// 通过 `LED:strip:r:g:b` 协议直接控制硬件，等价于预设的视觉效果：
  ///   - strip 1 (M 中) = 主色
  ///   - strip 2 (L 左) = 主色
  ///   - strip 3 (R 右) = 副色（纯色时与主色相同）
  ///   - strip 4 (B 后) = 副色
  ///
  /// 同步前会先把硬件 UI 切到 2（配色预设页），让 LCD 显示预设页面而非 RGB 页。
  Future<void> syncCustomToHardware(CustomPreset preset) async {
    // 自定义胶囊的颜色 = 用户当前生效色，记入本地 RGB 缓存
    _redValues['L'] = preset.r1;
    _greenValues['L'] = preset.g1;
    _blueValues['L'] = preset.b1;
    _redValues['M'] = preset.r1;
    _greenValues['M'] = preset.g1;
    _blueValues['M'] = preset.b1;
    _redValues['R'] = preset.r2;
    _greenValues['R'] = preset.g2;
    _blueValues['R'] = preset.b2;
    _redValues['B'] = preset.r2;
    _greenValues['B'] = preset.g2;
    _blueValues['B'] = preset.b2;

    // 标记为自定义色（用于其他逻辑判断），同时把当前 RGB 缓存持久化
    _hasCustomColors = true;
    _preferenceService.saveHasCustomColors(true);
    _preferenceService.saveCustomRGBColors({
      'L': {'r': preset.r1, 'g': preset.g1, 'b': preset.b1},
      'M': {'r': preset.r1, 'g': preset.g1, 'b': preset.b1},
      'R': {'r': preset.r2, 'g': preset.g2, 'b': preset.b2},
      'B': {'r': preset.r2, 'g': preset.g2, 'b': preset.b2},
    });

    notifyListeners();

    if (!_btProvider.isConnected) return;

    // 硬件 UI 保持在配色预设页（避免跳到 RGB 调色页）
    if (_lastSentHardwareUI != 2) {
      await _btProvider.setHardwareUI(2);
      _lastSentHardwareUI = 2;
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // ⚠️ 不节流 LED 命令：4 条 await 串行 BLE 写已天然限速（~120ms/批），
    //   如果再叠节流，重连/反向同步/快速选择时会被吞掉，导致硬件不响应。
    _lastPresetSyncTime = DateTime.now();

    // 连发 4 条 LED:strip:r:g:b
    await _btProvider.setLEDColor(1, preset.r1, preset.g1, preset.b1); // M
    await _btProvider.setLEDColor(2, preset.r1, preset.g1, preset.b1); // L
    await _btProvider.setLEDColor(3, preset.r2, preset.g2, preset.b2); // R
    await _btProvider.setLEDColor(4, preset.r2, preset.g2, preset.b2); // B
    debugPrint(
        '📤 自定义胶囊 ${preset.id} → LED main(${preset.r1},${preset.g1},${preset.b1}) sec(${preset.r2},${preset.g2},${preset.b2})');
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
  //  自定义胶囊 CRUD（带持久化）
  // ═══════════════════════════════════════════════════════════════

  /// 启动时调用，从 SharedPreferences 恢复自定义胶囊列表
  Future<void> loadCustomPresets() async {
    final list = await _preferenceService.getCustomPresets();
    _customPresets
      ..clear()
      ..addAll(list);
    notifyListeners();
    debugPrint('🎨 已恢复 ${_customPresets.length} 个用户自定义胶囊');
  }

  /// 检测一组 RGB 是否与已有胶囊（内置 + 自定义）重复
  ///
  /// 返回值:
  ///   - null  → 不重复
  ///   - `'preset:N'`  → 与第 N+1 个内置预设重复
  ///   - `'custom:ID'` → 与指定 id 的自定义胶囊重复
  ///
  /// [excludeCustomId] 用于编辑场景，避免与自身比较。
  /// 比较规则：纯色时只比较 (r1,g1,b1)；渐变时比较两端色 (r1,g1,b1) + (r2,g2,b2)。
  /// 双方都必须是相同 type 才视为重复。
  String? findDuplicateCapsule({
    required String type,
    required int r1,
    required int g1,
    required int b1,
    required int r2,
    required int g2,
    required int b2,
    String? excludeCustomId,
  }) {
    bool sameColor(int a, int b, int c, int x, int y, int z) =>
        a == x && b == y && c == z;

    // 1. 与内置预设比较
    for (int i = 0; i < ledPresets.length; i++) {
      final p = ledPresets[i];
      final presetIsSolid = p.type == 'solid';
      if (type == 'solid' && presetIsSolid) {
        if (sameColor(r1, g1, b1, p.led2R, p.led2G, p.led2B)) {
          return 'preset:$i';
        }
      } else if (type == 'gradient' && !presetIsSolid) {
        if (sameColor(r1, g1, b1, p.led2R, p.led2G, p.led2B) &&
            sameColor(r2, g2, b2, p.led3R, p.led3G, p.led3B)) {
          return 'preset:$i';
        }
      }
    }

    // 2. 与自定义胶囊比较
    for (final c in _customPresets) {
      if (c.id == excludeCustomId) continue;
      if (c.type != type) continue;
      if (type == 'solid') {
        if (sameColor(r1, g1, b1, c.r1, c.g1, c.b1)) {
          return 'custom:${c.id}';
        }
      } else {
        if (sameColor(r1, g1, b1, c.r1, c.g1, c.b1) &&
            sameColor(r2, g2, b2, c.r2, c.g2, c.b2)) {
          return 'custom:${c.id}';
        }
      }
    }
    return null;
  }

  /// 新增自定义胶囊。返回新胶囊的 customId；若与已有重复则返回 null。
  Future<String?> addCustomPreset({
    required String type,
    required int r1,
    required int g1,
    required int b1,
    required int r2,
    required int g2,
    required int b2,
  }) async {
    final r1c = r1.clamp(0, 255);
    final g1c = g1.clamp(0, 255);
    final b1c = b1.clamp(0, 255);
    final r2c = r2.clamp(0, 255);
    final g2c = g2.clamp(0, 255);
    final b2c = b2.clamp(0, 255);

    // 重复检测：避免创建与现有胶囊相同颜色
    final dup = findDuplicateCapsule(
      type: type,
      r1: r1c, g1: g1c, b1: b1c,
      r2: r2c, g2: g2c, b2: b2c,
    );
    if (dup != null) {
      debugPrint('⚠️ 拒绝创建重复胶囊（与 $dup 颜色一致）');
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'cp_${now}_${_customPresets.length}';
    final preset = CustomPreset(
      id: id,
      type: type,
      r1: r1c, g1: g1c, b1: b1c,
      r2: r2c, g2: g2c, b2: b2c,
      createdAtMs: now,
    );
    _customPresets.add(preset);
    await _preferenceService.saveCustomPresets(_customPresets);
    notifyListeners();
    return id;
  }

  /// 更新现有自定义胶囊。
  ///
  /// 返回值:
  ///   - 'ok'         → 更新成功
  ///   - 'not_found'  → id 找不到
  ///   - 'duplicate'  → 与其它胶囊颜色重复，未保存
  Future<String> updateCustomPreset(String id, CustomPreset updated) async {
    final i = _customPresets.indexWhere((p) => p.id == id);
    if (i < 0) return 'not_found';

    final dup = findDuplicateCapsule(
      type: updated.type,
      r1: updated.r1, g1: updated.g1, b1: updated.b1,
      r2: updated.r2, g2: updated.g2, b2: updated.b2,
      excludeCustomId: id,
    );
    if (dup != null) {
      debugPrint('⚠️ 拒绝更新（与 $dup 颜色一致）');
      return 'duplicate';
    }

    _customPresets[i] = updated;
    await _preferenceService.saveCustomPresets(_customPresets);
    notifyListeners();
    return 'ok';
  }

  /// 删除自定义胶囊。返回是否成功。
  Future<bool> removeCustomPreset(String id) async {
    final i = _customPresets.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    _customPresets.removeAt(i);
    await _preferenceService.saveCustomPresets(_customPresets);
    // 如果当前选中索引被影响，回退到第一个预设
    final removedAbsIndex = presetCount + i;
    if (_selectedColorIndex == removedAbsIndex) {
      _selectedColorIndex = 0;
    } else if (_selectedColorIndex > removedAbsIndex) {
      _selectedColorIndex -= 1;
    }
    notifyListeners();
    return true;
  }

  /// 通过 customId 查找
  CustomPreset? findCustomPreset(String id) {
    final i = _customPresets.indexWhere((p) => p.id == id);
    return i < 0 ? null : _customPresets[i];
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
