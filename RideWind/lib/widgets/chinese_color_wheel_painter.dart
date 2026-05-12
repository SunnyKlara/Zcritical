import 'dart:math';
import 'package:flutter/material.dart';
import '../data/traditional_chinese_colors.dart';

/// COPIC 风格中华传统色彩圆盘绘制器
///
/// 采用矩形色块从中心向外辐射排列的布局，类似 COPIC 色轮。
/// 每个色系占据一个扇形区域，内部的色块为梯形/矩形，
/// 越靠外越宽，每个色块上显示颜色名称和 RGB 值。
class ChineseColorWheelPainter extends CustomPainter {
  final List<ColorFamily> families;
  final ChineseColor? selectedColor;

  /// 内半径占画布短边的比例（中心空白区域）
  static const double _innerRadiusRatio = 0.10;

  /// 外半径占画布短边的比例
  static const double _outerRadiusRatio = 0.48;

  /// 扇形之间的间隔角度（弧度）
  static const double _sectorGap = 0.02;

  /// 环之间的径向间隔（像素）
  static const double _ringGap = 1.5;

  /// 选中色块描边宽度
  static const double _selectedStrokeWidth = 3.0;

  ChineseColorWheelPainter({
    required this.families,
    this.selectedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (families.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final shortSide = min(size.width, size.height);
    final outerRadius = shortSide * _outerRadiusRatio;
    final innerRadius = shortSide * _innerRadiusRatio;
    final familyCount = families.length;
    final totalSectorAngle = 2 * pi / familyCount;
    final usableSectorAngle = totalSectorAngle - _sectorGap;

    // 找出所有色系中最多的颜色数量
    final maxColors = families.fold<int>(
      0,
      (prev, f) => max(prev, f.colors.length),
    );
    if (maxColors == 0) return;

    final totalRadial = outerRadius - innerRadius;
    final ringThickness = (totalRadial - _ringGap * (maxColors - 1)) / maxColors;

    canvas.save();
    canvas.translate(center.dx, center.dy);

    for (int fi = 0; fi < familyCount; fi++) {
      final family = families[fi];
      final sectorStartAngle = fi * totalSectorAngle + _sectorGap / 2;

      // 绘制色系标题（在中心圆环内侧）
      _drawFamilyLabel(canvas, family, sectorStartAngle, usableSectorAngle, innerRadius);

      for (int ci = 0; ci < family.colors.length; ci++) {
        final color = family.colors[ci];
        final rInner = innerRadius + ci * (ringThickness + _ringGap);
        final rOuter = rInner + ringThickness;

        _drawSwatch(canvas, color, sectorStartAngle, usableSectorAngle, rInner, rOuter);
        _drawSwatchLabel(canvas, color, sectorStartAngle, usableSectorAngle, rInner, rOuter);
      }
    }

    canvas.restore();
  }

  /// 绘制色系标题（扇形区域的中心弧内侧）
  void _drawFamilyLabel(
    Canvas canvas,
    ColorFamily family,
    double startAngle,
    double sweepAngle,
    double innerRadius,
  ) {
    final midAngle = startAngle + sweepAngle / 2;
    final labelRadius = innerRadius * 0.65;
    final labelCenter = Offset(
      labelRadius * cos(midAngle),
      labelRadius * sin(midAngle),
    );

    final textStyle = TextStyle(
      color: Colors.white70,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
    );

    final textSpan = TextSpan(text: family.name, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    canvas.save();
    canvas.translate(labelCenter.dx, labelCenter.dy);
    canvas.rotate(midAngle + pi / 2);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  /// 绘制单个色块（梯形扇区）
  void _drawSwatch(
    Canvas canvas,
    ChineseColor color,
    double startAngle,
    double sweepAngle,
    double rInner,
    double rOuter,
  ) {
    final paint = Paint()
      ..color = color.toColor()
      ..style = PaintingStyle.fill;

    final path = _buildSwatchPath(startAngle, sweepAngle, rInner, rOuter);
    canvas.drawPath(path, paint);

    // 选中色块高亮描边
    final isSelected = selectedColor != null &&
        selectedColor!.name == color.name &&
        selectedColor!.family == color.family;

    if (isSelected) {
      final highlightPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _selectedStrokeWidth;
      canvas.drawPath(path, highlightPaint);
    }

    // 色块边框（细线分隔）
    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(path, borderPaint);
  }

  /// 在色块上绘制颜色名称和 RGB 值
  void _drawSwatchLabel(
    Canvas canvas,
    ChineseColor color,
    double startAngle,
    double sweepAngle,
    double rInner,
    double rOuter,
  ) {
    final midAngle = startAngle + sweepAngle / 2;
    final midRadius = (rInner + rOuter) / 2;
    final labelCenter = Offset(
      midRadius * cos(midAngle),
      midRadius * sin(midAngle),
    );

    // 根据色块大小动态计算字号
    final arcLength = midRadius * sweepAngle;
    final radialHeight = rOuter - rInner;
    final maxDimension = min(arcLength, radialHeight);

    // 颜色名称 - 较大字号
    final nameFontSize = (maxDimension * 0.28).clamp(7.0, 16.0);
    // RGB 值 - 较小字号
    final rgbFontSize = (maxDimension * 0.16).clamp(5.0, 10.0);

    final nameStyle = TextStyle(
      color: color.textColor,
      fontSize: nameFontSize,
      fontWeight: FontWeight.w600,
    );

    final rgbStyle = TextStyle(
      color: color.textColor.withOpacity(0.7),
      fontSize: rgbFontSize,
      fontFamily: 'monospace',
    );

    final nameSpan = TextSpan(text: color.name, style: nameStyle);
    final namePainter = TextPainter(
      text: nameSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final rgbText = '${color.r},${color.g},${color.b}';
    final rgbSpan = TextSpan(text: rgbText, style: rgbStyle);
    final rgbPainter = TextPainter(
      text: rgbSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final totalHeight = namePainter.height + rgbPainter.height + 1;

    // 如果文字太大放不下，只显示名称
    if (namePainter.width > arcLength * 0.9 ||
        totalHeight > radialHeight * 0.95) {
      // 尝试只绘制名称
      if (namePainter.width <= arcLength * 0.9 &&
          namePainter.height <= radialHeight * 0.9) {
        canvas.save();
        canvas.translate(labelCenter.dx, labelCenter.dy);
        canvas.rotate(midAngle + pi / 2);
        namePainter.paint(
          canvas,
          Offset(-namePainter.width / 2, -namePainter.height / 2),
        );
        canvas.restore();
      }
      return;
    }

    canvas.save();
    canvas.translate(labelCenter.dx, labelCenter.dy);
    canvas.rotate(midAngle + pi / 2);

    // 名称在上，RGB 在下
    final nameOffset = Offset(-namePainter.width / 2, -totalHeight / 2);
    namePainter.paint(canvas, nameOffset);

    final rgbOffset = Offset(
      -rgbPainter.width / 2,
      -totalHeight / 2 + namePainter.height + 1,
    );
    rgbPainter.paint(canvas, rgbOffset);

    canvas.restore();
  }

  /// 构建梯形扇区路径
  Path _buildSwatchPath(
    double startAngle,
    double sweepAngle,
    double rInner,
    double rOuter,
  ) {
    final path = Path();

    // 外弧
    path.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: rOuter),
      startAngle,
      sweepAngle,
      true,
    );

    // 连接到内弧终点
    path.lineTo(
      rInner * cos(startAngle + sweepAngle),
      rInner * sin(startAngle + sweepAngle),
    );

    // 内弧（反向）
    path.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: rInner),
      startAngle + sweepAngle,
      -sweepAngle,
      false,
    );

    path.close();
    return path;
  }

  /// 根据触摸坐标计算命中的颜色
  ChineseColor? colorHitTest(Offset position, Size size) {
    if (families.isEmpty) return null;

    final center = Offset(size.width / 2, size.height / 2);
    final shortSide = min(size.width, size.height);
    final outerRadius = shortSide * _outerRadiusRatio;
    final innerRadius = shortSide * _innerRadiusRatio;

    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < innerRadius || distance > outerRadius) return null;

    final familyCount = families.length;
    final totalSectorAngle = 2 * pi / familyCount;

    final maxColors = families.fold<int>(
      0,
      (prev, f) => max(prev, f.colors.length),
    );
    if (maxColors == 0) return null;

    final totalRadial = outerRadius - innerRadius;
    final ringThickness = (totalRadial - _ringGap * (maxColors - 1)) / maxColors;

    // 计算角度
    var angle = atan2(dy, dx);
    if (angle < 0) angle += 2 * pi;

    // 确定命中的色系
    final familyIndex = (angle / totalSectorAngle).floor() % familyCount;
    final family = families[familyIndex];

    // 确定命中的颜色（环索引）
    final distFromInner = distance - innerRadius;
    final colorIndex = (distFromInner / (ringThickness + _ringGap)).floor();
    if (colorIndex < 0 || colorIndex >= family.colors.length) return null;

    return family.colors[colorIndex];
  }

  /// Snap a rotation angle to the nearest sector boundary.
  static double snapToSector(double angle, int sectorCount) {
    if (sectorCount <= 0) return angle;
    final sectorAngle = 2 * pi / sectorCount;
    return (angle / sectorAngle).round() * sectorAngle;
  }

  @override
  bool shouldRepaint(covariant ChineseColorWheelPainter oldDelegate) {
    return families != oldDelegate.families ||
        selectedColor != oldDelegate.selectedColor;
  }
}
