import 'dart:math';

/// 烟雾动力学参数工具类
///
/// 所有公式 100% 来自反编译 ARM64 伪代码中的精确浮点常量。
/// 核心方法: _normalizeSpeed() = (speed / 340.0).clamp(0, 1)
///
/// 反编译来源: package:flutter3/utils/smoke_dynamics.dart
/// 地址范围: 0x3cb970 - 0x42a4f0
class SmokeDynamics {
  SmokeDynamics._();

  /// 归一化速度 — 所有参数计算的基础（公开版本供 FluidSimulation 使用）
  /// 反编译: scvtf d1, x1; fdiv d2, d1, d0(340.0); clamp(0, 1)
  static double normalizeSpeed(int windSpeed) {
    return (windSpeed / 340.0).clamp(0.0, 1.0);
  }

  static double _normalizeSpeed(int windSpeed) => normalizeSpeed(windSpeed);

  /// 波动动画速度
  /// 反编译 @ 0x3cb970: fmov d1, #3.0; fmul; fmov d1, #0.5; fadd
  static double getWaveAnimationSpeed(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return ns * 3.0 + 0.5;
  }

  /// 粒子散布范围（源区域垂直散布像素）
  /// 反编译 @ 0x3e3910: ldr d1(50.0); fmul; fmov d1, #20.0; fadd
  static double getParticleSpreadRange(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return ns * 50.0 + 20.0;
  }

  /// 粒子漂移范围（水平方向随机偏移幅度）
  /// 反编译 @ 0x3e394c: ldr d1(0.9); fmul; ldr d1(0.1); fadd
  static double getParticleDriftRange(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return ns * 0.9 + 0.1;
  }

  /// 粒子速度范围 [min, max]（主方向速度）
  /// 反编译 @ 0x3e3988:
  ///   min: ldr d0(1.6); fmul; fmov d0, #0.4(实际是ldr); fadd
  ///   max: fmov d0, #3.0; fmul; fmov d0, #1.0; fadd
  static List<double> getParticleSpeedRange(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    final minSpeed = ns * 1.6 + 0.4;
    final maxSpeed = ns * 3.0 + 1.0;
    return [minSpeed, maxSpeed];
  }

  /// 粒子透明度范围 [min, max]
  /// 反编译 @ 0x3e3a9c:
  ///   共用 fmul 结果 d2 = ns * 0.3
  ///   min: fadd d2 + 0.2
  ///   max: fadd d2 + 0.4
  static List<double> getParticleOpacityRange(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    final base = ns * 0.3;
    final minOpacity = base + 0.2;
    final maxOpacity = base + 0.4;
    return [minOpacity, maxOpacity];
  }

  /// 最大粒子数
  /// 反编译 @ 0x3e3ba8: fsqrt d1, d0; ldr d0(115.0); fmul; fmov d0, #5.0; fadd; round
  static int getMaxParticles(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return (sqrt(ns) * 115.0 + 5.0).round();
  }

  /// 烟雾生成间隔（每 N 帧生成一批）
  /// 反编译 @ 0x3e3c6c: fmov d0, #10.0; fmul; fmov d0, #12.0; fsub; round; clamp(2, 12)
  static int getSmokeGenerationInterval(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return (12.0 - ns * 10.0).round().clamp(2, 12);
  }

  /// 粒子大小范围 [min, max]
  /// 反编译 @ 0x3e3d50:
  ///   min: fmov d0, #5.0; fmul; fmov d0, #1.0; fadd
  ///   max: fmov d0, #9.0; fmul; fmov d0, #3.0; fadd
  static List<double> getParticleSizeRange(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    final minSize = ns * 5.0 + 1.0;
    final maxSize = ns * 9.0 + 3.0;
    return [minSize, maxSize];
  }

  /// 波动频率
  /// 反编译 @ 0x42a40c: fmov d0, #6.0; fmul; fmov d0, #2.0; fadd; round
  static int getWaveFrequency(int windSpeed) {
    final ns = _normalizeSpeed(windSpeed);
    return (ns * 6.0 + 2.0).round();
  }
}
