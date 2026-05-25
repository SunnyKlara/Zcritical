import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/device_model.dart';
import '../models/logo_slot_status.dart';
import '../models/speed_report.dart';
import '../services/ble_service.dart';
import '../services/firmware_compatibility.dart';
import '../services/device_capabilities.dart';
// import '../services/engine_audio_manager.dart';  // 已禁用
import '../protocol/command_sender.dart';
import '../protocol/response_router.dart';

// Re-export so existing code that imports bluetooth_provider still gets DeviceErrorMessages
export '../protocol/error_messages.dart' show DeviceErrorMessages;

/// 蓝牙提供者 — APP 与 ESP32 通信的中枢
///
/// 架构：
///   BLEService（底层BLE收发）
///     → CommandSender（命令构造+发送+重试）
///     → ResponseRouter（数据缓冲+分包+解析+流分发）
///     → BluetoothProvider（状态管理+UI接口）
///
/// 所有 Screen 通过 Provider.of<BluetoothProvider> 访问。
/// 公开 API 在重构中保持不变，Screen 文件零改动。
///
/// 参考：CONTINUATION_GUIDE.md 第三节

/// 蓝牙提供者
///
/// 管理蓝牙设备的扫描、连接、协议通信。
/// 内部使用 CommandSender 发送命令，ResponseRouter 接收和分发响应。
class BluetoothProvider with ChangeNotifier {
  final BLEService _bleService;
  late final CommandSender _cmd;
  late final ResponseRouter _router;

  /// 默认构造函数（向后兼容，内部创建依赖）
  BluetoothProvider() : _bleService = BLEService() {
    _cmd = CommandSender(_bleService);
    _router = ResponseRouter(_cmd);
    _setupListeners();
  }

  /// 依赖注入构造函数（由 service_locator 调用）
  BluetoothProvider.withDependencies({
    required BLEService bleService,
    required CommandSender commandSender,
    required ResponseRouter responseRouter,
  }) : _bleService = bleService,
       _cmd = commandSender,
       _router = responseRouter {
    _setupListeners();
  }

  bool _isScanning = false;
  bool _isBluetoothEnabled = false;
  final List<DeviceModel> _devices = [];
  DeviceModel? _connectedDevice;
  int? _currentSpeed;
  bool _wuhuaqiStatus = false;
  bool _streamlightStatus = false;

  // 运行模式
  int _currentRunningSpeed = 0;
  bool _isReceivingReport = false;
  bool _isThrottleMode = false;

  // 音量
  int _currentVolume = 0;

  // Logo 槽位
  LogoSlotStatus? _logoSlotStatus;

  // WiFi
  String? _esp32IpAddress;
  bool _isWifiProvisioning = false;

  // 固件兼容性
  FirmwareInfo? _firmwareInfo;
  CompatibilityResult? _compatibilityResult;
  DeviceCapabilities _capabilities = DeviceCapabilities.disconnected;

  // ── 转发流（从 ResponseRouter 转发到 UI 层）──
  // 这些流保持与旧版完全相同的公开接口
  final _wifiErrorCtrl = StreamController<String>.broadcast();
  final _wifiIpCtrl = StreamController<String>.broadcast();
  final _audioReadyCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _rawDataCtrl = StreamController<String>.broadcast();

  // ── Getters ──
  bool get isScanning => _isScanning;
  bool get isBluetoothEnabled => _isBluetoothEnabled;
  List<DeviceModel> get devices => _devices;
  DeviceModel? get connectedDevice => _connectedDevice;
  bool get isConnected => _bleService.isConnected;
  Stream<bool> get connectionStream => _bleService.connectionStream;
  int? get effectiveMtu => _bleService.isConnected ? _bleService.effectiveMtu : null;
  String? get lastConnectionError => _bleService.lastConnectionError;
  int? get currentSpeed => _currentSpeed;
  bool get wuhuaqiStatus => _wuhuaqiStatus;
  bool get streamlightStatus => _streamlightStatus;
  int get currentRunningSpeed => _currentRunningSpeed;
  bool get isThrottleMode => _isThrottleMode;
  int get currentVolume => _currentVolume;
  LogoSlotStatus? get logoSlotStatus => _logoSlotStatus;
  String? get esp32IpAddress => _esp32IpAddress;
  bool get isWifiProvisioning => _isWifiProvisioning;
  FirmwareInfo? get firmwareInfo => _firmwareInfo;
  CompatibilityResult? get compatibilityResult => _compatibilityResult;
  DeviceCapabilities get capabilities => _capabilities;

