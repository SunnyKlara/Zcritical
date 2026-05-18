import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/custom_preset.dart';
import '../screens/color_ring_screen.dart';

/// 自定义胶囊编辑器返回的结果
class CustomPresetEditResult {
  final String type; // 'solid' | 'gradient'
  final int r1, g1, b1;
  final int r2, g2, b2;

  const CustomPresetEditResult({
    required this.type,
    required this.r1,
    required this.g1,
    required this.b1,
    required this.r2,
    required this.g2,
    required this.b2,
  });
}

/// 新建 / 编辑自定义颜色胶囊的底部弹层
///
/// - 切换 solid / gradient
/// - 主色 + 副色（solid 时副色禁用、与主色相同）
/// - 双轨取色:
///     1. RGB 滑块手搓
///     2. "从色环选取" 按钮 → push ColorRingScreen 复用现有色环界面
/// - 实时预览胶囊外观
class CustomPresetEditorSheet extends StatefulWidget {
  /// 编辑时传入现有胶囊，null 表示新建
  final CustomPreset? initial;

  const CustomPresetEditorSheet({super.key, this.initial});

  static Future<CustomPresetEditResult?> show(
    BuildContext context, {
    CustomPreset? initial,
  }) {
    return showModalBottomSheet<CustomPresetEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomPresetEditorSheet(initial: initial),
    );
  }

  @override
  State<CustomPresetEditorSheet> createState() =>
      _CustomPresetEditorSheetState();
}

class _CustomPresetEditorSheetState extends State<CustomPresetEditorSheet> {
  late String _type;
  late int _r1, _g1, _b1;
  late int _r2, _g2, _b2;
  // 'main' or 'sec' — 当前活跃的"主色 / 副色"编辑通道
  String _activeChannel = 'main';

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _type = init.type;
      _r1 = init.r1; _g1 = init.g1; _b1 = init.b1;
      _r2 = init.r2; _g2 = init.g2; _b2 = init.b2;
    } else {
      _type = 'solid';
      _r1 = 255; _g1 = 100; _b1 = 0;
      _r2 = 255; _g2 = 100; _b2 = 0;
    }
  }

  Color get _mainColor => Color.fromARGB(255, _r1, _g1, _b1);
  Color get _secColor => Color.fromARGB(255, _r2, _g2, _b2);

  void _setActiveColor(int r, int g, int b) {
    setState(() {
      if (_activeChannel == 'main') {
        _r1 = r; _g1 = g; _b1 = b;
        if (_type == 'solid') {
          _r2 = r; _g2 = g; _b2 = b;
        }
      } else {
        _r2 = r; _g2 = g; _b2 = b;
      }
    });
  }

  int get _activeR => _activeChannel == 'main' ? _r1 : _r2;
  int get _activeG => _activeChannel == 'main' ? _g1 : _g2;
  int get _activeB => _activeChannel == 'main' ? _b1 : _b2;

  Future<void> _openColorRing() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ColorRingScreen(
          onColorSelected: (r, g, b) {
            _setActiveColor(r, g, b);
          },
        ),
      ),
    );
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      CustomPresetEditResult(
        type: _type,
        r1: _r1, g1: _g1, b1: _b1,
        r2: _type == 'solid' ? _r1 : _r2,
        g2: _type == 'solid' ? _g1 : _g2,
        b2: _type == 'solid' ? _b1 : _b2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1B1B1B),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(22)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGrabber(),
                const SizedBox(height: 6),
                Text(
                  isEdit ? '编辑自定义胶囊' : '新建自定义胶囊',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTypeToggle(),
                const SizedBox(height: 16),
                _buildPreview(),
                const SizedBox(height: 18),
                _buildChannelPicker(),
                const SizedBox(height: 14),
                _buildRgbSliders(),
                const SizedBox(height: 16),
                _buildColorRingButton(),
                const SizedBox(height: 24),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildTypeToggle() {
    Widget seg(String label, String value) {
      final selected = _type == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _type = value;
              if (_type == 'solid') {
                _r2 = _r1; _g2 = _g1; _b2 = _b1;
                _activeChannel = 'main';
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFC62828)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg('纯色', 'solid'),
        const SizedBox(width: 10),
        seg('渐变', 'gradient'),
      ],
    );
  }

  Widget _buildPreview() {
    final isSolid = _type == 'solid';
    return Center(
      child: Container(
        width: 64,
        height: 200,
        decoration: BoxDecoration(
          color: isSolid ? _mainColor : null,
          gradient: !isSolid
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_mainColor, _secColor],
                )
              : null,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: _mainColor.withValues(alpha: 0.4),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelPicker() {
    if (_type == 'solid') return const SizedBox.shrink();
    Widget tile(String label, String value, Color color) {
      final selected = _activeChannel == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _activeChannel = value);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.1),
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white24, width: 0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('主色', 'main', _mainColor),
        const SizedBox(width: 10),
        tile('副色', 'sec', _secColor),
      ],
    );
  }

  Widget _buildRgbSliders() {
    Widget row(String label, Color trackColor, int value,
        ValueChanged<int> onChanged) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: trackColor,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  overlayColor: trackColor.withValues(alpha: 0.15),
                ),
                child: Slider(
                  min: 0,
                  max: 255,
                  value: value.toDouble(),
                  onChanged: (v) => onChanged(v.round()),
                ),
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '$value',
                textAlign: TextAlign.right,
                style:
                    const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        row('R', const Color(0xFFE53935), _activeR,
            (v) => _setActiveColor(v, _activeG, _activeB)),
        row('G', const Color(0xFF43A047), _activeG,
            (v) => _setActiveColor(_activeR, v, _activeB)),
        row('B', const Color(0xFF1E88E5), _activeB,
            (v) => _setActiveColor(_activeR, _activeG, v)),
      ],
    );
  }

  Widget _buildColorRingButton() {
    return GestureDetector(
      onTap: _openColorRing,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFFC2185B)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.palette, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _type == 'solid'
                  ? '从色环选取颜色'
                  : '从色环选取${_activeChannel == 'main' ? '主色' : '副色'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('取消',
                style: TextStyle(color: Colors.white70)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextButton(
            onPressed: _confirm,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFFC62828),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              '保存',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
