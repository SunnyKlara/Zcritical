import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/speed_report.dart';
import '../models/logo_slot_status.dart';
import 'protocol_parser.dart';
import 'command_sender.dart';

/// 响应路由器 — 接收 BLE 原始数据，分包重组，分发到对应的 Stream
///
/// 职责：
/// - 数据缓冲 + 按 \n 分割完整命令（512字节溢出保护）
/// - 调用 ProtocolParser 解析每条完整命令
/// - 分发到对应的 StreamController（17个事件流）
/// - 管理同步查询的 Completer 队列（queryAllStatusSync 等）
///
/// 数据流：BLEService.rxDataStream → handleReceivedData() → 各 Stream
/// 由 BluetoothProvider 持有，Screen 不直接访问。
/// 架构参考: CONTINUATION_GUIDE.md 第三节
class ResponseRouter {
  final CommandSender _commandSender;

  // ── 数据缓冲区 ──
  String _dataBuffer = '';

  // ── 同步查询等待队列 ──
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  // ── 事件流 ──
  final _speedReportCtrl = StreamController<SpeedReport>.broadcast();
  final _throttleReportCtrl = StreamController<bool>.broadcast();
  final _unitReportCtrl = StreamController<bool>.broadcast();
  final _presetReportCtrl = StreamController<int>.broadcast();
  final _engineNotificationCtrl = StreamController<String>.broadcast();
  final _streamlightReportCtrl = StreamController<bool>.broadcast();
  final _buttonEventCtrl = StreamController<Map<String, String>>.broadcast();
  final _sensorDataCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _knobDeltaCtrl = StreamController<int>.broadcast();
  final _logoSlotsCtrl = StreamController<LogoSlotStatus>.broadcast();
  final _wifiIpCtrl = StreamController<String>.broadcast();
  final _wifiErrorCtrl = StreamController<String>.broadcast();
  final _audioReadyCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _volumeCtrl = StreamController<int>.broadcast();
  final _wifiScanCtrl = StreamController<String>.broadcast();
  final _rawResponseCtrl = StreamController<String>.broadcast();
  final _ledUpdateCtrl = StreamController<Map<String, int>>.broadcast();

  // ── 公开流 ──
  Stream<SpeedReport> get speedReportStream => _speedReportCtrl.stream;
  Stream<bool> get throttleReportStream => _throttleReportCtrl.stream;
  Stream<bool> get unitReportStream => _unitReportCtrl.stream;
  Stream<int> get presetReportStream => _presetReportCtrl.stream;
  Stream<String> get engineNotificationStream => _engineNotificationCtrl.stream;
  Stream<bool> get streamlightReportStream => _streamlightReportCtrl.stream;
  Stream<Map<String, String>> get buttonEventStream => _buttonEventCtrl.stream;
  Stream<Map<String, dynamic>> get sensorDataStream => _sensorDataCtrl.stream;
  Stream<int> get knobDeltaStream => _knobDeltaCtrl.stream;
  Stream<LogoSlotStatus> get logoSlotsStream => _logoSlotsCtrl.stream;
  Stream<String> get wifiIpStream => _wifiIpCtrl.stream;
  Stream<String> get wifiErrorStream => _wifiErrorCtrl.stream;
  Stream<Map<String, dynamic>> get audioReadyStream => _audioReadyCtrl.stream;
  Stream<int> get volumeStream => _volumeCtrl.stream;
  Stream<String> get wifiScanStream => _wifiScanCtrl.stream;
  Stream<Map<String, int>> get ledUpdateStream => _ledUpdateCtrl.stream;

  /// 原始响应流（每条完整命令，用于调试和向后兼容）
  Stream<String> get rawResponseStream => _rawResponseCtrl.stream;

  ResponseRouter(this._commandSender);

  // ═══════════════════════════════════════════════════════════════
  //  数据入口 — 由 BLEService.rxDataStream 驱动
  // ═══════════════════════════════════════════════════════════════

