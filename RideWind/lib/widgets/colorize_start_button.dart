import 'package:flutter/material.dart';

/// Colorize Mode - 开始涂色按钮组件
/// 
/// 功能：
/// - 动态颜色渐变（根据选中颜色）
/// - 模拟 SVG 的彩色渐变效果
/// - 发光阴影效果
class ColorizeStartButton extends StatelessWidget {
  final Color selectedColor;
  final VoidCallback onTap;
  final double height;

  const ColorizeStartButton({
    super.key,
    required this.selectedColor,
    required this.onTap,
    this.height = 80.0,
  });

  @override
  Widget build(BuildContext context) {
    // 根据选中的颜色生成渐变
    final bool isWhite = selectedColor == Colors.white;
    final bool isLightColor = selectedColor.computeLuminance() > 0.7 && !isWhite;
    
    List<Color> gradientColors;
    List<double> gradientStops;
    
    if (isWhite) {
      // 纯白色：使用白色渐变
      gradientColors = [
        Colors.white,
        const Color(0xFFF5F5F5),
        const Color(0xFFE0E0E0),
        const Color(0xFFF5F5F5),
      ];
      gradientStops = [0.0, 0.3, 0.7, 1.0];
    } else if (isLightColor) {
      // 浅色：使用彩虹渐变
      gradientColors = [
        const Color(0xFF55B6F2),
        const Color(0xFF7948EA),
        const Color(0xFFA349B3),
        const Color(0xFFF00000),
      ];
      gradientStops = [0.0, 0.48, 0.72, 1.0];
    } else {
      // 深色：基于选中颜色生成渐变
      gradientColors = [
        selectedColor,
        Color.lerp(selectedColor, Colors.white, 0.15)!,
        Color.lerp(selectedColor, Colors.black, 0.25)!,
        selectedColor.withAlpha(191),
      ];
      gradientStops = [0.0, 0.35, 0.7, 1.0];
    }
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: gradientColors,
            stops: gradientStops,
          ),
          borderRadius: BorderRadius.circular(height / 2), // 圆角与高度一致
          boxShadow: [
            // 内阴影效果
            BoxShadow(
              color: Colors.black.withAlpha(51),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
            // 外发光效果
            BoxShadow(
              color: selectedColor.withAlpha(102),
              blurRadius: 15,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '开始涂色',
            style: TextStyle(
              color: isWhite ? Colors.black : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              shadows: isWhite ? [] : [
                Shadow(
                  color: Colors.black.withAlpha(102),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

