import 'package:flutter/material.dart';

/// 🎯 速度数字弹跳动画
/// 
/// 为油门加速时的速度数字提供弹跳效果，
/// 使数字有"跳出屏幕"的视觉感。
class SpeedBounceAnimation {
  /// 创建弹跳动画控制器
  /// 
  /// [vsync] TickerProvider，通常是State with TickerProviderStateMixin
  static AnimationController createBounceController(TickerProvider vsync) {
    return AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: vsync,
    );
  }
  
  /// 创建缩放动画
  /// 
  /// 效果：1.0 → 1.3 → 1.0（先放大后回弹）
  static Animation<double> createScaleAnimation(AnimationController controller) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 50,
      ),
    ]).animate(controller);
  }
  
  /// 创建位移动画（向上弹跳）
  /// 
  /// 效果：0 → -15 → 0（先向上后回弹）
  static Animation<double> createOffsetAnimation(AnimationController controller) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -15.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -15.0, end: 0.0).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(controller);
  }
  
  /// 创建透明度动画（闪烁效果）
  /// 
  /// 效果：1.0 → 0.7 → 1.0
  static Animation<double> createOpacityAnimation(AnimationController controller) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.7),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.7, end: 1.0),
        weight: 70,
      ),
    ]).animate(controller);
  }
  
  /// 触发弹跳动画
  /// 
  /// [controller] 动画控制器
  static void triggerBounce(AnimationController controller) {
    controller.forward(from: 0.0);
  }
  
  /// 构建带弹跳效果的Widget
  /// 
  /// [controller] 动画控制器
  /// [child] 要添加弹跳效果的子Widget
  static Widget buildBounceWidget({
    required AnimationController controller,
    required Widget child,
  }) {
    final scaleAnimation = createScaleAnimation(controller);
    final offsetAnimation = createOffsetAnimation(controller);
    
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, offsetAnimation.value),
          child: Transform.scale(
            scale: scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
