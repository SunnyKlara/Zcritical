import 'package:flutter/material.dart';

/// 模式文字组件（基于SVG设计转换）
/// 支持三种模式：Cleaning Mode / Running Mode / Colorize Mode
class ModeTextWidget extends StatelessWidget {
  final String text;
  final bool debugMode;

  const ModeTextWidget({
    super.key,
    required this.text,
    this.debugMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 调试边框
      decoration: debugMode
          ? BoxDecoration(
              border: Border.all(color: Colors.orange, width: 2),
              color: Colors.orange.withAlpha(26),
            )
          : null,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 28, // 根据SVG viewBox高度估算
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          // SVG中的阴影效果：白色半透明高斯模糊
          shadows: [
            Shadow(
              color: Colors.white.withAlpha(138),
              blurRadius: 4, // stdDeviation="2" → blurRadius ≈ 4
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
    );
  }
}

