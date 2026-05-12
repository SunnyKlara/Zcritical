import 'package:flutter/material.dart';

/// 模式按钮组件（复刻设计图中的按钮样式）
class ModeButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isGreen; // true=绿色启动, false=红色关闭

  const ModeButton({
    super.key,
    required this.text,
    required this.onTap,
    this.isGreen = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(35),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isGreen
                ? [
                    const Color(0xFF25C485), // 绿色起始
                    const Color(0xFF28FAA6).withAlpha(153), // 绿色结束（60%透明度）
                  ]
                : [
                    const Color(0xFFFF4444), // 红色起始
                    const Color(0xFFFF6666).withAlpha(153), // 红色结束（60%透明度）
                  ],
          ),
          boxShadow: [
            // 外阴影
            BoxShadow(
              color: Colors.black.withAlpha(64),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
            // 内阴影效果（通过多层阴影模拟）
            BoxShadow(
              color: isGreen
                  ? const Color(0xFF0B2922).withAlpha(168)
                  : const Color(0xFF290B0B).withAlpha(168),
              offset: const Offset(0, 0),
              blurRadius: 6,
              spreadRadius: -3,
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [
                // 文字内发光效果
                Shadow(
                  color: Color(0xFFFFB0B0),
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

