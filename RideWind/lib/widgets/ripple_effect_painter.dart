import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 精致水波纹效果绘制器
/// 从指尖触碰点向外扩散，3 圈渐变波纹 + 中心发光点
class RippleEffectPainter extends CustomPainter {
  final Rect targetRect;
  final double rippleProgress; // 0.0 ~ 1.0
  final Color rippleColor;

  /// 波纹最大扩散半径（从中心点算起）
  static const double _maxRadius = 80.0;

  /// 3 圈波纹的相位差
  static const List<double> _phases = [0.0, 0.33, 0.66];

  /// 中心发光点半径
  static const double _glowRadius = 8.0;

  RippleEffectPainter({
    required this.targetRect,
    required this.rippleProgress,
    this.rippleColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 波纹从目标区域底部中心发出（手指指尖位置）
    final center = Offset(
      targetRect.center.dx,
      targetRect.bottom - targetRect.height * 0.15,
    );

    // 中心发光点（始终显示，微微呼吸）
    final glowOpacity = 0.3 + 0.2 * (1.0 - (rippleProgress * 2 - 1).abs());
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        _glowRadius,
        [
          rippleColor.withOpacity(glowOpacity),
          rippleColor.withOpacity(0.0),
        ],
      );
    canvas.drawCircle(center, _glowRadius, glowPaint);

    // 3 圈波纹
    for (int i = 0; i < _phases.length; i++) {
      final phase = (rippleProgress + _phases[i]) % 1.0;
      _drawRippleRing(canvas, center, phase, i);
    }
  }

  void _drawRippleRing(Canvas canvas, Offset center, double progress, int index) {
    // 半径从 4px 扩展到 _maxRadius
    final radius = 4.0 + (_maxRadius - 4.0) * progress;

    // 不透明度：先升后降（在 0.2 处达到峰值，然后渐隐）
    final double opacity;
    if (progress < 0.2) {
      opacity = 0.6 * (progress / 0.2);
    } else {
      opacity = 0.6 * (1.0 - (progress - 0.2) / 0.8);
    }

    if (opacity <= 0.01) return;

    // 线宽从粗到细
    final strokeWidth = 2.5 * (1.0 - progress * 0.7);

    final paint = Paint()
      ..color = rippleColor.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant RippleEffectPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        rippleProgress != oldDelegate.rippleProgress ||
        rippleColor != oldDelegate.rippleColor;
  }
}
