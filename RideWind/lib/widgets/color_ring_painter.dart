import 'dart:math';
import 'package:flutter/material.dart';
import '../data/traditional_chinese_colors.dart';

/// 排好序的色系数据
class SortedFamily {
  final String id;
  final String name;
  final List<ChineseColor> colors;
  final List<int> columnLengths;

  const SortedFamily({
    required this.id,
    required this.name,
    required this.colors,
    required this.columnLengths,
  });

  int get totalColumns => columnLengths.length;
  int get maxRows => columnLengths.isEmpty ? 0 : columnLengths.reduce(max);
}

/// 预渲染的文字标签缓存条目
class _CachedLabel {
  final TextPainter fullPainter;   // 完整名字
  final TextPainter? shortPainter; // 截断到1字的版本（可能为 null）

  _CachedLabel({required this.fullPainter, this.shortPainter});
}

/// 文字标签懒加载缓存
///
/// 按需创建 TextPainter 并缓存，避免一次性预渲染导致 OOM。
class LabelCache {
  /// key = "${colorName}_${family}_${fontSize.toStringAsFixed(1)}"
  final Map<String, _CachedLabel> _cache = {};

  /// 分批预热缓存，每帧处理一批，避免卡顿
  /// 需要传入一个回调在预热完成后触发重绘
  void preRender(List<SortedFamily> families, {VoidCallback? onBatchDone}) {
    _pendingFamilies = families;
    _onBatchDone = onBatchDone;
    _warmUpNextBatch();
  }

  List<SortedFamily>? _pendingFamilies;
  VoidCallback? _onBatchDone;
  int _warmUpIndex = 0;
  static const int _batchSize = 30; // 每帧预热30个颜色
  // 只预热最常用的字号
  static const List<double> _warmUpSizes = [6.0, 7.0, 8.0, 9.0, 10.0];

