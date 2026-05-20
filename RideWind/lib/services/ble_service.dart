/// BLE 底层连接管理 — 扫描/连接/MTU/服务发现/收发队列
///
/// 封装 flutter_blue_plus，提供设备类型检测(ESP32/F4)、
/// 自动重连、发送队列(20ms间隔防拥塞)、数据流分发。

import 'dart:async';
import 'dart:collection';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 设备类型枚举
enum DeviceType { esp32, f4, unknown }

/// BLE 连接状态机
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  discoveringServices,
  connected,
  reconnecting,
}

/// 发送任务
class _SendTask {
  final List<int> data;
  final Completer<void> completer;
  _SendTask(this.data, this.completer);
}

/// BLE 底层服务
///
/// 职责：扫描、连接、收发数据。
/// 扫描按 Service UUID 0xFFE0 过滤，不依赖设备名。
/// 连接后协商 MTU、请求高优先级连接参数。
/// 断线自动重连（指数退避，最多 5 次）。
/// 发送队列化，防止并发写入冲突。
class BLEService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic; // FFE1: write-without-response + notify

  StreamSubscription? _connectionSub;
  StreamSubscription? _notifySub;

  final _rxController = StreamController<List<int>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _stateController = StreamController<BleConnectionState>.broadcast();

  // ── 发送队列 ──
  final Queue<_SendTask> _sendQueue = Queue<_SendTask>();
  bool _draining = false;

  // ── MTU ──
  int _effectiveMtu = 20; // 默认保守值，连接后动态更新

  // ── 自动重连 ──
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  bool _userDisconnected = false;

  // ── UUID ──
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String charUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  BleConnectionState _state = BleConnectionState.disconnected;

  // ── 设备类型 ──
  DeviceType _deviceType = DeviceType.unknown;

  // ── 公开接口 ──
  Stream<List<int>> get rxDataStream => _rxController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<BleConnectionState> get stateStream => _stateController.stream;
  BleConnectionState get state => _state;
  DeviceType get deviceType => _deviceType;
  int get effectiveMtu => _effectiveMtu;

  bool get isConnected =>
      _device != null &&
      _characteristic != null &&
      _state == BleConnectionState.connected;

  void _setState(BleConnectionState s) {
    _state = s;
    _stateController.add(s);
  }

  // ═══════════════════════════════════════════════════════════════
  //  扫描 — 按 Service UUID 0xFFE0 过滤
  // ═══════════════════════════════════════════════════════════════

  Future<List<ScanResult>> scanDevices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (await FlutterBluePlus.isSupported == false) {
      print('❌ 设备不支持蓝牙');
      return [];
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      print('❌ 蓝牙未开启');
      return [];
    }

    await FlutterBluePlus.stopScan();
    _setState(BleConnectionState.scanning);

    print('🔍 扫描 BLE 设备 (${timeout.inSeconds}s)...');

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );

    await FlutterBluePlus.isScanning
        .where((v) => v == false)
        .first
        .timeout(timeout + const Duration(seconds: 2), onTimeout: () => false);

    await FlutterBluePlus.stopScan();

    // 过滤：广播中包含 FFE0 服务 UUID，或设备名包含已知关键字
    final allResults = FlutterBluePlus.lastScanResults;
    final results = allResults.where((r) {
      // 方式1：广播数据中包含 FFE0 服务 UUID
      final hasFFE0 = r.advertisementData.serviceUuids.any(
        (uuid) => uuid.toString().toLowerCase().contains('ffe0'),
      );
      if (hasFFE0) return true;

      // 方式2：设备名匹配（ESP32 广播名 "T1"，或旧版 JDY/BT/HC）
      final name = r.device.platformName.toUpperCase();
      if (name == 'T1') return true;
      if (name.contains('JDY') || name.contains('BT05') || name.contains('HC')) return true;

      return false;
    }).toList();

    print('✅ 扫描完成，全部 ${allResults.length} 个，匹配 ${results.length} 个');

    if (_state == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  //  连接
  // ═══════════════════════════════════════════════════════════════

  /// 用户主动连接（重置重连计数）
  Future<bool> connect(BluetoothDevice device) async {
    _userDisconnected = false;
    _reconnectAttempt = 0;
    _cancelReconnect();
    return _connectInternal(device);
  }

  /// 内部连接流程（首次连接 + 自动重连共用）
  Future<bool> _connectInternal(BluetoothDevice device) async {
    try {
      _cleanupConnection();
      _device = device;

      // 1. 物理连接
      _setState(BleConnectionState.connecting);
      print('🔗 [1/4] 连接 ${device.platformName}...');

      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      print('✅ [1/4] 物理连接成功');

      // 1.5. 根据设备名判断设备类型
      final deviceName = device.platformName.toUpperCase();
      if (deviceName.contains('T1')) {
        _deviceType = DeviceType.esp32;
      } else if (deviceName.contains('JDY') ||
          deviceName.contains('BT05') ||
          deviceName.contains('HC')) {
        _deviceType = DeviceType.f4;
      } else {
        _deviceType = DeviceType.unknown;
      }
      print('📱 设备类型: $_deviceType (名称: ${device.platformName})');

      // 2. 监听连接状态
      _connectionSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          print('⚡ 连接断开');
          _onDisconnected();
        }
      });

      // 3. MTU 协商 + 连接参数优化
      print('📐 [2/4] 协商 MTU...');
      try {
        final mtu = await device.requestMtu(247);
        _effectiveMtu = mtu - 3; // ATT header 占 3 字节
        if (_effectiveMtu < 20) _effectiveMtu = 20;
        print('✅ [2/4] MTU=$mtu, 有效载荷=${_effectiveMtu}B');
      } catch (e) {
        _effectiveMtu = 20;
        print('⚠️ [2/4] MTU 协商失败，使用默认 20B: $e');
      }

      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        print('✅ 连接参数已设为 high priority (11.25ms interval)');
      } catch (e) {
        print('⚠️ 连接参数设置失败（不影响功能）: $e');
      }

      // 4. 发现服务，查找 FFE1 特征
      _setState(BleConnectionState.discoveringServices);
      print('🔍 [3/4] 发现服务...');

      final services = await device.discoverServices();
      print('✅ [3/4] 发现 ${services.length} 个服务');

      for (var service in services) {
        if (!service.uuid.toString().toLowerCase().contains('ffe0')) continue;

        for (var char in service.characteristics) {
          if (!char.uuid.toString().toLowerCase().contains('ffe1')) continue;

          _characteristic = char;

          // 订阅 notify
          if (char.properties.notify) {
            await char.setNotifyValue(true);
            _notifySub = char.lastValueStream.listen((data) {
              if (data.isNotEmpty) {
                _rxController.add(data);
              }
            });
            print('✅ [4/4] FFE1 特征就绪 (write + notify)');
          }
          break;
        }
        if (_characteristic != null) break;
      }

      if (_characteristic == null) {
        print('❌ 未找到 FFE1 特征');
        _cleanupConnection();
        _setState(BleConnectionState.disconnected);
        return false;
      }

      _setState(BleConnectionState.connected);
      _connectionController.add(true);
      _reconnectAttempt = 0;
      print('🎉 连接完成！MTU=${_effectiveMtu + 3}');
      return true;
    } catch (e) {
      print('❌ 连接异常: $e');
      _cleanupConnection();
      _setState(BleConnectionState.disconnected);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  断线处理 + 自动重连
  // ═══════════════════════════════════════════════════════════════

  void _onDisconnected() {
    final wasDevice = _device;
    _cleanupConnection();
    _deviceType = DeviceType.unknown;
    _connectionController.add(false);
    _setState(BleConnectionState.disconnected);

    // 队列中未完成的任务全部报错
    while (_sendQueue.isNotEmpty) {
      _sendQueue.removeFirst().completer.completeError(
        Exception('BLE disconnected'),
      );
    }
    _draining = false;

    if (!_userDisconnected && wasDevice != null) {
      _device = wasDevice; // 保留设备引用用于重连
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      print('🔴 重连次数耗尽 ($_maxReconnectAttempts 次)');
      _device = null;
      return;
    }

    final delay = Duration(seconds: 1 << _reconnectAttempt);
    _reconnectAttempt++;
    print('🔄 ${delay.inSeconds}s 后第 $_reconnectAttempt 次重连...');

    _setState(BleConnectionState.reconnecting);

    _reconnectTimer = Timer(delay, () async {
      if (_device == null || _userDisconnected) return;

      final ok = await _connectInternal(_device!);
      if (!ok && !_userDisconnected) {
        _scheduleReconnect();
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════
  //  发送 — Completer 队列，零 busy-wait
  // ═══════════════════════════════════════════════════════════════

  /// 发送数据（自动排队，自动分包）
  Future<void> sendData(List<int> data) async {
    if (_characteristic == null) {
      print('❌ 发送失败：特征未初始化');
      return;
    }

    final completer = Completer<void>();
    _sendQueue.add(_SendTask(data, completer));
    if (!_draining) _drainQueue();
    return completer.future;
  }

  Future<void> _drainQueue() async {
    _draining = true;
    while (_sendQueue.isNotEmpty) {
      final task = _sendQueue.removeFirst();
      try {
        await _writeChunked(task.data);
        task.completer.complete();
      } catch (e) {
        task.completer.completeError(e);
      }
    }
    _draining = false;
  }

  Future<void> _writeChunked(List<int> data) async {
    final chunkSize = _effectiveMtu;

    if (data.length <= chunkSize) {
      await _characteristic!.write(data, withoutResponse: true);
    } else {
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        await _characteristic!.write(data.sublist(i, end), withoutResponse: true);
        // ESP32 BLE 协议栈有内部流控，最小间隔防极端情况
        if (i + chunkSize < data.length) {
          await Future.delayed(const Duration(milliseconds: 2));
        }
      }
    }
  }

  /// 发送字符串
  Future<void> sendString(String text) async {
    await sendData(text.codeUnits);
  }

  // ═══════════════════════════════════════════════════════════════
  //  断开 + 清理
  // ═══════════════════════════════════════════════════════════════

  /// 用户主动断开
  Future<void> disconnect() async {
    _userDisconnected = true;
    _cancelReconnect();
    try {
      await _device?.disconnect();
    } catch (e) {
      print('断开连接错误: $e');
    }
    _cleanupConnection();
    _device = null;
    _deviceType = DeviceType.unknown;
    _connectionController.add(false);
    _setState(BleConnectionState.disconnected);
  }

  /// 清理连接资源（不清空 _device，重连需要）
  void _cleanupConnection() {
    _connectionSub?.cancel();
    _connectionSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _characteristic = null;
  }

  /// 释放所有资源
  void dispose() {
    _userDisconnected = true;
    _cancelReconnect();
    _cleanupConnection();
    _device = null;
    _rxController.close();
    _connectionController.close();
    _stateController.close();
  }
}
