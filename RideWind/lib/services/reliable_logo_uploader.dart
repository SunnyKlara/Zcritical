import 'dart:async';
import 'dart:typed_data';
import '../providers/bluetooth_provider.dart';

/// 可靠的Logo上传器
/// 
/// 核心特性：
/// 1. 滑动窗口协议 - 批量发送，批量确认
/// 2. 丢包重传 - 检测丢失的包并重传
/// 3. 流量控制 - 根据ACK调整发送速度
/// 4. CRC校验 - 端到端数据完整性验证
class ReliableLogoUploader {
  final BluetoothProvider _btProvider;
  
  // 协议参数
  static const int PACKET_SIZE = 16;        // 每包数据大小
  static const int WINDOW_SIZE = 50;        // 滑动窗口大小（一次发送50包）
  static const int ACK_TIMEOUT_MS = 3000;   // ACK超时时间
  static const int MAX_RETRIES = 3;         // 最大重试次数
  static const int PACKET_DELAY_MS = 8;     // 包间延迟（毫秒）
  
  // 状态
  bool _isUploading = false;
  String _lastResponse = '';
  bool _responseReceived = false;
  StreamSubscription<String>? _responseSub;
  
  // 回调
  Function(String)? onLog;
  Function(double)? onProgress;
  Function(String)? onError;
  Function()? onSuccess;
  
  ReliableLogoUploader(this._btProvider);
  
  /// 开始上传
  Future<bool> upload(Uint8List imageData, int crc32) async {
    if (_isUploading) {
      _log('⚠️ 上传正在进行中');
      return false;
    }
    
    _isUploading = true;
    _setupResponseListener();
    
    try {
      // 1. 发送START命令，等待READY
      _log('=== 开始可靠上传 ===');
      _log('数据大小: ${imageData.length} bytes');
      _log('CRC32: 0x${crc32.toRadixString(16).padLeft(8, '0')}');
      
      final startOk = await _sendStartAndWaitReady(imageData.length, crc32);
      if (!startOk) {
        _log('❌ 硬件未就绪');
        return false;
      }
      
      // 2. 使用滑动窗口发送数据
      final dataOk = await _sendDataWithSlidingWindow(imageData);
      if (!dataOk) {
        _log('❌ 数据传输失败');
        return false;
      }
      
      // 3. 发送END命令，等待验证结果
      final endOk = await _sendEndAndWaitResult();
      if (!endOk) {
        _log('❌ 验证失败');
        return false;
      }
      
      _log('🎉 上传成功！');
      onSuccess?.call();
      return true;
      
    } catch (e) {
      _log('❌ 上传异常: $e');
      onError?.call(e.toString());
      return false;
    } finally {
      _isUploading = false;
      _responseSub?.cancel();
    }
  }
  
  /// 发送START命令并等待READY
  Future<bool> _sendStartAndWaitReady(int size, int crc32) async {
    final command = 'LOGO_START:$size:$crc32';
    _log('📤 发送: $command');
    
    await _btProvider.sendCommand(command);
    
    // 等待ERASING或READY
    var response = await _waitForResponse(
      timeout: const Duration(seconds: 10),
      expectedPrefixes: ['LOGO_ERASING', 'LOGO_READY', 'LOGO_ERROR'],
    );
    
    if (response.contains('LOGO_ERASING')) {
      _log('⏳ Flash擦除中...');
      response = await _waitForResponse(
        timeout: const Duration(seconds: 20),
        expectedPrefixes: ['LOGO_READY', 'LOGO_ERROR'],
      );
    }
    
    if (response.contains('LOGO_READY')) {
      _log('✅ 硬件就绪');
      return true;
    } else if (response.contains('LOGO_ERROR')) {
      _log('❌ 硬件错误: $response');
      onError?.call(response);
      return false;
    }
    
    _log('❌ 等待READY超时');
    return false;
  }
  
