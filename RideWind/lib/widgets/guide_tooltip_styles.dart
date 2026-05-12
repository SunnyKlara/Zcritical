import 'dart:ui';
import 'package:flutter/material.dart';

/// 引导提示框样式枚举
enum GuideTooltipStyle {
  glassmorphism, // 毛玻璃气泡
  glowBorder, // 呼吸光边框
}

/// 毛玻璃气泡提示框
/// 半透明磨砂背景 + 微弱白色边框 + 大圆角
class GlassmorphismTooltip extends StatelessWidget {
  final String text;
  final String? stepIndicator; // e.g. "1/8"
  final double maxWidth;

  const GlassmorphismTooltip({
    super.key,
    required this.text,
    this.stepIndicator,
    this.maxWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stepIndicator != null) ...[
                Text(
                  stepIndicator!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  letterSpacing: 0.3,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 呼吸光边框提示框
/// 暗色底 + 边缘发光动画 + 圆角
class GlowBorderTooltip extends StatefulWidget {
  final String text;
  final String? stepIndicator;
  final double maxWidth;
  final Color glowColor;

  const GlowBorderTooltip({
    super.key,
    required this.text,
    this.stepIndicator,
    this.maxWidth = 280,
    this.glowColor = Colors.white,
  });

  @override
  State<GlowBorderTooltip> createState() => _GlowBorderTooltipState();
}

class _GlowBorderTooltipState extends State<GlowBorderTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _glowAnimation = Tween<double>(begin: 0.15, end: 0.5).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D).withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.glowColor.withOpacity(_glowAnimation.value),
              width: 1.2,
            ),
            boxShadow: [
              // 外发光
              BoxShadow(
                color: widget.glowColor.withOpacity(_glowAnimation.value * 0.3),
                blurRadius: 16,
                spreadRadius: 1,
              ),
              // 底部阴影
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.stepIndicator != null) ...[
            Text(
              widget.stepIndicator!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            widget.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
              letterSpacing: 0.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
