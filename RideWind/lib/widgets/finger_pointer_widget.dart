import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ridewind/models/guide_models.dart';

/// 手指指针组件
/// 使用系统 emoji 渲染真实手指效果，根据手势类型播放不同动画
///
/// 在真机上会显示系统原生的彩色手指图标（iOS/Android 各自风格）
/// 后续可替换为自定义 PNG/SVG 资源以获得统一的跨平台效果
class FingerPointerWidget extends StatelessWidget {
  final Rect targetRect;
  final GestureType gestureType;
  final Animation<double> bounceAnimation;
  final Color color;
  final double iconSize;

  /// tap 弹跳振幅
  static const double bounceAmplitude = 14.0;

  /// swipe 水平/垂直位移
  static const double swipeDistance = 100.0;

  /// drag 来回位移
  static const double dragDistance = 70.0;

  /// longPress 下压距离
  static const double longPressDepth = 14.0;

  const FingerPointerWidget({
    super.key,
    required this.targetRect,
    required this.bounceAnimation,
    this.gestureType = GestureType.tap,
    this.color = Colors.white,
    this.iconSize = 64.0,
  });

  /// 根据手势类型和动画值计算手指位置的纯函数
  ///
  /// [gestureType] 手势类型，决定动画行为
  /// [targetRect] 目标元素的屏幕矩形
  /// [animationValue] 动画进度值 0.0 ~ 1.0
  ///
  /// 返回手指图标的左上角 Offset
  static Offset calculatePosition(
    GestureType gestureType,
    Rect targetRect,
    double animationValue,
  ) {
    final centerX = targetRect.center.dx;
    final centerY = targetRect.center.dy;

    switch (gestureType) {
      case GestureType.tap:
        // 上下弹跳：手指在目标中心上方，振幅 10px
        final bounceOffset = -bounceAmplitude * animationValue;
        return Offset(centerX, targetRect.bottom + bounceOffset);

      case GestureType.longPress:
        // 下压 → 停顿 → 抬起
        // animation 0.0~0.25: 下压 (y 从 0 到 longPressDepth)
        // animation 0.25~0.75: 停顿 (y 保持 longPressDepth)
        // animation 0.75~1.0: 抬起 (y 从 longPressDepth 回到 0)
        double pressOffset;
        if (animationValue <= 0.25) {
          // 下压阶段
          pressOffset = longPressDepth * (animationValue / 0.25);
        } else if (animationValue <= 0.75) {
          // 停顿阶段
          pressOffset = longPressDepth;
        } else {
          // 抬起阶段
          pressOffset = longPressDepth * (1.0 - (animationValue - 0.75) / 0.25);
        }
        return Offset(centerX, targetRect.bottom + pressOffset);

      case GestureType.swipeLeft:
        // 从右向左：x 从 +swipeDistance/2 到 -swipeDistance/2
        final dx = swipeDistance / 2 - swipeDistance * animationValue;
        return Offset(centerX + dx, centerY);

      case GestureType.swipeRight:
        // 从左向右：x 从 -swipeDistance/2 到 +swipeDistance/2
        final dx = -swipeDistance / 2 + swipeDistance * animationValue;
        return Offset(centerX + dx, centerY);

      case GestureType.swipeUp:
        // 从下向上：y 从 +swipeDistance/2 到 -swipeDistance/2
        final dy = swipeDistance / 2 - swipeDistance * animationValue;
        return Offset(centerX, centerY + dy);

      case GestureType.swipeDown:
        // 从上向下：y 从 -swipeDistance/2 到 +swipeDistance/2
        final dy = -swipeDistance / 2 + swipeDistance * animationValue;
        return Offset(centerX, centerY + dy);

      case GestureType.dragHorizontal:
        // 水平来回：使用 sin 曲线实现来回运动
        final dx = dragDistance * math.sin(animationValue * 2 * math.pi);
        return Offset(centerX + dx, centerY);

      case GestureType.dragVertical:
        // 垂直来回：使用 sin 曲线实现来回运动
        final dy = dragDistance * math.sin(animationValue * 2 * math.pi);
        return Offset(centerX, centerY + dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bounceAnimation,
      builder: (context, child) {
        final position = calculatePosition(
          gestureType,
          targetRect,
          bounceAnimation.value,
        );
        return Positioned(
          left: position.dx,
          top: position.dy,
          child: IgnorePointer(child: child!),
        );
      },
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcATop),
        child: Text(
          '👆',
          style: TextStyle(
            fontSize: iconSize,
            decoration: TextDecoration.none,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