  /// 使用滑动窗口发送数据
  Future<bool> _sendDataWithSlidingWindow(Uint8List data) async {
    final totalPackets = (data.length + PACKET_SIZE - 1) ~/ PACKET_SIZE;
    _log('--- 滑动窗口传输 ---');
    _log('总包数: $totalPackets, 窗口大小: $WINDOW_SIZE');
    
    int baseSeq = 0;  // 窗口基准序号
    int retryCount = 0;
    
    while (baseSeq < totalPackets) {
      // 计算本次窗口范围
      final windowEnd = (baseSeq + WINDOW_SIZE < totalPackets) 
          ? baseSeq + WINDOW_SIZE 
          : totalPackets;
      
      _log('📤 发送窗口 [$baseSeq - ${windowEnd - 1}]');
      
      // 发送窗口内的所有包
      for (int seq = baseSeq; seq < windowEnd; seq++) {
        final start = seq * PACKET_SIZE;
        final end = (start + PACKET_SIZE > data.length) 
            ? data.length 
            : start + PACKET_SIZE;
        final chunk = data.sublist(start, end);
        
        // 转换为十六进制
        final hexData = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
        final command = 'LOGO_DATA:$seq:$hexData';
        
        await _btProvider.sendCommand(command);
        
        // 包间延迟
        await Future.delayed(Duration(milliseconds: PACKET_DELAY_MS));
      }
      
      // 等待ACK
      _log('⏳ 等待ACK...');
      final response = await _waitForResponse(
        timeout: Duration(milliseconds: ACK_TIMEOUT_MS),
        expectedPrefixes: ['LOGO_ACK', 'LOGO_NAK', 'LOGO_ERROR'],
      );
      
      if (response.contains('LOGO_ACK:')) {
        // 解析ACK序号
        final ackSeq = _parseAckSeq(response);
        if (ackSeq != null && ackSeq >= windowEnd - 1) {
          // 窗口内所有包都确认了
          _log('✅ ACK:$ackSeq 窗口确认');
          baseSeq = windowEnd;
          retryCount = 0;
          
          // 更新进度
          final progress = baseSeq / totalPackets;
          onProgress?.call(progress);
          _log('📊 进度: ${(progress * 100).toStringAsFixed(1)}%');
        } else if (ackSeq != null) {
          // 部分确认，从ackSeq+1开始重传
          _log('⚠️ 部分确认 ACK:$ackSeq，需要重传 ${ackSeq + 1} - ${windowEnd - 1}');
          baseSeq = ackSeq + 1;
        }
      } else if (response.contains('LOGO_NAK:')) {
        // 需要重传
        final nakSeq = _parseNakSeq(response);
        _log('⚠️ NAK:$nakSeq 需要重传');
        if (nakSeq != null) {
          baseSeq = nakSeq;
        }
        retryCount++;
      } else if (response.contains('LOGO_ERROR')) {
        _log('❌ 传输错误: $response');
        onError?.call(response);
        return false;
      } else {
        // 超时，重试
        _log('⚠️ ACK超时，重试窗口');
        retryCount++;
      }
      
      // 检查重试次数
      if (retryCount >= MAX_RETRIES) {
        _log('❌ 重试次数超限');
        onError?.call('MAX_RETRIES_EXCEEDED');
        return false;
      }
    }
    
    _log('✅ 所有数据发送完成');
    return true;
  }
  
  /// 发送END命令并等待结果
  Future<bool> _sendEndAndWaitResult() async {
    _log('📤 发送: LOGO_END');
    await _btProvider.sendCommand('LOGO_END');
    
    _log('⏳ 等待CRC验证...');
    final response = await _waitForResponse(
      timeout: const Duration(seconds: 30),
      expectedPrefixes: ['LOGO_OK', 'LOGO_FAIL', 'LOGO_ERROR'],
    );
    
    if (response.contains('LOGO_OK')) {
      _log('✅ CRC验证通过，写入成功');
      return true;
    } else if (response.contains('LOGO_FAIL')) {
      _log('❌ 验证失败: $response');
      onError?.call(response);
      return false;
    }
    
    _log('❌ 等待结果超时');
    return false;
  }
  
  /// 设置响应监听
  void _setupResponseListener() {
    _responseSub?.cancel();
    _responseSub = _btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      
      // 过滤回显
      if (trimmed.startsWith('LOGO_START:') ||
          trimmed.startsWith('LOGO_DATA:') ||
          trimmed.contains('f800f800') ||  // 过滤数据回显
          trimmed == 'LOGO_END') {
        return;
      }
      
      // 记录协议响应
      if (trimmed.startsWith('LOGO_') && !trimmed.startsWith('LOGO_DAT')) {
        _log('📥 响应: $trimmed');
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }
  
  /// 等待响应
  Future<String> _waitForResponse({
    required Duration timeout,
    required List<String> expectedPrefixes,
  }) async {
    _responseReceived = false;
    _lastResponse = '';
    final deadline = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(deadline)) {
      if (_responseReceived) {
        final response = _lastResponse;
        _responseReceived = false;
        
        // 检查是否匹配期望的前缀
        if (expectedPrefixes.any((p) => response.contains(p))) {
          return response;
        }
        // 不匹配，继续等待
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return 'TIMEOUT';
  }
  
  /// 解析ACK序号
  int? _parseAckSeq(String response) {
    final match = RegExp(r'LOGO_ACK:(\d+)').firstMatch(response);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
  
  /// 解析NAK序号
  int? _parseNakSeq(String response) {
    final match = RegExp(r'LOGO_NAK:(\d+)').firstMatch(response);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
  
  /// 日志输出
  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final logMessage = '[$timestamp] $message';
    print('ReliableUploader: $logMessage');
    onLog?.call(logMessage);
  }
  
  /// 取消上传
  void cancel() {
    _isUploading = false;
    _responseSub?.cancel();
    _log('⚠️ 上传已取消');
  }
}
