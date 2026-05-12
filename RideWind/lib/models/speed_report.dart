/// 速度报告数据模型
///
/// 用于硬件端向APP端上报当前速度状态
/// 协议格式: SPEED_REPORT:value:unit\n
class SpeedReport {
  /// 速度值 (0-340)
  final int speed;

  /// 单位 (0=km/h, 1=mph)
  final int unit;

  /// 时间戳
  final DateTime timestamp;

  /// 是否来自硬件（用于区分本地更新和硬件上报）
  final bool fromHardware;

  SpeedReport({
    required this.speed,
    required this.unit,
    DateTime? timestamp,
    this.fromHardware = true,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 是否为公制单位 (km/h)
  bool get isMetric => unit == 0;

  /// 是否为英制单位 (mph)
  bool get isImperial => unit == 1;

  /// 获取单位字符串
  String get unitString => isMetric ? 'km/h' : 'mph';

  /// 转换为显示速度（如果需要单位转换）
  int toDisplaySpeed({bool targetMetric = true}) {
    if (isMetric == targetMetric) {
      return speed;
    }
    // km/h -> mph
    if (isMetric && !targetMetric) {
      return (speed * 0.621371).round();
    }
    // mph -> km/h
    return (speed / 0.621371).round();
  }

  @override
  String toString() {
    return 'SpeedReport(speed: $speed, unit: $unitString, fromHardware: $fromHardware)';
  }

  /// 从协议字符串解析
  /// 格式: SPEED_REPORT:value:unit 或 SPEED_REPORT:value
  static SpeedReport? fromProtocol(String response) {
    response = response.trim();
    print('🔍 [SpeedReport] 尝试解析: "$response"');

    // 匹配 SPEED_REPORT:value:unit 或 SPEED_REPORT:value
    final regex = RegExp(r'SPEED_REPORT:(\d+)(?::(\d+))?');
    final match = regex.firstMatch(response);

    if (match != null) {
      final speed = int.parse(match.group(1)!);
      final unit = match.group(2) != null ? int.parse(match.group(2)!) : 0;
      print('🔍 [SpeedReport] 正则匹配成功: speed=$speed, unit=$unit');

      // 验证范围
      if (speed < 0 || speed > 340) {
        print('⚠️ [SpeedReport] 速度超出范围: $speed');
        return null;
      }
      if (unit < 0 || unit > 1) {
        print('⚠️ [SpeedReport] 单位超出范围: $unit');
        return null;
      }

      print('✅ [SpeedReport] 解析成功!');
      return SpeedReport(speed: speed, unit: unit, fromHardware: true);
    }

    print('⚠️ [SpeedReport] 正则不匹配');
    return null;
  }

  /// 序列化为协议字符串
  String toProtocol() {
    return 'SPEED_REPORT:$speed:$unit\n';
  }
}
