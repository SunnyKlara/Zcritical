import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 模式文字SVG组件（使用flutter_svg包）
/// 直接渲染SVG文件，完美还原矢量设计
class ModeTextSvgPackage extends StatelessWidget {
  final String mode; // 'cleaning', 'running', 'colorize'
  final bool debugMode;

  const ModeTextSvgPackage({
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
      child: SvgPicture.asset(
        _getSvgPath(),
        fit: BoxFit.contain,
        // 启用抗锯齿
        placeholderBuilder: (context) => const SizedBox(),
      ),
    );
  }

  String _getSvgPath() {
    switch (mode) {
      case 'cleaning':
        return 'assets/svg/text_cleaning_mode.svg';
      case 'running':
        return 'assets/svg/text_running_mode.svg';
      case 'colorize':
        return 'assets/svg/text_colorize_mode.svg';
      default:
        return 'assets/svg/text_cleaning_mode.svg';
    }
  }
}

