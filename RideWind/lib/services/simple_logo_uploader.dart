import 'dart:async';
import 'dart:typed_data';
import '../providers/bluetooth_provider.dart';

/// 🔥 超级简单的Logo上传器 - 无复杂逻辑，直接发送
class SimpleLogoUploader {
  final BluetoothProvider btProvider;

  Function(double)? onProgress;
  Function(String)? onStatus;
  Function(String)? onError;

  StreamSubscription? _responseSub;
  String _lastResponse = '';
  bool _responseReceived = false;

  SimpleLogoUploader(this.btProvider);

  /// 上传未压缩的Logo（更快！）
  Future<bool> uploadUncompressed({
    required Uint8List rawData,
    required int crc32,
    Function(double)? onProgress,
    Function(String)? onStatus,
    Function(String)? onError,
  }) async {
    this.onProgress = onProgress;
    this.onStatus = onStatus;
    this.onError = onError;

    try {
      print('[SIMPLE] 开始上传（未压缩模式）');
      print('[SIMPLE] 数据大小: ${rawData.length}');

      // 1. 设置响应监听
      _setupListener();

      // 2. 发送START命令（未压缩）
      _updateStatus('发送START命令...');
      await btProvider.sendCommand('LOGO_START:${rawData.length}:$crc32');

      // 3. 等待LOGO_READY
      _updateStatus('等待硬件就绪...');
      var response = await _waitForResponse(timeout: Duration(seconds: 5));

      if (response == 'LOGO_ERASING') {
        _updateStatus('Flash擦除中...');
        response = await _waitForResponse(timeout: Duration(seconds: 15));
      }

      if (response != 'LOGO_READY') {
        throw Exception('硬件未就绪: $response');
      }

      print('[SIMPLE] 硬件就绪，开始传输');

      // 4. 发送数据包
      _updateStatus('传输中...');
      final totalPackets = (rawData.length + 15) ~/ 16;

      for (int seq = 0; seq < totalPackets; seq++) {
        // 发送数据包
        final start = seq * 16;
        final end = (start + 16 > rawData.length) ? rawData.length : start + 16;
        final chunk = rawData.sublist(start, end);
        final hexString = chunk
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join('');

        await btProvider.sendCommand('LOGO_DATA:$seq:$hexString');

        // 每100包等待一次ACK（减少等待次数，提高速度）
        if ((seq + 1) % 100 == 0 || seq == totalPackets - 1) {
          print(
            '[SIMPLE] 等待ACK (seq=$seq, progress=${((seq + 1) / totalPackets * 100).toStringAsFixed(1)}%)',
          );

          final ackResponse = await _waitForResponse(
            timeout: Duration(milliseconds: 500), // 增加超时时间
          );

          if (ackResponse.startsWith('LOGO_ACK:')) {
            final ackedSeq = int.tryParse(ackResponse.substring(9)) ?? -1;
            print('[SIMPLE] 收到ACK: $ackedSeq');
          } else if (ackResponse == 'TIMEOUT') {
            print('[SIMPLE] ACK超时');
            if (seq == totalPackets - 1) {
              print('[SIMPLE] 最后一个包超时，重发');
              seq--;
              continue;
            }
          } else if (ackResponse.startsWith('LOGO_BUSY')) {
            print('[SIMPLE] 硬件忙，等待100ms');
            await Future.delayed(Duration(milliseconds: 100));
            seq--;
            continue;
          }
        }

        // 更新进度
        final progress = (seq + 1) / totalPackets;
        _updateProgress(progress);

        // 🔥 移除延迟，让蓝牙全速发送
        // await Future.delayed(Duration(milliseconds: 1));
      }

      print('[SIMPLE] 所有数据包发送完成');
      print('[SIMPLE] 总共发送了 $totalPackets 个包');

      // 等待硬件处理完最后的包
      print('[SIMPLE] 等待硬件处理完最后的包...');
      await Future.delayed(Duration(milliseconds: 500));

      // 5. 发送END命令
      print('[SIMPLE] 发送LOGO_END命令');
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      final endResponse = await _waitForResponse(
        timeout: Duration(seconds: 10),
      );

      if (!endResponse.startsWith('LOGO_OK')) {
        throw Exception('校验失败: $endResponse');
      }

      print('[SIMPLE] 上传成功！');
      _updateStatus('上传成功');
      _updateProgress(1.0);

      return true;
    } catch (e) {
      print('[SIMPLE] 上传失败: $e');
      _updateError('上传失败: $e');
      return false;
    } finally {
      _responseSub?.cancel();
    }
  }

