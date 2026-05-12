import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive_utils.dart';

/// 气流控制按钮组件（基于SVG转换）
/// 支持两种状态：启动（绿色）和关闭（红色）
class AirflowButton extends StatelessWidget {
  final String text; // 按钮文字："启动气流" 或 "关闭气流"
  final bool isStart; // true=启动（绿色），false=关闭（红色）
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // 🆕 长按回调
  final bool debugMode;

  const AirflowButton({
    super.key,
    required this.text,
    required this.isStart,
    required this.onTap,
    this.onLongPress, // 🆕 可选的长按回调
    this.debugMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 响应式尺寸
    final isSmall = ResponsiveUtils.isSmallScreen(context);
    final buttonHeight = isSmall ? 52.0 : 68.0;
    final fontSize = isSmall ? 16.0 : 20.0;
    final borderRadius = buttonHeight / 2;

    // 根据状态选择颜色
    final List<Color> gradientColors = isStart
        ? [
            const Color(0xFF25C485), // 绿色主色
            const Color(0xFF28FAA6).withValues(alpha: 0.6), // 绿色半透明
          ]
        : [
            const Color(0xFFFF4444), // 红色主色
            const Color(0xFFFF6666).withValues(alpha: 0.6), // 红色半透明
          ];

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact(); // 震动反馈
        onTap();
      },
      onLongPress: onLongPress != null
          ? () {
              HapticFeedback.heavyImpact(); // 长按震动反馈
              onLongPress!();
            }
          : null,
      child: Container(
        height: buttonHeight,
        // 调试边框
        decoration: debugMode
            ? BoxDecoration(
                border: Border.all(
                  color: isStart ? Colors.green : Colors.red,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(borderRadius),
              )
            : null,
        child: Stack(
          children: [
            // 背景渐变
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: gradientColors,
                ),
                // 外阴影（SVG filter）
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.54),
                    blurRadius: 4,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),

            // 文字
            Center(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
