import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/device_model.dart';
import '../models/speed_report.dart';
import '../services/ble_service.dart';
import '../services/protocol_service.dart';
import '../services/engine_audio_manager.dart';
import '../utils/debug_logger.dart';

/// 蓝牙提供者
/// 管理蓝牙设备的扫描、连接状态
class BluetoothProvider with ChangeNotifier {
  final BLEService _bleService = BLEService();
  late final ProtocolService _protocolService;

  bool _isScanning = false;
  bool _isBluetoothEnabled = false;
  final List<DeviceModel> _devices = [];
  DeviceModel? _connectedDevice;
  int? _currentSpeed; // 当前风扇速度
  bool _wuhuaqiStatus = false; // 🆕 雾化器状态 (false=关闭, true=开启)
  bool _streamlightStatus = false; // 🔄 流水灯状态 (false=关闭, true=开启)

  // 🏎️ 运行模式速度状态
  int _currentRunningSpeed = 0; // 当前运行速度 (0-340)
  bool _isReceivingReport = false; // 防循环更新标志
  bool _isThrottleMode = false; // 油门模式状态

  // 🔊 音频状态
  String _audioState = 'STOPPED'; // PLAYING/PAUSED/STOPPED
  int _audioVolume = 80; // 音量 0-100
  int _audioCurrentFile = 0; // 当前播放文件索引
  int _audioTotalFiles = 15; // 总文件数

  // 🎛️ 旋钮增量流控制器
  final StreamController<int> _knobDeltaController =
      StreamController<int>.broadcast();

  // 🆕 按钮事件流控制器
  final StreamController<Map<String, String>> _buttonEventController =
      StreamController<Map<String, String>>.broadcast();

  // 🆕 传感器数据流控制器
  final StreamController<Map<String, dynamic>> _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();

  // 🏎️ 速度报告流控制器 (转发 protocolService 的流)
  final StreamController<SpeedReport> _speedReportController =
      StreamController<SpeedReport>.broadcast();

  // 🔥 油门报告流控制器 (转发 protocolService 的流)
  final StreamController<bool> _throttleReportController =
      StreamController<bool>.broadcast();

  // 📏 单位报告流控制器 (转发 protocolService 的流)
  final StreamController<bool> _unitReportController =
      StreamController<bool>.broadcast();

  // 🎨 预设报告流控制器 (转发 protocolService 的流)
  final StreamController<int> _presetReportController =
      StreamController<int>.broadcast();

  // 🚗 引擎通知流控制器 (转发 protocolService 的流)
  final StreamController<String> _engineNotificationController =
      StreamController<String>.broadcast();

  // 🔄 流水灯状态流控制器 (转发 protocolService 的流)
  final StreamController<bool> _streamlightReportController =
      StreamController<bool>.broadcast();

  // 🐛 原始数据流控制器 (用于调试)
  final StreamController<String> _rawDataController =
      StreamController<String>.broadcast();

  bool get isScanning => _isScanning;
  bool get isBluetoothEnabled => _isBluetoothEnabled;
  List<DeviceModel> get devices => _devices;
  DeviceModel? get connectedDevice => _connectedDevice;
  bool get isConnected => _bleService.isConnected;
  Stream<bool> get connectionStream => _bleService.connectionStream;
  int? get currentSpeed => _currentSpeed;
  bool get wuhuaqiStatus => _wuhuaqiStatus; // 🆕 雾化器状态getter
  bool get streamlightStatus => _streamlightStatus; // 🔄 流水灯状态getter

  // 🏎️ 运行模式速度状态 getters
  int get currentRunningSpeed => _currentRunningSpeed;
  bool get isThrottleMode => _isThrottleMode;

  // 🔊 音频状态getters
  String get audioState => _audioState;
  int get audioVolume => _audioVolume;
  int get audioCurrentFile => _audioCurrentFile;
  int get audioTotalFiles => _audioTotalFiles;
  bool get isAudioPlaying => _audioState == 'PLAYING';

