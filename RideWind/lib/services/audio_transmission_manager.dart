/// 音频上传传输管理器 — 滑动窗口协议实现（Logo/PCM 二进制上传）
///
/// 管理 BLE 大文件传输：分包、ACK 确认、CRC32 校验、超时重传。
/// 支持 Logo 图片和自定义引擎音效的上传。

import 'dart:async';
import 'dart:typed_data';
import '../providers/bluetooth_provider.dart';
import '../utils/crc32.dart';

/// 音频上传传输状态
enum AudioTransmissionState {
  idle,
  starting,
  transmitting,
  verifying,
  completed,
  error,
}

/// 音频层定义
enum AudioLayer {
  idle(0, 'Idle', '怠速 (800 RPM)'),
  low(1, 'Low', '低转速 (2000 RPM)'),
  mid(2, 'Mid', '中转速 (4000 RPM)'),
  high(3, 'High', '高转速 (7000 RPM)');

  final int layerIndex;
  final String name;
  final String description;
  const AudioLayer(this.layerIndex, this.name, this.description);
}

/// 音频传输管理器 — 基于 Logo 二进制传输协议
///
/// 协议流程:
///   APP → AUDIO_START_BIN:layer:size:crc32\n
///   ESP → AUDIO_READY:layer\r\n
///   APP → [raw binary PCM data in BLE packets]
///   ESP → AUDIO_ACK_BIN:received_bytes\r\n (every ~4KB)
///   APP → AUDIO_END\n
///   ESP → AUDIO_OK:layer\r\n or AUDIO_FAIL:reason\r\n
class AudioTransmissionManager {
  final BluetoothProvider btProvider;
  final Uint8List pcmData;
  final AudioLayer layer;

  AudioTransmissionState state = AudioTransmissionState.idle;
  double progress = 0.0;
  String statusMessage = '';

  Function(double)? onProgress;
  Function(AudioTransmissionState)? onStateChange;
  Function(String)? onStatusChange;
  Function()? onComplete;
  Function(String)? onError;

  String _lastResponse = '';
  bool _responseReceived = false;
  StreamSubscription<String>? _responseSub;
  bool _cancelled = false;
  DateTime? _startTime;

  AudioTransmissionManager({
    required this.btProvider,
    required this.pcmData,
    required this.layer,
    this.onProgress,
    this.onStateChange,
    this.onStatusChange,
    this.onComplete,
    this.onError,
  });

