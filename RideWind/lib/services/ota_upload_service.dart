import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../providers/bluetooth_provider.dart';
import '../utils/crc32.dart';
import 'firmware_update_service.dart';

/// OTA 升级状态枚举
enum OtaState {
  idle,
  preparing, // 读取固件、计算CRC
  erasing, // 等待STM32擦除Flash
  uploading, // 分包发送中
  verifying, // 等待CRC校验
  rebooting, // 等待设备重启
  complete,
  error,
}

/// OTA 固件上传服务
///
/// 负责固件文件分包发送、升级流程管理。
/// 协议流程: 计算CRC32 → OTA_START → 等待OTA_READY → 分包OTA_DATA → OTA_END → 等待OTA_OK
class OtaUploadService {
  final BluetoothProvider _btProvider;

  // 协议参数
  static const int packetSize = 16; // 每包数据大小（字节）
  static const int windowSize = 16; // 每16包等待ACK
  static const int ackTimeoutMs = 5000; // ACK 超时（毫秒）
  static const int maxRetries = 3; // 最大重试次数
  static const int packetDelayMs = 8; // 包间延迟（毫秒）
  static const int maxFirmwareSize = 960 * 1024; // 960KB

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
  ///
  /// 使用文件选择器让用户选择 .bin 固件文件，校验文件大小后返回固件数据。
  /// 返回 null 表示用户取消选择。
  /// 抛出 Exception 当文件无效（0 字节）或过大（超过 960KB）时。
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
    if (data.length > maxFirmwareSize) throw Exception('固件文件过大，最大支持 960KB');

