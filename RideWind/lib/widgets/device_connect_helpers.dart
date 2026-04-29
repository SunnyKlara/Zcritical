import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 倒三角指示器 Painter（用于颜色预设选择）
class TriangleIndicatorPainter extends CustomPainter {
  final bool isActive;
  final Color currentColor;

  TriangleIndicatorPainter({
    this.isActive = false,
    this.currentColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive ? currentColor : Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final scaleX = size.width / 26.5732421875;
    final scaleY = size.height / 9.5234375;

    final path = Path();
    path.moveTo(14.1659 * scaleX, 0.203846 * scaleY);
    path.lineTo(25.4495 * scaleX, 5.7271 * scaleY);
    path.cubicTo(
      27.3533 * scaleX, 6.65898 * scaleY,
      26.6899 * scaleX, 9.52344 * scaleY,
      24.5702 * scaleX, 9.52344 * scaleY,
    );
    path.lineTo(2.003 * scaleX, 9.52344 * scaleY);
    path.cubicTo(
      -0.116619 * scaleX, 9.52344 * scaleY,
      -0.780075 * scaleX, 6.65898 * scaleY,
      1.1237 * scaleX, 5.7271 * scaleY,
    );
    path.lineTo(12.4073 * scaleX, 0.203846 * scaleY);
    path.cubicTo(
      12.9621 * scaleX, -0.0676997 * scaleY,
      13.6112 * scaleX, -0.0676997 * scaleY,
      14.1659 * scaleX, 0.203846 * scaleY,
    );
    path.close();

    if (isActive) {
      canvas.drawShadow(path, Colors.black.withAlpha(102), 4.0, true);

      final glowPaint1 = Paint()
        ..color = currentColor.withAlpha(102)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint1);

      final glowPaint2 = Paint()
        ..color = currentColor.withAlpha(153)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint2);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TriangleIndicatorPainter oldDelegate) {
    return oldDelegate.currentColor != currentColor ||
        oldDelegate.isActive != isActive;
  }
}

/// 自定义滑动条圆形滑块
class CustomSliderThumbShape extends SliderComponentShape {
  final double radius;
  final Color color;

  CustomSliderThumbShape({this.radius = 24, this.color = Colors.white});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 6, true);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius - 0.5, borderPaint);
  }
}

/// 机械风格矩形滑块
class MechanicalThumbShape extends SliderComponentShape {
  final Color color;
  const MechanicalThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(20, 30);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 14, height: 24),
        const Radius.circular(4),
      ),
      paint,
    );

    final innerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 8, height: 18),
        const Radius.circular(2),
      ),
      innerPaint,
    );
  }
}

/// 关机/重启滑动对话框组件
class PowerSliderDialog extends StatefulWidget {
  final Future<void> Function() onShutdown;
  final Future<void> Function() onReboot;

  const PowerSliderDialog({
    super.key,
    required this.onShutdown,
    required this.onReboot,
  });

  @override
  State<PowerSliderDialog> createState() => _PowerSliderDialogState();
}

class _PowerSliderDialogState extends State<PowerSliderDialog> {
  double _sliderY = 0.0;
  bool _isDragging = false;

  static const double _capsuleWidth = 84.0;
  static const double _capsuleHeight = 320.0;
  static const double _sliderSize = 68.0;
  static const double _triggerThreshold = 60.0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _sliderY += details.delta.dy;
      double maxDrag = (_capsuleHeight - _sliderSize) / 2 - 10;
      _sliderY = _sliderY.clamp(-maxDrag, maxDrag);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) async {
    if (_sliderY <= -_triggerThreshold) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() { _sliderY = 0.0; _isDragging = false; });
      }
      await widget.onShutdown();
    } else if (_sliderY >= _triggerThreshold) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() { _sliderY = 0.0; _isDragging = false; });
      }
      await widget.onReboot();
    } else {
      if (mounted) {
        setState(() { _sliderY = 0.0; _isDragging = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isShutdownActive = _sliderY <= -_triggerThreshold;
    bool isRebootActive = _sliderY >= _triggerThreshold;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '关机',
            style: TextStyle(
              color: Colors.white.withAlpha(isShutdownActive ? 255 : 102),
              fontSize: 14,
              letterSpacing: 4.0,
              fontWeight: isShutdownActive ? FontWeight.bold : FontWeight.w300,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onVerticalDragStart: (_) => setState(() => _isDragging = true),
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            onVerticalDragCancel: () => setState(() {
              _sliderY = 0.0;
              _isDragging = false;
            }),
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(42),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: _capsuleWidth,
                  height: _capsuleHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(42),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 30,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: isShutdownActive ? 1.4 : 1.0,
                          child: Icon(
                            Icons.power_settings_new_rounded,
                            color: Colors.white.withAlpha(
                              isShutdownActive ? 255 : 102,
                            ),
                            size: 36,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          scale: isRebootActive ? 1.4 : 1.0,
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Colors.white.withAlpha(
                              isRebootActive ? 255 : 102,
                            ),
                            size: 36,
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: _isDragging
                            ? Duration.zero
                            : const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        top: (_capsuleHeight - _sliderSize) / 2 + _sliderY,
                        child: Container(
                          width: _sliderSize,
                          height: _sliderSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: 90 * 3.14159 / 180,
                            child: const Icon(
                              Icons.code_rounded,
                              color: Color(0xFF1A1A1A),
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '重启',
            style: TextStyle(
              color: Colors.white.withAlpha(isRebootActive ? 255 : 102),
              fontSize: 14,
              letterSpacing: 4.0,
              fontWeight: isRebootActive ? FontWeight.bold : FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}