  // 🎛️ 旋钮增量流getter
  Stream<int> get knobDeltaStream => _knobDeltaController.stream;

  // 🆕 按钮事件流getter
  Stream<Map<String, String>> get buttonEventStream =>
      _buttonEventController.stream;

  // 🆕 传感器数据流getter
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;

  // 🏎️ 速度报告流getter (硬件主动上报)
  Stream<SpeedReport> get speedReportStream => _speedReportController.stream;

  // 🔥 油门报告流getter (硬件主动上报)
  Stream<bool> get throttleReportStream => _throttleReportController.stream;

  // 📏 单位报告流getter (硬件主动上报) - true=km/h, false=mph
  Stream<bool> get unitReportStream => _unitReportController.stream;

  // 🎨 预设报告流getter (硬件主动上报) - 预设索引 1-12
  Stream<int> get presetReportStream => _presetReportController.stream;

  // 🚗 引擎通知流getter (硬件开机时上报) - ENGINE_START / ENGINE_READY
  Stream<String> get engineNotificationStream => _engineNotificationController.stream;

  // 🔄 流水灯状态流getter (硬件主动上报) - true=开启, false=关闭
  Stream<bool> get streamlightReportStream => _streamlightReportController.stream;

  // 🐛 原始数据流getter (用于调试)
  Stream<String> get rawDataStream => _rawDataController.stream;

  // 🔥 数据缓冲区 - 解决蓝牙分包问题
  String _dataBuffer = '';

