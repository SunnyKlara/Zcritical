import 'dart:async';
import 'ble_service.dart';
import '../models/speed_report.dart';

/// 通信协议服务
/// 负责封装BLE通信协议，提供高级控制接口
///
/// 🆕 双向通信功能:
/// - 硬件主动上报: 按钮事件、传感器数据、速度报告
/// - 同步查询: queryXxx() 方法等待硬件响应
/// - 旋钮联动: 通过 knobDeltaStream 广播
/// - 速度同步: 通过 speedReportStream 广播
class ProtocolService {
  final BLEService bleService;

  // 响应数据流控制器
  final StreamController<String> _responseController =
      StreamController<String>.broadcast();

  // 🆕 按钮事件流控制器
  final StreamController<Map<String, String>> _buttonEventController =
      StreamController<Map<String, String>>.broadcast();

  // 🆕 传感器数据流控制器
  final StreamController<Map<String, dynamic>> _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 🆕 速度报告流控制器 (硬件旋钮调整速度时上报)
  final StreamController<SpeedReport> _speedReportController =
      StreamController<SpeedReport>.broadcast();

  // 🆕 油门报告流控制器 (硬件三击进入/退出油门模式时上报)
  final StreamController<bool> _throttleReportController =
      StreamController<bool>.broadcast();

  // 🆕 单位报告流控制器 (硬件单击切换单位时上报)
  final StreamController<bool> _unitReportController =
      StreamController<bool>.broadcast();

  // 🆕 预设报告流控制器 (硬件旋钮切换预设时上报)
  final StreamController<int> _presetReportController =
      StreamController<int>.broadcast();

  // 🚗 引擎通知流控制器 (硬件开机时上报)
  final StreamController<String> _engineNotificationController =
      StreamController<String>.broadcast();

  // 🔄 流水灯状态流控制器 (硬件流水灯状态变化时上报)
  final StreamController<bool> _streamlightReportController =
      StreamController<bool>.broadcast();

  // 🆕 等待响应的请求队列 (用于同步查询)
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  // 🆕 响应超时时间
  static const Duration _responseTimeout = Duration(seconds: 3);

  Stream<String> get responseStream => _responseController.stream;

  // 🆕 按钮事件流
  Stream<Map<String, String>> get buttonEventStream =>
      _buttonEventController.stream;

  // 🆕 传感器数据流
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;

  // 🆕 速度报告流 (硬件主动上报)
  Stream<SpeedReport> get speedReportStream => _speedReportController.stream;

  // 🆕 油门报告流 (硬件主动上报)
  Stream<bool> get throttleReportStream => _throttleReportController.stream;

  // 🆕 单位报告流 (硬件主动上报) - true=km/h, false=mph
  Stream<bool> get unitReportStream => _unitReportController.stream;

  // 🆕 预设报告流 (硬件主动上报) - 预设索引 1-12
  Stream<int> get presetReportStream => _presetReportController.stream;

  // 🚗 引擎通知流 (硬件开机时上报) - ENGINE_START / ENGINE_READY
  Stream<String> get engineNotificationStream => _engineNotificationController.stream;

  // 🔄 流水灯状态流 (硬件主动上报) - true=开启, false=关闭
  Stream<bool> get streamlightReportStream => _streamlightReportController.stream;

  // 🔧 数据缓冲区（用于处理蓝牙分包）
  String _dataBuffer = '';

  ProtocolService(this.bleService) {
    // 监听BLE接收数据
    bleService.rxDataStream.listen(_handleReceivedData);
  }