  // ── 事件流（直接暴露 ResponseRouter 的流）──
  Stream<int> get knobDeltaStream => _router.knobDeltaStream;
  Stream<Map<String, String>> get buttonEventStream => _router.buttonEventStream;
  Stream<Map<String, dynamic>> get sensorDataStream => _router.sensorDataStream;
  Stream<SpeedReport> get speedReportStream => _router.speedReportStream;
  Stream<bool> get throttleReportStream => _router.throttleReportStream;
  Stream<bool> get unitReportStream => _router.unitReportStream;
  Stream<int> get presetReportStream => _router.presetReportStream;
  Stream<String> get engineNotificationStream => _router.engineNotificationStream;
  Stream<bool> get streamlightReportStream => _router.streamlightReportStream;
  Stream<String> get rawDataStream => _rawDataCtrl.stream;
  Stream<int> get volumeStream => _router.volumeStream;
  Stream<String> get wifiErrorStream => _wifiErrorCtrl.stream;
  Stream<String> get wifiIpStream => _wifiIpCtrl.stream;
  Stream<Map<String, dynamic>> get audioReadyStream => _audioReadyCtrl.stream;

  // ── 数据缓冲区（原始数据调试用）──
  String _dataBuffer = '';

  // ── BLE 心跳 timer ──
  Timer? _heartbeatTimer;

