import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 驾驶风格设置底部弹窗
///
/// 纯 UI 预览组件，无 BLE 通信，所有状态本地管理。
/// 视觉风格完全对齐 ThrottleEffectSelector / ColorizeRGBDetailView。
///
/// 使用方式：
/// ```dart
/// DrivingStyleSheet.show(context);
/// ```
class DrivingStyleSheet extends StatefulWidget {
  const DrivingStyleSheet({super.key});

  /// 显示驾驶风格设置弹窗
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      builder: (context) => const DrivingStyleSheet(),
    );
  }

  @override
  State<DrivingStyleSheet> createState() => _DrivingStyleSheetState();
}

class _DrivingStyleSheetState extends State<DrivingStyleSheet> {
  // ═══════════════════════════════════════════════════════════════
  //  色彩 — 完全对齐 APP 现有弹窗
  // ═══════════════════════════════════════════════════════════════

  static const _sheetBg = Color(0xFF1A1A1A);
  static const _accent = Color(0xFFC62828); // APP 统一红
  static const _accentSoft = Color(0x33C62828); // 20% 红

  // ═══════════════════════════════════════════════════════════════
  //  预设数据
  // ═══════════════════════════════════════════════════════════════

  static const List<_PresetData> _presets = [
    _PresetData(
      emoji: '🏎️',
      name: '赛车',
      desc: '强风 · 即时响应 · 引擎轰鸣',
      windMin: 30,
      windMax: 100,
      maxSpeed: 400,
      response: '即时',
      sensitivity: 80,
      sound: '引擎',
      volume: 90,
    ),
    _PresetData(
      emoji: '🚗',
      name: '巡航',
      desc: '中等风力 · 自然过渡 · 引擎低沉',
      windMin: 20,
      windMax: 70,
      maxSpeed: 340,
      response: '自然',
      sensitivity: 50,
      sound: '引擎',
      volume: 70,
    ),
    _PresetData(
      emoji: '🛵',
      name: '休闲',
      desc: '微风 · 惯性延迟 · 风声轻柔',
      windMin: 10,
      windMax: 50,
      maxSpeed: 200,
      response: '惯性',
      sensitivity: 30,
      sound: '风声',
      volume: 50,
    ),
  ];

  // ═══════════════════════════════════════════════════════════════
  //  状态
  // ═══════════════════════════════════════════════════════════════

  int _selectedPresetIndex = 1;
  RangeValues _windRange = const RangeValues(20, 70);
  double _maxSpeed = 340;
  String _response = '自然';
  double _sensitivity = 50;
  String _sound = '引擎';
  double _volume = 70;

  // Undo
  int? _prevPresetIndex;
  RangeValues? _prevWindRange;
  double? _prevMaxSpeed;
  String? _prevResponse;
  double? _prevSensitivity;
  String? _prevSound;
  double? _prevVolume;

  void _saveStateForUndo() {
    _prevPresetIndex = _selectedPresetIndex;
    _prevWindRange = _windRange;
    _prevMaxSpeed = _maxSpeed;
    _prevResponse = _response;
    _prevSensitivity = _sensitivity;
    _prevSound = _sound;
    _prevVolume = _volume;
  }

