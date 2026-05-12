/// Logo 槽位状态数据模型
///
/// 用于表示 ESP32 设备上 3 个 Logo 槽位的状态
/// 协议格式: LOGO_SLOTS:v0:v1:v2:active\r\n
/// 其中 v0/v1/v2 为各槽位是否有效 (0/1)，active 为当前活跃槽位索引
class LogoSlotStatus {
  /// 槽位 0 是否有有效 Logo
  final bool slot0Valid;

  /// 槽位 1 是否有有效 Logo
  final bool slot1Valid;

  /// 槽位 2 是否有有效 Logo
  final bool slot2Valid;

  /// 当前活跃槽位索引 (0-2)
  final int activeSlot;

  LogoSlotStatus({
    required this.slot0Valid,
    required this.slot1Valid,
    required this.slot2Valid,
    required this.activeSlot,
  });

  /// 从协议响应字符串解析
  /// 响应格式: LOGO_SLOTS:v0:v1:v2:active
  /// 返回: LogoSlotStatus 对象，解析失败返回 null
  factory LogoSlotStatus.fromProtocol(String response) {
    response = response.trim();

    final regex = RegExp(r'^LOGO_SLOTS:(\d+):(\d+):(\d+):(\d+)$');
    final match = regex.firstMatch(response);

    if (match == null) {
      throw FormatException('Invalid LOGO_SLOTS format: $response');
    }

    return LogoSlotStatus(
      slot0Valid: int.parse(match.group(1)!) != 0,
      slot1Valid: int.parse(match.group(2)!) != 0,
      slot2Valid: int.parse(match.group(3)!) != 0,
      activeSlot: int.parse(match.group(4)!),
    );
  }

  /// 检查指定槽位是否有效
  bool isSlotValid(int slot) {
    switch (slot) {
      case 0:
        return slot0Valid;
      case 1:
        return slot1Valid;
      case 2:
        return slot2Valid;
      default:
        return false;
    }
  }

  /// 有效槽位数量
  int get validSlotCount =>
      (slot0Valid ? 1 : 0) + (slot1Valid ? 1 : 0) + (slot2Valid ? 1 : 0);

  @override
  String toString() =>
      'LogoSlotStatus(slot0: $slot0Valid, slot1: $slot1Valid, slot2: $slot2Valid, active: $activeSlot)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoSlotStatus &&
          runtimeType == other.runtimeType &&
          slot0Valid == other.slot0Valid &&
          slot1Valid == other.slot1Valid &&
          slot2Valid == other.slot2Valid &&
          activeSlot == other.activeSlot;

  @override
  int get hashCode =>
      slot0Valid.hashCode ^
      slot1Valid.hashCode ^
      slot2Valid.hashCode ^
      activeSlot.hashCode;
}