  /// 设置所有流监听器（由构造函数调用）
  void _setupListeners() {
    // ── BLE 心跳 keep-alive（每 20 秒发送 PING，防止某些 Android 厂商杀后台连接）──
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (isConnected) {
        _cmd.sendRawCommand('PING\n');
      }
    });

    // 将 BLE 原始数据喂给 ResponseRouter
    _bleService.rxDataStream.listen((data) {
      // 同时维护原始数据流（调试用）
      final rawStr = String.fromCharCodes(data);
      _dataBuffer += rawStr;
      while (_dataBuffer.contains('\n')) {
        final lineEnd = _dataBuffer.indexOf('\n');
        final line = _dataBuffer.substring(0, lineEnd).trim();
        _dataBuffer = _dataBuffer.substring(lineEnd + 1);
        if (line.isNotEmpty) _rawDataCtrl.add(line);
      }
      if (_dataBuffer.length > 1024 && !_dataBuffer.contains('\n')) {
        _dataBuffer = '';
      }

      // 核心：交给 ResponseRouter 处理
      _router.handleReceivedData(data);
    });

    // ── 监听 ResponseRouter 的事件流，更新本地状态 ──

    _router.speedReportStream.listen((report) {
      _isReceivingReport = true;
      _currentRunningSpeed = report.speed;
      notifyListeners();
      Future.delayed(const Duration(milliseconds: 100), () {
        _isReceivingReport = false;
      });
    });

    _router.throttleReportStream.listen((isThrottle) {
      _isThrottleMode = isThrottle;
      notifyListeners();
    });

    _router.unitReportStream.listen((_) => notifyListeners());

    _router.presetReportStream.listen((_) => notifyListeners());

    _router.streamlightReportStream.listen((isEnabled) {
      _streamlightStatus = isEnabled;
      notifyListeners();
    });

    _router.volumeStream.listen((volume) {
      _currentVolume = volume;
      notifyListeners();
    });

    _router.logoSlotsStream.listen((logoSlots) {
      _logoSlotStatus = logoSlots;
      notifyListeners();
    });

    _router.wifiIpStream.listen((ip) {
      _esp32IpAddress = ip;
      _wifiIpCtrl.add(ip);
      notifyListeners();
    });

    _router.wifiErrorStream.listen((reason) {
      _wifiErrorCtrl.add(reason);
      notifyListeners();
    });

    _router.audioReadyStream.listen((audioReady) {
      _audioReadyCtrl.add(audioReady);
      notifyListeners();
    });

    // 解析 rawResponse 中的风扇速度和雾化器状态（向后兼容）
    _router.rawResponseStream.listen((response) {
      // FAN 速度
      final fanMatch = RegExp(r'FAN:(\d+)').firstMatch(response);
      if (fanMatch != null) {
        _currentSpeed = int.parse(fanMatch.group(1)!);
        notifyListeners();
      }
      // 雾化器状态
      final wuhuaMatch = RegExp(r'WUHUA:(\d+)').firstMatch(response);
      if (wuhuaMatch != null) {
        _wuhuaqiStatus = int.parse(wuhuaMatch.group(1)!) == 1;
        notifyListeners();
      }
    });

    // 监听物理连接状态
    _bleService.connectionStream.listen((connected) async {
      if (!connected) {
        _connectedDevice?.isConnected = false;
        _resetReceiveBuffers();
        // During WiFi provisioning, BLE disconnect is expected (ESP32 stops BLE
        // to avoid RF contention). Don't clear _connectedDevice so UI stays.
        if (!_isWifiProvisioning) {
          notifyListeners();
        } else {
          debugPrint('📶 BLE disconnected during WiFi provisioning — expected, not clearing device');
          notifyListeners();
        }
      } else if (_connectedDevice != null) {
        _resetReceiveBuffers();
        _connectedDevice!.isConnected = true;
        // If we were provisioning and BLE reconnected, clear the flag
        if (_isWifiProvisioning) {
          debugPrint('📶 BLE reconnected after WiFi provisioning');
          _isWifiProvisioning = false;
        }
        notifyListeners();
        debugPrint('🔄 检测到重连，同步硬件状态...');
        await _syncHardwareStateOnReconnect();
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  连接管理
  // ═══════════════════════════════════════════════════════════════

  Future<void> init() async {
    try {
      _isBluetoothEnabled = await FlutterBluePlus.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('初始化蓝牙失败: $e');
      _isBluetoothEnabled = false;
    }
  }

  Future<void> startScan() async {
    _isScanning = true;
    _devices.clear();
    notifyListeners();

    try {
      final results = await _bleService.scanDevices(
        timeout: const Duration(seconds: 4),
      );

      for (var result in results) {
        final deviceName = result.device.platformName;
        final deviceId = result.device.remoteId.toString();

        if (result.rssi > -90) {
          _devices.add(DeviceModel(
            id: deviceId,
            name: deviceName.isEmpty ? 'Critical Device' : deviceName,
            rssi: result.rssi,
            bluetoothDevice: result.device,
          ));
        }
      }

      _isScanning = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 扫描设备失败: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('停止扫描失败: $e');
    }
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectToDevice(DeviceModel device) async {
    try {
      if (device.bluetoothDevice == null) return false;

      final success = await _bleService.connect(device.bluetoothDevice!);
      if (!success) return false;

      bool hardwareOnline = await _verifyHardwareOnline();
      if (!hardwareOnline) {
        await _bleService.disconnect();
        return false;
      }

      device.isConnected = true;
      _connectedDevice = device;
      // EngineAudioManager().bindBluetoothProvider(this);  // 已禁用 — 音频由硬件端处理
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ 连接异常: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _bleService.disconnect();
        _connectedDevice!.isConnected = false;
        _connectedDevice = null;
        _capabilities = DeviceCapabilities.disconnected;
        _firmwareInfo = null;
        _compatibilityResult = null;
        notifyListeners();
      } catch (e) {
        debugPrint('断开连接失败: $e');
      }
    }
  }

  /// 重置 BLE 底层重连状态（用于 App 从后台恢复时清除卡住的重连计时器）
  void resetBleReconnectState() {
    _bleService.resetReconnectState();
  }

  Future<void> checkBluetoothState() async {
    try {
      _isBluetoothEnabled = await FlutterBluePlus.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('检查蓝牙状态失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  风扇控制
  // ═══════════════════════════════════════════════════════════════

  Future<bool> setFanSpeed(int speed) => _cmd.setFanSpeed(speed);
  Future<bool> getFanSpeed() => _cmd.getFanSpeed();

  Future<bool> setSpeedUnit(bool isMetric) async {
    if (!isConnected) return false;
    return _cmd.setSpeedUnit(isMetric ? 0 : 1);
  }

  Future<bool> setRunningSpeed(int speed) async {
    if (!isConnected) return false;
    if (_isReceivingReport) return true;
    _currentRunningSpeed = speed;
    return _cmd.setRunningSpeed(speed);
  }

  DateTime? _lastSpeedCommandTime;
  int? _pendingSpeed;
  Timer? _speedThrottleTimer;

  Future<bool> setRunningSpeedThrottled(int speed) async {
    if (!isConnected) return false;
    if (_isReceivingReport) return true;

    final now = DateTime.now();
    final lastTime = _lastSpeedCommandTime;

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
    return setRunningSpeed(speed);
  }

  Future<bool> setHardwareThrottleMode(bool enable) async {
    if (!isConnected) return false;
    return _cmd.setThrottleMode(enable);
  }

  Future<bool> setHardwareUI(int uiIndex) async {
    if (!isConnected) return false;
    return _cmd.setHardwareUI(uiIndex);
  }

  // ═══════════════════════════════════════════════════════════════
  //  LED 控制
  // ═══════════════════════════════════════════════════════════════

  Future<bool> setLEDPreset(int index) async {
    if (!isConnected) return false;
    return _cmd.setLEDPreset(index);
  }

  Future<bool> queryCurrentPreset() async {
    if (!isConnected) return false;
    return _cmd.queryCurrentPreset();
  }

  Future<bool> setLEDColor(int strip, int r, int g, int b) async {
    if (!isConnected) return false;
    return _cmd.setLEDColor(strip, r, g, b);
  }

  Future<bool> setLCDStatus(bool enable) async {
    if (!isConnected) return false;
    return _cmd.setLCDStatus(enable);
  }

  Future<bool> setBrightness(int brightness) async {
    if (!isConnected) return false;
    return _cmd.setBrightness(brightness);
  }

  // ═══════════════════════════════════════════════════════════════
  //  流水灯控制
  // ═══════════════════════════════════════════════════════════════

  Future<bool> setStreamlightMode(bool enable) async {
    if (!isConnected) return false;
    bool success = await _cmd.setStreamlightMode(enable);
    if (success) {
      _streamlightStatus = enable;
      notifyListeners();
    }
    return success;
  }

  Future<bool> getStreamlightStatus() async {
    if (!isConnected) return false;
    return _cmd.getStreamlightStatus();
  }

  /// 设置油门灯效模式 (1-6)
  Future<bool> setThrottleEffect(int mode) async {
    if (!isConnected) return false;
    return _cmd.setThrottleEffect(mode);
  }

  // ═══════════════════════════════════════════════════════════════
  //  音量控制
  // ═══════════════════════════════════════════════════════════════

  Future<bool> setVolume(int volume) async {
    if (!isConnected) return false;
    bool success = await _cmd.setVolume(volume);
    if (success) {
      _currentVolume = volume;
      notifyListeners();
    }
    return success;
  }

  // ═══════════════════════════════════════════════════════════════
  //  WiFi 音频投射
  // ═══════════════════════════════════════════════════════════════

  Future<bool> sendWifiCredentials(String ssid, String password) async {
    if (!isConnected) return false;
    _isWifiProvisioning = true;
    notifyListeners();
    return _cmd.sendWifiCredentials(ssid, password);
  }

  /// Clear the WiFi provisioning flag (called when provisioning completes or is cancelled)
  void clearWifiProvisioningFlag() {
    _isWifiProvisioning = false;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  //  雾化器控制
  // ═══════════════════════════════════════════════════════════════

  Future<bool> setWuhuaqiStatus(bool enable) async {
    if (!isConnected) return false;
    bool success = await _cmd.setWuhuaqiStatus(enable);
    if (success) {
      _wuhuaqiStatus = enable;
      notifyListeners();
    }
    return success;
  }

  Future<bool> getWuhuaqiStatus() async {
    if (!isConnected) return false;
    return _cmd.getWuhuaqiStatus();
  }

  // ═══════════════════════════════════════════════════════════════
  //  同步查询
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> queryFanSpeedSync() async {
    if (!isConnected) return {'success': false, 'error': 'not_connected'};
    final result = await _router.queryFanSpeedSync();
    if (result['success'] == true && result['speed'] != null) {
      _currentSpeed = result['speed'];
      notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> queryWuhuaqiStatusSync() async {
    if (!isConnected) return {'success': false, 'error': 'not_connected'};
    final result = await _router.queryWuhuaqiStatusSync();
    if (result['success'] == true && result['status'] != null) {
      _wuhuaqiStatus = (result['status'] == 1);
      notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> queryAllStatusSync() async {
    if (!isConnected) return {'success': false, 'error': 'not_connected'};
    final result = await _router.queryAllStatusSync();
    if (result['success'] == true) {
      if (result['fan'] != null) _currentSpeed = result['fan'];
      if (result['wuhua'] != null) _wuhuaqiStatus = (result['wuhua'] == 1);
      notifyListeners();
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  //  通用命令
  // ═══════════════════════════════════════════════════════════════

  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  Future<bool> sendCommand(String command) async {
    if (!isConnected) return false;
    return _cmd.sendRawCommand(command);
  }

  Future<void> writeBytes(Uint8List data) async {
    if (!isConnected) return;
    await _cmd.writeBytes(data);
  }

  /// 暴露 CommandSender 的 sendWithRetry（Logo/OTA 上传需要）
  Future<String?> sendCommandWithRetry(
    String command, {
    required String expectedPrefix,
    Duration timeout = const Duration(seconds: 3),
    int maxRetries = 2,
  }) {
    return _cmd.sendWithRetry(
      command,
      expectedPrefix: expectedPrefix,
      timeout: timeout,
      maxRetries: maxRetries,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  内部方法
  // ═══════════════════════════════════════════════════════════════

  Future<void> _syncHardwareStateOnReconnect() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!isConnected) return;

      await queryAllStatusSync();

      await Future.delayed(const Duration(milliseconds: 100));
      if (!isConnected) return;
      await _cmd.queryCurrentPreset();

      await Future.delayed(const Duration(milliseconds: 100));
      if (!isConnected) return;
      await _cmd.getLogoSlots();

      await Future.delayed(const Duration(milliseconds: 100));
      if (!isConnected) return;
      await _cmd.getVolume();

      await Future.delayed(const Duration(milliseconds: 100));
      if (!isConnected) return;
      await _cmd.getStreamlightStatus();
    } catch (e) {
      debugPrint('❌ 重连同步异常: $e');
    }
  }

  void _resetReceiveBuffers() {
    if (_dataBuffer.isNotEmpty) {
      _dataBuffer = '';
    }
    _router.reset();
  }

  Future<bool> _verifyHardwareOnline() async {
    try {
      if (!_bleService.isConnected) return false;
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_bleService.isConnected) return false;

      final result = await _router.queryAllStatusSync();

      if (result['success'] == true) {
        if (result['fan'] != null) _currentSpeed = result['fan'];
        if (result['wuhua'] != null) _wuhuaqiStatus = (result['wuhua'] == 1);

        // ── 版本协商 ──
        await Future.delayed(const Duration(milliseconds: 100));
        if (_bleService.isConnected) {
          await _negotiateFirmwareVersion();
        }

        await Future.delayed(const Duration(milliseconds: 100));
        if (!_bleService.isConnected) return true;
        await _cmd.queryCurrentPreset();

        await Future.delayed(const Duration(milliseconds: 100));
        if (!_bleService.isConnected) return true;
        await _cmd.getLogoSlots();

        await Future.delayed(const Duration(milliseconds: 100));
        if (!_bleService.isConnected) return true;
        await _cmd.getVolume();

        await Future.delayed(const Duration(milliseconds: 100));
        if (!_bleService.isConnected) return true;
        await _cmd.getStreamlightStatus();

        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ 硬件验证异常: $e');
      return false;
    }
  }

  /// 版本协商：发送 HELLO 握手，解析响应，获取 capabilities bitmap
  Future<void> _negotiateFirmwareVersion() async {
    try {
      // Phase 1: 尝试新的 HELLO 握手（返回 capabilities bitmap）
      final helloResponse = await _cmd.sendWithRetry(
        'HELLO:1.2.1:1:android',
        expectedPrefix: 'HELLO:',
        timeout: const Duration(seconds: 2),
        maxRetries: 1,
      );

      if (helloResponse != null) {
        // 新固件支持 HELLO — 解析 HELLO:fw_ver:proto_ver:hw_model:caps_hex
        final parts = helloResponse.trim().split(':');
        if (parts.length >= 5) {
          final fwVer = parts[1];
          final protoVer = int.tryParse(parts[2]) ?? 0;
          final hwModel = parts[3];
          final capsHex = parts[4];

          _firmwareInfo = FirmwareInfo(
            version: fwVer,
            protocolVersion: protoVer,
            hwModel: hwModel,
          );
          _compatibilityResult = FirmwareCompatibility.check(_firmwareInfo);
          _capabilities = DeviceCapabilities.fromHexBitmap(capsHex);
          debugPrint('🤝 HELLO 握手成功: $_firmwareInfo');
          debugPrint('🔗 设备能力: $_capabilities');
          return;
        }
      }

      // Phase 2: Fallback — 尝试旧的 GET:VERSION
      final versionResponse = await _cmd.sendWithRetry(
        'GET:VERSION',
        expectedPrefix: 'VERSION:',
        timeout: const Duration(seconds: 2),
        maxRetries: 1,
      );

      if (versionResponse != null) {
        _firmwareInfo = FirmwareInfo.parse(versionResponse);
        _compatibilityResult = FirmwareCompatibility.check(_firmwareInfo);
        _capabilities = DeviceCapabilities.fromFirmwareInfo(_firmwareInfo);
        debugPrint('🔗 GET:VERSION 协商: $_firmwareInfo → ${_compatibilityResult!.status.name}');
        debugPrint('🔗 设备能力（按协议版本推断）: $_capabilities');
      } else {
        // 旧固件不支持任何版本查询
        _firmwareInfo = null;
        _compatibilityResult = FirmwareCompatibility.check(null);
        _capabilities = DeviceCapabilities.forProtocol(null);
        debugPrint('🔗 固件不支持版本协商（旧固件），按兼容模式运行');
      }
    } catch (e) {
      debugPrint('⚠️ 版本协商异常: $e');
      _firmwareInfo = null;
      _compatibilityResult = FirmwareCompatibility.check(null);
      _capabilities = DeviceCapabilities.forProtocol(null);
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _wifiErrorCtrl.close();
    _wifiIpCtrl.close();
    _audioReadyCtrl.close();
    _rawDataCtrl.close();
    _speedThrottleTimer?.cancel();
    _router.dispose();
    super.dispose();
  }
}