    return data;
  }

  /// 从远程服务器下载固件
  ///
  /// [info] 固件版本信息（包含下载地址）
  /// [onProgress] 下载进度回调 (0.0 - 1.0)
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

  /// 开始 OTA 升级
  ///
  /// [firmwareData] 固件二进制数据，大小必须 > 0 且 ≤ 960KB
  /// 返回 true 表示升级成功（设备将重启）
  Future<bool> upload(Uint8List firmwareData) async {
    if (_isUploading) {
      _log('已有上传任务进行中');
      return false;
    }

    // 校验固件大小
    if (firmwareData.isEmpty) {
      onError?.call('固件文件无效');
      return false;
    }
    if (firmwareData.length > maxFirmwareSize) {
      onError?.call('固件文件过大，最大支持 960KB');
      return false;
    }

    _isUploading = true;
    _cancelled = false;
    _setupResponseListener();
    _setupConnectionListener();

    try {
      // 1. 准备阶段：计算 CRC32
      _setState(OtaState.preparing);
      final crc32 = Crc32.calculate(firmwareData);
      _log('固件大小: ${firmwareData.length} bytes, CRC32: 0x${crc32.toRadixString(16).padLeft(8, '0')}');

      // 2. 发送 OTA_START，等待 OTA_READY
      _setState(OtaState.erasing);
      final startOk = await _sendStartAndWaitReady(firmwareData.length, crc32);
      if (!startOk) return false;

      // 3. 分包发送固件数据
      _setState(OtaState.uploading);
      final dataOk = await _sendFirmwareData(firmwareData);
      if (!dataOk) return false;

      // 4. 发送 OTA_END，等待校验结果
      _setState(OtaState.verifying);
      final endOk = await _sendEndAndWaitResult();
      if (!endOk) return false;

      // 5. 升级成功，设备将重启
      _setState(OtaState.rebooting);
      _log('设备正在重启，Bootloader 将执行固件搬运...');

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

  /// 发送 OTA_START 并等待 OTA_READY
  Future<bool> _sendStartAndWaitReady(int size, int crc32) async {
    _checkCancelled();

    final cmd = 'OTA_START:$size:$crc32';
    _log('发送: $cmd');
    await _btProvider.sendCommand(cmd);

    // 等待 OTA_ERASING 或 OTA_READY
    var response = await _waitForResponse(timeout: Duration(milliseconds: ackTimeoutMs));

    if (response == 'OTA_ERASING') {
      _log('STM32 正在擦除 Flash...');
      // 擦除可能需要较长时间（~2.4s for 16 blocks），给更多时间
      response = await _waitForResponse(timeout: Duration(seconds: 15));
    }

    if (response == 'OTA_READY') {
      _log('STM32 就绪，开始传输');
      return true;
    }

    // 处理失败响应
    if (response.startsWith('OTA_FAIL:')) {
      final reason = response.substring(9);
      throw Exception('启动失败: $reason');
    }

    if (response == 'TIMEOUT') {
      throw Exception('启动超时：未收到 OTA_READY 响应');
    }

    throw Exception('启动异常响应: $response');
  }

  /// 分包发送固件数据
  ///
  /// 基础实现：每包16字节，每16包等待ACK，包间延迟8ms。
  /// 滑动窗口和重传细节将在 Task 6.4 中完善。
  Future<bool> _sendFirmwareData(Uint8List firmwareData) async {
    final totalPackets = (firmwareData.length + packetSize - 1) ~/ packetSize;
    _log('总包数: $totalPackets');

    int retryCount = 0;
    int seq = 0;

    while (seq < totalPackets) {
      _checkCancelled();

      // 构造数据包
      final start = seq * packetSize;
      final end = (start + packetSize > firmwareData.length)
          ? firmwareData.length
          : start + packetSize;
      final chunk = firmwareData.sublist(start, end);
      final hexString =
          chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

      // 发送 OTA_DATA:seq:hexdata
      await _btProvider.sendCommand('OTA_DATA:$seq:$hexString');

      // 每 windowSize 包或最后一包时等待 ACK
      final isWindowEnd = (seq + 1) % windowSize == 0;
      final isLastPacket = seq == totalPackets - 1;

      if (isWindowEnd || isLastPacket) {
        final ackResponse = await _waitForResponse(
          timeout: Duration(milliseconds: ackTimeoutMs),
        );

        if (ackResponse.startsWith('OTA_ACK:')) {
          // ACK 收到，重置重试计数
          retryCount = 0;
        } else if (ackResponse.startsWith('OTA_RESEND:')) {
          // 需要从指定序号重传
          final resendSeq = int.tryParse(ackResponse.substring(11));
          if (resendSeq != null) {
            _log('收到重传请求，从 seq=$resendSeq 重传');
            seq = resendSeq;
            retryCount++;
            if (retryCount > maxRetries) {
              throw Exception('重传次数超过上限 ($maxRetries)');
            }
            continue;
          }
        } else if (ackResponse.startsWith('OTA_NAK:')) {
          // 单包重传请求
          final nakSeq = int.tryParse(ackResponse.substring(8));
          _log('收到 NAK: seq=$nakSeq，重传当前窗口');
          retryCount++;
          if (retryCount > maxRetries) {
            throw Exception('重传次数超过上限 ($maxRetries)');
          }
          // 从当前窗口起始重传
          final windowStart = seq - (seq % windowSize);
          seq = windowStart;
          continue;
        } else if (ackResponse == 'TIMEOUT') {
          retryCount++;
          _log('ACK 超时 (重试 $retryCount/$maxRetries)');
          if (retryCount > maxRetries) {
            throw Exception('ACK 超时，重试 $maxRetries 次后仍失败');
          }
          // 重传当前窗口
          final windowStart = seq - (seq % windowSize);
          seq = windowStart;
          continue;
        } else if (ackResponse.startsWith('OTA_FAIL:')) {
          throw Exception('传输失败: ${ackResponse.substring(9)}');
        }
      }

      // 更新进度
      final progress = (seq + 1) / totalPackets;
      onProgress?.call(progress);

      seq++;

      // 包间延迟
      if (seq < totalPackets) {
        await Future.delayed(Duration(milliseconds: packetDelayMs));
      }
    }

    _log('所有数据包发送完成');
    return true;
  }

  /// 发送 OTA_END 并等待校验结果
  Future<bool> _sendEndAndWaitResult() async {
    _checkCancelled();

    _log('发送 OTA_END');
    await _btProvider.sendCommand('OTA_END');

    // 校验可能需要一些时间（读取整个暂存区计算CRC32）
    final response = await _waitForResponse(
      timeout: Duration(seconds: 10),
    );

    if (response == 'OTA_OK') {
      _log('校验通过，设备即将重启');
      return true;
    }

    if (response.startsWith('OTA_FAIL:')) {
      final reason = response.substring(9);
      throw Exception('校验失败: $reason');
    }

    if (response == 'TIMEOUT') {
      throw Exception('等待校验结果超时');
    }

    throw Exception('校验异常响应: $response');
  }

  // ─── BLE 通信基础设施 ───

  /// 设置 BLE 响应监听器
  void _setupResponseListener() {
    _responseSub?.cancel();
    _responseSub = _btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();

      // 过滤回显（App 发出的命令被 BLE 模块回显）
      if (trimmed.startsWith('OTA_DATA:') ||
          trimmed.startsWith('OTA_START:') ||
          trimmed == 'OTA_END' ||
          trimmed == 'OTA_ABORT' ||
          trimmed == 'OTA_VERSION') {
        return;
      }

      // 处理 OTA 相关响应
      if (trimmed.startsWith('OTA_')) {
        _log('收到响应: $trimmed');
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }

  /// 设置蓝牙连接状态监听
  void _setupConnectionListener() {
    _connectionSub?.cancel();
    _connectionSub = _btProvider.connectionStream.listen((connected) {
      if (!connected && _isUploading) {
        _log('蓝牙断开连接');
        _cancelled = true;
        _setState(OtaState.error);
        onError?.call('蓝牙连接已断开');
        _isUploading = false;
        _cleanup();
      }
    });
  }

  /// 等待 BLE 响应，带超时
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
      await Future.delayed(Duration(milliseconds: 10));
    }

    return 'TIMEOUT';
  }

  // ─── 工具方法 ───

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