  void _undo() {
    if (_prevWindRange == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedPresetIndex = _prevPresetIndex ?? _selectedPresetIndex;
      _windRange = _prevWindRange!;
      _maxSpeed = _prevMaxSpeed!;
      _response = _prevResponse!;
      _sensitivity = _prevSensitivity!;
      _sound = _prevSound!;
      _volume = _prevVolume!;
    });
  }

  void _applyPreset(int index) {
    _saveStateForUndo();
    HapticFeedback.lightImpact();
    final preset = _presets[index];
    setState(() {
      _selectedPresetIndex = index;
      _windRange =
          RangeValues(preset.windMin.toDouble(), preset.windMax.toDouble());
      _maxSpeed = preset.maxSpeed.toDouble();
      _response = preset.response;
      _sensitivity = preset.sensitivity.toDouble();
      _sound = preset.sound;
      _volume = preset.volume.toDouble();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '驾驶风格',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                GestureDetector(
                  onTap: _undo,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.undo_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 可滚动内容
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // ─── 预设卡片 ───
                ..._buildPresetCards(),
                const SizedBox(height: 20),
                // ─── 风力范围 ───
                _buildSectionTitle('风力范围'),
                const SizedBox(height: 10),
                _buildWindRangeCard(),
                const SizedBox(height: 16),
                // ─── 最大风速 ───
                _buildSectionTitle('最大风速'),
                const SizedBox(height: 10),
                _buildSliderCard(
                  value: _maxSpeed,
                  min: 100,
                  max: 500,
                  label: '${_maxSpeed.round()} km/h',
                  onChanged: (v) => setState(() {
                    _maxSpeed = v;
                    _selectedPresetIndex = -1;
                  }),
                ),
                const SizedBox(height: 16),
                // ─── 响应模式 ───
                _buildSectionTitle('响应模式'),
                const SizedBox(height: 10),
                _buildSegmentCard(
                  options: const ['即时', '自然', '惯性'],
                  selected: _response,
                  onChanged: (v) => setState(() {
                    _response = v;
                    _selectedPresetIndex = -1;
                  }),
                ),
                const SizedBox(height: 16),
                // ─── 旋钮灵敏度 ───
                _buildSectionTitle('旋钮灵敏度'),
                const SizedBox(height: 10),
                _buildSliderCard(
                  value: _sensitivity,
                  min: 0,
                  max: 100,
                  label: '${_sensitivity.round()}%',
                  leading: '慢',
                  trailing: '快',
                  onChanged: (v) => setState(() {
                    _sensitivity = v;
                    _selectedPresetIndex = -1;
                  }),
                ),
                const SizedBox(height: 16),
                // ─── 音效 ───
                _buildSectionTitle('音效'),
                const SizedBox(height: 10),
                _buildSegmentCard(
                  options: const ['引擎', '风声', '静音'],
                  selected: _sound,
                  onChanged: (v) => setState(() {
                    _sound = v;
                    _selectedPresetIndex = -1;
                  }),
                ),
                const SizedBox(height: 16),
                // ─── 音量 ───
                _buildSectionTitle('音量'),
                const SizedBox(height: 10),
                _buildSliderCard(
                  value: _volume,
                  min: 0,
                  max: 100,
                  label: '${_volume.round()}%',
                  onChanged: (v) => setState(() {
                    _volume = v;
                    _selectedPresetIndex = -1;
                  }),
                ),
                const SizedBox(height: 24),
                // ─── 保存按钮 ───
                _buildSaveButton(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  预设卡片 — 和 ThrottleEffectSelector 列表项同风格
  // ═══════════════════════════════════════════════════════════════

  List<Widget> _buildPresetCards() {
    return List.generate(_presets.length, (index) {
      final preset = _presets[index];
      final isSelected = _selectedPresetIndex == index;

      return GestureDetector(
        onTap: () => _applyPreset(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? _accentSoft
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? _accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Text(preset.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.desc,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: _accent, size: 22),
            ],
          ),
        ),
      );
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  滑条卡片 — 深色卡片内嵌滑条
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWindRangeCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SliderTheme(
            data: _rangeSliderTheme(),
            child: RangeSlider(
              values: _windRange,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (values) {
                setState(() {
                  _windRange = values;
                  _selectedPresetIndex = -1;
                });
              },
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_windRange.start.round()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_windRange.end.round()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard({
    required double value,
    required double min,
    required double max,
    required String label,
    String? leading,
    String? trailing,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (leading != null)
                Text(
                  leading,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  分段选择器 — 选中态用红色填充
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSegmentCard({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((option) {
          final isSelected = option == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(option);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  保存按钮
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        // Placeholder for save preset logic
      },
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Text(
          '保存为我的预设',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  通用
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Slider 主题 — 红色轨道 + 白色圆点
  // ═══════════════════════════════════════════════════════════════

  SliderThemeData _sliderTheme() {
    return SliderThemeData(
      activeTrackColor: _accent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      thumbColor: Colors.white,
      overlayColor: _accent.withValues(alpha: 0.1),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    );
  }

  SliderThemeData _rangeSliderTheme() {
    return SliderThemeData(
      activeTrackColor: _accent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
      thumbColor: Colors.white,
      overlayColor: _accent.withValues(alpha: 0.1),
      trackHeight: 3,
      rangeThumbShape:
          const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
    );
  }
}

/// Preset data model
class _PresetData {
  final String emoji;
  final String name;
  final String desc;
  final int windMin;
  final int windMax;
  final int maxSpeed;
  final String response;
  final int sensitivity;
  final String sound;
  final int volume;

  const _PresetData({
    required this.emoji,
    required this.name,
    required this.desc,
    required this.windMin,
    required this.windMax,
    required this.maxSpeed,
    required this.response,
    required this.sensitivity,
    required this.sound,
    required this.volume,
  });
}
