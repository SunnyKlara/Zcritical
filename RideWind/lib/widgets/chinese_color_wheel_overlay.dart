import 'package:flutter/material.dart';
import '../data/traditional_chinese_colors.dart';
import '../utils/responsive_utils.dart';
import 'chinese_color_wheel_painter.dart';

/// COPIC 风格中华传统色彩圆盘覆盖层
///
/// 全屏黑色半透明背景，使用 InteractiveViewer 支持缩放和平移，
/// 展示大型 COPIC 风格色彩参考图。顶部显示选中颜色预览，底部确认按钮。
class ChineseColorWheelOverlay extends StatefulWidget {
  final Function(int r, int g, int b) onColorSelected;

  const ChineseColorWheelOverlay({
    super.key,
    required this.onColorSelected,
  });

  @override
  State<ChineseColorWheelOverlay> createState() =>
      _ChineseColorWheelOverlayState();
}

class _ChineseColorWheelOverlayState extends State<ChineseColorWheelOverlay> {
  ChineseColor? _selectedColor;
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// 处理色块点击选择
  void _onTapUp(TapUpDetails details, double canvasSize) {
    // 将屏幕坐标转换为画布坐标（考虑缩放和平移）
    final matrix = _transformController.value;
    final inverseMatrix = Matrix4.inverted(matrix);
    final screenPoint = details.localPosition;
    final transformed = MatrixUtils.transformPoint(
      inverseMatrix,
      screenPoint,
    );

    final painter = ChineseColorWheelPainter(
      families: TraditionalChineseColors.families,
    );
    final hitColor = painter.colorHitTest(
      transformed,
      Size(canvasSize, canvasSize),
    );
    if (hitColor != null) {
      setState(() {
        _selectedColor = hitColor;
      });
    }
  }

  /// 双击色块直接确认选择
  void _onDoubleTapDown(TapDownDetails details, double canvasSize) {
    final matrix = _transformController.value;
    final inverseMatrix = Matrix4.inverted(matrix);
    final transformed = MatrixUtils.transformPoint(
      inverseMatrix,
      details.localPosition,
    );

    final painter = ChineseColorWheelPainter(
      families: TraditionalChineseColors.families,
    );
    final hitColor = painter.colorHitTest(
      transformed,
      Size(canvasSize, canvasSize),
    );
    if (hitColor != null) {
      setState(() {
        _selectedColor = hitColor;
      });
      _confirmSelection();
    }
  }

  void _confirmSelection() {
    if (_selectedColor != null) {
      widget.onColorSelected(
        _selectedColor!.r,
        _selectedColor!.g,
        _selectedColor!.b,
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = ResponsiveUtils.screenWidth(context);
    final screenHeight = ResponsiveUtils.screenHeight(context);

    // 画布尺寸：比屏幕大，让用户可以缩放查看细节
    final canvasSize = (screenWidth > screenHeight ? screenWidth : screenHeight) * 1.6;

    return Scaffold(
      backgroundColor: const Color(0xF0111111),
      body: SafeArea(
        child: Stack(
          children: [
            // 主体：可缩放平移的色彩圆盘
            Column(
              children: [
                // 顶部颜色预览
                _buildColorPreview(context),
                // 色彩圆盘（可缩放平移）
                Expanded(
                  child: GestureDetector(
                    onTapUp: (details) => _onTapUp(details, canvasSize),
                    onDoubleTapDown: (details) =>
                        _onDoubleTapDown(details, canvasSize),
                    onDoubleTap: () {}, // 需要注册才能触发 onDoubleTapDown
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.5,
                      maxScale: 4.0,
                      boundaryMargin: EdgeInsets.all(canvasSize * 0.3),
                      child: Center(
                        child: SizedBox(
                          width: canvasSize,
                          height: canvasSize,
                          child: CustomPaint(
                            key: const ValueKey('color_wheel_paint'),
                            size: Size(canvasSize, canvasSize),
                            painter: ChineseColorWheelPainter(
                              families: TraditionalChineseColors.families,
                              selectedColor: _selectedColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 底部确认按钮
                _buildConfirmButton(context),
                SizedBox(height: ResponsiveUtils.scaledHeight(context, 12)),
              ],
            ),
            // 关闭按钮（右上角）
            Positioned(
              top: ResponsiveUtils.scaledHeight(context, 4),
              right: ResponsiveUtils.horizontalPadding(context),
              child: _buildCloseButton(context),
            ),
            // 缩放提示
            Positioned(
              bottom: ResponsiveUtils.scaledHeight(context, 80),
              left: 0,
              right: 0,
              child: _buildZoomHint(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部颜色预览区域
  Widget _buildColorPreview(BuildContext context) {
    final previewFontSize = ResponsiveUtils.scaledFontSize(
      context, 18, minSize: 14, maxSize: 22,
    );
    final rgbFontSize = ResponsiveUtils.scaledFontSize(
      context, 14, minSize: 11, maxSize: 17,
    );

    if (_selectedColor == null) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveUtils.horizontalPadding(context),
          vertical: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '中华传统色',
              style: TextStyle(
                color: Colors.white70,
                fontSize: previewFontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '双指缩放查看 · 点击色块选色',
              style: TextStyle(
                color: Colors.white38,
                fontSize: rgbFontSize,
              ),
            ),
          ],
        ),
      );
    }

    final color = _selectedColor!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveUtils.horizontalPadding(context),
        vertical: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 颜色预览圆
          Container(
            width: ResponsiveUtils.scaledSize(context, 32),
            height: ResponsiveUtils.scaledSize(context, 32),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.toColor(),
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                color.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: previewFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'R:${color.r}  G:${color.g}  B:${color.b}',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: rgbFontSize,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 缩放提示
  Widget _buildZoomHint(BuildContext context) {
    return Center(
      child: AnimatedOpacity(
        opacity: _selectedColor == null ? 0.5 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '双指捏合缩放 · 拖动平移',
            style: TextStyle(
              color: Colors.white54,
              fontSize: ResponsiveUtils.scaledFontSize(context, 12, minSize: 10, maxSize: 14),
            ),
          ),
        ),
      ),
    );
  }

  /// 关闭按钮
  Widget _buildCloseButton(BuildContext context) {
    final buttonSize = ResponsiveUtils.scaledSize(context, 44);
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        alignment: Alignment.center,
        child: Icon(
          Icons.close,
          color: Colors.white70,
          size: ResponsiveUtils.scaledSize(context, 24),
        ),
      ),
    );
  }

  /// 底部确认按钮
  Widget _buildConfirmButton(BuildContext context) {
    final fontSize = ResponsiveUtils.scaledFontSize(
      context, 16, minSize: 13, maxSize: 19,
    );
    final buttonHeight = ResponsiveUtils.scaledSize(context, 44);
    final buttonWidth = ResponsiveUtils.scaledSize(context, 180);

    return GestureDetector(
      onTap: _selectedColor != null ? _confirmSelection : null,
      child: Container(
        width: buttonWidth,
        height: buttonHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(buttonHeight / 2),
          color: _selectedColor != null
              ? _selectedColor!.toColor()
              : Colors.white12,
          border: Border.all(
            color: _selectedColor != null ? Colors.white30 : Colors.white10,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _selectedColor != null ? '确认选择' : '请选择颜色',
          style: TextStyle(
            color: _selectedColor != null
                ? _selectedColor!.textColor
                : Colors.white30,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
