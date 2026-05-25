import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../widgets/smoke_flow_widget.dart';

/// 🏎️ 跑步机仪表盘页面 — 真实汽车仪表盘风格
///
/// 三表功能映射（对标真实汽车仪表台）：
/// - 中间大表 = 速度表（0-20 km/h，像真车速度表：大数字、宽间距、红区）
/// - 左侧小表 = 时间表（0-60 min，像真车油量表：极简弧线 + 指针）
/// - 右侧小表 = 距离表（0-10 km，像真车温度表：极简弧线 + 指针）
///
/// 设计原则：
/// - 纯黑钢琴烤漆背景
/// - 天穹型面板（顶部外凸拱形 + 底边平直）
/// - 中间烟雾动画
/// - 底部留空给按钮
class TreadmillDashboardScreen extends StatefulWidget {
  const TreadmillDashboardScreen({super.key});

  @override
  State<TreadmillDashboardScreen> createState() =>
      _TreadmillDashboardScreenState();
}

class _TreadmillDashboardScreenState extends State<TreadmillDashboardScreen>
    with SingleTickerProviderStateMixin {
  double _currentSpeed = 0.0;
  double _currentCadence = 0.0;
  double _currentDistance = 0.0;

  late AnimationController _needleController;
  late Animation<double> _needleAnimation;
  double _targetSpeed = 0.0;
  double _previousSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _needleAnimation = CurvedAnimation(
      parent: _needleController,
      curve: Curves.elasticOut,
    );
    _needleController.addListener(() {
      setState(() {
        _currentSpeed = _previousSpeed +
            (_targetSpeed - _previousSpeed) * _needleAnimation.value;
        _currentCadence = _currentSpeed * 8.5;
        _currentDistance += _currentSpeed * 0.0001;
      });
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _animateToSpeed(8.5);
    });
  }

  void _animateToSpeed(double speed) {
    _previousSpeed = _currentSpeed;
    _targetSpeed = speed.clamp(0.0, 20.0);
    _needleController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _needleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final topPadding = MediaQuery.of(context).padding.top;

    final instrumentHeight = screenHeight * 0.32;
    final smokeHeight = screenHeight * 0.45;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _PianoBlackPainter()),
          ),
          Positioned(
            top: instrumentHeight,
            left: 0,
            right: 0,
            height: smokeHeight,
            child: const SmokeFlowWidget(
              windSpeed: 3.0,
              smokeIntensity: 0.4,
              smokeColor: Color(0xFFBBBBBB),
              showObstacle: false,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: instrumentHeight + 40,
            child: CustomPaint(
              size: Size(screenWidth, instrumentHeight + 40),
              painter: _DashboardPainter(
                speed: _currentSpeed,
                maxSpeed: 496.0,
                cadence: _currentCadence,
                maxCadence: 200.0,
                distance: _currentDistance,
                topPadding: topPadding,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 钢琴烤漆纯黑背景
// ═══════════════════════════════════════════════════════════════

class _PianoBlackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);

    final hl = Offset(size.width * 0.4, size.height * 0.2);
    canvas.drawOval(
      Rect.fromCenter(center: hl, width: size.width * 1.4, height: size.height * 0.5),
      Paint()
        ..shader = ui.Gradient.radial(hl, size.width * 0.7, [
          Colors.white.withOpacity(0.04),
          Colors.white.withOpacity(0.015),
          Colors.transparent,
        ], [0.0, 0.35, 1.0]),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════
// 轻盈烟雾效果 — 渐变椭圆模拟一缕飘散的烟
// ═══════════════════════════════════════════════════════════════

class _WispSmokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 一缕从左侧飘出、逐渐发散的烟雾
    // 源点在左侧中间，往右飘散时越来越宽越来越淡

    final sourceX = size.width * 0.05;
    final sourceY = size.height * 0.5;

    // 用多个逐渐变大的模糊圆点模拟发散效果
    const puffs = 12;
    for (int i = 0; i < puffs; i++) {
      final t = i / (puffs - 1); // 0 到 1
      // X 位置：从左到右
      final x = sourceX + (size.width * 0.85) * t;
      // Y 位置：轻微 S 形飘动
      final y = sourceY + sin(t * 3.5) * size.height * 0.12;
      // 大小：从小到大（发散）
      final radius = 8.0 + t * 45.0;
      // 透明度：从浓到淡
      final opacity = 0.25 * (1.0 - t * 0.7);

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Colors.white.withOpacity(opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + t * 25),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Wisp {
  final double x, y, width, height, opacity;
  const _Wisp(this.x, this.y, this.width, this.height, this.opacity);
}

// ═══════════════════════════════════════════════════════════════
// 仪表台面板 Painter — 真实汽车仪表盘设计
// ═══════════════════════════════════════════════════════════════

class _DashboardPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final double cadence;
  final double maxCadence;
  final double distance;
  final double topPadding;

  _DashboardPainter({
    required this.speed,
    required this.maxSpeed,
    required this.cadence,
    required this.maxCadence,
    required this.distance,
    required this.topPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawPanelBackground(canvas, size);

    final centerY = topPadding + (size.height - topPadding - 30) * 0.45;
    final w = size.width;

    // 中间大表：速度表（0-20 km/h）— 放大
    final mainR = w * 0.24;
    final mainC = Offset(w * 0.5, centerY);
    _drawSpeedometer(canvas, mainC, mainR);

    // 左侧小表：油量表（E-F 风格，对应体力/电量）
    final subR = w * 0.13;
    final subDy = mainR * 0.35;
    final leftC = Offset(w * 0.5 - mainR - subR - w * 0.02, centerY + subDy);
    final fuelLevel = (cadence / maxCadence).clamp(0.0, 1.0); // 0=E, 1=F
    _drawFuelGauge(canvas, leftC, subR, fuelLevel);

    // 右侧小表：档位显示（1-6 档，根据速度自动计算）
    final rightC = Offset(w * 0.5 + mainR + subR + w * 0.02, centerY + subDy);
    final gear = _speedToGear(speed);
    _drawGearIndicator(canvas, rightC, subR, gear);

    // ═══ 速度攀升矩形条（大表和进度条之间） ═══
    _drawSpeedBars(canvas, size, w);

    // ═══ 里程进度条（仪表盘和底边之间的空隙） ═══
    _drawMileageBar(canvas, size, w);
  }

  /// 速度攀升方块 — 宽度等于大表直径，更多更粗的方块
  void _drawSpeedBars(Canvas canvas, Size size, double w) {
    const barCount = 16;
    // 宽度等于大表直径（mainR = w * 0.24，直径 = w * 0.48）
    final totalWidth = w * 0.48;
    final singleBarWidth = 10.0; // 更粗
    final barGap = (totalWidth - barCount * singleBarWidth) / (barCount - 1);
    final startX = (w - totalWidth) / 2;
    final barBottom = size.height - 55;

    // 高度平缓递增
    final minH = 10.0;
    final maxH = 24.0;

    final activeCount = ((speed / 20.0) * barCount).ceil().clamp(0, barCount);

    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (singleBarWidth + barGap);
      final t = i / (barCount - 1);
      final h = minH + (maxH - minH) * t;
      final y = barBottom - h;

      final isActive = i < activeCount;

      Color barColor;
      if (!isActive) {
        barColor = Colors.white.withOpacity(0.07);
      } else {
        barColor = Color.lerp(
          const Color(0xFFFF6060),
          const Color(0xFFCC1010),
          t,
        )!;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, singleBarWidth, h),
          const Radius.circular(1.5),
        ),
        Paint()..color = barColor,
      );
    }
  }

  /// 里程进度条 — 紧跟仪表盘下方，进度条在上，下方左km右数字
  void _drawMileageBar(Canvas canvas, Size size, double w) {
    final barHeight = 14.0;

    // 进度条位置：紧贴面板底部上方（留出文字空间）
    final barWidth = w * 0.75;
    final barLeft = (w - barWidth) / 2;
    final barTop = size.height - 50; // 给下方 km+数字留空间

    // 进度条底色
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
      const Radius.circular(4),
    );
    canvas.drawRRect(trackRect, Paint()..color = Colors.white.withOpacity(0.08));

    // 进度条填充
    final ratio = (distance / 10.0).clamp(0.0, 1.0);
    if (ratio > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, barWidth * ratio, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(fillRect, Paint()..color = Colors.white.withOpacity(0.55));
    }

    // 下方左边 "km"（与进度条左端对齐）
    final kmTp = TextPainter(
      text: TextSpan(text: 'km', style: TextStyle(
        color: Colors.white.withOpacity(0.4),
        fontSize: 11,
        fontWeight: FontWeight.w400,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    kmTp.paint(canvas, Offset(barLeft, barTop + barHeight + 5));

    // 下方右边数字 "000.0"（金属光泽）
    final kmNum = distance.toStringAsFixed(1).padLeft(5, '0');
    final numTp = TextPainter(
      text: TextSpan(text: kmNum, style: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
        shadows: [
          Shadow(color: Colors.black, offset: const Offset(0, 2), blurRadius: 4),
          Shadow(color: Colors.black.withOpacity(0.8), offset: const Offset(1, 3), blurRadius: 6),
        ],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    numTp.paint(canvas, Offset(
      barLeft + barWidth - numTp.width,
      barTop + barHeight + 5,
    ));
  }

  // ═══ 天穹型面板背景 ═══
  void _drawPanelBackground(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.5, -size.height * 0.08, size.width, size.height * 0.35)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = Colors.black);

    // 穹顶微光
    canvas.save();
    canvas.clipPath(path);
    final gc = Offset(size.width * 0.45, size.height * 0.2);
    canvas.drawOval(
      Rect.fromCenter(center: gc, width: size.width * 0.7, height: size.height * 0.3),
      Paint()
        ..shader = ui.Gradient.radial(gc, size.width * 0.35, [
          Colors.white.withOpacity(0.025),
          Colors.white.withOpacity(0.008),
          Colors.transparent,
        ], [0.0, 0.4, 1.0]),
    );
    canvas.restore();

    // 穹顶边线
    final dome = Path()
      ..moveTo(0, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.5, -size.height * 0.08, size.width, size.height * 0.35);
    canvas.drawPath(dome, Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    // 穹顶阴影（向下投射，隐隐约约的笼罩感）
    final domeShadow = Path()
      ..moveTo(0, size.height * 0.35 + 4)
      ..quadraticBezierTo(size.width * 0.5, -size.height * 0.08 + 8, size.width, size.height * 0.35 + 4);
    canvas.drawPath(domeShadow, Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  }


  // ═══════════════════════════════════════════════════════════════
  // 速度表（中间大表）— 真实汽车速度表风格
  //
  // 参考保时捷 911 速度表：
  // - 只有 5 个大数字：0, 5, 10, 15, 20
  // - 每个大刻度之间 1 个中刻度（2.5 km/h）
  // - 数字巨大清晰
  // - 红区 16-20（最后一段）
  // - 指针粗壮、锥形、红色
  // ═══════════════════════════════════════════════════════════════
  void _drawSpeedometer(Canvas canvas, Offset c, double r) {
    const startDeg = 135.0;
    const sweepDeg = 270.0;
    const maxVal = 496.0;
    const redStart = 400.0;

    canvas.save();

    // ── 外圈（去掉，不需要内外圈之分） ──

    // ── 外环阴影 ──
    canvas.drawCircle(
      Offset(c.dx + 1, c.dy + 3),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── 表盘底板（直接画，无边框） ──
    canvas.drawCircle(c, r * 0.92, Paint()
      ..shader = ui.Gradient.radial(
        Offset(c.dx - r * 0.1, c.dy - r * 0.15), r * 1.4,
        [const Color(0xFF0A0A0A), const Color(0xFF030303), Colors.black],
        [0.0, 0.4, 1.0],
      ));

    // ── 红区弧 (400-496) ──
    final redRatio0 = redStart / maxVal;
    final redArcStart = _rad(startDeg + sweepDeg * redRatio0);
    final redArcSweep = _rad(sweepDeg * (1.0 - redRatio0));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      redArcStart, redArcSweep, false,
      Paint()
        ..color = const Color(0xFFCC0000).withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14,
    );

    // ── 刻度线 ──
    // 粗长 / 细短 交替（每 50 km/h 粗长，每 10 km/h 细短）
    const majorStep = 50.0;
    const minorStep = 10.0;
    final totalMinor = (maxVal / minorStep).round();

    for (int i = 0; i <= totalMinor; i++) {
      final val = i * minorStep;
      if (val > maxVal) break;
      final t = val / maxVal;
      final angle = _rad(startDeg + sweepDeg * t);
      final isMajor = (val % majorStep) < 0.1;
      final isRed = val >= redStart;

      final outerR = r * 0.86;
      final innerR = isMajor ? r * 0.70 : r * 0.78;
      final width = isMajor ? 2.8 : 0.9;

      Color color;
      if (isRed) {
        color = isMajor ? const Color(0xFFFF3333) : const Color(0xFFAA2222).withOpacity(0.6);
      } else {
        color = isMajor ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.25);
      }

      final outer = Offset(c.dx + outerR * cos(angle), c.dy + outerR * sin(angle));
      final inner = Offset(c.dx + innerR * cos(angle), c.dy + innerR * sin(angle));
      canvas.drawLine(outer, inner, Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt);
    }

    // ── 数字：0, 100, 200, 300, 400 ──
    const numStep = 100.0;
    final numCount = (maxVal / numStep).floor();
    for (int i = 0; i <= numCount; i++) {
      final val = i * numStep;
      final t = val / maxVal;
      final angle = _rad(startDeg + sweepDeg * t);
      final isRed = val >= redStart;

      final tp = TextPainter(
        text: TextSpan(
          text: '${val.round()}',
          style: TextStyle(
            color: isRed ? const Color(0xFFFF4040) : Colors.white.withOpacity(0.9),
            fontSize: r * 0.15,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelR = r * 0.54;
      tp.paint(canvas, Offset(
        c.dx + labelR * cos(angle) - tp.width / 2,
        c.dy + labelR * sin(angle) - tp.height / 2,
      ));
    }

    // ── 指针（细长线，无中心轴钉） ──
    final displaySpeed = (speed / 20.0) * maxVal;
    _drawThinNeedle(canvas, c, r, displaySpeed / maxVal, startDeg, sweepDeg);

    // ── 数值显示（下移+放大，km/h 紧贴数字右下方） ──
    final valText = displaySpeed < 10
        ? displaySpeed.toStringAsFixed(0)
        : '${displaySpeed.round()}';
    final vtp = TextPainter(
      text: TextSpan(text: valText, style: TextStyle(
        color: Colors.white,
        fontSize: r * 0.28,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        height: 1.0,
        shadows: [
          Shadow(color: Colors.black, offset: const Offset(0, 3), blurRadius: 6),
          Shadow(color: Colors.black.withOpacity(0.8), offset: const Offset(1, 5), blurRadius: 10),
        ],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    final valX = c.dx - vtp.width / 2;
    final valY = c.dy + r * 0.42;
    vtp.paint(canvas, Offset(valX, valY));

    // km/h 单位（紧贴数字右下方）
    final utp = TextPainter(
      text: TextSpan(text: 'km/h', style: TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: r * 0.08,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        shadows: [
          Shadow(color: Colors.black, offset: const Offset(0, 1), blurRadius: 3),
        ],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    utp.paint(canvas, Offset(
      valX + vtp.width + 3,
      valY + vtp.height - utp.height,
    ));

    // ── 玻璃反光 ──
    _drawGlass(canvas, c, r);

    canvas.restore();
  }

  // ═══════════════════════════════════════════════════════════════
  // 油量表（左侧小表）— 上半圆弧 + 细长指针
  //
  // 只显示上半弧（180°，从左到右）
  // 指针是一根细长线，没有中心轴钉
  // ═══════════════════════════════════════════════════════════════
  void _drawFuelGauge(Canvas canvas, Offset c, double r, double level) {
    const startDeg = 135.0; // 和大表一样的弧度
    const sweepDeg = 270.0;

    canvas.save();

    // 外环阴影（金属质感，像 running mode）
    canvas.drawCircle(
      Offset(c.dx + 0.5, c.dy + 2),
      r * 0.92,
      Paint()
        ..color = Colors.black.withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 表盘底板（无边框，无高光边线）
    canvas.drawCircle(c, r * 0.90, Paint()
      ..shader = ui.Gradient.radial(c, r * 1.2,
        [const Color(0xFF080808), Colors.black], [0.0, 1.0]));

    // 弧形轨道（靠近边缘，带光泽渐变）
    // 底层：暗色弧
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      _rad(startDeg), _rad(sweepDeg), false,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round,
    );
    // 上层：亮色弧（上半部分更亮，模拟光泽）
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      _rad(startDeg), _rad(sweepDeg * 0.6), false,
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // 低油量警告区（左端红色弧，E 端）
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      _rad(startDeg), _rad(sweepDeg * 0.2), false,
      Paint()
        ..color = const Color(0xFFCC3333).withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..strokeCap = StrokeCap.round,
    );

    // 刻度线（只有一种：粗短，在弧形轨道内侧）
    const tickCount = 10;
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final angle = _rad(startDeg + sweepDeg * t);

      final outerR = r * 0.78; // 弧形轨道(0.82)内侧
      final innerR = r * 0.72;

      final outer = Offset(c.dx + outerR * cos(angle), c.dy + outerR * sin(angle));
      final inner = Offset(c.dx + innerR * cos(angle), c.dy + innerR * sin(angle));
      canvas.drawLine(outer, inner, Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.butt);
    }

    // E 和 F 标记（直接贴在油箱图标左右两侧）
    final etp = TextPainter(
      text: TextSpan(text: 'E', style: TextStyle(
        color: const Color(0xFFFF5555), fontSize: r * 0.14, fontWeight: FontWeight.w700,
        shadows: [Shadow(color: Colors.black, offset: const Offset(0, 2), blurRadius: 4)],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    etp.paint(canvas, Offset(
      c.dx - r * 0.22 - etp.width,
      c.dy + r * 0.37,
    ));

    final ftp = TextPainter(
      text: TextSpan(text: 'F', style: TextStyle(
        color: Colors.white, fontSize: r * 0.14, fontWeight: FontWeight.w700,
        shadows: [Shadow(color: Colors.black, offset: const Offset(0, 2), blurRadius: 4)],
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    ftp.paint(canvas, Offset(
      c.dx + r * 0.22,
      c.dy + r * 0.37,
    ));

    // ⛽ 图标（放大，往下移）
    final iconTp = TextPainter(
      text: TextSpan(text: '⛽', style: TextStyle(fontSize: r * 0.28)),
      textDirection: TextDirection.ltr,
    )..layout();
    iconTp.paint(canvas, Offset(c.dx - iconTp.width / 2, c.dy + r * 0.35));

    // 细长指针（简单线条，无中心轴钉）
    _drawThinNeedle(canvas, c, r, level, startDeg, sweepDeg);

    // 玻璃反光
    _drawGlass(canvas, c, r);

    canvas.restore();
  }

  // ═══════════════════════════════════════════════════════════════
  // 档位显示（右侧小表）— 上半圆弧 + 细长指针
  //
  // 档位数字沿上半弧排列，细长指针指向当前档位
  // ═══════════════════════════════════════════════════════════════
  void _drawGearIndicator(Canvas canvas, Offset c, double r, int gear) {
    const startDeg = 135.0; // 和大表一样的弧度
    const sweepDeg = 270.0;

    canvas.save();

    // 外环阴影（金属质感）
    canvas.drawCircle(
      Offset(c.dx + 0.5, c.dy + 2),
      r * 0.92,
      Paint()
        ..color = Colors.black.withOpacity(0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 表盘底板（无边框，无高光边线）
    canvas.drawCircle(c, r * 0.90, Paint()
      ..shader = ui.Gradient.radial(c, r * 1.2,
        [const Color(0xFF080808), Colors.black], [0.0, 1.0]));

    // 弧形轨道（靠近边缘，带光泽渐变）
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      _rad(startDeg), _rad(sweepDeg), false,
      Paint()
        ..color = Colors.white.withOpacity(0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.82),
      _rad(startDeg), _rad(sweepDeg * 0.6), false,
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..strokeCap = StrokeCap.round,
    );

    // 刻度线（长短交替：长的对应档位有数字，短的无数字）
    // 6档 = 6个长刻度，中间各1个短刻度 = 总共11个刻度
    const totalTicks = 11;
    for (int i = 0; i <= totalTicks; i++) {
      final t = i / totalTicks.toDouble();
      final angle = _rad(startDeg + sweepDeg * t);
      final isLong = i % 2 == 0; // 偶数=长（对应档位），奇数=短

      final outerR = r * 0.78;
      final innerR = isLong ? r * 0.62 : r * 0.70; // 长的更长
      final width = isLong ? 2.0 : 1.2;

      final outer = Offset(c.dx + outerR * cos(angle), c.dy + outerR * sin(angle));
      final inner = Offset(c.dx + innerR * cos(angle), c.dy + innerR * sin(angle));
      canvas.drawLine(outer, inner, Paint()
        ..color = Colors.white.withOpacity(isLong ? 0.7 : 0.3)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.butt);
    }

    // 档位数字沿弧排列（只在长刻度位置，下调）
    const gears = [1, 2, 3, 4, 5, 6];
    final gearR = r * 0.50; // 再下调

    for (int i = 0; i < gears.length; i++) {
      final t = i / (gears.length - 1);
      final angle = _rad(startDeg + sweepDeg * t);
      final isActive = gears[i] == gear;

      final gtp = TextPainter(
        text: TextSpan(
          text: '${gears[i]}',
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.25),
            fontSize: r * 0.18,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w400,
            shadows: isActive ? [
              Shadow(color: Colors.black, offset: const Offset(0, 2), blurRadius: 4),
            ] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      gtp.paint(canvas, Offset(
        c.dx + gearR * cos(angle) - gtp.width / 2,
        c.dy + gearR * sin(angle) - gtp.height / 2,
      ));
    }

    // 中心大档位数字（金属光泽）
    final mainGtp = TextPainter(
      text: TextSpan(
        text: '$gear',
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 0.45,
          fontWeight: FontWeight.w900,
          height: 1.0,
          shadows: [
            Shadow(color: Colors.black, offset: const Offset(0, 3), blurRadius: 6),
            Shadow(color: Colors.black.withOpacity(0.8), offset: const Offset(1, 5), blurRadius: 10),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    mainGtp.paint(canvas, Offset(
      c.dx - mainGtp.width / 2,
      c.dy + r * 0.25,
    ));

    // "GEAR" 标签（下调，不和数字重叠）
    final labelTp = TextPainter(
      text: TextSpan(text: 'GEAR', style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: r * 0.11,
        fontWeight: FontWeight.w400,
        letterSpacing: 2.0,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(
      c.dx - labelTp.width / 2,
      c.dy + r * 0.62,
    ));

    // 细长指针指向当前档位
    final gearRatio = (gear - 1) / 5.0; // 1-6 映射到 0-1
    _drawThinNeedle(canvas, c, r, gearRatio, startDeg, sweepDeg);

    // 玻璃反光
    _drawGlass(canvas, c, r);

    canvas.restore();
  }

  /// 细长三角形指针 — 尖端尖锐，底部有宽度
  void _drawThinNeedle(Canvas canvas, Offset c, double r,
      double ratio, double startDeg, double sweepDeg) {
    final angle = _rad(startDeg + sweepDeg * ratio.clamp(0.0, 1.0));
    final tipR = r * 0.73; // 尖端稍微穿入刻度线，指向时有重叠连接感
    final baseR = r * 0.18; // 尾部往后延长
    final perp = angle + pi / 2;
    final baseHalfW = 2.0; // 底部半宽（更细）

    // 尖端点（一个点，尖锐）
    final tip = Offset(c.dx + tipR * cos(angle), c.dy + tipR * sin(angle));
    // 底部两个角点
    final baseCenter = Offset(c.dx - baseR * cos(angle), c.dy - baseR * sin(angle));
    final baseL = Offset(baseCenter.dx + baseHalfW * cos(perp), baseCenter.dy + baseHalfW * sin(perp));
    final baseR2 = Offset(baseCenter.dx - baseHalfW * cos(perp), baseCenter.dy - baseHalfW * sin(perp));

    // 三角形阴影
    final shadowPath = Path()
      ..moveTo(tip.dx + 0.5, tip.dy + 1.5)
      ..lineTo(baseL.dx + 0.5, baseL.dy + 1.5)
      ..lineTo(baseR2.dx + 0.5, baseR2.dy + 1.5)
      ..close();
    canvas.drawPath(shadowPath, Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    // 三角形指针主体
    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR2.dx, baseR2.dy)
      ..close();
    canvas.drawPath(needlePath, Paint()..color = const Color(0xFFEE2020));
  }

  /// 速度转档位（模拟 6 档变速）
  int _speedToGear(double spd) {
    if (spd <= 0) return 1;
    if (spd < 3.5) return 1;
    if (spd < 6.5) return 2;
    if (spd < 9.5) return 3;
    if (spd < 12.5) return 4;
    if (spd < 16.0) return 5;
    return 6;
  }


  // ═══════════════════════════════════════════════════════════════
  // 共用组件
  // ═══════════════════════════════════════════════════════════════

  /// 指针 — 锥形红色，带阴影和配重
  void _drawNeedle(Canvas canvas, Offset c, double r,
      double ratio, double startDeg, double sweepDeg, bool isMain) {
    final angle = _rad(startDeg + sweepDeg * ratio.clamp(0.0, 1.0));
    final tipR = r * (isMain ? 0.84 : 0.74);
    final tailR = r * 0.15;
    final perp = angle + pi / 2;

    final tip = Offset(c.dx + tipR * cos(angle), c.dy + tipR * sin(angle));
    final tail = Offset(c.dx - tailR * cos(angle), c.dy - tailR * sin(angle));

    // 阴影
    canvas.drawLine(
      tip + const Offset(1, 2), tail + const Offset(1, 2),
      Paint()
        ..color = Colors.black.withOpacity(0.6)
        ..strokeWidth = isMain ? 4.0 : 3.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 前半段（红色锥形）
    final tipW = isMain ? 1.2 : 0.8;
    final baseW = isMain ? 3.5 : 2.2;
    final front = Path()
      ..moveTo(tip.dx + tipW * cos(perp), tip.dy + tipW * sin(perp))
      ..lineTo(tip.dx - tipW * cos(perp), tip.dy - tipW * sin(perp))
      ..lineTo(c.dx - baseW * cos(perp), c.dy - baseW * sin(perp))
      ..lineTo(c.dx + baseW * cos(perp), c.dy + baseW * sin(perp))
      ..close();

    canvas.drawPath(front, Paint()
      ..shader = ui.Gradient.linear(c, tip, [
        const Color(0xFFAA1010),
        const Color(0xFFEE2020),
      ], [0.0, 1.0]));

    // 后半段（配重）
    final tailW = isMain ? 5.5 : 3.5;
    final back = Path()
      ..moveTo(c.dx + baseW * cos(perp), c.dy + baseW * sin(perp))
      ..lineTo(c.dx - baseW * cos(perp), c.dy - baseW * sin(perp))
      ..lineTo(tail.dx - tailW * cos(perp), tail.dy - tailW * sin(perp))
      ..lineTo(tail.dx + tailW * cos(perp), tail.dy + tailW * sin(perp))
      ..close();

    canvas.drawPath(back, Paint()..color = const Color(0xFF1A1A1A));
  }

  /// 中心轴心
  void _drawHub(Canvas canvas, Offset c, double capR) {
    canvas.drawCircle(c, capR, Paint()
      ..shader = ui.Gradient.radial(
        Offset(c.dx - capR * 0.3, c.dy - capR * 0.3), capR * 2,
        [const Color(0xFF707070), const Color(0xFF3A3A3A), const Color(0xFF1A1A1A)],
        [0.0, 0.5, 1.0],
      ));
    canvas.drawCircle(c, capR * 0.5, Paint()..color = const Color(0xFF080808));
    canvas.drawCircle(
      Offset(c.dx - capR * 0.2, c.dy - capR * 0.2),
      capR * 0.15,
      Paint()..color = Colors.white.withOpacity(0.3),
    );
  }

  /// 中心数值文字 + 单位
  void _drawCenterText(Canvas canvas, Offset c, double r,
      String value, String unit, {String? labelAbove}) {
    // 功能标签（小表上方显示"时间"/"距离"）
    if (labelAbove != null) {
      final ltp = TextPainter(
        text: TextSpan(text: labelAbove, style: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: r * 0.11,
          fontWeight: FontWeight.w400,
          letterSpacing: 2.0,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      ltp.paint(canvas, Offset(c.dx - ltp.width / 2, c.dy - r * 0.05));
    }

    // 数值
    final vtp = TextPainter(
      text: TextSpan(text: value, style: TextStyle(
        color: Colors.white.withOpacity(0.92),
        fontSize: r * 0.22,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.5,
        height: 1.0,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    vtp.paint(canvas, Offset(c.dx - vtp.width / 2, c.dy + r * 0.18));

    // 单位
    final utp = TextPainter(
      text: TextSpan(text: unit, style: TextStyle(
        color: Colors.white.withOpacity(0.3),
        fontSize: r * 0.08,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    utp.paint(canvas, Offset(c.dx - utp.width / 2, c.dy + r * 0.35));
  }

  /// 玻璃反光
  void _drawGlass(Canvas canvas, Offset c, double r) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.90)));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.1, c.dy - r * 0.4),
        width: r * 1.1, height: r * 0.45,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - r * 0.65),
          Offset(c.dx, c.dy - r * 0.15),
          [Colors.white.withOpacity(0.05), Colors.transparent],
          [0.0, 1.0],
        ),
    );
    canvas.restore();
  }

  double _rad(double deg) => deg * pi / 180.0;

  @override
  bool shouldRepaint(covariant _DashboardPainter old) {
    return old.speed != speed || old.cadence != cadence || old.distance != distance;
  }
}
