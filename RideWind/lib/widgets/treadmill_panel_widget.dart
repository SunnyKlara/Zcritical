import 'package:flutter/material.dart';
import 'streamline_painter.dart';

/// 🏃 跑步机控制面板（占位骨架）
///
/// 设计参考：Tixing `pc_tests/test_wind_resistance.py` 的束线流线风格。
///
/// 当前为 UI 骨架：
///   - 全屏 6 股弧形束线动画背景（StreamlinePainter）
///   - 中央占位卡片（束线会绕过它形成山峰/山谷）
///   - 顶部标题、底部细进度条
///   - 三个控件占位区块（待后续填具体功能）
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
  final GlobalKey _centerKey = GlobalKey(debugLabel: 'treadmillCenterCard');

  // 0~1，控制束线颜色冷↔暖、尾流强度。骨架阶段先固定中段值。
  final double _intensity = 0.45;

  Rect? _obstacleRect;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureObstacle());
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  void _measureObstacle() {
    final ctx = _centerKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    final stackBox = context.findRenderObject() as RenderBox?;
    if (box == null || stackBox == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = origin & box.size;
    if (_obstacleRect != rect) {
      setState(() => _obstacleRect = rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 后重新量一遍，应对屏幕尺寸/容器高度变化
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureObstacle());

    return Container(
      color: const Color(0xFF050608),
      child: Stack(
        children: [
          // ── 束线流线动画背景 ───────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flowController,
              builder: (_, __) => CustomPaint(
                painter: StreamlinePainter(
                  tick: _flowController.value * 3600.0, // 0~3600 帧等效
                  intensity: _intensity,
                  obstacle: _obstacleRect,
                ),
              ),
            ),
          ),

          // ── 顶部标题 ─────────────────────────────────────
          const Positioned(
            top: 18,
            left: 22,
            child: Text(
              'TREADMILL',
              style: TextStyle(
                color: Color(0xFFB4DCFF),
                fontSize: 13,
                letterSpacing: 4.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 22,
            child: Text(
              'PANEL',
              style: TextStyle(
                color: Colors.white.withAlpha(70),
                fontSize: 13,
                letterSpacing: 4.0,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),

          // ── 中央占位卡片（束线绕开它）─────────────────────
          Center(
            child: Container(
              key: _centerKey,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(110),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withAlpha(40),
                  width: 1,
                ),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '0.00',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 2.0,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'km · placeholder',
                    style: TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 11,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 三个占位控件区块 ──────────────────────────────
          Positioned(
            left: 22,
            right: 22,
            bottom: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _placeholderTile('INCLINE', '0%'),
                _placeholderTile('TIME', '00:00'),
                _placeholderTile('PACE', '--'),
              ],
            ),
          ),

          // ── 底部细进度条 ─────────────────────────────────
          Positioned(
            left: 22,
            right: 22,
            bottom: 28,
            child: _IntensityBar(intensity: _intensity),
          ),

          // ── 提示 ────────────────────────────────────────
          Positioned(
            right: 22,
            bottom: 8,
            child: Text(
              'swipe →  Running',
              style: TextStyle(
                color: Colors.white.withAlpha(60),
                fontSize: 10,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withAlpha(110),
            fontSize: 10,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _IntensityBar extends StatelessWidget {
  const _IntensityBar({required this.intensity});

  final double intensity;

  @override
  Widget build(BuildContext context) {
    final t = intensity.clamp(0.0, 1.0);
    return SizedBox(
      height: 4,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F1216),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          FractionallySizedBox(
            widthFactor: t,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00A0FF), Color(0xFFFF6428)],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
