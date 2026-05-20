import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../providers/bluetooth_provider.dart';
import 'firmware_update_service.dart';

/// OTA 升级状态枚举
enum OtaState {
  idle,
  preparing, // 读取固件、计算大小
  erasing, // 等待 ESP32 擦除 Flash（3-5s）
  uploading, // 二进制流式传输中
  verifying, // 等待 ESP32 校验 + 设置启动分区
  rebooting, // 等待设备重启
  complete,
  error,
}

/// OTA 固件上传服务 — Binary Mode
///
/// 协议流程（与 ESP32 ota_service.c 对齐）：
///   1. App → ESP32: OTA_BEGIN:size\n
///   2. ESP32 → App: OTA_READY:partition_size\r\n
///   3. App → ESP32: [raw binary bytes — 按 MTU 分包发送]
///   4. ESP32 → App: OTA_ACK:received_bytes\r\n (每 ~4KB)
///   5. App → ESP32: OTA_END\n
///   6. ESP32 → App: OTA_OK:version\r\n 或 OTA_FAIL:reason\r\n
///   7. ESP32: esp_restart() 500ms 后
class OtaUploadService {
  final BluetoothProvider _btProvider;

  // 协议参数
  static const int maxFirmwareSize = 3 * 1024 * 1024; // 3MB（OTA 分区大小）
  static const int ackInterval = 4096; // ESP32 每 ~4KB 发一次 ACK
  static const int ackTimeoutMs = 10000; // ACK 超时（擦除阶段需要更长）
  static const int chunkDelayMs = 4; // 每个 BLE 包之间的延迟（ms）

  // 回调
  Function(String)? onLog;
  Function(double)? onProgress;
  Function(OtaState)? onStateChanged;
  Function(String)? onError;
  Function()? onSuccess;

  // 内部状态
  OtaState _state = OtaState.idle;
  bool _isUploading = false;
  bool _cancelled = false;
  StreamSubscription? _responseSub;
  StreamSubscription? _connectionSub;
  String _lastResponse = '';
  bool _responseReceived = false;

  OtaUploadService(this._btProvider);

