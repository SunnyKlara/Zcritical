import '../models/speed_report.dart';
import '../models/logo_slot_status.dart';

/// 协议解析器 — 纯函数，零依赖，可直接单元测试
///
/// 将 ESP32 返回的文本协议字符串解析为 Dart 对象。
/// 所有方法都是静态的，不持有任何状态。
/// 51 个单元测试覆盖：test/protocol/protocol_parser_test.dart
///
/// 协议格式参考: RideWind/PROTOCOL_SPECIFICATION.md
/// 架构参考: CONTINUATION_GUIDE.md 第三节
class ProtocolParser {
  ProtocolParser._(); // 禁止实例化

  // ═══════════════════════════════════════════════════════════════
  //  状态查询响应
  // ═══════════════════════════════════════════════════════════════

  /// 解析 STATUS:FAN:50:WUHUA:1:BRIGHT:80
  static Map<String, int>? parseAllStatus(String response) {
    final match = RegExp(r'STATUS:FAN:(\d+):WUHUA:(\d+):BRIGHT:(\d+)')
        .firstMatch(response.trim());
    if (match == null) return null;
    return {
      'fan': int.parse(match.group(1)!),
      'wuhua': int.parse(match.group(2)!),
      'brightness': int.parse(match.group(3)!),
    };
  }

  /// 解析 FAN:50 或 OK:FAN:50
  static int? parseFanSpeed(String response) {
    final match = RegExp(r'FAN:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!);
  }

  /// 解析 WUHUA:0 或 WUHUA:1 或 OK:WUHUA:x
  static int? parseWuhuaqiStatus(String response) {
    final match = RegExp(r'WUHUA:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!);
  }

  // ═══════════════════════════════════════════════════════════════
  //  硬件主动上报
  // ═══════════════════════════════════════════════════════════════

  /// 解析 SPEED_REPORT:120:0
  static SpeedReport? parseSpeedReport(String response) {
    return SpeedReport.fromProtocol(response);
  }

  /// 解析 THROTTLE_REPORT:0 或 THROTTLE_REPORT:1
  static bool? parseThrottleReport(String response) {
    final match =
        RegExp(r'THROTTLE_REPORT:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) == 1;
  }

  /// 解析 UNIT_REPORT:0 (km/h) 或 UNIT_REPORT:1 (mph)
  /// 返回: true=km/h, false=mph
  static bool? parseUnitReport(String response) {
    final match = RegExp(r'UNIT_REPORT:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) == 0;
  }

  /// 解析 PRESET_REPORT:n (n=1-14)
  static int? parsePresetReport(String response) {
    final match = RegExp(r'PRESET_REPORT:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    final preset = int.parse(match.group(1)!);
    return (preset >= 1 && preset <= 14) ? preset : null;
  }

  /// 解析 ENGINE_START 或 ENGINE_READY
  static String? parseEngineNotification(String response) {
    final trimmed = response.trim();
    if (trimmed == 'ENGINE_START' || trimmed == 'ENGINE_READY') {
      return trimmed;
    }
    return null;
  }

  /// 解析 STREAMLIGHT_REPORT:x 或 STREAMLIGHT:x
  static bool? parseStreamlightReport(String response) {
    final match =
        RegExp(r'STREAMLIGHT(?:_REPORT)?:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) == 1;
  }

  /// 解析 OK:STREAMLIGHT:x
  static bool? parseStreamlightOk(String response) {
    final match =
        RegExp(r'^OK:STREAMLIGHT:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) == 1;
  }

  /// 解析 BTN:type:action (如 BTN:KNOB:CLICK)
  static Map<String, String>? parseButtonEvent(String response) {
    final match = RegExp(r'BTN:(\w+):(\w+)').firstMatch(response.trim());
    if (match == null) return null;
    return {'type': match.group(1)!, 'action': match.group(2)!};
  }

  /// 解析 SENSOR:type:value (如 SENSOR:TEMP:45)
  static Map<String, dynamic>? parseSensorData(String response) {
    final match =
        RegExp(r'SENSOR:(\w+):(-?\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return {'type': match.group(1)!, 'value': int.parse(match.group(2)!)};
  }

  /// 解析 KNOB:delta 或 ENCODER:delta
  static int? parseKnobDelta(String response) {
    final match =
        RegExp(r'(?:KNOB|ENCODER):(-?\d+)').firstMatch(response.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!);
  }

  // ═══════════════════════════════════════════════════════════════
  //  ESP32 特有响应
  // ═══════════════════════════════════════════════════════════════

  /// 解析 LOGO_SLOTS:v0:v1:v2:active
  static LogoSlotStatus? parseLogoSlots(String response) {
    final match = RegExp(r'^LOGO_SLOTS:(\d+):(\d+):(\d+):(\d+)')
        .firstMatch(response.trim());
    if (match == null) return null;
    try {
      return LogoSlotStatus(
        slot0Valid: int.parse(match.group(1)!) != 0,
        slot1Valid: int.parse(match.group(2)!) != 0,
        slot2Valid: int.parse(match.group(3)!) != 0,
        activeSlot: int.parse(match.group(4)!),
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析 WIFI_IP:x.x.x.x
  static String? parseWifiIp(String response) {
    final match = RegExp(r'^WIFI_IP:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
        .firstMatch(response.trim());
    return match?.group(1);
  }

  /// 解析 AUDIO_READY:ip:port
  static Map<String, dynamic>? parseAudioReady(String response) {
    final match = RegExp(
            r'^AUDIO_READY:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d+)')
        .firstMatch(response.trim());
    if (match == null) return null;
    try {
      return {'ip': match.group(1)!, 'port': int.parse(match.group(2)!)};
    } catch (_) {
      return null;
    }
  }

  /// 解析 WIFI_ERR:reason
  static String? parseWifiError(String response) {
    final trimmed = response.trim();
    if (trimmed.startsWith('WIFI_ERR:') && trimmed.length > 9) {
      return trimmed.substring(9);
    }
    return null;
  }

  /// 解析 VOL:xx (0-100)
  static int? parseVolume(String response) {
    final match = RegExp(r'^VOL:(\d+)').firstMatch(response.trim());
    if (match == null) return null;
    final volume = int.parse(match.group(1)!);
    return (volume >= 0 && volume <= 100) ? volume : null;
  }

  /// 解析 WIFI_SCAN:USE_PHONE
  static String? parseWifiScan(String response) {
    final trimmed = response.trim();
    if (trimmed.startsWith('WIFI_SCAN:') && trimmed.length > 10) {
      return trimmed.substring(10);
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  //  响应分类 — 用于 ResponseRouter 判断响应类型
  // ═══════════════════════════════════════════════════════════════

  /// 判断响应是否为已知的 OK/ACK 类型（不需要主动解析分发）
  static bool isAckResponse(String response) {
    final trimmed = response.trim();
    return trimmed.startsWith('OK:') ||
        trimmed.startsWith('LOGO_ACK:') ||
        trimmed.startsWith('LOGO_SACK:') ||
        trimmed.startsWith('LOGO_READY:') ||
        trimmed.startsWith('LOGO_OK:') ||
        trimmed.startsWith('LOGO_FAIL:') ||
        trimmed.startsWith('LOGO_ERROR:') ||
        trimmed.startsWith('LOGO_ERASING') ||
        trimmed.startsWith('OTA_ACK:') ||
        trimmed.startsWith('OTA_READY') ||
        trimmed.startsWith('OTA_OK') ||
        trimmed.startsWith('OTA_FAIL:') ||
        trimmed.startsWith('PRESET_REPORT:');
  }
}
