/// 驾驶物理引擎 — 对标 Forza Horizon 操控手感
///
/// 核心链路：
/// 油门力度(0~1) → 扭矩 → 加速度(含档位齿比) → 速度积分
/// → 转速计算 → 红区触发升档 → 升档后转速回落
///
/// 物理特性：
/// - 涡轮迟滞：油门响应有 ~50ms 延迟（一阶低通滤波）
/// - 惯性滑行：松油门后速度以指数衰减（不是立即停）
/// - 发动机制动：高档位松油门减速更快
/// - 刹车线性：力度越大减速越快
/// - 档位齿比：低档加速快但极速低，高档相反

import 'dart:math';

class DrivingPhysics {
  // ═══ 状态 ═══
  double speed = 0.0; // km/h (0~20 对应跑步机)
  double rpm = 0.0; // 归一化转速 0~1
  int gear = 1; // 当前档位 1~6
  String driveMode = 'D'; // D=前进, R=倒退, N=空档

  // ═══ 输入 ═══
  double _throttleInput = 0.0; // 原始油门输入
  double _brakeInput = 0.0; // 原始刹车输入
  double _smoothedThrottle = 0.0; // 平滑后的油门（涡轮迟滞）

  // ═══ 常量 ═══
  static const double maxSpeed = 496.0; // km/h（仪表盘最大值）
  static const double maxRpm = 1.0;
  static const double idleRpm = 0.1; // 怠速转速

  // 涡轮迟滞系数（越小延迟越大）
  static const double _throttleSmoothing = 0.12; // 快速响应，爽感优先

  // 各档齿比（影响加速度和转速映射）
  // 低档：齿比大→加速快→转速攀升快→极速低
  static const List<double> _gearRatios = [
    4.2, // 1档
    2.8, // 2档
    2.0, // 3档
    1.5, // 4档
    1.15, // 5档
    0.9, // 6档
  ];

  // 各档极速（km/h）— 统一到 496 范围
  static const List<double> _gearMaxSpeeds = [
    85.0, // 1档
    160.0, // 2档
    250.0, // 3档
    340.0, // 4档
    420.0, // 5档
    496.0, // 6档
  ];

  // 升档转速阈值
  static const double _upshiftRpm = 0.85;
  // 降档转速阈值
  static const double _downshiftRpm = 0.25;

  // 阻力系数 — 适配 0~496 范围
  static const double _dragCoeff = 0.0003; // 风阻（极小，高速才有感觉）
  static const double _rollingResistance = 2.0; // 滚动阻力（恒定小值）
  static const double _engineBraking = 0.0; // 无发动机制动（模拟器爽感优先）

  // ═══ 公开方法 ═══

  /// 设置油门力度 (0~1)
  void setThrottle(double value) {
    _throttleInput = value.clamp(0.0, 1.0);
  }

  /// 设置刹车力度 (0~1)
  void setBrake(double value) {
    _brakeInput = value.clamp(0.0, 1.0);
  }

  /// 设置驾驶模式
  void setDriveMode(String mode) {
    if (mode == 'D' || mode == 'R' || mode == 'N') {
      driveMode = mode;
    }
  }

  /// 手动升档
  void manualShiftUp() {
    if (gear < 6) {
      gear++;
      rpm = (rpm * 0.6).clamp(0.0, 1.0); // 升档转速回落
    }
  }

  /// 手动降档
  void manualShiftDown() {
    if (gear > 1) {
      gear--;
      rpm = (rpm * 1.4).clamp(0.0, 0.95); // 降档转速上升
    }
  }

  /// 每帧更新（dt 单位秒，通常 ~0.016）
  void update(double dt) {
    if (driveMode == 'N') {
      // 空档：只有阻力减速
      _smoothedThrottle = 0.0;
      _applyDrag(dt);
      _updateRpm();
      return;
    }

    // 1. 涡轮迟滞：一阶低通滤波
    _smoothedThrottle += (_throttleInput - _smoothedThrottle) * _throttleSmoothing;

    // 2. 计算加速度
    final gearIdx = (gear - 1).clamp(0, 5);
    final ratio = _gearRatios[gearIdx];
    final gearMax = _gearMaxSpeeds[gearIdx];

    // 扭矩 = 油门 × 齿比 × 扭矩曲线
    // 扭矩曲线：中转速最大（模拟涡轮增压特性）
    final torqueCurve = _getTorqueCurve(rpm);
    final torque = _smoothedThrottle * ratio * torqueCurve;

    // 加速度 — 用整体极速做衰减，不用档位极速（避免每档顶部加速死掉）
    final overallRatio = (speed / maxSpeed).clamp(0.0, 1.0);
    final acceleration = torque * (1.0 - overallRatio * overallRatio) * 150.0;

    // 3. 刹车减速
    final brakeDecel = _brakeInput * 300.0; // 刹车力度

    // 4. 阻力
    final drag = speed * speed * _dragCoeff + _rollingResistance;
    final engineBrake = (_smoothedThrottle < 0.05 && speed > 0.5)
        ? _engineBraking * ratio * 0.5
        : 0.0;

    // 5. 速度积分
    final netAccel = acceleration - brakeDecel - drag - engineBrake;
    speed += netAccel * dt;

    // 方向限制
    if (driveMode == 'D') {
      speed = speed.clamp(0.0, maxSpeed);
    } else if (driveMode == 'R') {
      speed = speed.clamp(-80.0, 0.0); // 倒档最大 80 km/h
    }

    // 6. 更新转速
    _updateRpm();

    // 7. 自动换档
    _autoShift();
  }