  /// 🆕 统一处理接收到的数据（带分包重组）
  void _handleReceivedData(List<int> data) {
    String chunk = String.fromCharCodes(data);
    print('📩 协议层收到片段: $chunk');

    // 将新数据追加到缓冲区
    _dataBuffer += chunk;

    // 按换行符分割，处理完整的命令
    while (_dataBuffer.contains('\n')) {
      int newlineIndex = _dataBuffer.indexOf('\n');
      String completeCommand = _dataBuffer.substring(0, newlineIndex).trim();
      _dataBuffer = _dataBuffer.substring(newlineIndex + 1);

      if (completeCommand.isNotEmpty) {
        print('📩 协议层完整命令: $completeCommand');

        // 尝试匹配等待中的请求
        _matchPendingRequest(completeCommand);

        // 尝试解析主动上报的数据
        _parseProactiveReport(completeCommand);

        // 广播到响应流（保持原有逻辑）
        _responseController.add(completeCommand);
      }
    }

    // 防止缓冲区过大（异常情况）
    if (_dataBuffer.length > 512) {
      print('⚠️ 缓冲区过大，清空: $_dataBuffer');
      _dataBuffer = '';
    }
  }

  /// 🆕 匹配等待中的请求（用于同步查询）
  void _matchPendingRequest(String response) {
    String? requestKey;
    Map<String, dynamic>? result;

    if (response.contains('FAN:')) {
      requestKey = 'GET:FAN';
      int? speed = parseFanSpeed(response);
      if (speed != null) {
        result = {'success': true, 'speed': speed};
      }
    } else if (response.contains('WUHUA:')) {
      requestKey = 'GET:WUHUA';
      int? status = parseWuhuaqiStatus(response);
      if (status != null) {
        result = {'success': true, 'status': status};
      }
    } else if (response.startsWith('AUDIO:') &&
        response.split(':').length >= 5) {
      requestKey = 'GET:AUDIO';
      var audioStatus = parseAudioStatus(response);
      if (audioStatus != null) {
        result = {'success': true, ...audioStatus};
      }
    } else if (response.contains('STATUS:')) {
      requestKey = 'GET:ALL';
      var allStatus = parseAllStatus(response);
      if (allStatus != null) {
        result = {'success': true, ...allStatus};
      }
    }

    // 完成等待中的请求
    if (requestKey != null && _pendingRequests.containsKey(requestKey)) {
      _pendingRequests[requestKey]!.complete(result ?? {'success': false});
      _pendingRequests.remove(requestKey);
    }
  }

