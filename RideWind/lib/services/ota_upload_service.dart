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

/// OTA 固件上传服务 — Binary Mode (MTU-paced)
///
/// 协议流程（与 ESP32 ota_service.c 对齐）：
///   1. App → ESP32: OTA_BEGIN:size\n
///   2. ESP32 → App: OTA_READY:partition_size\r\n
///   3. App → ESP32: [raw binary bytes — 逐 MTU 包发送，每包间隔 20ms]
///   4. ESP32 → App: OTA_ACK:received_bytes\r\n (每 ~4KB)
///   5. App → ESP32: OTA_END\n
///   6. ESP32 → App: OTA_OK:version\r\n 或 OTA_FAIL:reason\r\n
///   7. ESP32: esp_restart() 500ms 后
///
/// 关键修复（2026-05-21）：
///   - 不再一次性 writeBytes 4KB（BLE 层瞬间拆成 ~17 个 MTU 包淹没 ESP32）
///   - 改为逐 MTU 包发送，每包间隔 20ms，给 ESP32 足够时间做 flash 写入
///   - 严格等待 OTA_ACK 后再发下一批，超时不再继续发送
class OtaUploadService {
  final BluetoothProvider _btProvider;

  // 协议参数
  static const int maxFirmwareSize = 3 * 1024 * 1024; // 3MB（OTA 分区大小）
  static const int ackInterval = 4096; // ESP32 每 ~4KB 发一次 ACK
  static const int ackTimeoutMs = 15000; // ACK 超时（flash 写入可能需要较长时间）
  static const int packetDelayMs = 20; // 每个 MTU 包之间的延迟（ms）— 防止淹没 ESP32
  static const int defaultMtu = 244; // 默认 MTU payload（247 - 3 ATT header）

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

