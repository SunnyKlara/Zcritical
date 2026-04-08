import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/debug_logger.dart';

class BLEService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;

  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;

  final StreamController<List<int>> _rxDataController =
      StreamController<List<int>>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  // ✅ Bug修复：发送锁，防止并发发送导致蓝牙指令混乱
  bool _isSending = false;

  Stream<List<int>> get rxDataStream => _rxDataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  // 🔧 关键修复：只有设备连接且TX/RX特征都初始化后才算真正连接成功
  // 否则发送命令时 _txCharacteristic 为 null 会导致发送失败
  bool get isConnected =>
      _device != null && _txCharacteristic != null && _rxCharacteristic != null;

  // JDY-08常见UUID (透传模式)
  static const String serviceUuid = "0000FFE0-0000-1000-8000-00805F9B34FB";
  static const String charUuid = "0000FFE1-0000-1000-8000-00805F9B34FB";

  /// 扫描BLE设备
  Future<List<ScanResult>> scanDevices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    List<ScanResult> results = [];

    try {
      // 1. 检查蓝牙是否可用
      if (await FlutterBluePlus.isSupported == false) {
        print("❌ 蓝牙不支持");
        return results;
      }

      // 2. 检查蓝牙状态（不自动请求开启，权限应在引导页处理）
      final adapterState = await FlutterBluePlus.adapterState.first;
      print('📡 蓝牙状态: $adapterState');

      if (adapterState != BluetoothAdapterState.on) {
        print("❌ 蓝牙未开启");
        return results;
      }

      // 3. 先停止之前的扫描（如果有）
      await FlutterBluePlus.stopScan();

      // 4. 开始扫描
      print('🔍 开始扫描 (${timeout.inSeconds}秒)...');
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      // 5. 等待扫描完成
      await FlutterBluePlus.isScanning
          .where((val) => val == false)
          .first
          .timeout(
            timeout + const Duration(seconds: 2),
            onTimeout: () => false,
          );

      print('✅ 扫描完成');

      // 6. 获取扫描结果
      results = FlutterBluePlus.lastScanResults;
      print('📋 扫描到 ${results.length} 个设备');

      // 7. 确保停止扫描
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('❌ 扫描错误: $e');
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }

    return results;
  }

  /// 连接设备
  Future<bool> connect(BluetoothDevice device) async {
    final logger = DebugLogger();

    try {
      _device = device;

      final msg1 = '🔗 [1/4] 连接: ${device.platformName}';
      print(msg1);
      logger.log(msg1);

      // 连接设备
      await device.connect(timeout: const Duration(seconds: 15));

      const msg2 = '✅ [2/4] 物理连接成功';
      print(msg2);
      logger.log(msg2);

      // 监听连接状态
      _connectionSubscription = device.connectionState.listen((state) {
        _connectionController.add(state == BluetoothConnectionState.connected);
        if (state == BluetoothConnectionState.disconnected) {
          _cleanup();
        }
      });

      // 发现服务
      const msg3 = '🔍 [3/4] 发现服务...';
      print(msg3);
      logger.log(msg3);

      List<BluetoothService> services = await device.discoverServices();

      final msg4 = '✅ [3/4] 发现 ${services.length} 个服务';
      print(msg4);
      logger.log(msg4);

      // 查找特征
      for (var service in services) {
        final svcUuid = service.uuid.toString();
        print('🔍 服务 UUID: $svcUuid');
        logger.log('🔍 服务: $svcUuid');

        for (var char in service.characteristics) {
          print('  📋 特征 UUID: ${char.uuid}');
          logger.log('  📋 特征: ${char.uuid}');

          final props =
              'W=${char.properties.write ? "✓" : "✗"} '
              'WN=${char.properties.writeWithoutResponse ? "✓" : "✗"} '
              'N=${char.properties.notify ? "✓" : "✗"} '
              'R=${char.properties.read ? "✓" : "✗"}';
          print('     属性: $props');
          logger.log('     $props');

          // 🔧 检查 UUID（支持短格式和长格式）
          final charUuidStr = char.uuid.toString().toLowerCase();
          final isFFE1 = charUuidStr.contains('ffe1');
          final isFFE0Service = svcUuid.toLowerCase().contains('ffe0');

          // 🔧 严格要求：必须是 FFE0 服务下的 FFE1 特征（JDY-08标准）
          // 同一个特征既可写又可通知（透传模式）
          if (isFFE0Service && isFFE1) {
            // FFE1 用于发送（写入）
            if (char.properties.writeWithoutResponse || char.properties.write) {
              _txCharacteristic = char;
              print('  ✅ 设置为TX特征（FFE1 写入）');
              logger.log('  ✅ TX特征 (FFE1)');
            }

            // FFE1 也用于接收（通知）
            if (char.properties.notify) {
              _rxCharacteristic = char;
              print('  ✅ 设置为RX特征（FFE1 通知）');
              logger.log('  ✅ RX特征 (FFE1)');

              // 订阅通知
              await char.setNotifyValue(true);
              print('  📡 已订阅FFE1通知');
              logger.log('  📡 已订阅通知');

              // 监听数据
              _dataSubscription = char.lastValueStream.listen((data) {
                if (data.isNotEmpty) {
                  print('📥 收到数据: $data (${String.fromCharCodes(data)})');
                  logger.log('📥 收到: ${String.fromCharCodes(data)}');
                  _rxDataController.add(data);
                }
              });
            }
          }
          // 🚫 移除备用方案！不再接受非JDY-08设备！
        }
      }

      print(
        'TX特征: ${_txCharacteristic?.uuid}, RX特征: ${_rxCharacteristic?.uuid}',
      );

      bool success = _txCharacteristic != null && _rxCharacteristic != null;

      if (success) {
        const msg5 = '🎉 [4/4] 连接成功！';
        print(msg5);
        logger.log(msg5);
      } else {
        const msg5 = '❌ [4/4] 未找到FFE1特征';
        print(msg5);
        logger.log(msg5);
        logger.log('   TX: ${_txCharacteristic != null ? "✓" : "✗"}');
        logger.log('   RX: ${_rxCharacteristic != null ? "✓" : "✗"}');
        _cleanup();
      }

      return success;
    } catch (e) {
      final msgErr = '❌ 连接异常: $e';
      print(msgErr);
      logger.log(msgErr);
      _cleanup();
      return false;
    }
  }

  /// 发送数据
  Future<void> sendData(List<int> data) async {
    final logger = DebugLogger();

    // ✅ Bug修复：增加发送锁，防止并发发送导致蓝牙指令混乱
    // JDY-08 透传模式下，快速连续发送会导致数据粘包或丢失
    // 🔧 修复：使用循环等待而不是直接丢弃
    int waitCount = 0;
    const maxWait = 50;  // 最多等待500ms
    while (_isSending && waitCount < maxWait) {
      await Future.delayed(const Duration(milliseconds: 10));
      waitCount++;
    }
    
    if (_isSending) {
      print('⚠️ [BLEService] 发送队列超时，强制发送');
      // 不再丢弃，继续发送
    }

    _isSending = true;

    print('📤 [BLEService] sendData 被调用');
    logger.log('📤 [BLE] sendData 调用');

    if (_txCharacteristic == null) {
      print('❌ [BLEService] 发送特征未初始化');
      logger.log('❌ [BLE] TX特征为null');
      _isSending = false;
      return;
    }

    print('✅ [BLEService] TX特征正常: ${_txCharacteristic!.uuid}');
    logger.log('✅ [BLE] TX特征: ${_txCharacteristic!.uuid}');

    try {
      print('📤 [BLEService] 准备发送 ${data.length} 字节: $data');
      print('📤 [BLEService] 字符串形式: ${String.fromCharCodes(data)}');
      logger.log('📤 [BLE] 发送: ${String.fromCharCodes(data).trim()}');

      // JDY-08透传模式，使用withoutResponse=true
      if (data.length <= 20) {
        print('📤 [BLEService] 调用 write...');
        await _txCharacteristic!.write(data, withoutResponse: true);
        print('✅ [BLEService] write 返回成功');
        logger.log('✅ [BLE] 发送成功');
      } else {
        // 分包发送
        print('📦 [BLEService] 数据过长，分包发送');
        logger.log('📦 [BLE] 分包发送');
        for (int i = 0; i < data.length; i += 20) {
          int end = (i + 20 < data.length) ? i + 20 : data.length;
          List<int> chunk = data.sublist(i, end);
          await _txCharacteristic!.write(chunk, withoutResponse: true);
          print('📤 [BLEService] 发送包 ${i ~/ 20 + 1}: $chunk');
          await Future.delayed(
            const Duration(milliseconds: 10), // 🔥 从80ms减少到10ms，提速8倍！
          );
        }
        print('✅ 所有包发送完成');
      }

      // ✅ Bug修复：发送后增加最小间隔，防止指令粘包
      // 🔥 从5ms减少到0ms，Logo上传不需要防粘包
      // await Future.delayed(const Duration(milliseconds: 5));
    } catch (e) {
      print('❌ 发送失败: $e');
    } finally {
      _isSending = false;
    }
  }

  /// 发送字符串
  Future<void> sendString(String text) async {
    await sendData(text.codeUnits);
  }

  /// 断开连接
  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (e) {
      print('断开连接错误: $e');
    }
    _cleanup();
  }

  /// 清理资源
  void _cleanup() {
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _device = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
  }

  /// 释放资源
  void dispose() {
    _cleanup();
    _rxDataController.close();
    _connectionController.close();
  }
}