  void _warmUpNextBatch() {
    final families = _pendingFamilies;
    if (families == null) return;

    // 收集所有颜色
    final allColors = <ChineseColor>[];
    for (final f in families) {
      allColors.addAll(f.colors);
    }

    if (_warmUpIndex >= allColors.length) {
      _pendingFamilies = null;
      return;
    }

    final end = (_warmUpIndex + _batchSize).clamp(0, allColors.length);
    for (int i = _warmUpIndex; i < end; i++) {
      final color = allColors[i];
      for (final fs in _warmUpSizes) {
        final key = '${color.name}_${color.family}_${fs.toStringAsFixed(1)}';
        if (!_cache.containsKey(key)) {
          _createAndCache(key, color, fs);
        }
      }
    }
    _warmUpIndex = end;
    _onBatchDone?.call();

    if (_warmUpIndex < allColors.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _warmUpNextBatch());
    }
  }

  /// 按需获取（或创建）缓存的标签
  TextPainter? get(ChineseColor color, double fontSize,
      double maxWidth, double maxHeight) {
    final key = '${color.name}_${color.family}_${fontSize.toStringAsFixed(1)}';
    final cached = _cache[key] ?? _createAndCache(key, color, fontSize);

    // 先试完整名字
    if (cached.fullPainter.width <= maxWidth * 1.05 &&
        cached.fullPainter.height <= maxHeight * 0.95) {
      return cached.fullPainter;
    }

    // 再试截断版
    if (cached.shortPainter != null &&
        cached.shortPainter!.width <= maxWidth * 1.05 &&
        cached.shortPainter!.height <= maxHeight * 0.95) {
      return cached.shortPainter;
    }

    return null;
  }

  _CachedLabel _createAndCache(String key, ChineseColor color, double fontSize) {
    final textColor = color.textColor;
    final style = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    );

    final fullPainter = TextPainter(
      text: TextSpan(text: color.name, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    TextPainter? shortPainter;
    if (color.name.length > 1) {
      shortPainter = TextPainter(
        text: TextSpan(text: color.name.substring(0, 1), style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
    }

    final label = _CachedLabel(fullPainter: fullPainter, shortPainter: shortPainter);
    _cache[key] = label;
    return label;
  }
}

/// 色彩圆环绘制器 — COPIC 风格色轮
///
/// 两层结构：
/// 1. 最内圈：白灰色系（neutral）形成闭合圆环
/// 2. 外圈：彩色色系，内圈固定，外圈自由生长
class ColorRingPainter extends CustomPainter {
  final List<SortedFamily> sortedFamilies;
  final double rotationAngle;
  final ChineseColor? selectedColor;
  final double innerRadius;
  final double outerRadius;
  final LabelCache? labelCache;

  static const double neutralRingHeight = 28.0;
  static const double ringGap = 6.0;
  static const double rowHeight = 28.0;
  static const double sectorGap = 0.016;
  static const double layerGap = 1.5;
  static const double colGap = 1.5;
  static const double separatorWidth = 2.0;
  static const double selectedStrokeWidth = 3.0;

  ColorRingPainter({
    required this.sortedFamilies,
    required this.rotationAngle,
    this.selectedColor,
    required this.innerRadius,
    required this.outerRadius,
    this.labelCache,
  });

  double get neutralOuterRadius => innerRadius + neutralRingHeight;
  double get colorRingInnerRadius => neutralOuterRadius + ringGap;

  SortedFamily? get _neutralFamily {
    for (final sf in sortedFamilies) {
      if (sf.id == 'neutral') return sf;
    }
    return null;
  }

  List<SortedFamily> get _colorFamilies =>
      sortedFamilies.where((sf) => sf.id != 'neutral').toList();

  @override
  void paint(Canvas canvas, Size size) {
    if (sortedFamilies.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);

    final neutral = _neutralFamily;
    if (neutral != null && neutral.colors.isNotEmpty) {
      _drawNeutralRing(canvas, neutral);
    }

    final colorFams = _colorFamilies;
    if (colorFams.isNotEmpty) {
      _drawColorRing(canvas, colorFams);
    }

    canvas.restore();
  }

  void _drawNeutralRing(Canvas canvas, SortedFamily neutral) {
    final colors = List<ChineseColor>.from(neutral.colors);
    if (colors.isEmpty) return;

    colors.sort((a, b) {
      final la = 0.299 * a.r + 0.587 * a.g + 0.114 * a.b;
      final lb = 0.299 * b.r + 0.587 * b.g + 0.114 * b.b;
      return la.compareTo(lb);
    });

    final count = colors.length;
    final sweepPerBlock = 2 * pi / count;
    const gapAngle = 0.005;

    for (int i = 0; i < count; i++) {
      final color = colors[i];
      final startAngle = rotationAngle + i * sweepPerBlock + gapAngle / 2;
      final blockSweep = sweepPerBlock - gapAngle;

      final rInner = innerRadius + 1.0;
      final rOuter = neutralOuterRadius - 1.0;

      final paint = Paint()
        ..color = color.toColor()
        ..style = PaintingStyle.fill;
      final path = _buildRectRingPath(startAngle, blockSweep, rInner, rOuter);
      canvas.drawPath(path, paint);

      _drawBlockLabel(canvas, color, startAngle, blockSweep, rInner, rOuter);

      if (selectedColor != null &&
          selectedColor!.name == color.name &&
          selectedColor!.family == color.family) {
        final hlPaint = Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = selectedStrokeWidth;
        canvas.drawPath(path, hlPaint);
      }
    }

    final borderPaint = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(Offset.zero, innerRadius + 0.5, borderPaint);
    canvas.drawCircle(Offset.zero, neutralOuterRadius - 0.5, borderPaint);
  }

  void _drawColorRing(Canvas canvas, List<SortedFamily> colorFams) {
    final familyCount = colorFams.length;
    final List<int> familyCols =
        colorFams.map((f) => f.totalColumns).toList();
    final totalCols = familyCols.fold<int>(0, (sum, c) => sum + c);
    if (totalCols == 0) return;

    final cInner = colorRingInnerRadius;
    final totalGap = sectorGap * familyCount;
    final usableAngle = 2 * pi - totalGap;

    double sectorStart = rotationAngle;
    for (int fi = 0; fi < familyCount; fi++) {
      final sf = colorFams[fi];
      final cols = familyCols[fi];
      if (cols == 0) {
        sectorStart += sectorGap;
        continue;
      }

      final sectorSweep = usableAngle * cols / totalCols;
      final blockStart = sectorStart + sectorGap / 2;

      final maxOuterR = cInner + sf.maxRows * rowHeight;
      final midRadius = (cInner + maxOuterR) / 2;
      final colGapAngle = colGap / midRadius;
      final totalColGapAngle = colGapAngle * max(0, cols - 1);
      final blockSweep =
          cols > 1 ? (sectorSweep - totalColGapAngle) / cols : sectorSweep;

      int colorIdx = 0;
      for (int col = 0; col < cols; col++) {
        final colAngle = blockStart + col * (blockSweep + colGapAngle);
        final rowsInCol = sf.columnLengths[col];

        for (int row = 0; row < rowsInCol; row++) {
          if (colorIdx >= sf.colors.length) break;

          final color = sf.colors[colorIdx];
          final rInner = cInner + row * rowHeight + layerGap / 2;
          final rOuter = cInner + (row + 1) * rowHeight - layerGap / 2;

          final paint = Paint()
            ..color = color.toColor()
            ..style = PaintingStyle.fill;
          final path =
              _buildRectRingPath(colAngle, blockSweep, rInner, rOuter);
          canvas.drawPath(path, paint);

          _drawBlockLabel(canvas, color, colAngle, blockSweep, rInner, rOuter);

          if (selectedColor != null &&
              selectedColor!.name == color.name &&
              selectedColor!.family == color.family) {
            final hlPaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = selectedStrokeWidth;
            canvas.drawPath(path, hlPaint);
          }

          colorIdx++;
        }
      }

      sectorStart += sectorSweep + sectorGap;
    }

    _drawSeparators(canvas, colorFams, familyCols, totalCols, usableAngle);
  }

  void _drawBlockLabel(Canvas canvas, ChineseColor color, double startAngle,
      double sweepAngle, double rInner, double rOuter) {
    final midAngle = startAngle + sweepAngle / 2;
    final midRadius = (rInner + rOuter) / 2;

    final arcLength = midRadius * sweepAngle;
    final radialHeight = rOuter - rInner;
    final minDim = min(arcLength, radialHeight);

    if (minDim < 6) return;

    // 字号基于径向位置递进：内圈小，外圈大
    // rInner 范围大约 90~400+，映射到字号 6.0~10.0
    final radialProgress = ((rInner - 80) / 350).clamp(0.0, 1.0);
    final baseSize = 6.0 + radialProgress * 4.0;  // 6.0 → 10.0

    // 根据字数缩放：确保长名字不会比短名字的字号大
    final charCount = color.name.length;
    final charScale = charCount <= 1 ? 1.0 : charCount == 2 ? 0.85 : 0.7;

    // 同时不能超过色块能容纳的大小
    final maxByBlock = (minDim * 0.36).clamp(5.0, 10.0);
    final rawFontSize = min(baseSize * charScale, maxByBlock);

    // 量化字号到 0.5 步长，匹配缓存 key
    final fontSize = (rawFontSize * 2).roundToDouble() / 2;

    // 从缓存获取预渲染的 TextPainter
    TextPainter? textPainter;
    if (labelCache != null) {
      textPainter = labelCache!.get(color, fontSize, arcLength, radialHeight);
    }

    // 缓存未命中时回退到即时创建（不应该发生）
    if (textPainter == null && labelCache == null) {
      textPainter = _createLabelFallback(color, fontSize, arcLength, radialHeight);
    }

    if (textPainter == null) return;

    final labelCenter = Offset(
      midRadius * cos(midAngle),
      midRadius * sin(midAngle),
    );

    canvas.save();
    canvas.translate(labelCenter.dx, labelCenter.dy);

    double normalizedAngle = midAngle % (2 * pi);
    if (normalizedAngle < 0) normalizedAngle += 2 * pi;

    double textRotation;
    if (normalizedAngle > pi / 2 && normalizedAngle < 3 * pi / 2) {
      textRotation = midAngle + pi / 2 + pi;
    } else {
      textRotation = midAngle - pi / 2;
    }

    canvas.rotate(textRotation);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  /// 回退：无缓存时即时创建（仅用于 hit test 等场景）
  TextPainter? _createLabelFallback(ChineseColor color, double fontSize,
      double maxWidth, double maxHeight) {
    String label = color.name;
    for (int attempt = 0; attempt < 2; attempt++) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color.textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      if (tp.width <= maxWidth * 1.05 && tp.height <= maxHeight * 0.95) {
        return tp;
      }
      if (attempt == 0 && label.length > 1) {
        label = label.substring(0, 1);
      } else {
        break;
      }
    }
    return null;
  }

  void _drawSeparators(Canvas canvas, List<SortedFamily> families,
      List<int> familyCols, int totalCols, double usableAngle) {
    final separatorPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = separatorWidth;

    final cInner = colorRingInnerRadius;

    double angle = rotationAngle;
    for (int fi = 0; fi < families.length; fi++) {
      final sf = families[fi];
      final colOuter = cInner + sf.maxRows * rowHeight;

      final startPoint = Offset(
        cInner * cos(angle),
        cInner * sin(angle),
      );
      final endPoint = Offset(
        colOuter * cos(angle),
        colOuter * sin(angle),
      );
      canvas.drawLine(startPoint, endPoint, separatorPaint);

      final sectorSweep = usableAngle * familyCols[fi] / totalCols;
      angle += sectorSweep + sectorGap;
    }
  }

  Path _buildRectRingPath(
    double startAngle,
    double sweepAngle,
    double rInner,
    double rOuter,
  ) {
    final path = Path();
    path.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: rOuter),
      startAngle,
      sweepAngle,
      true,
    );
    path.lineTo(
      rInner * cos(startAngle + sweepAngle),
      rInner * sin(startAngle + sweepAngle),
    );
    path.arcTo(
      Rect.fromCircle(center: Offset.zero, radius: rInner),
      startAngle + sweepAngle,
      -sweepAngle,
      false,
    );
    path.close();
    return path;
  }

  /// 命中检测
  ChineseColor? colorHitTest(Offset localPosition, Size size) {
    if (sortedFamilies.isEmpty) return null;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = sqrt(dx * dx + dy * dy);

    double angle = atan2(dy, dx);
    angle -= rotationAngle;
    angle = angle % (2 * pi);
    if (angle < 0) angle += 2 * pi;

    // 检测灰度内环
    final neutral = _neutralFamily;
    if (neutral != null &&
        distance >= innerRadius &&
        distance <= neutralOuterRadius) {
      final colors = List<ChineseColor>.from(neutral.colors);
      colors.sort((a, b) {
        final la = 0.299 * a.r + 0.587 * a.g + 0.114 * a.b;
        final lb = 0.299 * b.r + 0.587 * b.g + 0.114 * b.b;
        return la.compareTo(lb);
      });
      final count = colors.length;
      if (count > 0) {
        final sweepPerBlock = 2 * pi / count;
        final idx = (angle / sweepPerBlock).floor();
        if (idx >= 0 && idx < count) {
          return colors[idx];
        }
      }
    }

    // 检测彩色外环
    final cInner = colorRingInnerRadius;
    if (distance < cInner) return null;

    final colorFams = _colorFamilies;
    final familyCount = colorFams.length;
    final List<int> familyCols =
        colorFams.map((f) => f.totalColumns).toList();
    final totalCols = familyCols.fold<int>(0, (sum, c) => sum + c);
    if (totalCols == 0) return null;

    final totalGap = sectorGap * familyCount;
    final usableAngle = 2 * pi - totalGap;

    double sectorStart = 0.0;
    for (int fi = 0; fi < familyCount; fi++) {
      final cols = familyCols[fi];
      final sectorSweep = usableAngle * cols / totalCols;
      final sectorEnd = sectorStart + sectorSweep + sectorGap;

      if (angle >= sectorStart && angle < sectorEnd) {
        final blockStart = sectorStart + sectorGap / 2;
        final blockEnd = sectorStart + sectorGap / 2 + sectorSweep;
        if (angle < blockStart || angle > blockEnd) return null;

        final sf = colorFams[fi];
        if (cols == 0) return null;

        final maxOuterR = cInner + sf.maxRows * rowHeight;
        final midRadius = (cInner + maxOuterR) / 2;
        final colGapAngle = colGap / midRadius;
        final totalColGapAngle = colGapAngle * max(0, cols - 1);
        final blockSweep =
            cols > 1 ? (sectorSweep - totalColGapAngle) / cols : sectorSweep;

        final angleInSector = angle - blockStart;
        final colStep = blockSweep + colGapAngle;
        final col = (angleInSector / colStep).floor();
        if (col < 0 || col >= cols) return null;

        final posInCol = angleInSector - col * colStep;
        if (posInCol > blockSweep) return null;

        final rowsInCol = sf.columnLengths[col];
        final colOuter = cInner + rowsInCol * rowHeight;

        if (distance > colOuter) return null;

        final row = ((distance - cInner) / rowHeight).floor();
        if (row < 0 || row >= rowsInCol) return null;

        final posInRow = distance - cInner - row * rowHeight;
        if (posInRow < layerGap / 2 || posInRow > rowHeight - layerGap / 2) {
          return null;
        }

        int colorIndex = 0;
        for (int c = 0; c < col; c++) {
          colorIndex += sf.columnLengths[c];
        }
        colorIndex += row;
        if (colorIndex >= sf.colors.length) return null;

        return sf.colors[colorIndex];
      }

      sectorStart = sectorEnd;
    }

    return null;
  }

  @override
  bool shouldRepaint(covariant ColorRingPainter oldDelegate) {
    return sortedFamilies != oldDelegate.sortedFamilies ||
        rotationAngle != oldDelegate.rotationAngle ||
        selectedColor != oldDelegate.selectedColor ||
        innerRadius != oldDelegate.innerRadius ||
        outerRadius != oldDelegate.outerRadius;
  }
}