  /// 上传压缩后的Logo
  Future<bool> uploadCompressed({
    required Uint8List compressedData,
    required int originalSize,
    required int crc32,
    Function(double)? onProgress,
    Function(String)? onStatus,
    Function(String)? onError,
  }) async {
    this.onProgress = onProgress;
    this.onStatus = onStatus;
    this.onError = onError;

    try {
      print('[SIMPLE] 开始上传');
      print('[SIMPLE] 压缩数据大小: ${compressedData.length}');
      print('[SIMPLE] 原始大小: $originalSize');

      // 1. 设置响应监听
      _setupListener();

      // 2. 发送START命令
      _updateStatus('发送START命令...');
      await btProvider.sendCommand(
        'LOGO_START_COMPRESSED:$originalSize:${compressedData.length}:$crc32',
      );

      // 3. 等待LOGO_READY
      _updateStatus('等待硬件就绪...');
      var response = await _waitForResponse(timeout: Duration(seconds: 5));

      if (response == 'LOGO_ERASING') {
        _updateStatus('Flash擦除中...');
        response = await _waitForResponse(timeout: Duration(seconds: 15));
      }

      if (response != 'LOGO_READY') {
        throw Exception('硬件未就绪: $response');
      }

      print('[SIMPLE] 硬件就绪，开始传输');

      // 4. 发送数据包
      _updateStatus('传输中...');
      final totalPackets = (compressedData.length + 15) ~/ 16;

      for (int seq = 0; seq < totalPackets; seq++) {
        // 发送数据包
        final start = seq * 16;
        final end = (start + 16 > compressedData.length)
            ? compressedData.length
            : start + 16;
        final chunk = compressedData.sublist(start, end);
        final hexString = chunk
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join('');

        await btProvider.sendCommand('LOGO_DATA:$seq:$hexString');

        // 🔥 优化：每30包等待一次ACK（进一步加速）
        if ((seq + 1) % 30 == 0 || seq == totalPackets - 1) {
          print(
            '[SIMPLE] 等待ACK (seq=$seq, progress=${((seq + 1) / totalPackets * 100).toStringAsFixed(1)}%)',
          );

          // 等待ACK，超时时间缩短
          final ackResponse = await _waitForResponse(
            timeout: Duration(milliseconds: 150), // 从200ms改为150ms
          );

          if (ackResponse.startsWith('LOGO_ACK:')) {
            final ackedSeq = int.tryParse(ackResponse.substring(9)) ?? -1;
            print('[SIMPLE] 收到ACK: $ackedSeq');
          } else if (ackResponse == 'TIMEOUT') {
            print('[SIMPLE] ACK超时');
            // 🔥 如果是最后一个包，重发
            if (seq == totalPackets - 1) {
              print('[SIMPLE] 最后一个包超时，重发');
              seq--;
              continue;
            }
          } else if (ackResponse.startsWith('LOGO_BUSY')) {
            print('[SIMPLE] 硬件忙，等待100ms');
            await Future.delayed(Duration(milliseconds: 100));
            // 重发当前包
            seq--;
            continue;
          }
        }

        // 更新进度
        final progress = (seq + 1) / totalPackets;
        _updateProgress(progress);

        // 小延迟，避免蓝牙拥塞（优化为1ms）
        await Future.delayed(Duration(milliseconds: 1));
      }

      print('[SIMPLE] 所有数据包发送完成');
      print('[SIMPLE] 总共发送了 $totalPackets 个包');

      // 等待硬件处理完最后的包
      print('[SIMPLE] 等待硬件处理完最后的包...');
      await Future.delayed(Duration(milliseconds: 500));

      // 5. 发送END命令
      print('[SIMPLE] 发送LOGO_END命令');
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      final endResponse = await _waitForResponse(
        timeout: Duration(seconds: 10),
      );

      if (!endResponse.startsWith('LOGO_OK')) {
        throw Exception('校验失败: $endResponse');
      }

      print('[SIMPLE] 上传成功！');
      _updateStatus('上传成功');
      _updateProgress(1.0);

      return true;
    } catch (e) {
      print('[SIMPLE] 上传失败: $e');
      _updateError('上传失败: $e');
      return false;
    } finally {
      _responseSub?.cancel();
    }
  }

  void _setupListener() {
    _responseSub?.cancel();
    _responseSub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();

      // 过滤回显
      if (trimmed.startsWith('LOGO_START:') ||
          trimmed.startsWith('LOGO_DATA:') ||
          trimmed == 'LOGO_END') {
        return;
      }

      // 处理响应
      if (trimmed.startsWith('LOGO_')) {
        print('[SIMPLE] 收到响应: $trimmed');
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }

  Future<String> _waitForResponse({required Duration timeout}) async {
    _responseReceived = false;
    _lastResponse = '';
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      if (_responseReceived) {
        final response = _lastResponse;
        _responseReceived = false;
        return response;
      }
      await Future.delayed(Duration(milliseconds: 10));
    }

    return 'TIMEOUT';
  }

  void _updateProgress(double progress) {
    if (onProgress != null) {
      onProgress!(progress);
    }
  }

  void _updateStatus(String status) {
    print('[SIMPLE] 状态: $status');
    if (onStatus != null) {
      onStatus!(status);
    }
  }

  void _updateError(String error) {
    print('[SIMPLE] 错误: $error');
    if (onError != null) {
      onError!(error);
    }
  }
}