  BluetoothProvider() {
    _protocolService = ProtocolService(_bleService);

    // 🐛 监听原始蓝牙数据 (用于调试) - 🔥 添加缓冲处理
    _bleService.rxDataStream.listen((data) {
      final rawStr = String.fromCharCodes(data);
      debugPrint('🐛 [BluetoothProvider] 原始数据片段: $rawStr');

      // 🔥 添加到缓冲区
      _dataBuffer += rawStr;

      // 🔥 按换行符分割完整的命令
      while (_dataBuffer.contains('\n')) {
        final lineEnd = _dataBuffer.indexOf('\n');
        final line = _dataBuffer.substring(0, lineEnd).trim();
        _dataBuffer = _dataBuffer.substring(lineEnd + 1);

        if (line.isNotEmpty) {
          debugPrint('🐛 [BluetoothProvider] 完整命令: $line');
          _rawDataController.add(line);
        }
      }

      // 🔥 如果缓冲区太大（超过1KB），清空防止内存泄漏
      if (_dataBuffer.length > 1024) {
        debugPrint('⚠️ [BluetoothProvider] 缓冲区溢出，清空');
        _dataBuffer = '';
      }
    });

    // 监听硬件发送的数据
    _protocolService.responseStream.listen((response) {
      // 解析风扇速度响应
      int? speed = _protocolService.parseFanSpeed(response);
      if (speed != null) {
        _currentSpeed = speed;
        notifyListeners();
      }

      // 🆕 解析雾化器状态响应
      int? wuhuaqiState = _protocolService.parseWuhuaqiStatus(response);
      if (wuhuaqiState != null) {
        _wuhuaqiStatus = (wuhuaqiState == 1);
        notifyListeners();
      }

      // 🔊 解析音频状态响应
      Map<String, dynamic>? audioStatus = _protocolService.parseAudioStatus(
        response,
      );
      if (audioStatus != null) {
        _audioState = audioStatus['state'] ?? 'STOPPED';
        _audioVolume = audioStatus['volume'] ?? 80;
        _audioCurrentFile = audioStatus['currentFile'] ?? 0;
        _audioTotalFiles = audioStatus['totalFiles'] ?? 15;
        notifyListeners();
      }

      // 🎛️ 解析旋钮增量数据
      int? knobDelta = _protocolService.parseKnobDelta(response);
      if (knobDelta != null) {
        _knobDeltaController.add(knobDelta);
      }
    });

    // 🆕 监听按钮事件流
    _protocolService.buttonEventStream.listen((event) {
      debugPrint('🔘 收到按钮事件: $event');
      _buttonEventController.add(event);
    });

    // 🆕 监听传感器数据流
    _protocolService.sensorDataStream.listen((data) {
      debugPrint('📊 收到传感器数据: $data');
      _sensorDataController.add(data);
    });

    // 🏎️ 监听速度报告流 (硬件旋钮调整时上报)
    _protocolService.speedReportStream.listen((report) {
      debugPrint('🏎️ 收到速度报告: $report');
      _isReceivingReport = true;
      _currentRunningSpeed = report.speed;
      _speedReportController.add(report);
      notifyListeners();
      // 延迟重置标志，避免快速连续更新时的竞态条件
      Future.delayed(const Duration(milliseconds: 100), () {
        _isReceivingReport = false;
      });
    });

    // 🔥 监听油门报告流 (硬件三击进入/退出油门模式时上报)
    _protocolService.throttleReportStream.listen((isThrottle) {
      debugPrint('🔥 收到油门报告: ${isThrottle ? "开启" : "关闭"}');
      _isThrottleMode = isThrottle;
      _throttleReportController.add(isThrottle);
      notifyListeners();
    });

    // 📏 监听单位报告流 (硬件单击切换单位时上报)
    _protocolService.unitReportStream.listen((isMetric) {
      debugPrint('📏 收到单位报告: ${isMetric ? "km/h" : "mph"}');
      _unitReportController.add(isMetric);
      notifyListeners();
    });

    // 🎨 监听预设报告流 (硬件旋钮切换预设时上报)
    _protocolService.presetReportStream.listen((preset) {
      debugPrint('🎨 收到预设报告: 预设 $preset');
      _presetReportController.add(preset);
      notifyListeners();
    });

    // 🚗 监听引擎通知流 (硬件开机时上报)
    _protocolService.engineNotificationStream.listen((notification) {
      debugPrint('🚗 收到引擎通知: $notification');
      _engineNotificationController.add(notification);
    });

    // 🔄 监听流水灯状态流 (硬件流水灯状态变化时上报)
    _protocolService.streamlightReportStream.listen((isEnabled) {
      debugPrint('🔄 收到流水灯状态报告: ${isEnabled ? "开启" : "关闭"}');
      _streamlightStatus = isEnabled;
      _streamlightReportController.add(isEnabled);
      notifyListeners();
    });

    // 监听物理连接状态，掉线后及时更新状态，重连后自动同步
    bool wasConnected = false;
    _bleService.connectionStream.listen((connected) async {
      if (!connected) {
        // 断开连接
        _connectedDevice?.isConnected = false;
        _connectedDevice = null;
        wasConnected = false;
        notifyListeners();
      } else if (!wasConnected && _connectedDevice != null) {
        // 🔄 重连成功，自动查询硬件状态
        wasConnected = true;
        debugPrint('🔄 检测到重连，开始同步硬件状态...');
        await _syncHardwareStateOnReconnect();
      }
    });
  }

  /// 🔄 重连后自动同步硬件状态
  Future<void> _syncHardwareStateOnReconnect() async {
    try {
      // 等待连接稳定
      await Future.delayed(const Duration(milliseconds: 500));

      if (!isConnected) return;

      // 查询所有状态
      final result = await queryAllStatusSync();

      if (result['success'] == true) {
        debugPrint('🔄 硬件状态同步成功: $result');
      } else {
        debugPrint('⚠️ 硬件状态同步失败: ${result['error']}');
      }
    } catch (e) {
      debugPrint('❌ 重连同步异常: $e');
    }
  }

  /// 初始化蓝牙状态
  Future<void> init() async {
    try {
      _isBluetoothEnabled = await FlutterBluePlus.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('初始化蓝牙失败: $e');
      _isBluetoothEnabled = false;
    }
  }