  void _setupResponseListener() {
    _responseSub?.cancel();
    _responseSub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();

      // 过滤回显
      if (trimmed.startsWith('AUDIO_START') ||
          trimmed.startsWith('AUDIO_DATA:') ||
          trimmed == 'AUDIO_END' ||
          trimmed == 'AUDIO_DELETE' ||
          trimmed == 'GET:AUDIO') {
        return;
      }

      // 只处理硬件的真实响应
      if (trimmed.startsWith('AUDIO_')) {
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }

  Future<String> _waitForResponse({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    _responseReceived = false;
    _lastResponse = '';
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (_responseReceived) {
        final response = _lastResponse;
        _responseReceived = false;
        return response;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return 'TIMEOUT';
  }

  void _setState(AudioTransmissionState newState) {
    state = newState;
    onStateChange?.call(newState);
  }

  void _updateStatus(String msg) {
    statusMessage = msg;
    onStatusChange?.call(msg);
  }

  /// 上传 PCM 音频数据到指定层
  Future<bool> transmit() async {
    _setupResponseListener();
    _startTime = DateTime.now();
    _cancelled = false;
    _setState(AudioTransmissionState.starting);

    try {
      final crc32 = Crc32.calculate(pcmData);
      final startCmd =
          'AUDIO_START_BIN:${layer.layerIndex}:${pcmData.length}:$crc32';
      await btProvider.sendCommand(startCmd);

      final response = await _waitForResponse(
        timeout: const Duration(seconds: 5),
      );

      if (response.startsWith('AUDIO_ERROR:')) {
        throw Exception('硬件错误: ${response.substring(12)}');
      }

      if (!response.startsWith('AUDIO_READY:')) {
        throw Exception('硬件未就绪: $response');
      }

      // ═══════════════════════════════════════════════════════
      // 分段二进制传输 + ACK 校验 + 断点重传
      // ═══════════════════════════════════════════════════════
      _setState(AudioTransmissionState.transmitting);
      _updateStatus('传输中 (${layer.description})...');

      const int mtuPayload = 244;
      final int totalBytes = pcmData.length;
      const int segmentPackets = 16;
      final int segmentBytes = segmentPackets * mtuPayload;
      int confirmed = 0;
      int segmentRetries = 0;
      const int maxSegmentRetries = 3;

      while (confirmed < totalBytes) {
        if (_cancelled) {
          throw Exception('用户取消上传');
        }

        final int segmentEnd = (confirmed + segmentBytes > totalBytes)
            ? totalBytes
            : confirmed + segmentBytes;
        int sent = confirmed;

        // 发送本段的所有 BLE 包
        while (sent < segmentEnd) {
          final int chunkEnd = (sent + mtuPayload > segmentEnd)
              ? segmentEnd
              : sent + mtuPayload;
          final chunk = pcmData.sublist(sent, chunkEnd);
          await btProvider.writeBytes(Uint8List.fromList(chunk));
          sent += chunk.length;

          if ((sent - confirmed) ~/ mtuPayload % 4 == 0) {
            await Future.delayed(const Duration(milliseconds: 2));
          }
        }

        await Future.delayed(const Duration(milliseconds: 20));

        final ackResponse = await _waitForResponse(
          timeout: const Duration(seconds: 3),
        );

        if (ackResponse != 'TIMEOUT' &&
            ackResponse.startsWith('AUDIO_ACK_BIN:')) {
          final receivedBytes =
              int.tryParse(ackResponse.substring(14));
          if (receivedBytes != null) {
            if (receivedBytes >= segmentEnd) {
              confirmed = receivedBytes;
              segmentRetries = 0;
              progress = confirmed / totalBytes;
              onProgress?.call(progress);
            } else if (receivedBytes > confirmed) {
              confirmed = receivedBytes;
              segmentRetries++;
              if (segmentRetries > maxSegmentRetries) {
                throw Exception(
                    '段重传失败: ESP32 只收到 $confirmed/$segmentEnd 字节');
              }
              progress = confirmed / totalBytes;
              onProgress?.call(progress);
            } else {
              segmentRetries++;
              if (segmentRetries > maxSegmentRetries) {
                throw Exception(
                    '段重传失败: ESP32 停在 $receivedBytes 字节');
              }
              await Future.delayed(const Duration(milliseconds: 50));
            }
          }
        } else {
          segmentRetries++;
          if (segmentRetries > maxSegmentRetries) {
            throw Exception('ACK 超时 $maxSegmentRetries 次，传输中止');
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // ═══════════════════════════════════════════════════════
      // 校验阶段
      // ═══════════════════════════════════════════════════════
      _setState(AudioTransmissionState.verifying);
      _updateStatus('校验中...');
      await btProvider.sendCommand('AUDIO_END');

      final endResponse = await _waitForResponse(
        timeout: const Duration(seconds: 10),
      );

      if (endResponse.startsWith('AUDIO_OK')) {
        // 成功
      } else if (endResponse.startsWith('AUDIO_FAIL:')) {
        throw Exception('校验失败: ${endResponse.substring(11)}');
      } else {
        throw Exception('校验失败: $endResponse');
      }

      _setState(AudioTransmissionState.completed);
      progress = 1.0;
      onProgress?.call(1.0);

      final elapsed = DateTime.now().difference(_startTime!);
      final speed =
          (totalBytes / elapsed.inMilliseconds * 1000 / 1024)
              .toStringAsFixed(1);
      _updateStatus(
          '${layer.name} 上传成功 (${elapsed.inSeconds}s, $speed KB/s)');
      onComplete?.call();
      return true;
    } catch (e) {
      _setState(AudioTransmissionState.error);
      _updateStatus('上传失败: $e');
      onError?.call(e.toString());
      return false;
    } finally {
      _responseSub?.cancel();
    }
  }

  /// 取消上传
  void cancel() {
    _cancelled = true;
    _setState(AudioTransmissionState.error);
    _responseSub?.cancel();
    try {
      btProvider.sendCommand('AUDIO_END');
    } catch (_) {}
    onError?.call('用户取消上传');
  }

  /// 查询自定义音频状态
  ///
  /// 返回 Map: {0: bool, 1: bool, 2: bool, 3: bool, 'custom': bool}
  static Future<Map<String, dynamic>?> queryAudioStatus(
      BluetoothProvider btProvider) async {
    if (!btProvider.isConnected) return null;

    final completer = Completer<String>();

    final sub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      if (trimmed.startsWith('AUDIO_STATUS:') && !completer.isCompleted) {
        completer.complete(trimmed);
      }
    });

    await btProvider.sendCommand('GET:AUDIO');

    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 3),
      );
      // AUDIO_STATUS:idle:low:mid:high:custom
      final parts = response.split(':');
      if (parts.length >= 6) {
        return {
          '0': parts[1] == '1',
          '1': parts[2] == '1',
          '2': parts[3] == '1',
          '3': parts[4] == '1',
          'custom': parts[5] == '1',
        };
      }
    } on TimeoutException {
      // 超时
    } finally {
      sub.cancel();
    }
    return null;
  }

  /// 删除所有自定义音频
  static Future<bool> deleteAllAudio(BluetoothProvider btProvider) async {
    if (!btProvider.isConnected) return false;

    final completer = Completer<String>();

    final sub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      if (trimmed.contains('AUDIO_DELETE') && !completer.isCompleted) {
        completer.complete(trimmed);
      }
    });

    await btProvider.sendCommand('AUDIO_DELETE');

    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 3),
      );
      return response.contains('OK');
    } on TimeoutException {
      return false;
    } finally {
      sub.cancel();
    }
  }
}
