
/// 烟雾动力学参数工具类
/// 根据风速动态调整粒子生成和行为参数
class SmokeDynamics {
  SmokeDynamics._();

  /// 粒子大小范围 [min, max]
  static List<double> getParticleSizeRange(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    final minSize = 8.0 + factor * 6.0;
    final maxSize = 20.0 + factor * 15.0;
    return [minSize, maxSize];
  }

  /// 粒子透明度范围 [min, max]
  static List<double> getParticleOpacityRange(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    final minOpacity = 0.3 + factor * 0.1;
    final maxOpacity = 0.7 + factor * 0.2;
    return [minOpacity, maxOpacity];
  }

  /// 粒子速度范围 [min, max]（主方向速度）
  static List<double> getParticleSpeedRange(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    final minSpeed = 1.0 + factor * 2.0;
    final maxSpeed = 3.0 + factor * 4.0;
    return [minSpeed, maxSpeed];
  }

  /// 粒子漂移范围（垂直方向随机偏移幅度）
  static double getParticleDriftRange(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    return 0.5 + factor * 1.5;
  }

  /// 粒子生成散布范围（源区域垂直散布像素）
  static double getParticleSpreadRange(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    return 80.0 + factor * 60.0;
  }

  /// 烟雾生成间隔（每 N 帧生成一批）
  static int getSmokeGenerationInterval(int windSpeed) {
    if (windSpeed > 200) return 1;
    if (windSpeed > 100) return 1;
    if (windSpeed > 50) return 2;
    return 2;
  }

  /// 最大粒子数
  static int getMaxParticles(int windSpeed) {
    final factor = (windSpeed / 340).clamp(0.0, 1.0);
    return (500 + factor * 500).toInt();
  }
}