  /// Binary mode: 逐 MTU 包发送原始固件字节（防止淹没 ESP32）
  ///
  /// 关键改动：
  /// 1. 不再一次性 writeBytes 4KB（会被 BLE 层瞬间拆成 ~17 个 MTU 包）
  /// 2. 改为 APP 自己按 MTU 大小逐包发送，每包间隔 20ms
  /// 3. 每发送 ~4KB（一个 ACK 窗口）后，严格等待 OTA_ACK 再继续
  /// 4. ACK 超时视为失败，不再盲目继续发送
  Future<bool> _sendBinaryData(Uint8List firmwareData) async {
    final totalSize = firmwareData.length;
    int sent = 0;
    int lastAckAt = 0;

    // 获取实际 MTU（从 BLE 层），如果不可用则用默认值
    final mtu = _btProvider.effectiveMtu ?? defaultMtu;
    final packetsPerAck = (ackInterval / mtu).ceil(); // ~17 packets per ACK window

    _log('开始 MTU-paced 传输: total=$totalSize, mtu=$mtu, packetsPerAck=$packetsPerAck');

    while (sent < totalSize) {
      _checkCancelled();

      // 发送一个 ACK 窗口的数据（~4KB），逐 MTU 包发送
      int windowSent = 0;
      final windowTarget = ackInterval.clamp(0, totalSize - sent);

      while (windowSent < windowTarget && sent < totalSize) {
        _checkCancelled();

        // 计算本包大小（不超过 MTU）
        final remaining = totalSize - sent;
        final packetSize = remaining > mtu ? mtu : remaining;

        // 发送单个 MTU 包（不经过 BLE 层的 _writeChunked 分包）
        final packet = firmwareData.sublist(sent, sent + packetSize);
        await _btProvider.writeBytes(packet);
        sent += packetSize;
        windowSent += packetSize;

        // 每包之间延迟 20ms — 给 ESP32 时间处理 flash 写入
        if (sent < totalSize) {
          await Future.delayed(const Duration(milliseconds: packetDelayMs));
        }
      }

      // 更新进度
      onProgress?.call(sent / totalSize);

      // 严格等待 ACK — 不超时继续
      final ackResponse = await _waitForResponse(
        timeout: Duration(milliseconds: ackTimeoutMs),
      );

      if (ackResponse.startsWith('OTA_ACK:')) {
        final acked = int.tryParse(
          ackResponse.substring(8).replaceAll('\r\n', ''),
        );
        if (acked != null) {
          lastAckAt = acked;
          // 检查 ACK 字节数是否合理
          if ((acked - sent).abs() > ackInterval * 2) {
            _log('⚠️ ACK 偏差较大: sent=$sent, acked=$acked');
          }
        }
      } else if (ackResponse.startsWith('OTA_FAIL:')) {
        final reason = ackResponse.substring(9).replaceAll('\r\n', '');
        throw Exception('传输失败: $reason');
      } else if (ackResponse == 'TIMEOUT') {
        // 严格模式：ACK 超时 = 失败，不再继续发送
        throw Exception('OTA_ACK 超时 (sent=$sent/$totalSize, lastAck=$lastAckAt)。'
            'ESP32 可能已 crash，请检查串口日志。');
      } else if (ackResponse == 'CANCELLED') {
        return false;
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

  // ═══════════════════════════════════════════════════════════════
  //  WiFi WebSocket OTA — 比 BLE 快 30-100 倍
  //
  //  协议与 BLE 完全相同（OTA_BEGIN → binary → OTA_END），
  //  但传输层从 BLE MTU 包改为 WebSocket binary frames。
  //  4KB/frame，无需 20ms 延迟，局域网 WiFi ~1MB/s。
  //  2.9MB 固件约 3-5 秒传完。
  // ═══════════════════════════════════════════════════════════════

  /// WiFi OTA chunk size — 4KB per WebSocket binary frame
  static const int wifiChunkSize = 4096;

  /// WiFi OTA: upload firmware via WebSocket (much faster than BLE)
  ///
  /// Requires ESP32 WiFi to be connected (esp32IpAddress != null).
  /// Uses ws://[ip]:81/ws — same WebSocket server as command channel.
  Future<bool> uploadViaWifi(Uint8List firmwareData) async {
    if (_isUploading) {
      _log('已有上传任务进行中');
      return false;
    }

    final ip = _btProvider.esp32IpAddress;
    if (ip == null || ip.isEmpty) {
      onError?.call('ESP32 WiFi 未连接，无法使用 WiFi OTA');
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
    WebSocket? ws;
    StreamSubscription? wsSub;

    try {
      // 1. 连接 WebSocket
      _setState(OtaState.preparing);
      _log('WiFi OTA: 连接 ws://$ip:81/ws ...');

      ws = await WebSocket.connect('ws://$ip:81/ws')
          .timeout(const Duration(seconds: 5));
      _log('WebSocket 已连接');

      // Single persistent listener — WebSocket is a single-subscription stream
      Completer<String>? pendingResponse;

      wsSub = ws.listen((data) {
        if (data is String) {
          final trimmed = data.trim();
          if (trimmed.startsWith('OTA_')) {
            _log('← $trimmed');
            if (pendingResponse != null && !pendingResponse!.isCompleted) {
              pendingResponse!.complete(trimmed);
            }
          }
        }
      }, onError: (e) {
        _log('WebSocket 错误: $e');
        if (pendingResponse != null && !pendingResponse!.isCompleted) {
          pendingResponse!.complete('WS_ERROR:$e');
        }
      }, onDone: () {
        _log('WebSocket 关闭');
        if (pendingResponse != null && !pendingResponse!.isCompleted) {
          pendingResponse!.complete('WS_CLOSED');
        }
      });

      // Helper: wait for next OTA response
      Future<String> waitWsResponse(Duration timeout) async {
        pendingResponse = Completer<String>();
        try {
          return await pendingResponse!.future.timeout(timeout);
        } on TimeoutException {
          return 'TIMEOUT';
        }
      }

      // 2. 发送 OTA_BEGIN
      _setState(OtaState.erasing);
      final beginCmd = 'OTA_BEGIN:${firmwareData.length}\n';
      _log('发送: ${beginCmd.trim()}');
      ws.add(beginCmd);

      // 等待 OTA_READY（擦除分区 3-5s）
      final readyResp = await waitWsResponse(const Duration(seconds: 15));
      if (readyResp.startsWith('OTA_READY:')) {
        _log('ESP32 就绪: $readyResp');
      } else if (readyResp.startsWith('OTA_FAIL:')) {
        throw Exception('OTA 启动失败: ${readyResp.substring(9)}');
      } else if (readyResp == 'TIMEOUT') {
        throw Exception('OTA 启动超时（15s）');
      } else {
        throw Exception('OTA 启动异常: $readyResp');
      }

      // 3. 发送固件数据 — streaming mode (no per-chunk ACK wait)
      // TCP flow control handles backpressure automatically.
      // ESP32 still sends OTA_ACK every ~4KB for progress tracking,
      // but we don't block on them — just update progress asynchronously.
      _setState(OtaState.uploading);
      final totalSize = firmwareData.length;
      int sent = 0;
      int lastAckedBytes = 0;
      final sw = Stopwatch()..start();

      _log('开始 WiFi 流式传输: total=$totalSize bytes, chunk=$wifiChunkSize');

      // Listen for ACKs asynchronously (update progress from ACK values)
      // Replace the pendingResponse mechanism with a stream-based approach
      Completer<String>? otaEndResponse;
      String? otaError;

      // Swap listener to async ACK consumer
      wsSub?.cancel();
      wsSub = ws.listen((data) {
        if (data is String) {
          final trimmed = data.trim();
          if (trimmed.startsWith('OTA_ACK:')) {
            // Parse received bytes from ACK for accurate progress
            final acked = int.tryParse(trimmed.substring(8)) ?? 0;
            if (acked > lastAckedBytes) {
              lastAckedBytes = acked;
              onProgress?.call(lastAckedBytes / totalSize);
            }
          } else if (trimmed.startsWith('OTA_OK:') || trimmed.startsWith('OTA_FAIL:')) {
            _log('← $trimmed');
            if (otaEndResponse != null && !otaEndResponse!.isCompleted) {
              otaEndResponse!.complete(trimmed);
            }
          } else if (trimmed.startsWith('OTA_')) {
            _log('← $trimmed');
          }
        }
      }, onError: (e) {
        otaError = 'WebSocket 错误: $e';
        if (otaEndResponse != null && !otaEndResponse!.isCompleted) {
          otaEndResponse!.complete('WS_ERROR:$e');
        }
      }, onDone: () {
        if (otaEndResponse != null && !otaEndResponse!.isCompleted) {
          otaEndResponse!.complete('WS_CLOSED');
        }
      });

      // Stream all chunks without waiting for ACK
      while (sent < totalSize) {
        if (_cancelled) throw Exception('升级已取消');
        if (otaError != null) throw Exception(otaError);

        final end = (sent + wifiChunkSize).clamp(0, totalSize);
        final chunk = firmwareData.sublist(sent, end);

        ws.add(chunk);
        sent += chunk.length;

        // Update send progress (ACK-based progress also updates via listener)
        onProgress?.call(sent / totalSize);

        // Yield to event loop every 64KB to allow ACK processing
        if (sent % (64 * 1024) == 0 || sent >= totalSize) {
          await Future.delayed(Duration.zero);
        }
      }

      sw.stop();
      final speed = (totalSize / 1024) / (sw.elapsedMilliseconds / 1000);
      _log('数据发送完成: ${sw.elapsedMilliseconds}ms (${speed.toStringAsFixed(1)} KB/s)');

      // 4. 发送 OTA_END — wait for final verification response
      _setState(OtaState.verifying);
      _log('发送 OTA_END');
      otaEndResponse = Completer<String>();
      ws.add('OTA_END\n');

      // Wait for OTA_OK or OTA_FAIL (ESP32 flushes buffer + validates image)
      String endResp;
      try {
        endResp = await otaEndResponse!.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        endResp = 'TIMEOUT';
      }
      if (endResp.startsWith('OTA_OK:')) {
        final version = endResp.substring(7).replaceAll('\r\n', '');
        _log('✅ WiFi OTA 成功！新固件版本: $version');
      } else if (endResp.startsWith('OTA_FAIL:')) {
        throw Exception('OTA 校验失败: ${endResp.substring(9)}');
      } else if (endResp == 'TIMEOUT') {
        throw Exception('等待 OTA 校验结果超时（15s）');
      } else {
        throw Exception('OTA 校验异常: $endResp');
      }

      // 5. 成功
      _setState(OtaState.rebooting);
      _log('ESP32 正在重启...');
      _setState(OtaState.complete);
      onSuccess?.call();
      return true;
    } catch (e) {
      _setState(OtaState.error);
      final msg = e.toString();
      _log('WiFi OTA 失败: $msg');
      onError?.call(msg);
      return false;
    } finally {
      _isUploading = false;
      wsSub?.cancel();
      try { ws?.close(); } catch (_) {}
    }
  }
}
