/// 驾驶操控区 V6 — 天穹面板（实心）+ 中心车库轮播 + 全屏触控
///
/// 设计理念：
/// - 底部是一整块实心面板，顶部边缘是天穹型弧线（向上凸起）
/// - 和上方仪表盘面板对称呼应（上面板顶部弧线向上，底面板顶部弧线也向上）
/// - 圆形车库图片嵌在面板中央
/// - 车名文字在图片下方，面板内
/// - 拨片贴在面板两侧
/// - 整个面板区域按住 = 油门/刹车（左刹右油）

import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════
// 回调
// ═══════════════════════════════════════════════════════════════

typedef ThrottleCallback = void Function(double throttle);
typedef BrakeCallback = void Function(double brake);
typedef GearCallback = void Function(String mode);
typedef CarChangedCallback = void Function(int index, String carName);

// ═══════════════════════════════════════════════════════════════
// 主控件
// ═══════════════════════════════════════════════════════════════

class DrivingControlsWidget extends StatefulWidget {
  final ThrottleCallback? onThrottleChanged;
  final BrakeCallback? onBrakeChanged;
  final GearCallback? onGearChanged;
  final CarChangedCallback? onCarChanged;
  final int currentGear;
  final String driveMode;
  final double currentRpm; // 0~1
  final bool justShifted;

  const DrivingControlsWidget({
    super.key,
    this.onThrottleChanged,
    this.onBrakeChanged,
    this.onGearChanged,
    this.onCarChanged,
    this.currentGear = 1,
    this.driveMode = 'D',
    this.currentRpm = 0.0,
    this.justShifted = false,
  });

  @override
  State<DrivingControlsWidget> createState() => _DrivingControlsWidgetState();
}

