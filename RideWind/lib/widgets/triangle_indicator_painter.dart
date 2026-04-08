import 'package:flutter/material.dart';

/// 倒三角指示器（CustomPainter）
/// 
/// 功能：
/// - SVG圆角梯形形状
/// - 动态颜色（跟随选中颜色条）
/// - 发光效果
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
      ..color = isActive ? currentColor : Colors.white.withAlpha(77)
      ..style = PaintingStyle.fill;

    // 使用设计图的SVG path（圆角梯形）
    // 原始viewBox: 26.5732421875 x 9.5234375
    final scaleX = size.width / 26.5732421875;
    final scaleY = size.height / 9.5234375;
    
    final path = Path();
    
    // 还原SVG path
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

    // 多层阴影实现发光效果
    if (isActive) {
      // 第一层：黑色底部阴影
      canvas.drawShadow(path, Colors.black.withAlpha(102), 4.0, true);
      
      // 第二层：颜色发光（外发光）
      final glowPaint1 = Paint()
        ..color = currentColor.withAlpha(102)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint1);
      
      // 第三层：更强的颜色发光（内发光）
      final glowPaint2 = Paint()
        ..color = currentColor.withAlpha(153)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, glowPaint2);
    }
    
    // 绘制主体
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(TriangleIndicatorPainter oldDelegate) {
    return oldDelegate.currentColor != currentColor || 
           oldDelegate.isActive != isActive;
  }
}