  /// 处理 BLE 接收到的原始字节
  void handleReceivedData(List<int> data) {
    final chunk = String.fromCharCodes(data);
    _dataBuffer += chunk;

    // 按换行符分割完整命令
    while (_dataBuffer.contains('\n')) {
      final idx = _dataBuffer.indexOf('\n');
      final command = _dataBuffer.substring(0, idx).trim();
      _dataBuffer = _dataBuffer.substring(idx + 1);

      if (command.isNotEmpty) {
        _routeResponse(command);
      }
    }

    // 缓冲区溢出保护（1024 字节无换行符则清空）
    // 增大到 1024 以容纳 Logo ACK 等较长响应
    if (_dataBuffer.length > 1024 && !_dataBuffer.contains('\n')) {
      debugPrint('⚠️ [ResponseRouter] 缓冲区溢出 (${_dataBuffer.length}B)，清空');
      _dataBuffer = '';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  同步查询
  // ═══════════════════════════════════════════════════════════════

  static const _queryTimeout = Duration(seconds: 3);

  /// 发送 GET:ALL 并等待 STATUS 响应
  Future<Map<String, dynamic>> queryAllStatusSync() =>
      _querySync('GET:ALL', 'GET:ALL');

  /// 发送 GET:FAN 并等待 FAN 响应
  Future<Map<String, dynamic>> queryFanSpeedSync() =>
      _querySync('GET:FAN', 'GET:FAN');

  /// 发送 GET:WUHUA 并等待 WUHUA 响应
  Future<Map<String, dynamic>> queryWuhuaqiStatusSync() =>
      _querySync('GET:WUHUA', 'GET:WUHUA');

  Future<Map<String, dynamic>> _querySync(
      String command, String requestKey) async {
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;

    try {
      await _commandSender.sendRawCommand(command);
      return await completer.future.timeout(_queryTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      return {'success': false, 'error': 'timeout'};
    } catch (e) {
      _pendingRequests.remove(requestKey);
      return {'success': false, 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  响应路由核心
  // ═══════════════════════════════════════════════════════════════

  void _routeResponse(String response) {
    // Filter out echoed commands. Some Android BLE stacks echo writes back
    // through the notify stream. We only filter patterns that are clearly
    // outbound commands and can never be valid firmware responses.
    // Firmware responses: STATUS:, OK:, PRESET:, VOL:, LOGO_SLOTS:,
    //   WIFI_IP:, WIFI_ERR:, WIFI_SCAN:, AUDIO_READY:, STREAMLIGHT:, REPORT:
    if (response.startsWith('GET:') ||
        response.startsWith('UNIT:') ||
        response.startsWith('THROTTLE:') ||
        response.startsWith('LED:') ||
        response.startsWith('LCD:') ||
        response.startsWith('WUHUAQI:') ||
        response.startsWith('LOGO_START:') ||
        response.startsWith('LOGO_DATA:') ||
        response.startsWith('LOGO_END') ||
        response.startsWith('SPEED_MAX:') ||
        response.startsWith('FAN_RANGE:') ||
        response.startsWith('AUDIO_START') ||
        response.startsWith('AUDIO_END') ||
        response.startsWith('OTA_START') ||
        response.startsWith('OTA_END') ||
        (response.startsWith('SPEED:') && !response.contains('REPORT')) ||
        (response.startsWith('UI:') && response.length <= 4)) {
      debugPrint('🔇 [ResponseRouter] filtered echo: "$response"');
      return;
    }

    // 1. 广播原始响应（调试 + 向后兼容）
    _rawResponseCtrl.add(response);

    // 2. 尝试匹配 CommandSender 的前缀等待请求
    _commandSender.matchPrefixRequest(response);

    // 3. 尝试匹配同步查询请求
    _matchPendingRequest(response);

    // 4. 解析并分发主动上报
    _dispatchProactiveReport(response);
  }

  void _matchPendingRequest(String response) {
    String? requestKey;
    Map<String, dynamic>? result;

    // STATUS 必须在 FAN/WUHUA 之前匹配
    if (response.contains('STATUS:')) {
      requestKey = 'GET:ALL';
      final parsed = ProtocolParser.parseAllStatus(response);
      if (parsed != null) result = {'success': true, ...parsed};
    } else if (response.startsWith('LOGO_SLOTS:')) {
      requestKey = 'GET:LOGO_SLOTS';
      final parsed = ProtocolParser.parseLogoSlots(response);
      if (parsed != null) result = {'success': true, 'logoSlots': parsed};
    } else if (response.startsWith('VOL:')) {
      requestKey = 'GET:VOL';
      final vol = ProtocolParser.parseVolume(response);
      if (vol != null) result = {'success': true, 'volume': vol};
    } else if (response.startsWith('OK:STREAMLIGHT:')) {
      requestKey = 'STREAMLIGHT';
      final state = ProtocolParser.parseStreamlightOk(response);
      if (state != null) result = {'success': true, 'state': state};
    } else if (response.startsWith('WIFI_IP:')) {
      requestKey = 'WIFI';
      final ip = ProtocolParser.parseWifiIp(response);
      if (ip != null) result = {'success': true, 'ip': ip};
    } else if (response.startsWith('AUDIO_READY:')) {
      requestKey = 'AUDIO_READY';
      final ar = ProtocolParser.parseAudioReady(response);
      if (ar != null) result = {'success': true, ...ar};
    } else if (response.startsWith('WIFI_ERR:')) {
      requestKey = 'WIFI';
      final reason = ProtocolParser.parseWifiError(response);
      if (reason != null) result = {'success': false, 'error': reason};
    } else if (response.startsWith('WIFI_SCAN:')) {
      requestKey = 'WIFI_SCAN';
      final scan = ProtocolParser.parseWifiScan(response);
      if (scan != null) result = {'success': true, 'result': scan};
    } else if (response.contains('FAN:')) {
      requestKey = 'GET:FAN';
      final speed = ProtocolParser.parseFanSpeed(response);
      if (speed != null) result = {'success': true, 'speed': speed};
    } else if (response.contains('WUHUA:')) {
      requestKey = 'GET:WUHUA';
      final status = ProtocolParser.parseWuhuaqiStatus(response);
      if (status != null) result = {'success': true, 'status': status};
    }

    if (requestKey != null && _pendingRequests.containsKey(requestKey)) {
      _pendingRequests[requestKey]!.complete(result ?? {'success': false});
      _pendingRequests.remove(requestKey);
    }
  }

  void _dispatchProactiveReport(String response) {
    // 速度报告（高频，优先）
    final speed = ProtocolParser.parseSpeedReport(response);
    if (speed != null) { _speedReportCtrl.add(speed); return; }

    final throttle = ProtocolParser.parseThrottleReport(response);
    if (throttle != null) { _throttleReportCtrl.add(throttle); return; }

    final unit = ProtocolParser.parseUnitReport(response);
    if (unit != null) { _unitReportCtrl.add(unit); return; }

    final preset = ProtocolParser.parsePresetReport(response);
    if (preset != null) { _presetReportCtrl.add(preset); return; }

    final engine = ProtocolParser.parseEngineNotification(response);
    if (engine != null) { _engineNotificationCtrl.add(engine); return; }

    final streamlight = ProtocolParser.parseStreamlightReport(response);
    if (streamlight != null) { _streamlightReportCtrl.add(streamlight); return; }

    final streamlightOk = ProtocolParser.parseStreamlightOk(response);
    if (streamlightOk != null) { _streamlightReportCtrl.add(streamlightOk); return; }

    final logoSlots = ProtocolParser.parseLogoSlots(response);
    if (logoSlots != null) { _logoSlotsCtrl.add(logoSlots); return; }

    final wifiIp = ProtocolParser.parseWifiIp(response);
    if (wifiIp != null) { _wifiIpCtrl.add(wifiIp); return; }

    final audioReady = ProtocolParser.parseAudioReady(response);
    if (audioReady != null) { _audioReadyCtrl.add(audioReady); return; }

    final wifiErr = ProtocolParser.parseWifiError(response);
    if (wifiErr != null) { _wifiErrorCtrl.add(wifiErr); return; }

    final vol = ProtocolParser.parseVolume(response);
    if (vol != null) { _volumeCtrl.add(vol); return; }

    final wifiScan = ProtocolParser.parseWifiScan(response);
    if (wifiScan != null) { _wifiScanCtrl.add(wifiScan); return; }

    final knob = ProtocolParser.parseKnobDelta(response);
    if (knob != null) { _knobDeltaCtrl.add(knob); return; }

    final ledUpdate = ProtocolParser.parseLedUpdate(response);
    if (ledUpdate != null) { _ledUpdateCtrl.add(ledUpdate); return; }

    final btn = ProtocolParser.parseButtonEvent(response);
    if (btn != null) { _buttonEventCtrl.add(btn); return; }

    final sensor = ProtocolParser.parseSensorData(response);
    if (sensor != null) { _sensorDataCtrl.add(sensor); return; }

    // 未知响应（排除已知 ACK 类型）
    if (!ProtocolParser.isAckResponse(response)) {
      debugPrint('⚠️ [ResponseRouter] 未知响应: "$response"');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  重置 / 释放
  // ═══════════════════════════════════════════════════════════════

  /// 重置缓冲区和等待队列（重连时调用）
  void reset() {
    _dataBuffer = '';
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('Reset on reconnect'));
      }
    }
    _pendingRequests.clear();
    _commandSender.resetPendingRequests();
  }

  void dispose() {
    _speedReportCtrl.close();
    _throttleReportCtrl.close();
    _unitReportCtrl.close();
    _presetReportCtrl.close();
    _engineNotificationCtrl.close();
    _streamlightReportCtrl.close();
    _buttonEventCtrl.close();
    _sensorDataCtrl.close();
    _knobDeltaCtrl.close();
    _logoSlotsCtrl.close();
    _wifiIpCtrl.close();
    _wifiErrorCtrl.close();
    _audioReadyCtrl.close();
    _volumeCtrl.close();
    _wifiScanCtrl.close();
    _rawResponseCtrl.close();
    _ledUpdateCtrl.close();
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.complete({'success': false, 'error': 'disposed'});
      }
    }
    _pendingRequests.clear();
  }
}
