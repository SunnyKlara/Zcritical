import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/protocol/protocol_parser.dart';

void main() {
  group('ProtocolParser', () {
    // ── parseAllStatus ──
    group('parseAllStatus', () {
      test('parses valid STATUS response', () {
        final result = ProtocolParser.parseAllStatus('STATUS:FAN:50:WUHUA:1:BRIGHT:80');
        expect(result, isNotNull);
        expect(result!['fan'], 50);
        expect(result['wuhua'], 1);
        expect(result['brightness'], 80);
      });

      test('parses STATUS with zero values', () {
        final result = ProtocolParser.parseAllStatus('STATUS:FAN:0:WUHUA:0:BRIGHT:0');
        expect(result, isNotNull);
        expect(result!['fan'], 0);
        expect(result['wuhua'], 0);
        expect(result['brightness'], 0);
      });

      test('returns null for invalid format', () {
        expect(ProtocolParser.parseAllStatus('INVALID'), isNull);
        expect(ProtocolParser.parseAllStatus('STATUS:FAN:50'), isNull);
        expect(ProtocolParser.parseAllStatus(''), isNull);
      });
    });

    // ── parseFanSpeed ──
    group('parseFanSpeed', () {
      test('parses FAN:50', () {
        expect(ProtocolParser.parseFanSpeed('FAN:50'), 50);
      });

      test('parses OK:FAN:75', () {
        expect(ProtocolParser.parseFanSpeed('OK:FAN:75'), 75);
      });

      test('returns null for non-FAN response', () {
        expect(ProtocolParser.parseFanSpeed('WUHUA:1'), isNull);
      });
    });

    // ── parseWuhuaqiStatus ──
    group('parseWuhuaqiStatus', () {
      test('parses WUHUA:1', () {
        expect(ProtocolParser.parseWuhuaqiStatus('WUHUA:1'), 1);
      });

      test('parses OK:WUHUA:0', () {
        expect(ProtocolParser.parseWuhuaqiStatus('OK:WUHUA:0'), 0);
      });
    });

    // ── parseSpeedReport ──
    group('parseSpeedReport', () {
      test('parses SPEED_REPORT:120:0', () {
        final report = ProtocolParser.parseSpeedReport('SPEED_REPORT:120:0');
        expect(report, isNotNull);
        expect(report!.speed, 120);
        expect(report.unit, 0);
        expect(report.isMetric, true);
      });

      test('parses SPEED_REPORT:75:1 (mph)', () {
        final report = ProtocolParser.parseSpeedReport('SPEED_REPORT:75:1');
        expect(report, isNotNull);
        expect(report!.speed, 75);
        expect(report.isImperial, true);
      });

      test('parses SPEED_REPORT:0 (no unit)', () {
        final report = ProtocolParser.parseSpeedReport('SPEED_REPORT:0');
        expect(report, isNotNull);
        expect(report!.speed, 0);
        expect(report.unit, 0); // defaults to km/h
      });

      test('returns null for out-of-range speed', () {
        expect(ProtocolParser.parseSpeedReport('SPEED_REPORT:999:0'), isNull);
      });

      test('returns null for invalid format', () {
        expect(ProtocolParser.parseSpeedReport('NOT_SPEED'), isNull);
      });
    });

    // ── parseThrottleReport ──
    group('parseThrottleReport', () {
      test('parses THROTTLE_REPORT:1 as true', () {
        expect(ProtocolParser.parseThrottleReport('THROTTLE_REPORT:1'), true);
      });

      test('parses THROTTLE_REPORT:0 as false', () {
        expect(ProtocolParser.parseThrottleReport('THROTTLE_REPORT:0'), false);
      });

      test('returns null for invalid', () {
        expect(ProtocolParser.parseThrottleReport('OTHER'), isNull);
      });
    });

    // ── parseUnitReport ──
    group('parseUnitReport', () {
      test('parses UNIT_REPORT:0 as km/h (true)', () {
        expect(ProtocolParser.parseUnitReport('UNIT_REPORT:0'), true);
      });

      test('parses UNIT_REPORT:1 as mph (false)', () {
        expect(ProtocolParser.parseUnitReport('UNIT_REPORT:1'), false);
      });
    });

    // ── parsePresetReport ──
    group('parsePresetReport', () {
      test('parses valid preset 1-14', () {
        expect(ProtocolParser.parsePresetReport('PRESET_REPORT:1'), 1);
        expect(ProtocolParser.parsePresetReport('PRESET_REPORT:14'), 14);
        expect(ProtocolParser.parsePresetReport('PRESET_REPORT:7'), 7);
      });

      test('returns null for out-of-range preset', () {
        expect(ProtocolParser.parsePresetReport('PRESET_REPORT:0'), isNull);
        expect(ProtocolParser.parsePresetReport('PRESET_REPORT:15'), isNull);
      });
    });

    // ── parseEngineNotification ──
    group('parseEngineNotification', () {
      test('parses ENGINE_START', () {
        expect(ProtocolParser.parseEngineNotification('ENGINE_START'), 'ENGINE_START');
      });

      test('parses ENGINE_READY', () {
        expect(ProtocolParser.parseEngineNotification('ENGINE_READY'), 'ENGINE_READY');
      });

      test('returns null for other', () {
        expect(ProtocolParser.parseEngineNotification('ENGINE_STOP'), isNull);
      });
    });

    // ── parseStreamlightReport ──
    group('parseStreamlightReport', () {
      test('parses STREAMLIGHT:1', () {
        expect(ProtocolParser.parseStreamlightReport('STREAMLIGHT:1'), true);
      });

      test('parses STREAMLIGHT_REPORT:0', () {
        expect(ProtocolParser.parseStreamlightReport('STREAMLIGHT_REPORT:0'), false);
      });
    });

    // ── parseStreamlightOk ──
    group('parseStreamlightOk', () {
      test('parses OK:STREAMLIGHT:1', () {
        expect(ProtocolParser.parseStreamlightOk('OK:STREAMLIGHT:1'), true);
      });

      test('parses OK:STREAMLIGHT:0', () {
        expect(ProtocolParser.parseStreamlightOk('OK:STREAMLIGHT:0'), false);
      });

      test('does not match STREAMLIGHT:1 (no OK prefix)', () {
        expect(ProtocolParser.parseStreamlightOk('STREAMLIGHT:1'), isNull);
      });
    });

    // ── parseButtonEvent ──
    group('parseButtonEvent', () {
      test('parses BTN:KNOB:CLICK', () {
        final result = ProtocolParser.parseButtonEvent('BTN:KNOB:CLICK');
        expect(result, {'type': 'KNOB', 'action': 'CLICK'});
      });

      test('parses BTN:KNOB:TRIPLE', () {
        final result = ProtocolParser.parseButtonEvent('BTN:KNOB:TRIPLE');
        expect(result, {'type': 'KNOB', 'action': 'TRIPLE'});
      });
    });

    // ── parseSensorData ──
    group('parseSensorData', () {
      test('parses SENSOR:TEMP:45', () {
        final result = ProtocolParser.parseSensorData('SENSOR:TEMP:45');
        expect(result, {'type': 'TEMP', 'value': 45});
      });

      test('parses negative values', () {
        final result = ProtocolParser.parseSensorData('SENSOR:TEMP:-10');
        expect(result, {'type': 'TEMP', 'value': -10});
      });
    });

    // ── parseKnobDelta ──
    group('parseKnobDelta', () {
      test('parses KNOB:5', () {
        expect(ProtocolParser.parseKnobDelta('KNOB:5'), 5);
      });

      test('parses ENCODER:-3', () {
        expect(ProtocolParser.parseKnobDelta('ENCODER:-3'), -3);
      });
    });

    // ── parseLogoSlots ──
    group('parseLogoSlots', () {
      test('parses LOGO_SLOTS:1:0:1:2', () {
        final result = ProtocolParser.parseLogoSlots('LOGO_SLOTS:1:0:1:2');
        expect(result, isNotNull);
        expect(result!.slot0Valid, true);
        expect(result.slot1Valid, false);
        expect(result.slot2Valid, true);
        expect(result.activeSlot, 2);
      });

      test('parses all zeros', () {
        final result = ProtocolParser.parseLogoSlots('LOGO_SLOTS:0:0:0:0');
        expect(result, isNotNull);
        expect(result!.validSlotCount, 0);
      });

      test('returns null for invalid', () {
        expect(ProtocolParser.parseLogoSlots('LOGO_SLOTS:1:0'), isNull);
      });
    });

    // ── parseWifiIp ──
    group('parseWifiIp', () {
      test('parses WIFI_IP:192.168.1.100', () {
        expect(ProtocolParser.parseWifiIp('WIFI_IP:192.168.1.100'), '192.168.1.100');
      });

      test('returns null for invalid IP', () {
        expect(ProtocolParser.parseWifiIp('WIFI_IP:invalid'), isNull);
      });
    });

    // ── parseAudioReady ──
    group('parseAudioReady', () {
      test('parses AUDIO_READY:192.168.1.100:8080', () {
        final result = ProtocolParser.parseAudioReady('AUDIO_READY:192.168.1.100:8080');
        expect(result, isNotNull);
        expect(result!['ip'], '192.168.1.100');
        expect(result['port'], 8080);
      });
    });

    // ── parseWifiError ──
    group('parseWifiError', () {
      test('parses WIFI_ERR:CONNECT_FAILED', () {
        expect(ProtocolParser.parseWifiError('WIFI_ERR:CONNECT_FAILED'), 'CONNECT_FAILED');
      });

      test('returns null for too short', () {
        expect(ProtocolParser.parseWifiError('WIFI_ERR:'), isNull);
      });
    });

    // ── parseVolume ──
    group('parseVolume', () {
      test('parses VOL:80', () {
        expect(ProtocolParser.parseVolume('VOL:80'), 80);
      });

      test('parses VOL:0', () {
        expect(ProtocolParser.parseVolume('VOL:0'), 0);
      });

      test('parses VOL:100', () {
        expect(ProtocolParser.parseVolume('VOL:100'), 100);
      });

      test('returns null for out-of-range', () {
        expect(ProtocolParser.parseVolume('VOL:101'), isNull);
      });
    });

    // ── parseWifiScan ──
    group('parseWifiScan', () {
      test('parses WIFI_SCAN:USE_PHONE', () {
        expect(ProtocolParser.parseWifiScan('WIFI_SCAN:USE_PHONE'), 'USE_PHONE');
      });
    });

    // ── isAckResponse ──
    group('isAckResponse', () {
      test('recognizes OK: responses', () {
        expect(ProtocolParser.isAckResponse('OK:FAN:50'), true);
      });

      test('recognizes LOGO_ACK:', () {
        expect(ProtocolParser.isAckResponse('LOGO_ACK:1'), true);
      });

      test('recognizes OTA_ACK:', () {
        expect(ProtocolParser.isAckResponse('OTA_ACK:1'), true);
      });

      test('does not match unknown responses', () {
        expect(ProtocolParser.isAckResponse('SPEED_REPORT:120:0'), false);
      });
    });
  });
}
