import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'streamline_painter.dart';

/// 🏃 跑步机控制面板 — 束线流线 + 数字滚轮
///
/// 视觉参考：Tixing `pc_tests/test_wind_resistance.py` 的 6 股弧形束线。
/// 数字滚轮：从 RunningModeWidget 的滚轮风格抽出来（5 项可见，
/// 中间项放大高亮，左侧红点+横线刻度，上下渐变遮罩）。
///
/// 滑动入口：device_connect_screen.dart 顶层 PageView 第 0 页（running 左侧）。
class TreadmillPanelWidget extends StatefulWidget {
  const TreadmillPanelWidget({super.key});

  @override
  State<TreadmillPanelWidget> createState() => _TreadmillPanelWidgetState();
}

class _TreadmillPanelWidgetState extends State<TreadmillPanelWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;
  late final FixedExtentScrollController _wheelController;

  // 滚轮范围（骨架阶段沿用 running mode 的 0~340，后续可换成跑步机专用范围）
  static const int _maxValue = 340;
  int _value = 0;

  Rect? _obstacleRect;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _wheelController = FixedExtentScrollController(initialItem: _value);
  }

  @override
  void dispose() {
    _flowController.dispose();
    _wheelController.dispose();
    super.dispose();
  }

  /// 束线流线绕开的"障碍物"= 中央高亮数字所在那一行。
  /// 用 LayoutBuilder 给出的 size + itemExtent 直接计算，无需 GlobalKey 二次量测。
  Rect _computeObstacle(Size size, double itemExtent) {
    // 中央数字横向只占据中间一段，纵向就是当前那一项 itemExtent
    final cx = size.width / 2;
    final cy = size.height / 2;
    // 给数字留出一个相对紧凑的"挡板"矩形：宽度 ~46% 屏宽，高度 ~itemExtent
    final hw = size.width * 0.23;
    final hh = itemExtent * 0.45;
    return Rect.fromCenter(
      center: Offset(cx, cy),
      width: hw * 2,
      height: hh * 2,
    );
  }

  // 单位的强度映射：0~340 → 0.15~0.95，用于束线冷↔暖色 + 尾流强度
  double get _intensity {
    final t = (_value / _maxValue).clamp(0.0, 1.0);
    return 0.15 + 0.80 * t;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF050608),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          // 滚轮项高度自适应，保证整屏看起来恰好显示 5 项
          final itemExtent = (size.height / 5.2).clamp(56.0, 110.0);
          _obstacleRect ??= _computeObstacle(size, itemExtent);
          // 尺寸变了就重算
          final newRect = _computeObstacle(size, itemExtent);
          if (newRect != _obstacleRect) {
            _obstacleRect = newRect;
          }

          return Stack(
            children: [
              // ── 束线流线动画背景 ───────────────────────────
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _flowController,
                  builder: (_, __) => CustomPaint(
                    painter: StreamlinePainter(
                      tick: _flowController.value * 3600.0,
                      intensity: _intensity,
                      obstacle: _obstacleRect,
                    ),
                  ),
                ),
              ),

              // ── 中央数字滚轮 ──────────────────────────────
              Positioned.fill(
                child: _DigitWheel(
                  controller: _wheelController,
                  itemExtent: itemExtent,
                  maxValue: _maxValue,
                  currentValue: _value,
                  onChanged: (v) {
                    if (v == _value) return;
                    HapticFeedback.selectionClick();
                    setState(() => _value = v);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 数字滚轮 — 风格抽自 RunningModeWidget._buildSpeedItemWithIndicator
class _DigitWheel extends StatelessWidget {
  const _DigitWheel({
    required this.controller,
    required this.itemExtent,
    required this.maxValue,
    required this.currentValue,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final int maxValue;
  final int currentValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: itemExtent,
          diameterRatio: 1.8,
          perspective: 0.002,
          physics: const BouncingScrollPhysics(
            parent: FixedExtentScrollPhysics(),
          ),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, index) {
              if (index < 0 || index > maxValue) return null;
              return _DigitItem(
                value: index,
                currentValue: currentValue,
                itemExtent: itemExtent,
              );
            },
            childCount: maxValue + 1,
          ),
        ),
        // 上下渐变遮罩：让滚轮上下边缘融进背景
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: itemExtent * 0.9,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF050608), Color(0x00050608)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: itemExtent * 0.9,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFF050608), Color(0x00050608)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DigitItem extends StatelessWidget {
  const _DigitItem({
    required this.value,
    required this.currentValue,
    required this.itemExtent,
  });

  final int value;
  final int currentValue;
  final double itemExtent;

  @override
  Widget build(BuildContext context) {
    final bool isCurrent = value == currentValue;
    final int distance = (value - currentValue).abs();
    final double opacity = distance == 0
        ? 1.0
        : distance == 1
            ? 0.7
            : distance == 2
                ? 0.4
                : 0.2;

    final selectedFontSize = (itemExtent * 1.05).clamp(60.0, 110.0);
    final smallFontSize = (itemExtent * 0.48).clamp(28.0, 50.0);

    return Row(
      children: [
        // 左侧刻度（红点 / 横线）
        SizedBox(
          width: 42,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: _ScaleIndicator(
              isCurrent: isCurrent,
              offset: (value - currentValue),
              distance: distance,
            ),
          ),
        ),
        // 中央数字
        Expanded(
          child: Center(
            child: Text(
              value.toString(),
              style: TextStyle(
                color: isCurrent
                    ? Colors.white
                    : const Color(0xFFC94A4A)
                        .withAlpha((opacity * 0.7 * 255).round()),
                fontSize: isCurrent ? selectedFontSize : smallFontSize,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: isCurrent ? 4 : 2,
                height: 1.0,
                shadows: isCurrent
                    ? const [
                        Shadow(
                          color: Colors.black,
                          offset: Offset(0, 4),
                          blurRadius: 8,
                        ),
                        Shadow(
                          color: Color(0xCC000000),
                          offset: Offset(2, 6),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
        // 右侧留白，对称视觉重心
        const SizedBox(width: 42),
      ],
    );
  }
}

class _ScaleIndicator extends StatelessWidget {
  const _ScaleIndicator({
    required this.isCurrent,
    required this.offset,
    required this.distance,
  });

  final bool isCurrent;
  final int offset;
  final int distance;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      // 当前项：红点
      return const Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFFF0000),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    // 非当前项：长短横线循环
    int o = offset % 7;
    if (o < 0) o += 7;
    const lengths = [22.0, 12.0, 12.0, 22.0, 12.0, 22.0, 12.0];
    final lineOpacity = distance > 2 ? 0.3 : 0.5;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: lengths[o],
        height: 2.5,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha((lineOpacity * 255).round()),
          borderRadius: BorderRadius.circular(1.25),
        ),
      ),
    );
  }
}
