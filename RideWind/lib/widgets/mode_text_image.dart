import 'package:flutter/material.dart';

/// 模式文字图片组件（100%还原设计）
/// 使用PNG图片，完美保留设计师的字体效果
class ModeTextImage extends StatelessWidget {
  final String mode; // 'cleaning', 'running', 'colorize'
  final bool debugMode;

  const ModeTextImage({
    super.key,
    required this.mode,
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
      child: Image.asset(
        _getImagePath(),
        fit: BoxFit.contain,
        // 使用高质量图片过滤
        filterQuality: FilterQuality.high,
      ),
    );
  }

  String _getImagePath() {
    switch (mode) {
      case 'cleaning':
        return 'assets/images/text_cleaning_mode.png';
      case 'running':
        return 'assets/images/text_running_mode.png';
      case 'colorize':
        return 'assets/images/text_colorize_mode.png';
      default:
        return 'assets/images/text_cleaning_mode.png';
    }
  }
}