class _DrivingControlsWidgetState extends State<DrivingControlsWidget>
    with SingleTickerProviderStateMixin {
  double _throttle = 0.0;
  double _brake = 0.0;
  bool _isThrottling = false;
  bool _isBraking = false;
  int _pointerCount = 0;

  late AnimationController _pulseController;

  // 车库轮播
  List<Map<String, dynamic>> _carList = [];
  late PageController _pageController;
  int _currentCarIndex = 0;
  bool _carListLoaded = false;

  // 渐进速率
  static const double _rampUp = 0.03;
  static const double _rampDown = 0.05;
  static const double _brakeRampUp = 0.05;
  static const double _brakeRampDown = 0.08;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_tick);
    _pulseController.repeat();

    _pageController = PageController(
      viewportFraction: 1.0,
      initialPage: 0,
    );

    _loadCarList();
  }

  Future<void> _loadCarList() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_index.json',
      );
      final List<dynamic> data = json.decode(jsonStr);
      setState(() {
        _carList = data.cast<Map<String, dynamic>>();
        _carListLoaded = true;
        if (_carList.isNotEmpty) {
          _currentCarIndex = Random().nextInt(_carList.length);
          _pageController = PageController(
            viewportFraction: 1.0,
            initialPage: _currentCarIndex,
          );
        }
      });
    } catch (e) {
      debugPrint('Failed to load car_index.json: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _tick() {
    bool changed = false;

    if (_isThrottling && !_isBraking) {
      final old = _throttle;
      _throttle = (_throttle + _rampUp).clamp(0.0, 1.0);
      if (_throttle != old) changed = true;
    } else {
      final old = _throttle;
      _throttle = (_throttle - _rampDown).clamp(0.0, 1.0);
      if (_throttle != old) changed = true;
    }

    if (_isBraking) {
      final old = _brake;
      _brake = (_brake + _brakeRampUp).clamp(0.0, 1.0);
      if (_brake != old) changed = true;
    } else {
      final old = _brake;
      _brake = (_brake - _brakeRampDown).clamp(0.0, 1.0);
      if (_brake != old) changed = true;
    }

    if (changed) {
      widget.onThrottleChanged?.call(_throttle);
      widget.onBrakeChanged?.call(_brake);
      setState(() {});
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerCount++;
    final screenWidth = context.size?.width ?? 400;
    final isLeftSide = event.localPosition.dx < screenWidth / 2;

    if (isLeftSide) {
      _isBraking = true;
      _isThrottling = false;
      HapticFeedback.mediumImpact();
    } else {
      _isThrottling = true;
      _isBraking = false;
      HapticFeedback.lightImpact();
    }
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 10);
    if (_pointerCount == 0) {
      _isThrottling = false;
      _isBraking = false;
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 10);
    if (_pointerCount == 0) {
      _isThrottling = false;
      _isBraking = false;
    }
    setState(() {});
  }

  void _shiftUp() {
    HapticFeedback.mediumImpact();
    // 单击右拨片 = 下一张车
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _shiftDown() {
    HapticFeedback.mediumImpact();
    // 单击左拨片 = 上一张车
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onCarPageChanged(int index) {
    setState(() {
      _currentCarIndex = index;
    });
    HapticFeedback.selectionClick();
    if (_carList.isNotEmpty) {
      final car = _carList[index % _carList.length];
      widget.onCarChanged?.call(index % _carList.length, car['full_name'] ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // 面板顶部弧线的最高点（向上凸起的程度）
        // 弧线起点/终点 Y = h * 0.35（面板从这里开始）
        // 弧线最高点 Y = h * 0.05（控制点，越小弧线越饱满）
        final arcEdgeY = h * 0.35;

        // 图片区域：裸图片，无边框无容器
        final imgWidth = w * 0.55;
        final imgHeight = imgWidth * 0.55;
        final imgCenterY = arcEdgeY + (h - arcEdgeY) * 0.36;

        // 车名文字位置
        final textY = imgCenterY + imgHeight / 2 + 8;

        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // 实心面板背景 + 天穹弧线（带刻度+进度） + 拨片
              Positioned.fill(
                child: CustomPaint(
                  painter: _ControlPanelPainter(
                    rpm: widget.currentRpm,
                    throttle: _throttle,
                    brake: _brake,
                    isThrottling: _isThrottling,
                    isBraking: _isBraking,
                    pulsePhase: _pulseController.value,
                    justShifted: widget.justShifted,
                  ),
                ),
              ),

              // 中心车库图片（裸图，无边框无容器）
              if (_carListLoaded && _carList.isNotEmpty)
                Positioned(
                  left: w / 2 - imgWidth / 2,
                  top: imgCenterY - imgHeight / 2,
                  width: imgWidth,
                  height: imgHeight,
                  child: _buildCarImage(imgWidth, imgHeight),
                ),

              // 车名标签
              if (_carListLoaded && _carList.isNotEmpty)
                Positioned(
                  left: 50,
                  right: 50,
                  top: textY,
                  child: Text(
                    _carList[_currentCarIndex % _carList.length]['full_name'] ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          offset: const Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),

              // 左拨片触控区（中心和图片中心对齐）
              Positioned(
                left: w / 2 - imgWidth / 2 - 40,
                top: imgCenterY - 20,
                width: 40,
                height: 60,
                child: GestureDetector(
                  onTap: _shiftDown,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
              // 右拨片触控区（中心和图片中心对齐）
              Positioned(
                right: w / 2 - imgWidth / 2 - 40,
                top: imgCenterY - 20,
                width: 40,
                height: 60,
                child: GestureDetector(
                  onTap: _shiftUp,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建车库图片（裸图，无边框无容器，直接展示）
  Widget _buildCarImage(double imgWidth, double imgHeight) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onCarPageChanged,
      itemCount: _carList.length * 1000,
      itemBuilder: (context, index) {
        final carIndex = index % _carList.length;
        final car = _carList[carIndex];
        final filename = car['filename'] as String? ?? '';

        return Image.asset(
          'assets/car_thumbnails/$filename',
          fit: BoxFit.contain,
          width: imgWidth,
          height: imgHeight,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(
              Icons.directions_car,
              color: Colors.white.withValues(alpha: 0.2),
              size: imgHeight * 0.5,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 操控面板 Painter — 实心天穹面板 + 弧线高光 + 拨片 + 转速光带
// ═══════════════════════════════════════════════════════════════

class _ControlPanelPainter extends CustomPainter {
  final double rpm;
  final double throttle;
  final double brake;
  final bool isThrottling;
  final bool isBraking;
  final double pulsePhase;
  final bool justShifted;

  _ControlPanelPainter({
    required this.rpm,
    required this.throttle,
    required this.brake,
    required this.isThrottling,
    required this.isBraking,
    required this.pulsePhase,
    required this.justShifted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 面板弧线参数（和 build() 中一致）
    final arcEdgeY = h * 0.35;

    // ═══ 1. 实心面板（天穹弧线顶部 + 底边平直） ═══
    _drawPanel(canvas, w, h, arcEdgeY);

    // ═══ 2. 弧线高光 + 刻度 + 转速进度（集成在天穹弧线上） ═══
    _drawArcWithTicks(canvas, w, h, arcEdgeY);

    // ═══ 3. 拨片（中心和图片中心对齐） ═══
    final imgHalfW = w * 0.55 / 2;
    final imgCY = arcEdgeY + (h - arcEdgeY) * 0.36;
    _drawPaddle(canvas, w / 2 - imgHalfW - 28, imgCY + 10, true);
    _drawPaddle(canvas, w / 2 + imgHalfW + 28, imgCY + 10, false);

    // ═══ 4. 操作提示 ═══
    if (throttle < 0.01 && brake < 0.01) {
      _drawHint(canvas, w / 2, h - 20);
    }
  }

  /// 实心面板 — 顶部天穹弧线向上凸起，底边平直，整块填充
  void _drawPanel(Canvas canvas, double w, double h, double arcEdgeY) {
    final panelPath = Path()
      ..moveTo(0, h) // 左下角
      ..lineTo(0, arcEdgeY) // 左侧边
      // 顶部天穹弧线
      ..quadraticBezierTo(
        w * 0.5, // 控制点 X = 中间
        arcEdgeY - h * 0.25, // 控制点 Y = 向上凸起
        w, // 终点 X = 右端
        arcEdgeY, // 终点 Y = 和左端同高
      )
      ..lineTo(w, h) // 右下角
      ..close();

    // 深色渐变填充（顶部稍亮，底部纯黑融入背景）
    canvas.drawPath(panelPath, Paint()
      ..shader = ui.Gradient.linear(
        Offset(w / 2, arcEdgeY - h * 0.1),
        Offset(w / 2, h),
        [
          const Color(0xFF0D0D0D),
          const Color(0xFF080808),
          const Color(0xFF040404),
          const Color(0xFF000000),
        ],
        [0.0, 0.3, 0.7, 1.0],
      ));

    // 油门/刹车时面板微微发光
    if (throttle > 0.03 || brake > 0.03) {
      final glowColor = isBraking ? const Color(0xFFFF2222) : _getRpmColor();
      final glowIntensity = (throttle > 0 ? throttle : brake) * 0.04;
      canvas.drawPath(panelPath, Paint()
        ..color = glowColor.withValues(alpha: glowIntensity));
    }
  }

  /// 天穹弧线 + 刻度线 + 转速进度（一体化设计）
  void _drawArcWithTicks(Canvas canvas, double w, double h, double arcEdgeY) {
    // 天穹弧线路径
    final arcPath = Path()
      ..moveTo(0, arcEdgeY)
      ..quadraticBezierTo(
        w * 0.5,
        arcEdgeY - h * 0.25,
        w,
        arcEdgeY,
      );

    // 主高光线（加粗，有进度条的厚度感）
    canvas.drawPath(arcPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round);

    // 内侧柔和光泽带
    final innerPath = Path()
      ..moveTo(0, arcEdgeY + 2)
      ..quadraticBezierTo(
        w * 0.5,
        arcEdgeY - h * 0.25 + 2,
        w,
        arcEdgeY + 2,
      );
    canvas.drawPath(innerPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0);

    // ═══ 刻度线（沿弧线向下延伸） ═══
    final metrics = arcPath.computeMetrics().first;
    final totalLength = metrics.length;
    const tickCount = 16; // 刻度数量

    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      final pos = metrics.getTangentForOffset(totalLength * t);
      if (pos == null) continue;

      final isMajor = i % 4 == 0; // 每4个一个大刻度
      final tickLen = isMajor ? 10.0 : 5.0;
      final tickWidth = isMajor ? 1.8 : 0.8;

      // 刻度向下延伸（法线方向）
      final normal = Offset(-pos.vector.dy, pos.vector.dx); // 垂直于切线
      final normalNorm = normal / normal.distance;

      final start = pos.position;
      final end = start + normalNorm * tickLen;

      // 刻度颜色：已激活的亮，未激活的暗
      final isActive = t <= rpm;
      Color tickColor;
      if (isActive) {
        tickColor = _getRpmColor().withValues(alpha: 0.8);
      } else {
        tickColor = Colors.white.withValues(alpha: isMajor ? 0.15 : 0.06);
      }

      canvas.drawLine(start, end, Paint()
        ..color = tickColor
        ..strokeWidth = tickWidth
        ..strokeCap = StrokeCap.round);
    }

    // ═══ 转速进度发光（沿弧线） ═══
    if (rpm > 0.01) {
      final color = _getRpmColor();
      final fillPath = metrics.extractPath(0, totalLength * rpm.clamp(0.0, 1.0));

      canvas.drawPath(fillPath, Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round);

      // 发光
      canvas.drawPath(fillPath, Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }

    // 油门/刹车时弧线发光
    if (throttle > 0.03 || brake > 0.03) {
      final glowColor = isBraking ? const Color(0xFFFF3333) : _getRpmColor();
      final glowIntensity = (throttle > 0 ? throttle : brake) * 0.3;
      canvas.drawPath(arcPath, Paint()
        ..color = glowColor.withValues(alpha: glowIntensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    // 换档闪白
    if (justShifted) {
      canvas.drawPath(arcPath, Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
  }

  /// 拨片
  void _drawPaddle(Canvas canvas, double cx, double cy, bool isLeft) {
    final pw = 18.0;
    final ph = 50.0;
    final paddleRect = Rect.fromCenter(center: Offset(cx, cy), width: pw, height: ph);
    final rrect = RRect.fromRectAndRadius(paddleRect, const Radius.circular(9));

    // 投影
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 2), width: pw + 2, height: ph + 2),
        const Radius.circular(10),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 主体
    canvas.drawRRect(rrect, Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, cy - ph / 2),
        Offset(cx, cy + ph / 2),
        [
          const Color(0xFF2E2E2E),
          const Color(0xFF1A1A1A),
          const Color(0xFF141414),
        ],
        [0.0, 0.5, 1.0],
      ));

    // 边框
    canvas.drawRRect(rrect, Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);

    // 箭头
    final arrowY = cy - 4;
    final arrowPath = Path();
    if (isLeft) {
      arrowPath.moveTo(cx - 4, arrowY - 4);
      arrowPath.lineTo(cx, arrowY + 4);
      arrowPath.lineTo(cx + 4, arrowY - 4);
    } else {
      arrowPath.moveTo(cx - 4, arrowY + 4);
      arrowPath.lineTo(cx, arrowY - 4);
      arrowPath.lineTo(cx + 4, arrowY + 4);
    }
    canvas.drawPath(arrowPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // 标签
    final label = isLeft ? '−' : '+';
    final tp = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        color: Colors.white.withValues(alpha: 0.25),
        fontSize: 12,
        fontWeight: FontWeight.w300,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + 12));
  }

  void _drawHint(Canvas canvas, double cx, double cy) {
    final tp = TextPainter(
      text: TextSpan(text: '← BRAKE  |  THROTTLE →', style: TextStyle(
        color: Colors.white.withValues(alpha: 0.08),
        fontSize: 9,
        fontWeight: FontWeight.w400,
        letterSpacing: 2.0,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy));
  }

  Color _getRpmColor() {
    if (rpm > 0.8) {
      return Color.lerp(
        const Color(0xFFFF6600),
        const Color(0xFFFF0000),
        (rpm - 0.8) / 0.2,
      )!;
    } else if (rpm > 0.5) {
      return Color.lerp(
        const Color(0xFF00CC66),
        const Color(0xFFFF6600),
        (rpm - 0.5) / 0.3,
      )!;
    }
    return const Color(0xFF00CC66);
  }

  @override
  bool shouldRepaint(covariant _ControlPanelPainter old) =>
      rpm != old.rpm ||
      throttle != old.throttle ||
      brake != old.brake ||
      isThrottling != old.isThrottling ||
      isBraking != old.isBraking ||
      pulsePhase != old.pulsePhase ||
      justShifted != old.justShifted;
}
