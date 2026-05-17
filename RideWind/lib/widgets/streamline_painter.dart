import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 🌬️ 束线流线 CustomPainter
///
/// 移植自 Tixing 项目 `pc_tests/test_wind_resistance.py` 的 6 股弧形束线设计：
///   - 6 根细线从左侧均匀进入
///   - 中间遇到障碍物（中央占位卡片）：上 3 根弧形上展开，下 3 根弧形下展开
///   - 绕过后平滑回归原位
///   - 障碍物右侧产生尾流湍流，强度随 [intensity] 增大
///   - 颜色随 [intensity] 在冷蓝 → 暖橙之间渐变
///
/// [tick] 单调递增的帧序号，由外部 AnimationController 驱动。
/// [obstacle] 障碍物在画布中的矩形（绘制坐标系），可为空表示无障碍。
class StreamlinePainter extends CustomPainter {
  StreamlinePainter({
    required this.tick,
    required this.intensity,
    this.obstacle,
  }) : super();

  final double tick;
  final double intensity; // 0.0 ~ 1.0
  final Rect? obstacle;

  static const int _numLines = 6;
  static const int _segments = 140;

  // 每根线的相位 / 频率（与 pygame 版一致）
  static const List<double> _phases = [0.0, 1.7, 3.4, 0.9, 2.6, 4.3];
  static const List<double> _freqs = [1.0, 0.85, 1.15, 0.95, 1.1, 0.9];

  // 颜色锚点：低速冷蓝 → 中段冷白 → 高速暖橙
  static const Color _windLo = Color(0xFF00A0FF);
  static const Color _windMid = Color(0xFFB4DCFF);
  static const Color _windHi = Color(0xFFFF6428);

  static Color _lerp(Color a, Color b, double t) {
    t = t.clamp(0.0, 1.0);
    return Color.fromARGB(
      255,
      (a.r * 255 + (b.r * 255 - a.r * 255) * t).round(),
      (a.g * 255 + (b.g * 255 - a.g * 255) * t).round(),
      (a.b * 255 + (b.b * 255 - a.b * 255) * t).round(),
    );
  }

  static Color _windColor(double t) {
    if (t < 0.5) return _lerp(_windLo, _windMid, t * 2.0);
    return _lerp(_windMid, _windHi, (t - 0.5) * 2.0);
  }

  // ── 弧形绕行：cos 半波包络（与 pygame 版一致） ──────────────────
  double _arcDeflection(
    int lineIdx,
    double x,
    double obsCx,
    double obsCy,
    double obsHw,
    double obsHh,
    List<double> baseY,
  ) {
    final spread = obsHw * 2.5;
    final left = obsCx - spread;
    final right = obsCx + spread;
    if (x <= left || x >= right) return 0.0;

    final nx = (x - obsCx) / spread; // -1 ~ +1
    final envelope = (1.0 + math.cos(nx * math.pi)) / 2.0;

    const half = _numLines ~/ 2; // 3
    const lineGap = 12.0; // 屏幕坐标 (像素)，比 pygame 的 5 大一些以适配手机
    double needed;
    if (lineIdx < half) {
      // 上方线 → 向上 (负方向)
      final rank = half - lineIdx; // 1,2,3
      final peak = obsHh + rank * lineGap;
      needed = (obsCy - peak) - baseY[lineIdx];
      if (needed > 0) needed = 0;
    } else {
      final rank = lineIdx - half + 1;
      final peak = obsHh + rank * lineGap;
      needed = (obsCy + peak) - baseY[lineIdx];
      if (needed < 0) needed = 0;
    }
    return needed * envelope;
  }

  // ── 飘动：层流 + 尾流湍流 ─────────────────────────────────────
  double _flutter(double xNorm, double phase, double freq, double wakeBoost) {
    final fp = xNorm * 6.0 - tick * 0.06 * freq + phase;
    const baseAmp = 3.0; // 屏幕像素
    double y = math.sin(fp * 0.5) * baseAmp * 0.7;
    y += math.sin(fp * 1.2 + phase * 2.0) * baseAmp * 0.3;
    if (wakeBoost > 0) {
      final turb = 14.0 * wakeBoost;
      y += math.sin(fp * 3.0 + phase * 1.5) * turb * 0.45;
      y += math.sin(fp * 5.5 + phase * 3.0) * turb * 0.30;
      y += math.sin(fp * 9.0 + phase) * turb * 0.25;
    }
    return y;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final t = intensity.clamp(0.0, 1.0);
    final color = _windColor(t);
    final brightness = 0.6 + 0.4 * t;

    // 6 根线在画布纵向均匀分布（垂直内边距 14%）
    final yMin = size.height * 0.14;
    final yMax = size.height * 0.86;
    final baseY = List<double>.generate(
      _numLines,
      (i) => yMin + (yMax - yMin) * (i + 0.5) / _numLines,
    );

    // 障碍物参数
    double obsCx = 0, obsCy = 0, obsHw = 0, obsHh = 0;
    final hasObs = obstacle != null && !obstacle!.isEmpty;
    if (hasObs) {
      obsCx = obstacle!.center.dx;
      obsCy = obstacle!.center.dy;
      obsHw = obstacle!.width / 2 + 8;
      obsHh = obstacle!.height / 2 + 6;
    }

    final wakeStart = obsCx + obsHw;
    final wakeEnd = wakeStart + obsHw * 2.5;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (int i = 0; i < _numLines; i++) {
      final phase = _phases[i];
      final freq = _freqs[i];

      // 越靠中间越亮
      final centerDist =
          (i - (_numLines - 1) / 2.0).abs() / ((_numLines - 1) / 2.0);
      final lineBright = brightness * (0.65 + 0.35 * (1.0 - centerDist));
      final lc = Color.fromARGB(
        255,
        (color.r * 255 * lineBright).clamp(0, 255).round(),
        (color.g * 255 * lineBright).clamp(0, 255).round(),
        (color.b * 255 * lineBright).clamp(0, 255).round(),
      );

      final path = Path();
      for (int seg = 0; seg <= _segments; seg++) {
        final xNorm = seg / _segments;
        final x = xNorm * size.width;

        double wake = 0.0;
        if (hasObs && x > wakeStart && x < wakeEnd) {
          final wp = (x - wakeStart) / (wakeEnd - wakeStart);
          wake = math.sin(wp * math.pi) * t;
        }

        final flutterY = _flutter(xNorm, phase, freq, wake);
        final deflectY = hasObs
            ? _arcDeflection(i, x, obsCx, obsCy, obsHw, obsHh, baseY)
            : 0.0;
        final y = baseY[i] + deflectY + flutterY;

        if (seg == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      paint
        ..color = lc
        ..strokeWidth = 1.6;
      canvas.drawPath(path, paint);

      // 高强度时叠一层柔光
      if (t > 0.4) {
        final glow = (60 * (t - 0.4) / 0.6).round();
        final gc = Color.fromARGB(
          110,
          (lc.r * 255 + glow).clamp(0, 255).round(),
          (lc.g * 255 + glow).clamp(0, 255).round(),
          (lc.b * 255 + glow).clamp(0, 255).round(),
        );
        paint
          ..color = gc
          ..strokeWidth = 3.0;
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StreamlinePainter old) =>
      old.tick != tick ||
      old.intensity != intensity ||
      old.obstacle != obstacle;
}