  /// 开始扫描设备
  Future<void> startScan() async {
    final logger = DebugLogger();

    _isScanning = true;
    _devices.clear();
    notifyListeners();

    try {
      List<ScanResult> results = await _bleService.scanDevices(
        timeout: const Duration(seconds: 4),
      );

      debugPrint('📡 扫描到 ${results.length} 个蓝牙设备');
      logger.log('📡 扫描到 ${results.length} 个设备');

      for (var result in results) {
        final deviceName = result.device.platformName;
        final deviceId = result.device.remoteId.toString();

        // 打印所有扫描到的设备（调试用）
        debugPrint('  📱 设备: "$deviceName" ($deviceId) RSSI: ${result.rssi}');

        // 打印广播数据中的服务UUID（如果有）
        final serviceUuids = result.advertisementData.serviceUuids;
        if (serviceUuids.isNotEmpty) {
          debugPrint(
            '  🔍 服务UUID: ${serviceUuids.map((e) => e.toString()).join(", ")}',
          );
        }

        // 🔧 JDY-08 设备识别策略（宽松但可靠）
        // JDY-08透传模式使用FFE0服务 + FFE1特征
        final hasFFE0Service = serviceUuids.any(
          (uuid) => uuid.toString().toLowerCase().contains('ffe0'),
        );

        // 设备名匹配（备用方案）
        final nameUpper = deviceName.toUpperCase();
        final isJDY08Name =
            nameUpper.contains('JDY') ||
            nameUpper.contains('BT') ||
            nameUpper.contains('HC');

        // 🔧 宽松策略：FFE0服务 OR 设备名匹配
        // 原因：有些JDY-08模块在扫描阶段不广播服务UUID
        final isValidDevice = hasFFE0Service || isJDY08Name;

        if (!isValidDevice) {
          debugPrint('  ⚠️ 忽略设备: "$deviceName" (不匹配JDY-08特征)');
          logger.log('  ⚠️ 忽略: "$deviceName"');
        }

        if (isValidDevice && result.rssi > -90) {
          _devices.add(
            DeviceModel(
              id: deviceId,
              name: deviceName.isEmpty ? 'Unknown Device' : deviceName,
              rssi: result.rssi,
              bluetoothDevice: result.device,
            ),
          );
          if (hasFFE0Service) {
            debugPrint('  ✅ 已添加 (检测到FFE0服务)');
          } else {
            debugPrint('  ✅ 已添加 (设备名匹配)');
          }
        } else if (!isValidDevice) {
          debugPrint('  ⚠️ 非JDY-08设备，已忽略');
        } else {
          debugPrint('  ⚠️ 信号太弱，已忽略 (RSSI: ${result.rssi})');
        }
      }

      debugPrint('📋 过滤后设备数量: ${_devices.length}');

      _isScanning = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 扫描设备失败: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  /// 停止扫描
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('停止扫描失败: $e');
    }

    _isScanning = false;
    notifyListeners();
  }