  /// 🆕 解析硬件主动上报的数据
  void _parseProactiveReport(String response) {
    print('🔍 [ProtocolService] 尝试解析: "${response.trim()}"');

    // 解析速度报告 (优先级最高，因为是高频数据)
    var speedReport = parseSpeedReport(response);
    if (speedReport != null) {
      print('🏎️ [ProtocolService] 速度报告解析成功: $speedReport');
      print('🏎️ [ProtocolService] 广播到 speedReportStream...');
      _speedReportController.add(speedReport);
      print('🏎️ [ProtocolService] 广播完成');
      return;
    } else {
      print('⚠️ [ProtocolService] 速度报告解析失败');
    }

    // 解析油门报告
    var throttleReport = parseThrottleReport(response);
    if (throttleReport != null) {
      print('🔥 收到油门报告: ${throttleReport ? "开启" : "关闭"}');
      _throttleReportController.add(throttleReport);
      return;
    }

    // 🆕 解析单位报告
    var unitReport = parseUnitReport(response);
    if (unitReport != null) {
      print('📏 收到单位报告: ${unitReport ? "km/h" : "mph"}');
      _unitReportController.add(unitReport);
      return;
    }

    // 🆕 解析预设报告
    var presetReport = parsePresetReport(response);
    if (presetReport != null) {
      print('🎨 收到预设报告: 预设 $presetReport');
      _presetReportController.add(presetReport);
      return;
    }

    // 🚗 解析引擎通知 (ENGINE_START / ENGINE_READY)
    var engineNotification = parseEngineNotification(response);
    if (engineNotification != null) {
      print('🚗 收到引擎通知: $engineNotification');
      _engineNotificationController.add(engineNotification);
      return;
    }

    // 🔄 解析流水灯状态报告
    var streamlightReport = parseStreamlightReport(response);
    if (streamlightReport != null) {
      print('🔄 收到流水灯状态报告: ${streamlightReport ? "开启" : "关闭"}');
      _streamlightReportController.add(streamlightReport);
      return;
    }

    // 解析按钮事件
    var btnEvent = parseButtonEvent(response);
    if (btnEvent != null) {
      print('🔘 收到按钮事件: $btnEvent');
      _buttonEventController.add(btnEvent);
      return;
    }

    // 解析传感器数据
    var sensorData = parseSensorData(response);
    if (sensorData != null) {
      print('📊 收到传感器数据: $sensorData');
      _sensorDataController.add(sensorData);
      return;
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🆕 同步查询方法 (等待硬件响应)                        ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 🆕 查询风扇速度（同步等待响应）
  /// 返回: {success: bool, speed: int?, error: String?}
  Future<Map<String, dynamic>> queryFanSpeedSync() async {
    const requestKey = 'GET:FAN';

    // 创建Completer
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;

    // 发送查询命令
    await bleService.sendString('GET:FAN\n');

    // 等待响应（带超时）
    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      print('⏰ 查询风扇速度超时');
      return {'success': false, 'error': 'timeout'};
    }
  }

  /// 🆕 查询雾化器状态（同步等待响应）
  /// 返回: {success: bool, status: int?, error: String?}
  Future<Map<String, dynamic>> queryWuhuaqiStatusSync() async {
    const requestKey = 'GET:WUHUA';

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;

    await bleService.sendString('GET:WUHUA\n');

    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      print('⏰ 查询雾化器状态超时');
      return {'success': false, 'error': 'timeout'};
    }
  }

