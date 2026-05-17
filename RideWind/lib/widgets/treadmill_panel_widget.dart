import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'streamline_painter.dart';

/// 跑步机控制面板 — 束线流线 + 固定中央数字
///
/// 视觉参考：Tixing `pc_tests/test_wind_resistance.py` 的 6 股弧形束线。
///
/// 控制逻辑（参考油门模式 — 不操作时自动怠速减速）：
///   - 中央数字位置固定（不再用滚轮）
///   - 红点靠左，数字仍全屏居中
///   - 数字变化时使用"翻牌式"跳动动画（旧值上滑出 + 新值下滑入）
///   - 单击中央 → +1
///   - 长按中央 → 连续递增，松手停下
///   - 双击 → 归零
///   - 不操作时自动怠速：松手后约隔 0.6s 开始减速，递减到 0 为止
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

  static const int _maxValue = 340;
  int _value = 0;

  Timer? _holdTimer;
  bool _isHolding = false;

  // 单位：true=公制 km/h, false=英制 mp/h（参考 RunningModeWidget 风格）
  bool _isMetric = true;

  // 怠速：不操作时自动递减到 0（松手立即开始）
  Timer? _idleDecayTimer;
  static const Duration _idleTickInterval = Duration(milliseconds: 90);

  Rect? _obstacleRect;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    _holdTimer?.cancel();
    _idleDecayTimer?.cancel();
    super.dispose();
  }

  // ── 交互 ────────────────────────────────────────────
  void _bumpOnce() {
    _cancelIdleDecay();
    HapticFeedback.selectionClick();
    setState(() {
      _value = (_value + 1).clamp(0, _maxValue);
    });
    _scheduleIdleDecay();
  }

  void _startHold() {
    if (_isHolding) return;
    _isHolding = true;
    _cancelIdleDecay();
    HapticFeedback.mediumImpact();
    int tickCount = 0;
    // 越按越快：步长从 1 升到 5
    _holdTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      tickCount++;
      final step = tickCount < 8
          ? 1
          : tickCount < 20
              ? 2
              : tickCount < 40
                  ? 3
                  : 5;
      setState(() {
        _value = (_value + step).clamp(0, _maxValue);
      });
      if (_value >= _maxValue) _stopHold();
      // 节流震动反馈
      if (tickCount % 4 == 0) HapticFeedback.selectionClick();
    });
  }

  void _stopHold() {
    _isHolding = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _scheduleIdleDecay();
  }

  void _resetValue() {
    _cancelIdleDecay();
    HapticFeedback.lightImpact();
    setState(() => _value = 0);
  }

  void _toggleUnit() {
    HapticFeedback.mediumImpact();
    setState(() => _isMetric = !_isMetric);
  }

  // ── 怠速（不操作时自动递减到 0，松手立即开始）─────────
  void _scheduleIdleDecay() {
    _idleDecayTimer?.cancel();
    if (_value <= 0) return;
    int tickCount = 0;
    _idleDecayTimer = Timer.periodic(_idleTickInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isHolding || _value <= 0) {
        timer.cancel();
        _idleDecayTimer = null;
        return;
      }
      tickCount++;
      // 初期温柔，随后平稳
      final step = tickCount < 6 ? 1 : (tickCount < 18 ? 2 : 3);
      setState(() {
        _value = (_value - step).clamp(0, _maxValue);
      });
    });
  }

  void _cancelIdleDecay() {
    _idleDecayTimer?.cancel();
    _idleDecayTimer = null;
  }

  // ── 束线障碍物：中央数字所在那一块矩形 ──
  Rect _computeObstacle(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final hw = size.width * 0.22;
    final hh = size.height * 0.10;
    return Rect.fromCenter(
      center: Offset(cx, cy),
      width: hw * 2,
      height: hh * 2,
    );
  }

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
          _obstacleRect = _computeObstacle(size);
          final fontSize = (size.height * 0.22).clamp(72.0, 130.0);

          // 整个面板都是手势热区：单击 / 双击 / 长按都能在任意位置触发
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _bumpOnce,
            onDoubleTap: _resetValue,
            onLongPressStart: (_) => _startHold(),
            onLongPressEnd: (_) => _stopHold(),
            onLongPressCancel: _stopHold,
            child: Stack(
              children: [
                // ── 束线流线动画背景 ───────────────────────────
                Positioned.fill(
                  child: IgnorePointer(
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
                ),

                // ── 左侧红点 ────────────────────────────────
                Positioned(
                  left: 22,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF0000),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── 中央翻牌数字 ─────────────────────────────
                Center(
                  child: IgnorePointer(
                    child: _FlipDigit(
                      value: _value,
                      fontSize: fontSize,
                    ),
                  ),
                ),

                // ── 右侧单位（点击切换 km/h ⇄ mp/h）───────────────
                Positioned(
                  right: 22,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleUnit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
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
                              const TextSpan(
                                text: '/',
                                style: TextStyle(
                                  color: Color(0xFFC94A4A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(
                                text: 'h',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 翻牌式跳动数字 — 新值从下方滑入，旧值向上滑出。
/// 复用 AnimatedSwitcher 内置的过渡机制，避免自己写动画控制器。
class _FlipDigit extends StatelessWidget {
  const _FlipDigit({required this.value, required this.fontSize});

  final int value;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: 4,
      height: 1.0,
      shadows: const [
        Shadow(color: Colors.black, offset: Offset(0, 4), blurRadius: 8),
        Shadow(
          color: Color(0xCC000000),
          offset: Offset(2, 6),
          blurRadius: 12,
        ),
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        // 新进入：从下方 +35% 高度处滑入；离开：向上滑出
        final isIncoming = child.key == ValueKey<int>(value);
        final beginOffset = isIncoming
            ? const Offset(0, 0.35)
            : const Offset(0, -0.35);
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: Text(
        value.toString(),
        key: ValueKey<int>(value),
        style: style,
      ),
    );
  }
}