  /// 从本地选择固件文件
  static Future<Uint8List?> pickLocalFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) return null;

    final file = File(path);
    final data = await file.readAsBytes();

    if (data.isEmpty) throw Exception('固件文件无效');
    if (data.length > maxFirmwareSize) throw Exception('固件文件过大，最大支持 3MB');

    return data;
  }

  /// 从远程服务器下载固件
  static Future<Uint8List?> downloadRemoteFirmware(
    FirmwareInfo info, {
    Function(double)? onProgress,
  }) async {
    return FirmwareUpdateService.downloadFirmware(info, onProgress: onProgress);
  }

  /// 当前状态
  OtaState get state => _state;

  /// 是否正在上传
  bool get isUploading => _isUploading;

  /// 开始 OTA 升级 — Binary Mode
  ///
  /// [firmwareData] 固件二进制数据（ridewind-esp.bin）
  Future<bool> upload(Uint8List firmwareData) async {
    if (_isUploading) {
      _log('已有上传任务进行中');
      return false;
    }

    if (firmwareData.isEmpty) {
      onError?.call('固件文件无效');
      return false;
    }
    if (firmwareData.length > maxFirmwareSize) {
      onError?.call('固件文件过大，最大支持 3MB');
      return false;
    }

    _isUploading = true;
    _cancelled = false;
    _setupResponseListener();
    _setupConnectionListener();

    try {
      // 1. 准备阶段
      _setState(OtaState.preparing);
      _log('固件大小: ${firmwareData.length} bytes (${(firmwareData.length / 1024).toStringAsFixed(1)} KB)');

      // 2. 发送 OTA_BEGIN，等待 OTA_READY
      _setState(OtaState.erasing);
      final beginOk = await _sendBeginAndWaitReady(firmwareData.length);
      if (!beginOk) return false;

      // 3. Binary mode: 直接发送原始固件字节
      _setState(OtaState.uploading);
      final dataOk = await _sendBinaryData(firmwareData);
      if (!dataOk) return false;

      // 4. 发送 OTA_END，等待校验结果
      _setState(OtaState.verifying);
      final endOk = await _sendEndAndWaitResult();
      if (!endOk) return false;

      // 5. 升级成功
      _setState(OtaState.rebooting);
      _log('ESP32 正在重启，新固件将在 Rollback 自检后生效...');

      _setState(OtaState.complete);
      onSuccess?.call();
      return true;
    } catch (e) {
      _setState(OtaState.error);
      final msg = e.toString();
      _log('上传失败: $msg');
      onError?.call(msg);
      return false;
    } finally {
      _isUploading = false;
      _cleanup();
    }
  }

  /// 取消升级
  void cancel() {
    if (!_isUploading) return;
    _cancelled = true;
    _log('用户取消升级，发送 OTA_ABORT');
    _btProvider.sendCommand('OTA_ABORT');
    _setState(OtaState.idle);
    _isUploading = false;
    _cleanup();
  }

  // ─── 内部方法 ───

  /// 发送 OTA_BEGIN:size 并等待 OTA_READY
  Future<bool> _sendBeginAndWaitReady(int size) async {
    _checkCancelled();

    // 使用 OTA_BEGIN 格式（ESP32 protocol.c 支持）
    final cmd = 'OTA_BEGIN:$size';
    _log('发送: $cmd');
    await _btProvider.sendCommand(cmd);

    // 等待 OTA_READY（擦除 3MB 分区需要 3-5 秒）
    final response = await _waitForResponse(
      timeout: const Duration(seconds: 15),
    );

    if (response.startsWith('OTA_READY:')) {
      final partSize = response.substring(10).replaceAll('\r\n', '');
      _log('ESP32 就绪，OTA 分区大小: $partSize bytes');
      return true;
    }

    if (response.startsWith('OTA_FAIL:')) {
      final reason = response.substring(9).replaceAll('\r\n', '');
      throw Exception('OTA 启动失败: $reason');
    }

    if (response == 'TIMEOUT') {
      throw Exception('OTA 启动超时：ESP32 未响应 OTA_READY（15s）');
    }

    throw Exception('OTA 启动异常响应: $response');
  }

  /// Binary mode: 直接发送原始固件字节
  ///
  /// ESP32 进入 binary mode 后，所有收到的 BLE 数据都被当作固件字节。
  /// 按 MTU 大小分包发送，ESP32 每 ~4KB 回复一个 OTA_ACK。
  Future<bool> _sendBinaryData(Uint8List firmwareData) async {
    final totalSize = firmwareData.length;
    int sent = 0;
    int lastAckAt = 0;

    _log('开始 binary mode 传输，总大小: $totalSize bytes');

    // 按 ~4KB 批次发送，匹配 ESP32 ACK 间隔
    const batchSize = 4096;

    while (sent < totalSize) {
      _checkCancelled();

      // 计算本批大小
      final remaining = totalSize - sent;
      final thisChunk = remaining > batchSize ? batchSize : remaining;

      // 发送一批原始字节（BLEService 内部按 MTU 自动分包）
      final chunk = firmwareData.sublist(sent, sent + thisChunk);
      await _btProvider.writeBytes(chunk);
      sent += thisChunk;

      // 更新进度
      onProgress?.call(sent / totalSize);

      // 等待 ACK（ESP32 每 ~4KB 发一次）
      final ackResponse = await _waitForResponse(
        timeout: Duration(milliseconds: ackTimeoutMs),
      );

      if (ackResponse.startsWith('OTA_ACK:')) {
        final acked = int.tryParse(
          ackResponse.substring(8).replaceAll('\r\n', ''),
        );
        if (acked != null) {
          lastAckAt = acked;
          if ((acked - sent).abs() > batchSize * 2) {
            _log('⚠️ ACK 字节数偏差较大: sent=$sent, acked=$acked');
          }
        }
      } else if (ackResponse.startsWith('OTA_FAIL:')) {
        final reason = ackResponse.substring(9).replaceAll('\r\n', '');
        throw Exception('传输失败: $reason');
      } else if (ackResponse == 'TIMEOUT') {
        // ACK 超时不一定失败，ESP32 可能在忙于 flash 写入
        _log('⚠️ ACK 超时 (sent=$sent/$totalSize)，继续传输...');
        lastAckAt = sent;
      } else if (ackResponse == 'CANCELLED') {
        return false;
      }

      // 批次间短暂延迟
      if (sent < totalSize) {
        await Future.delayed(const Duration(milliseconds: chunkDelayMs));
      }
    }

    _log('所有数据发送完成: $sent bytes (lastAck=$lastAckAt)');
    return true;
  }

  /// 发送 OTA_END 并等待校验结果
  Future<bool> _sendEndAndWaitResult() async {
    _checkCancelled();

    _log('发送 OTA_END');
    await _btProvider.sendCommand('OTA_END');

    // 等待校验（ESP32 flush buffer + validate image + set boot partition）
    final response = await _waitForResponse(
      timeout: const Duration(seconds: 15),
    );

    if (response.startsWith('OTA_OK:')) {
      final version = response.substring(7).replaceAll('\r\n', '');
      _log('✅ OTA 成功！新固件版本: $version');
      return true;
    }

    if (response.startsWith('OTA_FAIL:')) {
      final reason = response.substring(9).replaceAll('\r\n', '');
      throw Exception('OTA 校验失败: $reason');
    }

    if (response == 'TIMEOUT') {
      throw Exception('等待 OTA 校验结果超时（15s）');
    }

    throw Exception('OTA 校验异常响应: $response');
  }

  // ─── BLE 通信基础设施 ───

  void _setupResponseListener() {
    _responseSub?.cancel();
    _responseSub = _btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();

      // 只处理 OTA 相关响应
      if (trimmed.startsWith('OTA_READY:') ||
          trimmed.startsWith('OTA_ACK:') ||
          trimmed.startsWith('OTA_OK:') ||
          trimmed.startsWith('OTA_FAIL:') ||
          trimmed.startsWith('OTA_VERSION:')) {
        _log('← $trimmed');
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }

  void _setupConnectionListener() {
    _connectionSub?.cancel();
    _connectionSub = _btProvider.connectionStream.listen((connected) {
      if (!connected && _isUploading) {
        _log('蓝牙断开连接，中止 OTA');
        _cancelled = true;
        _setState(OtaState.error);
        onError?.call('蓝牙连接已断开。ESP32 Rollback 机制会自动恢复上一个有效固件。');
        _isUploading = false;
        _cleanup();
      }
    });
  }

  Future<String> _waitForResponse({required Duration timeout}) async {
    _responseReceived = false;
    _lastResponse = '';
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) return 'CANCELLED';
      if (_responseReceived) {
        final response = _lastResponse;
        _responseReceived = false;
        return response;
      }
      await Future.delayed(const Duration(milliseconds: 10));
    }

    return 'TIMEOUT';
  }

  void _setState(OtaState newState) {
    _state = newState;
    _log('状态: ${newState.name}');
    onStateChanged?.call(newState);
  }

  void _log(String message) {
    final msg = '[OTA] $message';
    print(msg);
    onLog?.call(msg);
  }

  void _checkCancelled() {
    if (_cancelled) throw Exception('升级已取消');
  }

  void _cleanup() {
    _responseSub?.cancel();
    _responseSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
  }
}