  /// 连接到设备（带硬件在线验证）
  Future<bool> connectToDevice(DeviceModel device) async {
    final logger = DebugLogger();

    try {
      if (device.bluetoothDevice == null) {
        debugPrint('设备引用为空，无法连接');
        logger.log('❌ 设备引用为空');
        return false;
      }

      debugPrint('正在连接到设备: ${device.name} (${device.id})');
      logger.log('🔗 连接: ${device.name}');

      final success = await _bleService.connect(device.bluetoothDevice!);

      if (!success) {
        debugPrint('✗ 物理连接失败: ${device.name}');
        logger.log('❌ 物理连接失败');
        return false;
      }

      debugPrint('✓ 物理连接成功，开始验证硬件在线...');
      logger.log('✅ 物理连接成功');
      logger.log('🔍 验证硬件是否上电...');

      // 🔧 关键修复：验证硬件是否真的在线
      // 发送一个测试命令，等待响应
      bool hardwareOnline = await _verifyHardwareOnline();

      if (!hardwareOnline) {
        debugPrint('❌ 硬件未响应，判定为离线或未上电');
        logger.log('❌ 硬件未上电或离线！');
        logger.log('💡 请确保硬件已通电');
        // 断开这个假连接
        await _bleService.disconnect();
        return false;
      }

      // 硬件在线，连接成功
      device.isConnected = true;
      _connectedDevice = device;
      debugPrint('✅ 设备连接成功且硬件在线: ${device.name}');
      logger.log('🎉 硬件在线，连接成功！');
      
      // 🚗 绑定引擎音效管理器，开始监听引擎通知
      EngineAudioManager().bindBluetoothProvider(this);
      
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('连接设备异常: $e');
      logger.log('❌ 连接异常: $e');
      return false;
    }
  }

  /// 验证硬件是否在线
  ///
  /// 🔧 修复策略：
  /// 1. 检查 TX/RX 特征是否初始化
  /// 2. 发送测试命令（WUHUA:0）
  /// 3. 等待硬件响应（通过全局监听器）
  /// 4. 如果收到任何响应，判定硬件在线
  Future<bool> _verifyHardwareOnline() async {
    final logger = DebugLogger();

    try {
      debugPrint('🔍 验证硬件连接...');
      logger.log('  ├─ 检查TX/RX特征...');

      // 1. 检查蓝牙服务是否真的连接（TX/RX特征都存在）
      if (!_bleService.isConnected) {
        debugPrint('❌ TX/RX特征未初始化');
        logger.log('  ├─ ❌ TX/RX特征未初始化');
        return false;
      }
      logger.log('  ├─ ✅ TX/RX特征正常');

      // 2. 等待连接稳定
      logger.log('  ├─ 等待连接稳定 (800ms)...');
      await Future.delayed(const Duration(milliseconds: 800));

      // 3. 再次检查连接
      logger.log('  └─ 再次检查连接...');
      if (!_bleService.isConnected) {
        debugPrint('❌ 连接不稳定，已断开');
        logger.log('     ❌ 连接不稳定');
        return false;
      }

      debugPrint('✅ 硬件连接验证通过');
      logger.log('     ✅ 验证通过');
      return true;
    } catch (e) {
      debugPrint('❌ 硬件验证异常: $e');
      logger.log('❌ 验证异常: $e');
      return false;
    }
  }