  /// 扭矩曲线（模拟涡轮增压：低转弱→中转强→高转略降）
  double _getTorqueCurve(double r) {
    if (r < 0.3) return 0.6 + r * 1.3; // 低转：逐渐上升
    if (r < 0.7) return 1.0; // 中转：平台区（最大扭矩）
    return 1.0 - (r - 0.7) * 0.5; // 高转：略微下降
  }

  /// 更新转速（基于速度在当前档位速度区间内的进度）
  /// 每个档位有自己的速度区间，RPM 代表在该区间内的进度 0~1
  void _updateRpm() {
    final gearIdx = (gear - 1).clamp(0, 5);
    final gearMax = _gearMaxSpeeds[gearIdx];
    final gearMin = gearIdx > 0 ? _gearMaxSpeeds[gearIdx - 1] : 0.0;
    final absSpeed = speed.abs();

    // RPM = 速度在当前档位区间 [gearMin, gearMax] 内的进度
    final gearRange = gearMax - gearMin;
    final baseRpm = gearRange > 0
        ? ((absSpeed - gearMin) / gearRange).clamp(0.0, 1.0)
        : 0.0;

    // 加入油门对转速的直接影响（模拟空转）
    final throttleBoost = _smoothedThrottle * 0.1 * (1.0 - baseRpm);

    rpm = (baseRpm + throttleBoost).clamp(0.0, 1.0);
  }

  /// 自动换档逻辑 — 直接用速度阈值，不依赖 RPM
  void _autoShift() {
    if (driveMode != 'D') return;

    // 换档冷却：刚换完档 300ms 内不再换
    if (_lastShiftTime != null &&
        DateTime.now().difference(_lastShiftTime!).inMilliseconds < 300) {
      return;
    }

    final absSpeed = speed.abs();

    // 升档：速度超过当前档位极速的 85%
    if (gear < 6) {
      final currentGearMax = _gearMaxSpeeds[gear - 1];
      if (absSpeed >= currentGearMax * 0.85) {
        gear++;
        _lastShiftTime = DateTime.now();
        _lastShiftWasUp = true;
      }
    }

    // 降档：速度低于当前档位下限的 50%（即上一档极速的 50%）
    if (gear > 1) {
      final lowerGearMax = _gearMaxSpeeds[gear - 2];
      if (absSpeed < lowerGearMax * 0.5) {
        gear--;
        _lastShiftTime = DateTime.now();
        _lastShiftWasUp = false;
      }
    }
  }

  // ═══ 换档事件追踪 ═══
  DateTime? _lastShiftTime;
  bool _lastShiftWasUp = true;

  /// 是否刚刚换档（用于触发视觉效果，200ms 内算"刚刚"）
  bool get justShifted {
    if (_lastShiftTime == null) return false;
    return DateTime.now().difference(_lastShiftTime!).inMilliseconds < 200;
  }

  /// 最近一次换档是升档还是降档
  bool get lastShiftWasUp => _lastShiftWasUp;

  /// 阻力减速（空档/松油门时）
  void _applyDrag(double dt) {
    if (speed.abs() < 0.01) {
      speed = 0.0;
      return;
    }
    final drag = speed * speed * _dragCoeff + _rollingResistance;
    if (speed > 0) {
      speed = max(0.0, speed - drag * dt);
    } else {
      speed = min(0.0, speed + drag * dt);
    }
  }

  // ═══ 便捷 getter ═══

  /// 速度百分比 (0~1)
  double get speedRatio => (speed.abs() / maxSpeed).clamp(0.0, 1.0);

  /// 是否在红区
  bool get isRedline => rpm > 0.8;

  /// 距离增量（每帧调用，返回 km）
  double getDistanceDelta(double dt) {
    return speed.abs() / 3600.0 * dt; // km/h → km/s → km/frame
  }
}