  /// 🆕 查询音频状态（同步等待响应）
  /// 返回: {success: bool, state, volume, currentFile, totalFiles, error?}
  Future<Map<String, dynamic>> queryAudioStatusSync() async {
    const requestKey = 'GET:AUDIO';

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;

    await bleService.sendString('GET:AUDIO\n');

    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      print('⏰ 查询音频状态超时');
      return {'success': false, 'error': 'timeout'};
    }
  }

  /// 🆕 查询所有状态（同步等待响应）
  /// 返回: {success: bool, fan, wuhua, brightness, error?}
  Future<Map<String, dynamic>> queryAllStatusSync() async {
    const requestKey = 'GET:ALL';

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;

    await bleService.sendString('GET:ALL\n');

    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      print('⏰ 查询所有状态超时');
      return {'success': false, 'error': 'timeout'};
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🆕 硬件主动上报解析方法                               ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 🆕 解析按钮事件
  /// 响应格式: BTN:type:action
  /// 例: BTN:KNOB:CLICK, BTN:KNOB:LONG, BTN:KNOB:TRIPLE
  /// 返回: {type, action}，解析失败返回null
  Map<String, String>? parseButtonEvent(String response) {
    response = response.trim();

    RegExp btnRegex = RegExp(r'BTN:(\w+):(\w+)');
    Match? match = btnRegex.firstMatch(response);

    if (match != null) {
      return {
        'type': match.group(1)!, // KNOB, POWER, etc.
        'action': match.group(2)!, // CLICK, LONG, DOUBLE, TRIPLE
      };
    }
    return null;
  }

  /// 🆕 解析传感器数据
  /// 响应格式: SENSOR:type:value
  /// 例: SENSOR:TEMP:45, SENSOR:BAT:85
  /// 返回: {type, value}，解析失败返回null
  Map<String, dynamic>? parseSensorData(String response) {
    response = response.trim();

    RegExp sensorRegex = RegExp(r'SENSOR:(\w+):(-?\d+)');
    Match? match = sensorRegex.firstMatch(response);

    if (match != null) {
      return {
        'type': match.group(1)!, // TEMP, BAT, etc.
        'value': int.parse(match.group(2)!),
      };
    }
    return null;
  }

  /// 🆕 解析所有状态响应
  /// 响应格式: STATUS:FAN:50:WUHUA:1:BRIGHT:80
  /// 返回: {fan, wuhua, brightness}，解析失败返回null
  Map<String, dynamic>? parseAllStatus(String response) {
    response = response.trim();

    RegExp statusRegex = RegExp(r'STATUS:FAN:(\d+):WUHUA:(\d+):BRIGHT:(\d+)');
    Match? match = statusRegex.firstMatch(response);

    if (match != null) {
      return {
        'fan': int.parse(match.group(1)!),
        'wuhua': int.parse(match.group(2)!),
        'brightness': int.parse(match.group(3)!),
      };
    }
    return null;
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🏎️ 速度报告解析 (硬件旋钮调整时上报)                  ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 🆕 解析速度报告
  /// 响应格式: SPEED_REPORT:value:unit 或 SPEED_REPORT:value
  /// 例: SPEED_REPORT:120:0 (120 km/h), SPEED_REPORT:75:1 (75 mph)
  /// 返回: SpeedReport 对象，解析失败返回 null
  SpeedReport? parseSpeedReport(String response) {
    return SpeedReport.fromProtocol(response);
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🔥 油门报告解析 (硬件三击进入/退出油门模式时上报)       ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 🆕 解析油门报告
  /// 响应格式: THROTTLE_REPORT:0 或 THROTTLE_REPORT:1
  /// 返回: true=进入油门模式, false=退出油门模式, null=解析失败
  bool? parseThrottleReport(String response) {
    response = response.trim();

    RegExp throttleRegex = RegExp(r'THROTTLE_REPORT:(\d+)');
    Match? match = throttleRegex.firstMatch(response);

    if (match != null) {
      int state = int.parse(match.group(1)!);
      return state == 1;
    }
    return null;
  }

  /// 🆕 解析单位报告
  /// 响应格式: UNIT_REPORT:0 (km/h) 或 UNIT_REPORT:1 (mph)
  /// 返回: true=km/h, false=mph, null=解析失败
  bool? parseUnitReport(String response) {
    response = response.trim();

    RegExp unitRegex = RegExp(r'UNIT_REPORT:(\d+)');
    Match? match = unitRegex.firstMatch(response);

    if (match != null) {
      int unit = int.parse(match.group(1)!);
      return unit == 0; // 0=km/h(true), 1=mph(false)
    }
    return null;
  }

  /// 🆕 解析预设报告
  /// 响应格式: PRESET_REPORT:n (n=1-12)
  /// 返回: 预设索引 1-12, null=解析失败
  int? parsePresetReport(String response) {
    response = response.trim();

    RegExp presetRegex = RegExp(r'PRESET_REPORT:(\d+)');
    Match? match = presetRegex.firstMatch(response);

    if (match != null) {
      int preset = int.parse(match.group(1)!);
      if (preset >= 1 && preset <= 12) {
        return preset;
      }
    }
    return null;
  }

  /// 🚗 解析引擎通知
  /// 响应格式: ENGINE_START 或 ENGINE_READY
  /// 返回: 通知类型字符串, null=解析失败
  String? parseEngineNotification(String response) {
    response = response.trim();
    
    if (response == 'ENGINE_START') {
      return 'ENGINE_START';
    } else if (response == 'ENGINE_READY') {
      return 'ENGINE_READY';
    }
    return null;
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🔄 流水灯控制 (Streamlight Mode)                     ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置流水灯模式
  /// [enable] true=开启流水灯, false=关闭流水灯
  /// 
  /// 命令格式: STREAMLIGHT:1\n (开启) 或 STREAMLIGHT:0\n (关闭)
  /// 响应格式: OK:STREAMLIGHT:1\r\n 或 OK:STREAMLIGHT:0\r\n
  /// 
  /// 返回: true=发送成功, false=发送失败
  Future<bool> setStreamlightMode(bool enable) async {
    String command = 'STREAMLIGHT:${enable ? 1 : 0}\n';
    print('📤 发送流水灯命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送流水灯命令失败: $e');
      return false;
    }
  }

  /// 查询流水灯状态
  /// 
  /// 命令格式: GET:STREAMLIGHT\n
  /// 响应格式: STREAMLIGHT:0\r\n 或 STREAMLIGHT:1\r\n
  /// 
  /// 返回: true=发送成功, false=发送失败
  Future<bool> getStreamlightStatus() async {
    String command = 'GET:STREAMLIGHT\n';
    print('📤 查询流水灯状态');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 查询流水灯状态失败: $e');
      return false;
    }
  }

  /// 解析流水灯状态报告
  /// 响应格式: STREAMLIGHT_REPORT:0 或 STREAMLIGHT_REPORT:1
  /// 或: STREAMLIGHT:0 或 STREAMLIGHT:1
  /// 返回: true=开启, false=关闭, null=解析失败
  bool? parseStreamlightReport(String response) {
    response = response.trim();

    // 匹配 STREAMLIGHT_REPORT:数字 或 STREAMLIGHT:数字
    RegExp streamlightRegex = RegExp(r'STREAMLIGHT(?:_REPORT)?:(\d+)');
    Match? match = streamlightRegex.firstMatch(response);

    if (match != null) {
      int state = int.parse(match.group(1)!);
      return state == 1;
    }
    return null;
  }

  /// 设置风扇速度
  /// [speed] 风扇速度 (0-100)
  /// 返回: true=发送成功, false=发送失败
  Future<bool> setFanSpeed(int speed) async {
    // 参数校验
    if (speed < 0 || speed > 100) {
      print('❌ 风扇速度超出范围: $speed (应为0-100)');
      return false;
    }

    // 构造命令: FAN:speed\n
    String command = 'FAN:$speed\n';
    print('📤 发送命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送失败: $e');
      return false;
    }
  }

  /// 查询风扇速度
  Future<bool> getFanSpeed() async {
    String command = 'GET:FAN\n';
    print('📤 查询风扇速度');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 查询失败: $e');
      return false;
    }
  }

  /// 设置速度单位
  /// [unit] 0=km/h, 1=mph
  Future<bool> setSpeedUnit(int unit) async {
    String command = 'UNIT:$unit\n';
    print('📤 设置速度单位: ${unit == 0 ? "km/h" : "mph"}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 设置单位失败: $e');
      return false;
    }
  }

  /// 运行模式速度同步
  /// [speed] 绝对速度 (0-340)
  Future<bool> setRunningSpeed(int speed) async {
    String command = 'SPEED:$speed\n';
    // 节约日志，高频指令不打印详情
    // print('📤 同步运行速度: $speed');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 同步运行速度失败: $e');
      return false;
    }
  }

  /// 开启/关闭硬件油门模式 (远程模拟三击)
  /// [enable] true=开始加速, false=停止加速
  Future<bool> setHardwareThrottleMode(bool enable) async {
    String command = 'THROTTLE:${enable ? 1 : 0}\n';
    print('📤 发送油门模式指令: ${enable ? "开启" : "关闭"}');
    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送油门模式指令失败: $e');
      return false;
    }
  }

  /// 解析风扇速度响应
  /// 响应格式: FAN:50 或 OK:FAN:50
  int? parseFanSpeed(String response) {
    response = response.trim();

    // 匹配 FAN:数字
    RegExp fanRegex = RegExp(r'FAN:(\d+)');
    Match? match = fanRegex.firstMatch(response);

    if (match != null) {
      int speed = int.parse(match.group(1)!);
      print('✅ 解析到风扇速度: $speed');
      return speed;
    }

    return null;
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🌫️ 雾化器控制 (Cleaning Mode)                       ║
  // ║          协议格式参考: 蓝牙.md - 文本协议规范                  ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置雾化器状态 (Cleaning Mode 气流控制)
  ///
  /// [enable] true=开启雾化器, false=关闭雾化器
  ///
  /// 命令格式: WUHUA:1\n (开启) 或 WUHUA:0\n (关闭)
  /// 响应格式: OK:WUHUA:1\r\n 或 OK:WUHUA:0\r\n
  ///
  /// 硬件端: PB8 引脚控制雾化器开关
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> setWuhuaqiStatus(bool enable) async {
    // 构造命令: WUHUA:0 或 WUHUA:1
    String command = 'WUHUA:${enable ? 1 : 0}\n';
    print('📤 [ProtocolService] 准备发送雾化器命令: ${command.trim()}');
    print('📤 [ProtocolService] 命令字节: ${command.codeUnits}');

    try {
      print('📤 [ProtocolService] 调用 bleService.sendString...');
      await bleService.sendString(command);
      print('✅ [ProtocolService] sendString 返回成功');
      return true;
    } catch (e) {
      print('❌ [ProtocolService] 发送失败: $e');
      return false;
    }
  }

  /// 查询雾化器状态
  ///
  /// 命令格式: GET:WUHUA\n
  /// 响应格式: WUHUA:0\r\n 或 WUHUA:1\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> getWuhuaqiStatus() async {
    String command = 'GET:WUHUA\n';
    print('📤 查询雾化器状态');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 查询雾化器状态失败: $e');
      return false;
    }
  }

  /// 解析雾化器状态响应
  ///
  /// 响应格式: WUHUA:0 或 WUHUA:1 或 OK:WUHUA:0 或 OK:WUHUA:1
  ///
  /// 返回: 0=关闭, 1=开启, null=解析失败
  int? parseWuhuaqiStatus(String response) {
    response = response.trim();

    // 匹配 WUHUA:数字
    RegExp wuhuaqiRegex = RegExp(r'WUHUA:(\d+)');
    Match? match = wuhuaqiRegex.firstMatch(response);

    if (match != null) {
      int status = int.parse(match.group(1)!);
      print('✅ 解析到雾化器状态: ${status == 1 ? "开启" : "关闭"}');
      return status;
    }

    return null;
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🎛️ 旋钮增量控制 (Encoder Delta)                     ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 解析旋钮增量数据
  ///
  /// 响应格式: KNOB:delta 或 ENCODER:delta
  /// delta: 正数=顺时针旋转，负数=逆时针旋转
  ///
  /// 返回: 增量值，null=解析失败
  int? parseKnobDelta(String response) {
    response = response.trim();

    // 匹配 KNOB:数字 或 ENCODER:数字（支持负数）
    RegExp knobRegex = RegExp(r'(?:KNOB|ENCODER):(-?\d+)');
    Match? match = knobRegex.firstMatch(response);

    if (match != null) {
      int delta = int.parse(match.group(1)!);
      print('🎛️ 解析到旋钮增量: $delta');
      return delta;
    }

    return null;
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          📺 LCD屏幕控制                                        ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置LCD状态
  /// [enable] true=开屏, false=熄屏
  Future<bool> setLCDStatus(bool enable) async {
    String command = 'LCD:${enable ? 1 : 0}\n';
    print('📤 发送LCD命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送失败: $e');
      return false;
    }
  }

  /// 设置硬件UI界面
  /// [uiIndex] 0=开机动画, 1=调速操作界面, 2=配色预设, 3=RGB调色, 4=亮度调节
  Future<bool> setHardwareUI(int uiIndex) async {
    String command = 'UI:$uiIndex\n';
    print('📤 同步硬件UI: $uiIndex');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 同步硬件UI失败: $e');
      return false;
    }
  }

  /// 设置全局亮度
  /// [brightness] 亮度值 (0-100)
  Future<bool> setBrightness(int brightness) async {
    if (brightness < 0 || brightness > 100) {
      print('❌ 亮度值超出范围: $brightness (应为0-100)');
      return false;
    }

    String command = 'BRIGHT:$brightness\n';
    print('📤 发送亮度命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送亮度失败: $e');
      return false;
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          💡 LED颜色控制 (Colorize Mode)                       ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置LED预设方案
  /// [index] 预设索引 (1-12)
  Future<bool> setLEDPreset(int index) async {
    if (index < 1 || index > 12) {
      print('❌ LED预设索引超出范围: $index (应为1-12)');
      return false;
    }

    String command = 'PRESET:$index\n';
    print('📤 发送LED预设命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送失败: $e');
      return false;
    }
  }

  /// 🆕 查询当前LED预设
  /// 
  /// 命令格式: GET:PRESET\n
  /// 响应格式: PRESET_REPORT:n\r\n (n=1-12)
  /// 
  /// 返回: true=发送成功, false=发送失败
  Future<bool> queryCurrentPreset() async {
    String command = 'GET:PRESET\n';
    print('📤 查询当前LED预设');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 查询LED预设失败: $e');
      return false;
    }
  }

  /// 🆕 设置LED颜色
  /// [strip] 灯带编号 (1-4): 1=M, 2=L, 3=R, 4=B
  /// [r] 红色值 (0-255)
  /// [g] 绿色值 (0-255)
  /// [b] 蓝色值 (0-255)
  /// 返回: true=发送成功, false=发送失败
  Future<bool> setLEDColor(int strip, int r, int g, int b) async {
    // 参数校验
    if (strip < 1 || strip > 4) {
      print('❌ 灯带编号超出范围: $strip (应为1-4)');
      return false;
    }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      print('❌ RGB值超出范围: R=$r, G=$g, B=$b (应为0-255)');
      return false;
    }

    // 构造命令: LED:strip:r:g:b\n
    String command = 'LED:$strip:$r:$g:$b\n';
    print('📤 发送LED命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 发送失败: $e');
      return false;
    }
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🔊 音频控制 (Audio Control)                          ║
  // ║          协议格式参考: 蓝牙.md - 已实现命令列表                 ║
  // ║          硬件: VS1003 MP3解码器 + W25Q128 Flash               ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 播放音频文件
  ///
  /// [index] 音频文件索引 (0-14)
  ///
  /// 命令格式: AUDIO:PLAY:xx\n
  /// 响应格式: OK:AUDIO:PLAY:xx\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioPlay(int index) async {
    // 参数校验
    if (index < 0 || index > 14) {
      print('❌ 音频索引超出范围: $index (应为0-14)');
      return false;
    }

    String command = 'AUDIO:PLAY:$index\n';
    print('📤 发送音频播放命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 音频播放命令发送失败: $e');
      return false;
    }
  }

  /// 停止音频播放
  ///
  /// 命令格式: AUDIO:STOP\n
  /// 响应格式: OK:AUDIO:STOP\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioStop() async {
    String command = 'AUDIO:STOP\n';
    print('📤 发送音频停止命令');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 音频停止命令发送失败: $e');
      return false;
    }
  }

  /// 暂停音频播放
  ///
  /// 命令格式: AUDIO:PAUSE\n
  /// 响应格式: OK:AUDIO:PAUSE\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioPause() async {
    String command = 'AUDIO:PAUSE\n';
    print('📤 发送音频暂停命令');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 音频暂停命令发送失败: $e');
      return false;
    }
  }

  /// 继续音频播放
  ///
  /// 命令格式: AUDIO:RESUME\n
  /// 响应格式: OK:AUDIO:RESUME\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioResume() async {
    String command = 'AUDIO:RESUME\n';
    print('📤 发送音频继续命令');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 音频继续命令发送失败: $e');
      return false;
    }
  }

  /// 设置音量
  ///
  /// [volume] 音量值 (0-100)
  ///
  /// 命令格式: AUDIO:VOL:xx\n
  /// 响应格式: OK:AUDIO:VOL:xx\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioSetVolume(int volume) async {
    // 参数校验
    if (volume < 0 || volume > 100) {
      print('❌ 音量值超出范围: $volume (应为0-100)');
      return false;
    }

    String command = 'AUDIO:VOL:$volume\n';
    print('📤 发送音量设置命令: ${command.trim()}');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 音量设置命令发送失败: $e');
      return false;
    }
  }

  /// 下一首
  ///
  /// 命令格式: AUDIO:NEXT\n
  /// 响应格式: OK:AUDIO:NEXT\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioNext() async {
    String command = 'AUDIO:NEXT\n';
    print('📤 发送下一首命令');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 下一首命令发送失败: $e');
      return false;
    }
  }

  /// 上一首
  ///
  /// 命令格式: AUDIO:PREV\n
  /// 响应格式: OK:AUDIO:PREV\r\n
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> audioPrev() async {
    String command = 'AUDIO:PREV\n';
    print('📤 发送上一首命令');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 上一首命令发送失败: $e');
      return false;
    }
  }

  /// 查询音频状态
  ///
  /// 命令格式: GET:AUDIO\n
  /// 响应格式: AUDIO:PLAYING:80:0:15\r\n
  ///          └─状态  └音量 └当前 └总数
  ///
  /// 返回: true=发送成功, false=发送失败
  Future<bool> getAudioStatus() async {
    String command = 'GET:AUDIO\n';
    print('📤 查询音频状态');

    try {
      await bleService.sendString(command);
      return true;
    } catch (e) {
      print('❌ 查询音频状态失败: $e');
      return false;
    }
  }

  /// 解析音频状态响应
  ///
  /// 响应格式: AUDIO:PLAYING:80:0:15
  ///          AUDIO:状态:音量:当前文件:总文件数
  ///
  /// 返回: Map包含 {state, volume, currentFile, totalFiles}，解析失败返回null
  Map<String, dynamic>? parseAudioStatus(String response) {
    response = response.trim();

    // 匹配 AUDIO:状态:音量:当前:总数
    RegExp audioRegex = RegExp(r'AUDIO:(\w+):(\d+):(\d+):(\d+)');
    Match? match = audioRegex.firstMatch(response);

    if (match != null) {
      Map<String, dynamic> status = {
        'state': match.group(1), // PLAYING/PAUSED/STOPPED
        'volume': int.parse(match.group(2)!),
        'currentFile': int.parse(match.group(3)!),
        'totalFiles': int.parse(match.group(4)!),
      };
      print('✅ 解析到音频状态: $status');
      return status;
    }

    return null;
  }

  /// 🆕 发送原始命令（用于Logo上传等自定义协议）
  /// [command] 命令字符串（不需要包含换行符，会自动添加）
  Future<bool> sendRawCommand(String command) async {
    // 确保命令以换行符结尾
    String fullCommand = command.endsWith('\n') ? command : '$command\n';
    print('📤 发送原始命令: ${fullCommand.trim()}');

    try {
      await bleService.sendString(fullCommand);
      return true;
    } catch (e) {
      print('❌ 发送原始命令失败: $e');
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    _responseController.close();
    _buttonEventController.close();
    _sensorDataController.close();
    _speedReportController.close();
    _throttleReportController.close();
    _unitReportController.close();
    _presetReportController.close();
    _engineNotificationController.close(); // 🚗 关闭引擎通知流
    _streamlightReportController.close(); // 🔄 关闭流水灯状态流
    // 取消所有等待中的请求
    for (var completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete({'success': false, 'error': 'disposed'});
      }
    }
    _pendingRequests.clear();
  }
}
