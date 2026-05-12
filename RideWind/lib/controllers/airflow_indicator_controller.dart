import 'dart:async';
import 'package:flutter/foundation.dart';

/// 🌫️ 雾化器指示器控制器
/// 
/// 管理雾化器状态指示器的显示逻辑：
/// - 开启时显示绿色提示1.5秒后自动隐藏
/// - 关闭时显示关闭提示1秒后自动隐藏
/// - 雾化器开启状态下不持续显示指示器
class AirflowIndicatorController {
  /// 开启提示显示时长
  static const Duration _showOnDuration = Duration(milliseconds: 1500);
  
  /// 关闭提示显示时长
  static const Duration _showOffDuration = Duration(milliseconds: 1000);
  
  /// 隐藏定时器
  Timer? _hideTimer;
  
  /// 指示器是否可见
  final ValueNotifier<bool> isVisible = ValueNotifier(false);
  
  /// 指示器是否显示开启状态（绿色）
  final ValueNotifier<bool> isOn = ValueNotifier(false);
  
  /// 雾化器实际状态（用于内部跟踪）
  bool _airflowActualState = false;
  
  /// 获取雾化器实际状态
  bool get airflowActualState => _airflowActualState;
  
  /// 显示开启指示器
  /// 
  /// 显示绿色指示器1.5秒后自动隐藏
  void showOnIndicator() {
    _airflowActualState = true;
    isVisible.value = true;
    isOn.value = true;
    
    _hideTimer?.cancel();
    _hideTimer = Timer(_showOnDuration, () {
      isVisible.value = false;
    });
    
    debugPrint('🌫️ 雾化器指示器：显示开启提示（1.5秒后隐藏）');
  }
  
  /// 显示关闭指示器
  /// 
  /// 显示关闭提示1秒后自动隐藏
  void showOffIndicator() {
    _airflowActualState = false;
    isVisible.value = true;
    isOn.value = false;
    
    _hideTimer?.cancel();
    _hideTimer = Timer(_showOffDuration, () {
      isVisible.value = false;
    });
    
    debugPrint('🌫️ 雾化器指示器：显示关闭提示（1秒后隐藏）');
  }
  
  /// 立即隐藏指示器
  void hide() {
    _hideTimer?.cancel();
    isVisible.value = false;
  }
  
  /// 切换雾化器状态
  /// 
  /// 根据当前状态自动显示对应的指示器
  void toggle() {
    if (_airflowActualState) {
      showOffIndicator();
    } else {
      showOnIndicator();
    }
  }
  
  /// 设置雾化器状态（不显示指示器）
  /// 
  /// 用于恢复状态时使用
  void setStateWithoutIndicator(bool isOn) {
    _airflowActualState = isOn;
  }
  
  /// 释放资源
  void dispose() {
    _hideTimer?.cancel();
    isVisible.dispose();
    isOn.dispose();
  }
}
