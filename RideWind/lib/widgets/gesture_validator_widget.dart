import 'package:flutter/material.dart';
import 'package:ridewind/models/guide_models.dart';

/// 手势事件数据，用于手势匹配判断
class GestureData {
  final GestureType gestureType;
  final Offset velocity;
  final Offset displacement;

  const GestureData({
    required this.gestureType,
    this.velocity = Offset.zero,
    this.displacement = Offset.zero,
  });
}

/// 拖动位移匹配阈值（像素）
const double dragDisplacementThreshold = 30.0;

/// 纯函数：判断实际手势数据是否匹配期望的手势类型
bool matchesGesture(GestureType expected, GestureData actual) {
  switch (expected) {
    case GestureType.tap:
      return actual.gestureType == GestureType.tap;
    case GestureType.longPress:
      return actual.gestureType == GestureType.longPress;
    case GestureType.swipeLeft:
      return actual.gestureType == GestureType.swipeLeft &&
          actual.velocity.dx < 0;
    case GestureType.swipeRight:
      return actual.gestureType == GestureType.swipeRight &&
          actual.velocity.dx > 0;
    case GestureType.swipeUp:
      return actual.gestureType == GestureType.swipeUp &&
          actual.velocity.dy < 0;
    case GestureType.swipeDown:
      return actual.gestureType == GestureType.swipeDown &&
          actual.velocity.dy > 0;
    case GestureType.dragHorizontal:
      return actual.gestureType == GestureType.dragHorizontal &&
          actual.displacement.dx.abs() >= dragDisplacementThreshold;
    case GestureType.dragVertical:
      return actual.gestureType == GestureType.dragVertical &&
          actual.displacement.dy.abs() >= dragDisplacementThreshold;
  }
}
