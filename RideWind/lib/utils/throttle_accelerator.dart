import 'dart:math';

/// 🚀 油门加速器
/// 
/// 实现乱序递增模式，使油门加速时数字跳动更有节奏感。
/// 支持回退到固定步长1的模式。
class ThrottleAccelerator {
  final Random _random = Random();
  
  /// 是否使用乱序模式
  bool useRandomStep = true;
  
  /// 加速计数器（用于节奏控制）
  int _accelerationCount = 0;
  
  /// 获取下一个加速步长
  /// 
  /// 乱序模式：返回1-3之间的随机步长
  /// 回退模式：返回固定步长1
  int getNextStep() {
    _accelerationCount++;
    
    if (!useRandomStep) {
      return 1;
    }
    
    // 乱序递增：1-3之间的随机步长
    // 使用加权随机，让步长分布更有节奏感
    // 60%概率返回1，30%概率返回2，10%概率返回3
    final roll = _random.nextDouble();
    if (roll < 0.6) {
      return 1;
    } else if (roll < 0.9) {
      return 2;
    } else {
      return 3;
    }
  }
  
  /// 获取回退模式的固定步长
  int getFallbackStep() {
    return 1;
  }
  
  /// 重置加速计数器
  void reset() {
    _accelerationCount = 0;
  }
  
  /// 获取当前加速计数
  int get accelerationCount => _accelerationCount;
  
  /// 是否应该触发强震动（每5次加速触发一次）
  bool get shouldHeavyImpact => _accelerationCount % 5 == 0;
  
  /// 是否应该触发轻震动（每次加速都触发）
  bool get shouldLightImpact => true;
  
  /// 切换到回退模式
  void enableFallbackMode() {
    useRandomStep = false;
  }
  
  /// 切换到乱序模式
  void enableRandomMode() {
    useRandomStep = true;
  }
}