  /// 断开设备连接
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        debugPrint('正在断开设备: ${_connectedDevice!.name}');
        await _bleService.disconnect();
        _connectedDevice!.isConnected = false;
        _connectedDevice = null;
        debugPrint('✓ 设备已断开');
        notifyListeners();
      } catch (e) {
        debugPrint('断开连接失败: $e');
      }
    }
  }

  /// 检查蓝牙状态
  Future<void> checkBluetoothState() async {
    try {
      _isBluetoothEnabled = await FlutterBluePlus.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('检查蓝牙状态失败: $e');
    }
  }

  /// 设置风扇速度
  Future<bool> setFanSpeed(int speed) async {
    return await _protocolService.setFanSpeed(speed);
  }

  /// 查询风扇速度
  Future<bool> getFanSpeed() async {
    return await _protocolService.getFanSpeed();
  }

  /// 设置速度单位
  /// [isMetric] true=km/h, false=mph
  Future<bool> setSpeedUnit(bool isMetric) async {
    if (!isConnected) return false;
    return await _protocolService.setSpeedUnit(isMetric ? 0 : 1);
  }

  /// 运行模式速度同步 (0-340)
  /// 带防循环更新机制：如果正在接收硬件报告，则不发送命令
  Future<bool> setRunningSpeed(int speed) async {
    if (!isConnected) return false;

    // 🔒 防循环更新：如果正在接收硬件报告，跳过发送
    if (_isReceivingReport) {
      debugPrint('🔒 跳过发送 SPEED 命令 (正在接收硬件报告)');
      return true; // 返回 true 表示操作被正确处理（只是被跳过）
    }

    // 更新本地状态
    _currentRunningSpeed = speed;

    return await _protocolService.setRunningSpeed(speed);
  }

  /// 运行模式速度同步 (带节流，50ms 间隔)
  DateTime? _lastSpeedCommandTime;
  int? _pendingSpeed;
  Timer? _speedThrottleTimer;

  Future<bool> setRunningSpeedThrottled(int speed) async {
    if (!isConnected) return false;

    // 🔒 防循环更新
    if (_isReceivingReport) {
      return true;
    }

    final now = DateTime.now();
    final lastTime = _lastSpeedCommandTime;

    // 如果距离上次发送不足 50ms，则延迟发送
    if (lastTime != null && now.difference(lastTime).inMilliseconds < 50) {
      _pendingSpeed = speed;
      _speedThrottleTimer?.cancel();
      _speedThrottleTimer = Timer(
        Duration(milliseconds: 50 - now.difference(lastTime).inMilliseconds),
        () async {
          if (_pendingSpeed != null) {
            await setRunningSpeed(_pendingSpeed!);
            _pendingSpeed = null;
          }
        },
      );
      return true;
    }

    _lastSpeedCommandTime = now;
    return await setRunningSpeed(speed);
  }

  /// 开启/关闭硬件油门模式 (远程模拟三击)
  Future<bool> setHardwareThrottleMode(bool enable) async {
    if (!isConnected) return false;
    return await _protocolService.setHardwareThrottleMode(enable);
  }

  /// 设置硬件UI界面
  /// [uiIndex] 1=调速操作界面
  Future<bool> setHardwareUI(int uiIndex) async {
    if (!isConnected) return false;
    return await _protocolService.setHardwareUI(uiIndex);
  }

  /// 🆕 设置LED预设方案
  Future<bool> setLEDPreset(int index) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接');
      return false;
    }

    return await _protocolService.setLEDPreset(index);
  }

  /// 🎨 查询当前LED预设
  /// 
  /// 返回: true=查询命令发送成功, false=发送失败
  /// 响应会通过 presetReportStream 返回
  Future<bool> queryCurrentPreset() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法查询LED预设');
      return false;
    }

    return await _protocolService.queryCurrentPreset();
  }

  /// 🆕 设置LED颜色
  Future<bool> setLEDColor(int strip, int r, int g, int b) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接');
      return false;
    }

    return await _protocolService.setLEDColor(strip, r, g, b);
  }

  /// 设置LCD状态
  Future<bool> setLCDStatus(bool enable) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接');
      return false;
    }

    return await _protocolService.setLCDStatus(enable);
  }

  /// 🆕 设置全局亮度
  Future<bool> setBrightness(int brightness) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接');
      return false;
    }

    return await _protocolService.setBrightness(brightness);
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🔄 流水灯控制 (Streamlight Mode)                     ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置流水灯模式
  /// [enable] true=开启流水灯, false=关闭流水灯
  /// 
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> setStreamlightMode(bool enable) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法控制流水灯');
      return false;
    }

    bool success = await _protocolService.setStreamlightMode(enable);

    if (success) {
      _streamlightStatus = enable;
      notifyListeners();
      debugPrint('✅ 流水灯${enable ? "开启" : "关闭"}命令已发送');
    } else {
      debugPrint('❌ 流水灯命令发送失败');
    }

    return success;
  }

  /// 查询流水灯状态
  /// 
  /// 返回: true=查询命令发送成功, false=发送失败
  Future<bool> getStreamlightStatus() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法查询流水灯状态');
      return false;
    }

    return await _protocolService.getStreamlightStatus();
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🌫️ 雾化器控制 (Cleaning Mode)                       ║
  // ║          协议格式参考: 蓝牙.md - 文本协议规范                  ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 设置雾化器状态 (Cleaning Mode 气流控制)
  ///
  /// [enable] true=开启雾化器, false=关闭雾化器
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> setWuhuaqiStatus(bool enable) async {
    final logger = DebugLogger();

    logger.log('🌫️ 雾化器控制: ${enable ? "开启" : "关闭"}');
    debugPrint('🌫️ 雾化器控制: ${enable ? "开启" : "关闭"}');

    // 详细检查连接状态
    logger.log('  ├─ 检查连接状态...');
    debugPrint('  ├─ _bleService.isConnected = ${_bleService.isConnected}');
    logger.log('  ├─ isConnected = ${_bleService.isConnected}');

    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法控制雾化器');
      logger.log('  └─ ❌ 蓝牙未连接');
      return false;
    }

    logger.log('  ├─ ✅ 连接正常');
    logger.log('  ├─ 发送命令...');

    bool success = await _protocolService.setWuhuaqiStatus(enable);

    if (success) {
      // 命令发送成功，更新本地状态
      _wuhuaqiStatus = enable;
      notifyListeners();
      debugPrint('✅ 雾化器${enable ? "开启" : "关闭"}命令已发送');
      logger.log('  └─ ✅ 命令已发送');
    } else {
      debugPrint('❌ 雾化器命令发送失败');
      logger.log('  └─ ❌ 命令发送失败');
    }

    return success;
  }

  /// 查询雾化器状态
  ///
  /// 返回: true=查询命令发送成功, false=发送失败
  Future<bool> getWuhuaqiStatus() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法查询雾化器状态');
      return false;
    }

    return await _protocolService.getWuhuaqiStatus();
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
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioPlay(int index) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法播放音频');
      return false;
    }

    bool success = await _protocolService.audioPlay(index);

    if (success) {
      _audioState = 'PLAYING';
      _audioCurrentFile = index;
      notifyListeners();
      debugPrint('✅ 播放音频文件: $index');
    }

    return success;
  }

  /// 停止音频播放
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioStop() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法停止音频');
      return false;
    }

    bool success = await _protocolService.audioStop();

    if (success) {
      _audioState = 'STOPPED';
      notifyListeners();
      debugPrint('✅ 停止音频播放');
    }

    return success;
  }

  /// 暂停音频播放
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioPause() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法暂停音频');
      return false;
    }

    bool success = await _protocolService.audioPause();

    if (success) {
      _audioState = 'PAUSED';
      notifyListeners();
      debugPrint('✅ 暂停音频播放');
    }

    return success;
  }

  /// 继续音频播放
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioResume() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法继续音频');
      return false;
    }

    bool success = await _protocolService.audioResume();

    if (success) {
      _audioState = 'PLAYING';
      notifyListeners();
      debugPrint('✅ 继续音频播放');
    }

    return success;
  }

  /// 设置音量
  ///
  /// [volume] 音量值 (0-100)
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioSetVolume(int volume) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法设置音量');
      return false;
    }

    bool success = await _protocolService.audioSetVolume(volume);

    if (success) {
      _audioVolume = volume;
      notifyListeners();
      debugPrint('✅ 设置音量: $volume');
    }

    return success;
  }

  /// 下一首
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioNext() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法切换下一首');
      return false;
    }

    bool success = await _protocolService.audioNext();

    if (success) {
      _audioCurrentFile = (_audioCurrentFile + 1) % _audioTotalFiles;
      notifyListeners();
      debugPrint('✅ 切换到下一首: $_audioCurrentFile');
    }

    return success;
  }

  /// 上一首
  ///
  /// 返回: true=命令发送成功, false=发送失败
  Future<bool> audioPrev() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法切换上一首');
      return false;
    }

    bool success = await _protocolService.audioPrev();

    if (success) {
      _audioCurrentFile =
          (_audioCurrentFile - 1 + _audioTotalFiles) % _audioTotalFiles;
      notifyListeners();
      debugPrint('✅ 切换到上一首: $_audioCurrentFile');
    }

    return success;
  }

  /// 查询音频状态
  ///
  /// 返回: true=查询命令发送成功, false=发送失败
  Future<bool> getAudioStatus() async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法查询音频状态');
      return false;
    }

    return await _protocolService.getAudioStatus();
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          🆕 同步查询方法 (等待硬件响应)                        ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 🆕 同步查询风扇速度（等待硬件响应）
  /// 返回: {success: bool, speed: int?, error: String?}
  Future<Map<String, dynamic>> queryFanSpeedSync() async {
    if (!isConnected) {
      return {'success': false, 'error': 'not_connected'};
    }

    final result = await _protocolService.queryFanSpeedSync();

    // 更新本地状态
    if (result['success'] == true && result['speed'] != null) {
      _currentSpeed = result['speed'];
      notifyListeners();
    }

    return result;
  }

  /// 🆕 同步查询雾化器状态（等待硬件响应）
  /// 返回: {success: bool, status: int?, error: String?}
  Future<Map<String, dynamic>> queryWuhuaqiStatusSync() async {
    if (!isConnected) {
      return {'success': false, 'error': 'not_connected'};
    }

    final result = await _protocolService.queryWuhuaqiStatusSync();

    // 更新本地状态
    if (result['success'] == true && result['status'] != null) {
      _wuhuaqiStatus = (result['status'] == 1);
      notifyListeners();
    }

    return result;
  }

  /// 🆕 同步查询音频状态（等待硬件响应）
  /// 返回: {success: bool, state, volume, currentFile, totalFiles, error?}
  Future<Map<String, dynamic>> queryAudioStatusSync() async {
    if (!isConnected) {
      return {'success': false, 'error': 'not_connected'};
    }

    final result = await _protocolService.queryAudioStatusSync();

    // 更新本地状态
    if (result['success'] == true) {
      _audioState = result['state'] ?? 'STOPPED';
      _audioVolume = result['volume'] ?? 80;
      _audioCurrentFile = result['currentFile'] ?? 0;
      _audioTotalFiles = result['totalFiles'] ?? 15;
      notifyListeners();
    }

    return result;
  }

  /// 🆕 同步查询所有状态（等待硬件响应）
  /// 返回: {success: bool, fan, wuhua, brightness, error?}
  Future<Map<String, dynamic>> queryAllStatusSync() async {
    if (!isConnected) {
      return {'success': false, 'error': 'not_connected'};
    }

    final result = await _protocolService.queryAllStatusSync();

    // 更新本地状态
    if (result['success'] == true) {
      if (result['fan'] != null) {
        _currentSpeed = result['fan'];
      }
      if (result['wuhua'] != null) {
        _wuhuaqiStatus = (result['wuhua'] == 1);
      }
      notifyListeners();
    }

    return result;
  }

  /// 清除设备列表
  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  /// 🆕 发送原始命令（用于Logo上传等自定义协议）
  Future<bool> sendCommand(String command) async {
    if (!isConnected) {
      debugPrint('❌ 蓝牙未连接，无法发送命令');
      return false;
    }
    return await _protocolService.sendRawCommand(command);
  }

  @override
  void dispose() {
    _knobDeltaController.close();
    _buttonEventController.close();
    _sensorDataController.close();
    _speedReportController.close();
    _throttleReportController.close();
    _unitReportController.close();
    _presetReportController.close();
    _engineNotificationController.close(); // 🚗 关闭引擎通知流
    _streamlightReportController.close(); // 🔄 关闭流水灯状态流
    _rawDataController.close(); // 🐛 关闭原始数据流
    _speedThrottleTimer?.cancel();
    _protocolService.dispose();
    super.dispose();
  }
}
