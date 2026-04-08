import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/bluetooth_provider.dart';

// ════════════════════════════════════════════════════════════
// 传输状态枚举
// ════════════════════════════════════════════════════════════
enum TransmissionState {
  idle,
  preparing,
  starting,
  transmitting,
  paused,
  retrying,
  verifying,
  completed,
  error,
}

// ════════════════════════════════════════════════════════════
// ACK类型枚举
// ════════════════════════════════════════════════════════════
enum AckType { cumulative, selective, nak }

// ════════════════════════════════════════════════════════════
// 错误类型枚举
// ════════════════════════════════════════════════════════════
enum TransmissionError {
  bluetoothDisconnected,
  connectionTimeout,
  invalidResponse,
  protocolMismatch,
  packetLost,
  checksumMismatch,
  timeoutExceeded,
  flashEraseFailed,
  flashWriteFailed,
  bufferOverflow,
  userCancelled,
  unknownError,
}

// ════════════════════════════════════════════════════════════
// 包信息类
// ════════════════════════════════════════════════════════════
class PacketInfo {
  final int seq;
  final Uint8List data;
  DateTime sendTime;
  int retryCount;
  bool acked;

  PacketInfo({
    required this.seq,
    required this.data,
    required this.sendTime,
    this.retryCount = 0,
    this.acked = false,
  });

  Duration get age => DateTime.now().difference(sendTime);
  bool isTimeout(int timeoutMs) => age.inMilliseconds > timeoutMs;
}

// ════════════════════════════════════════════════════════════
// ACK信息类
// ════════════════════════════════════════════════════════════
class AckInfo {
  final AckType type;
  final int seq;
  final String? bitmap;
  final DateTime receiveTime;

  AckInfo({
    required this.type,
    required this.seq,
    this.bitmap,
    DateTime? receiveTime,
  }) : receiveTime = receiveTime ?? DateTime.now();

  List<int> getLostPackets() {
    if (type != AckType.selective || bitmap == null) return [];

    final lost = <int>[];
    for (int i = 0; i < bitmap!.length; i++) {
      if (bitmap![i] == '0') {
        lost.add(seq + i + 1);
      }
    }
    return lost;
  }
}

// ════════════════════════════════════════════════════════════
// 传输统计类
// ════════════════════════════════════════════════════════════
class TransmissionStats {
  final int totalPackets;
  final int sentPackets;
  final int retransmittedPackets;
  final int lostPackets;
  final Duration totalTime;
  final double averageRTT;
  final double lossRate;
  final double throughput;

  TransmissionStats({
    required this.totalPackets,
    required this.sentPackets,
    required this.retransmittedPackets,
    required this.lostPackets,
    required this.totalTime,
    required this.averageRTT,
    required this.lossRate,
    required this.throughput,
  });

  @override
  String toString() {
    return '''
传输统计:
- 总包数: $totalPackets
- 发送包数: $sentPackets
- 重传包数: $retransmittedPackets
- 丢失包数: $lostPackets
- 总耗时: ${totalTime.inSeconds}秒
- 平均RTT: ${averageRTT.toStringAsFixed(1)}ms
- 丢包率: ${(lossRate * 100).toStringAsFixed(2)}%
- 吞吐量: ${(throughput / 1024).toStringAsFixed(2)} KB/s
''';
  }
}

// ════════════════════════════════════════════════════════════
// 传输异常类
// ════════════════════════════════════════════════════════════
class TransmissionException implements Exception {
  final TransmissionError error;
  final String message;
  final dynamic details;
  final bool recoverable;

  TransmissionException({
    required this.error,
    required this.message,
    this.details,
    this.recoverable = false,
  });

  @override
  String toString() => 'TransmissionException: $message';
}

// ════════════════════════════════════════════════════════════
// 滑动窗口类
// ════════════════════════════════════════════════════════════
class SlidingWindow {
  int windowSize;
  int sendBase;
  int nextSeqNum;
  final int totalPackets;

  final Map<int, PacketInfo> inFlightPackets = {};
  final Set<int> ackedPackets = {};
  final Set<int> lostPackets = {};

  SlidingWindow({
    required this.windowSize,
    required this.totalPackets,
    this.sendBase = 0,
    this.nextSeqNum = 0,
  });

  bool get isFull => (nextSeqNum - sendBase) >= windowSize;
  bool get isEmpty => sendBase == nextSeqNum;
  int get inFlightCount => nextSeqNum - sendBase;

  void slideWindow(int ackedSeq) {
    for (int seq = sendBase; seq <= ackedSeq; seq++) {
      ackedPackets.add(seq);
      inFlightPackets.remove(seq);
      lostPackets.remove(seq);
    }
    sendBase = ackedSeq + 1;

    // 🔧 修复：确保nextSeqNum不会回退到sendBase之前
    // 这防止了重新发送已确认的包
    if (nextSeqNum < sendBase) {
      print('[WINDOW] ⚠️ nextSeqNum回退修正: $nextSeqNum→$sendBase');
      nextSeqNum = sendBase;
    }
  }

  void markLost(int seq) {
    lostPackets.add(seq);
  }

  void markAcked(int seq) {
    ackedPackets.add(seq);
    inFlightPackets.remove(seq);
    lostPackets.remove(seq);
  }
}

// ════════════════════════════════════════════════════════════
// RTT估算器
// ════════════════════════════════════════════════════════════
class RTTEstimator {
  double estimatedRTT = 200.0; // 🔥 从500ms降到200ms
  double devRTT = 50.0; // 🔥 从100ms降到50ms

  final double alpha = 0.125;
  final double beta = 0.25;

  void updateRTT(Duration measuredRTT) {
    final sampleRTT = measuredRTT.inMilliseconds.toDouble();
    estimatedRTT = (1 - alpha) * estimatedRTT + alpha * sampleRTT;
    devRTT = (1 - beta) * devRTT + beta * (sampleRTT - estimatedRTT).abs();
  }

  int getTimeout() {
    final timeout = (estimatedRTT + 4 * devRTT).toInt();
    return timeout.clamp(100, 1000); // 🔥 从300-3000ms改为100-1000ms
  }
}

// ════════════════════════════════════════════════════════════
// 丢包率监控
// ════════════════════════════════════════════════════════════
class PacketLossMonitor {
  int sentPackets = 0;
  int lostPackets = 0;
  int retransmittedPackets = 0;

  double get lossRate {
    if (sentPackets == 0) return 0.0;
    return lostPackets / sentPackets;
  }

  void recordSent() {
    sentPackets++;
  }

  void recordLost() {
    lostPackets++;
  }

  void recordRetransmit() {
    retransmittedPackets++;
  }

  void resetIfNeeded() {
    if (sentPackets >= 100) {
      sentPackets = 0;
      lostPackets = 0;
      retransmittedPackets = 0;
    }
  }
}

// ════════════════════════════════════════════════════════════
// 自适应速率控制器
// ════════════════════════════════════════════════════════════
class AdaptiveRateController {
  int sendInterval = 5; // 🔥 从20ms降到5ms

  final int minInterval = 2; // 🔥 从10ms降到2ms
  final int normalInterval = 10; // 🔥 从30ms降到10ms
  final int maxInterval = 30; // 🔥 从80ms降到30ms

  void adjustRate(double lossRate) {
    if (lossRate < 0.05) {
      sendInterval = max(minInterval, sendInterval - 5);
    } else if (lossRate > 0.15) {
      sendInterval = min(maxInterval, sendInterval + 10);
    } else {
      if (sendInterval > normalInterval) {
        sendInterval--;
      } else if (sendInterval < normalInterval) {
        sendInterval++;
      }
    }
  }

  Future<void> waitBeforeSend() async {
    await Future.delayed(Duration(milliseconds: sendInterval));
  }
}

// ════════════════════════════════════════════════════════════
// 窗口大小控制器
// ════════════════════════════════════════════════════════════
class WindowSizeController {
  int windowSize = 40; // 🔥 从20增加到40 - 更激进

  final int minWindow = 20; // 🔥 从10增加到20
  final int maxWindow = 60; // 🔥 从30增加到60

  int consecutiveSuccess = 0;
  int consecutiveFailure = 0;

  void onSuccess() {
    consecutiveSuccess++;
    consecutiveFailure = 0;

    if (consecutiveSuccess >= 10 && windowSize < maxWindow) {
      windowSize++;
      consecutiveSuccess = 0;
    }
  }

  void onFailure() {
    consecutiveFailure++;
    consecutiveSuccess = 0;

    if (consecutiveFailure >= 3 && windowSize > minWindow) {
      windowSize = max(minWindow, windowSize - 2);
      consecutiveFailure = 0;
    }
  }
}

// ════════════════════════════════════════════════════════════
// 传输进度类
// ════════════════════════════════════════════════════════════
class TransmissionProgress {
  int totalPackets;
  int lastAckedSeq;
  Set<int> receivedPackets;
  DateTime lastUpdateTime;

  TransmissionProgress({
    required this.totalPackets,
    required this.lastAckedSeq,
    required this.receivedPackets,
    required this.lastUpdateTime,
  });

  Future<void> save(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'logo_progress_$deviceId';

    final receivedList = receivedPackets.toList();
    final receivedStr = receivedList.join('|');

    await prefs.setString(
      key,
      '$totalPackets,$lastAckedSeq,$receivedStr,${lastUpdateTime.millisecondsSinceEpoch}',
    );
  }

  static Future<TransmissionProgress?> load(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'logo_progress_$deviceId';
    final dataStr = prefs.getString(key);

    if (dataStr == null) return null;

    try {
      final parts = dataStr.split(',');
      if (parts.length < 4) return null;

      final totalPackets = int.parse(parts[0]);
      final lastAckedSeq = int.parse(parts[1]);
      final receivedPackets = parts[2].isEmpty
          ? <int>{}
          : parts[2].split('|').map(int.parse).toSet();
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        int.parse(parts[3]),
      );

      // 超过1小时的进度失效
      if (DateTime.now().difference(timestamp).inHours > 1) {
        await prefs.remove(key);
        return null;
      }

      return TransmissionProgress(
        totalPackets: totalPackets,
        lastAckedSeq: lastAckedSeq,
        receivedPackets: receivedPackets,
        lastUpdateTime: timestamp,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> clear(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logo_progress_$deviceId');
  }
}

// ════════════════════════════════════════════════════════════
// 传输日志器
// ════════════════════════════════════════════════════════════
class TransmissionLogger {
  int _logCounter = 0;
  final int _logInterval = 50;

  void logPacket(int seq, String action, int totalPackets) {
    _logCounter++;
    if (_logCounter % _logInterval == 0) {
      print(
        '[$action] seq=$seq, progress=${(seq * 100 / totalPackets).toStringAsFixed(1)}%',
      );
    }
  }

  void logImportant(String message) {
    print('[IMPORTANT] $message');
  }
}

// ════════════════════════════════════════════════════════════
// ACK批处理器
// ════════════════════════════════════════════════════════════
class AckBatcher {
  final List<AckInfo> _pendingAcks = [];
  Timer? _batchTimer;
  final Duration batchDelay;
  final Function(List<AckInfo>) onBatchReady;

  AckBatcher({
    this.batchDelay = const Duration(milliseconds: 50),
    required this.onBatchReady,
  });

  void addAck(AckInfo ack) {
    _pendingAcks.add(ack);

    // 取消之前的定时器
    _batchTimer?.cancel();

    // 设置新的定时器
    _batchTimer = Timer(batchDelay, _processBatch);
  }

  void _processBatch() {
    if (_pendingAcks.isEmpty) return;

    // 合并累积ACK - 只保留最大的
    final cumulativeAcks = _pendingAcks
        .where((ack) => ack.type == AckType.cumulative)
        .toList();
    final maxCumulativeAck = cumulativeAcks.isEmpty
        ? null
        : cumulativeAcks.reduce((a, b) => a.seq > b.seq ? a : b);

    // 收集所有SACK
    final selectiveAcks = _pendingAcks
        .where((ack) => ack.type == AckType.selective)
        .toList();

    // 收集所有NAK
    final naks = _pendingAcks.where((ack) => ack.type == AckType.nak).toList();

    // 构建批处理结果
    final batch = <AckInfo>[];
    if (maxCumulativeAck != null) batch.add(maxCumulativeAck);
    batch.addAll(selectiveAcks);
    batch.addAll(naks);

    // 清空待处理队列
    _pendingAcks.clear();

    // 回调处理
    if (batch.isNotEmpty) {
      onBatchReady(batch);
    }
  }

  void flush() {
    _batchTimer?.cancel();
    _processBatch();
  }

  void dispose() {
    _batchTimer?.cancel();
    _pendingAcks.clear();
  }
}

// ════════════════════════════════════════════════════════════
// Logo传输管理器 - 主类
// ════════════════════════════════════════════════════════════
class LogoTransmissionManager {
  final BluetoothProvider btProvider;
  Uint8List imageData;
  final int totalPackets;
  final int chunkSize = 16;

  late SlidingWindow window;
  late AdaptiveRateController rateController;
  late WindowSizeController windowController;
  late RTTEstimator rttEstimator;
  late PacketLossMonitor lossMonitor;
  late TransmissionLogger logger;

  TransmissionState state = TransmissionState.idle;
  double progress = 0.0;
  String statusMessage = '';

  int totalSent = 0;
  int totalRetransmitted = 0;
  DateTime? startTime;

  Function(double)? onProgress;
  Function(String)? onStatusChange;
  Function(TransmissionStats)? onComplete;
  Function(String)? onError;

  String _lastResponse = '';
  bool _responseReceived = false;
  StreamSubscription<String>? _responseSub;

  int lastAckSeq = -1;
  int duplicateAckCount = 0;

  LogoTransmissionManager({
    required this.btProvider,
    required this.imageData,
    this.onProgress,
    this.onStatusChange,
    this.onComplete,
    this.onError,
  }) : totalPackets = (imageData.length / 16).ceil() {
    window = SlidingWindow(
      windowSize: 40, // 🔥 从20改为40 - 更大的窗口
      totalPackets: totalPackets,
    );
    rateController = AdaptiveRateController();
    windowController = WindowSizeController();
    rttEstimator = RTTEstimator();
    lossMonitor = PacketLossMonitor();
    logger = TransmissionLogger();

    _setupResponseListener();
  }

  void _setupResponseListener() {
    // 先取消之前的监听器
    _responseSub?.cancel();

    _responseSub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();

      // 🔥 过滤回显：忽略APP发送的命令
      if (trimmed.startsWith('LOGO_START:') ||
          trimmed.startsWith('LOGO_DATA:') ||
          trimmed == 'LOGO_END' ||
          trimmed == 'LOGO_DELETE' ||
          trimmed == 'GET:LOGO') {
        // 这是回显，忽略
        return;
      }

      // 只处理硬件的真实响应
      if (trimmed.startsWith('LOGO_')) {
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

  Future<void> transmit() async {
    startTime = DateTime.now();
    state = TransmissionState.starting;

    try {
      // 发送LOGO_START
      final crc32 = _calculateCRC32(imageData);
      await btProvider.sendCommand('LOGO_START:${imageData.length}:$crc32');

      var response = await _waitForResponse(
        timeout: const Duration(seconds: 10),
      );

      if (response.contains('LOGO_ERASING')) {
        _updateStatus('Flash擦除中...');
        response = await _waitForResponse(timeout: const Duration(seconds: 15));
      }

      if (!response.contains('LOGO_READY')) {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件未就绪: $response',
        );
      }

      state = TransmissionState.transmitting;
      await _transmitWithSlidingWindow();

      state = TransmissionState.verifying;
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');
      response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (!response.startsWith('LOGO_OK')) {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $response',
        );
      }

      state = TransmissionState.completed;
      final stats = _getStats();
      logger.logImportant('传输完成！\n$stats');
      onComplete?.call(stats);
    } catch (e) {
      state = TransmissionState.error;
      final errorMsg = e.toString();
      logger.logImportant('传输失败: $errorMsg');
      onError?.call(errorMsg);
      rethrow;
    } finally {
      _responseSub?.cancel();
    }
  }

  Future<void> _transmitWithSlidingWindow() async {
    // 🔥 激进策略：快速发送，批量等待ACK
    int lastAckWaitSeq = -1;

    print('[SLIDING_WINDOW] 开始传输');
    print(
      '[SLIDING_WINDOW] totalPackets=${window.totalPackets}, sendBase=${window.sendBase}',
    );
    print('[SLIDING_WINDOW] imageData.length=${imageData.length}');

    while (window.sendBase < window.totalPackets) {
      // 🔧 修复：双重保护，确保nextSeqNum不会小于sendBase
      if (window.nextSeqNum < window.sendBase) {
        logger.logImportant(
          '⚠️ 检测到nextSeqNum异常: ${window.nextSeqNum} < ${window.sendBase}，已修正',
        );
        window.nextSeqNum = window.sendBase;
      }

      // 🚀 策略1：快速填满窗口（不等待）
      while (!window.isFull && window.nextSeqNum < window.totalPackets) {
        print('[SLIDING_WINDOW] 发送包 seq=${window.nextSeqNum}');
        await _sendPacket(window.nextSeqNum);
        window.nextSeqNum++;
        // 🔥 极小延迟，让蓝牙有时间发送
        await Future.delayed(const Duration(milliseconds: 2));
      }

      // � 策略2：每发送10包才等待一次ACK（与硬件ACK频率匹配）
      final shouldWaitForAck =
          (window.nextSeqNum - lastAckWaitSeq) >= 10 ||
          window.nextSeqNum >= window.totalPackets;

      if (shouldWaitForAck) {
        // 等待ACK
        final response = await _waitForResponse(
          timeout: Duration(milliseconds: rttEstimator.getTimeout()),
        );

        if (response != 'TIMEOUT') {
          _handleAckResponse(response);
          lastAckWaitSeq = window.nextSeqNum;
        } else {
          await _handleTimeout();
        }

        // 重传丢失的包
        await _retransmitLostPackets();

        // 更新进度
        _updateProgress();

        // 调整速率和窗口大小
        lossMonitor.resetIfNeeded();
        rateController.adjustRate(lossMonitor.lossRate);
        window.windowSize = windowController.windowSize;
      }
    }
  }

  Future<void> _sendPacket(int seq) async {
    final start = seq * chunkSize;
    final end = min(start + chunkSize, imageData.length);
    final chunk = imageData.sublist(start, end);
    final hexString = chunk
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');

    await btProvider.sendCommand('LOGO_DATA:$seq:$hexString');

    window.inFlightPackets[seq] = PacketInfo(
      seq: seq,
      data: chunk,
      sendTime: DateTime.now(),
    );

    totalSent++;
    lossMonitor.recordSent();
    logger.logPacket(seq, 'SEND', totalPackets);
  }

  void _handleAckResponse(String response) {
    if (response.startsWith('LOGO_ACK:')) {
      final ackedSeq = int.tryParse(response.substring(9)) ?? -1;
      _handleCumulativeAck(ackedSeq);
    } else if (response.startsWith('LOGO_SACK:')) {
      final parts = response.substring(10).split(':');
      if (parts.length == 2) {
        final baseSeq = int.tryParse(parts[0]) ?? -1;
        final bitmap = parts[1];
        _handleSelectiveAck(baseSeq, bitmap);
      }
    } else if (response.startsWith('LOGO_NAK:')) {
      final nakSeq = int.tryParse(response.substring(9)) ?? -1;
      if (nakSeq >= 0) {
        window.markLost(nakSeq);
        lossMonitor.recordLost();
      }
    }
  }

  void _handleCumulativeAck(int ackedSeq) {
    logger.logImportant(
      '收到ACK:$ackedSeq (sendBase=${window.sendBase}, nextSeqNum=${window.nextSeqNum})',
    );

    if (ackedSeq == lastAckSeq) {
      duplicateAckCount++;
      if (duplicateAckCount == 3) {
        // 快速重传
        final nextSeq = ackedSeq + 1;
        if (window.inFlightPackets.containsKey(nextSeq)) {
          logger.logImportant('快速重传: seq=$nextSeq');
          window.markLost(nextSeq);
        }
        duplicateAckCount = 0;
      }
    } else {
      lastAckSeq = ackedSeq;
      duplicateAckCount = 0;

      // 更新RTT
      for (int seq = window.sendBase; seq <= ackedSeq; seq++) {
        final packet = window.inFlightPackets[seq];
        if (packet != null && !packet.acked) {
          rttEstimator.updateRTT(packet.age);
        }
      }

      window.slideWindow(ackedSeq);
      logger.logImportant(
        '窗口滑动后: sendBase=${window.sendBase}, nextSeqNum=${window.nextSeqNum}',
      );
      windowController.onSuccess();
    }
  }

  void _handleSelectiveAck(int baseSeq, String bitmap) {
    for (int i = 0; i < bitmap.length && i < 16; i++) {
      final seq = baseSeq + i + 1;
      if (bitmap[i] == '1') {
        window.markAcked(seq);
      } else {
        window.markLost(seq);
        lossMonitor.recordLost();
      }
    }

    // 更新sendBase到最小未确认包
    while (window.sendBase < totalPackets &&
        window.ackedPackets.contains(window.sendBase)) {
      window.sendBase++;
    }
  }

  Future<void> _handleTimeout() async {
    logger.logImportant('超时检测');
    final timeout = rttEstimator.getTimeout();

    for (final entry in window.inFlightPackets.entries) {
      final seq = entry.key;
      final packet = entry.value;

      if (!packet.acked && packet.isTimeout(timeout)) {
        packet.retryCount++;
        if (packet.retryCount > 10) {
          throw TransmissionException(
            error: TransmissionError.timeoutExceeded,
            message: '包$seq重传失败,超过最大次数',
          );
        }
        window.markLost(seq);
        windowController.onFailure();
      }
    }
  }

  Future<void> _retransmitLostPackets() async {
    final lostList = window.lostPackets.toList()..sort();
    for (final seq in lostList) {
      logger.logImportant('重传包: $seq');
      await _sendPacket(seq);
      window.lostPackets.remove(seq);
      totalRetransmitted++;
      lossMonitor.recordRetransmit();
      await rateController.waitBeforeSend();
    }
  }

  void _updateProgress() {
    // 🎯 简单可靠的进度计算：只用已确认的包
    // sendBase = 硬件已确认接收的最后一个包序号
    progress = (window.sendBase / totalPackets).clamp(0.0, 1.0);
    onProgress?.call(progress);

    // 调试日志
    if (window.sendBase % 100 == 0 || window.sendBase == totalPackets) {
      logger.logImportant(
        '进度更新: ${(progress * 100).toStringAsFixed(1)}% '
        '(已确认:${window.sendBase}/$totalPackets)',
      );
    }
  }

  void _updateStatus(String status) {
    statusMessage = status;
    onStatusChange?.call(status);
  }

  TransmissionStats _getStats() {
    final elapsed = startTime != null
        ? DateTime.now().difference(startTime!)
        : Duration.zero;
    return TransmissionStats(
      totalPackets: totalPackets,
      sentPackets: totalSent,
      retransmittedPackets: totalRetransmitted,
      lostPackets: lossMonitor.lostPackets,
      totalTime: elapsed,
      averageRTT: rttEstimator.estimatedRTT,
      lossRate: lossMonitor.lossRate,
      throughput: imageData.length / elapsed.inSeconds,
    );
  }

  int _calculateCRC32(Uint8List data) {
    const table = [
      0x00000000,
      0x77073096,
      0xEE0E612C,
      0x990951BA,
      0x076DC419,
      0x706AF48F,
      0xE963A535,
      0x9E6495A3,
      0x0EDB8832,
      0x79DCB8A4,
      0xE0D5E91E,
      0x97D2D988,
      0x09B64C2B,
      0x7EB17CBD,
      0xE7B82D07,
      0x90BF1D91,
      0x1DB71064,
      0x6AB020F2,
      0xF3B97148,
      0x84BE41DE,
      0x1ADAD47D,
      0x6DDDE4EB,
      0xF4D4B551,
      0x83D385C7,
      0x136C9856,
      0x646BA8C0,
      0xFD62F97A,
      0x8A65C9EC,
      0x14015C4F,
      0x63066CD9,
      0xFA0F3D63,
      0x8D080DF5,
      0x3B6E20C8,
      0x4C69105E,
      0xD56041E4,
      0xA2677172,
      0x3C03E4D1,
      0x4B04D447,
      0xD20D85FD,
      0xA50AB56B,
      0x35B5A8FA,
      0x42B2986C,
      0xDBBBC9D6,
      0xACBCF940,
      0x32D86CE3,
      0x45DF5C75,
      0xDCD60DCF,
      0xABD13D59,
      0x26D930AC,
      0x51DE003A,
      0xC8D75180,
      0xBFD06116,
      0x21B4F4B5,
      0x56B3C423,
      0xCFBA9599,
      0xB8BDA50F,
      0x2802B89E,
      0x5F058808,
      0xC60CD9B2,
      0xB10BE924,
      0x2F6F7C87,
      0x58684C11,
      0xC1611DAB,
      0xB6662D3D,
      0x76DC4190,
      0x01DB7106,
      0x98D220BC,
      0xEFD5102A,
      0x71B18589,
      0x06B6B51F,
      0x9FBFE4A5,
      0xE8B8D433,
      0x7807C9A2,
      0x0F00F934,
      0x9609A88E,
      0xE10E9818,
      0x7F6A0DBB,
      0x086D3D2D,
      0x91646C97,
      0xE6635C01,
      0x6B6B51F4,
      0x1C6C6162,
      0x856530D8,
      0xF262004E,
      0x6C0695ED,
      0x1B01A57B,
      0x8208F4C1,
      0xF50FC457,
      0x65B0D9C6,
      0x12B7E950,
      0x8BBEB8EA,
      0xFCB9887C,
      0x62DD1DDF,
      0x15DA2D49,
      0x8CD37CF3,
      0xFBD44C65,
      0x4DB26158,
      0x3AB551CE,
      0xA3BC0074,
      0xD4BB30E2,
      0x4ADFA541,
      0x3DD895D7,
      0xA4D1C46D,
      0xD3D6F4FB,
      0x4369E96A,
      0x346ED9FC,
      0xAD678846,
      0xDA60B8D0,
      0x44042D73,
      0x33031DE5,
      0xAA0A4C5F,
      0xDD0D7CC9,
      0x5005713C,
      0x270241AA,
      0xBE0B1010,
      0xC90C2086,
      0x5768B525,
      0x206F85B3,
      0xB966D409,
      0xCE61E49F,
      0x5EDEF90E,
      0x29D9C998,
      0xB0D09822,
      0xC7D7A8B4,
      0x59B33D17,
      0x2EB40D81,
      0xB7BD5C3B,
      0xC0BA6CAD,
      0xEDB88320,
      0x9ABFB3B6,
      0x03B6E20C,
      0x74B1D29A,
      0xEAD54739,
      0x9DD277AF,
      0x04DB2615,
      0x73DC1683,
      0xE3630B12,
      0x94643B84,
      0x0D6D6A3E,
      0x7A6A5AA8,
      0xE40ECF0B,
      0x9309FF9D,
      0x0A00AE27,
      0x7D079EB1,
      0xF00F9344,
      0x8708A3D2,
      0x1E01F268,
      0x6906C2FE,
      0xF762575D,
      0x806567CB,
      0x196C3671,
      0x6E6B06E7,
      0xFED41B76,
      0x89D32BE0,
      0x10DA7A5A,
      0x67DD4ACC,
      0xF9B9DF6F,
      0x8EBEEFF9,
      0x17B7BE43,
      0x60B08ED5,
      0xD6D6A3E8,
      0xA1D1937E,
      0x38D8C2C4,
      0x4FDFF252,
      0xD1BB67F1,
      0xA6BC5767,
      0x3FB506DD,
      0x48B2364B,
      0xD80D2BDA,
      0xAF0A1B4C,
      0x36034AF6,
      0x41047A60,
      0xDF60EFC3,
      0xA867DF55,
      0x316E8EEF,
      0x4669BE79,
      0xCB61B38C,
      0xBC66831A,
      0x256FD2A0,
      0x5268E236,
      0xCC0C7795,
      0xBB0B4703,
      0x220216B9,
      0x5505262F,
      0xC5BA3BBE,
      0xB2BD0B28,
      0x2BB45A92,
      0x5CB36A04,
      0xC2D7FFA7,
      0xB5D0CF31,
      0x2CD99E8B,
      0x5BDEAE1D,
      0x9B64C2B0,
      0xEC63F226,
      0x756AA39C,
      0x026D930A,
      0x9C0906A9,
      0xEB0E363F,
      0x72076785,
      0x05005713,
      0x95BF4A82,
      0xE2B87A14,
      0x7BB12BAE,
      0x0CB61B38,
      0x92D28E9B,
      0xE5D5BE0D,
      0x7CDCEFB7,
      0x0BDBDF21,
      0x86D3D2D4,
      0xF1D4E242,
      0x68DDB3F8,
      0x1FDA836E,
      0x81BE16CD,
      0xF6B9265B,
      0x6FB077E1,
      0x18B74777,
      0x88085AE6,
      0xFF0F6A70,
      0x66063BCA,
      0x11010B5C,
      0x8F659EFF,
      0xF862AE69,
      0x616BFFD3,
      0x166CCF45,
      0xA00AE278,
      0xD70DD2EE,
      0x4E048354,
      0x3903B3C2,
      0xA7672661,
      0xD06016F7,
      0x4969474D,
      0x3E6E77DB,
      0xAED16A4A,
      0xD9D65ADC,
      0x40DF0B66,
      0x37D83BF0,
      0xA9BCAE53,
      0xDEBB9EC5,
      0x47B2CF7F,
      0x30B5FFE9,
      0xBDBDF21C,
      0xCABAC28A,
      0x53B39330,
      0x24B4A3A6,
      0xBAD03605,
      0xCDD706B3,
      0x54DE5729,
      0x23D967BF,
      0xB3667A2E,
      0xC4614AB8,
      0x5D681B02,
      0x2A6F2B94,
      0xB40BBE37,
      0xC30C8EA1,
      0x5A05DF1B,
      0x2D02EF8D,
    ];
    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      crc = (crc >> 8) ^ table[(crc ^ data[i]) & 0xFF];
    }
    return crc ^ 0xFFFFFFFF;
  }

  void dispose() {
    _responseSub?.cancel();
  }

  /// 断点续传
  Future<void> resumeTransmission(String deviceId) async {
    startTime = DateTime.now();
    state = TransmissionState.starting;

    try {
      // 查询硬件端进度
      await btProvider.sendCommand('LOGO_QUERY_PROGRESS');
      var response = await _waitForResponse(
        timeout: const Duration(seconds: 3),
      );

      int resumeSeq = 0;
      if (response.startsWith('LOGO_PROGRESS:')) {
        final parts = response.substring(14).split(':');
        if (parts.length >= 2) {
          final hwReceivedSeq = int.tryParse(parts[0]) ?? 0;
          resumeSeq = hwReceivedSeq;
          logger.logImportant('硬件端进度: $hwReceivedSeq');
        }
      }

      // 加载本地进度
      final localProgress = await TransmissionProgress.load(deviceId);
      if (localProgress != null) {
        resumeSeq = min(resumeSeq, localProgress.lastAckedSeq);
        logger.logImportant('本地进度: ${localProgress.lastAckedSeq}');
      }

      logger.logImportant('从包$resumeSeq继续传输');

      // 调整窗口起始位置
      window.sendBase = resumeSeq;
      window.nextSeqNum = resumeSeq;

      state = TransmissionState.transmitting;
      await _transmitWithSlidingWindow();

      state = TransmissionState.verifying;
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');
      response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (!response.startsWith('LOGO_OK')) {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $response',
        );
      }

      state = TransmissionState.completed;
      final stats = _getStats();
      logger.logImportant('传输完成！\n$stats');
      onComplete?.call(stats);

      // 清除断点进度
      await TransmissionProgress.clear(deviceId);
    } catch (e) {
      state = TransmissionState.error;
      final errorMsg = e.toString();
      logger.logImportant('传输失败: $errorMsg');
      onError?.call(errorMsg);
      rethrow;
    } finally {
      _responseSub?.cancel();
    }
  }

  /// 保存当前进度
  Future<void> saveProgress(String deviceId) async {
    final progress = TransmissionProgress(
      totalPackets: totalPackets,
      lastAckedSeq: window.sendBase - 1,
      receivedPackets: window.ackedPackets,
      lastUpdateTime: DateTime.now(),
    );
    await progress.save(deviceId);
  }

  // ════════════════════════════════════════════════════════════
  // 压缩数据传输支持
  // ════════════════════════════════════════════════════════════

  /// 传输压缩后的图片数据
  ///
  /// 使用新的LOGO_START_COMPRESSED协议
  /// 格式: LOGO_START_COMPRESSED:原始大小:压缩大小:CRC32
  Future<bool> transmitCompressedImage(
    Uint8List compressedData,
    int originalSize,
    int crc32, {
    Function(double)? onProgressCallback,
  }) async {
    // 初始化传输状态
    startTime = DateTime.now();
    state = TransmissionState.starting;

    if (onProgressCallback != null) {
      onProgress = onProgressCallback;
    }

    // 初始化数据和窗口
    imageData = compressedData;
    window = SlidingWindow(
      totalPackets: (compressedData.length + 15) ~/ 16,
      windowSize: 50,
    );

    // 设置响应监听器
    _setupResponseListener();

    try {
      // 1. 发送压缩信息头
      await btProvider.sendCommand(
        'LOGO_START_COMPRESSED:$originalSize:${compressedData.length}:$crc32',
      );

      // 2. 等待硬件就绪（支持LOGO_ERASING状态）
      var response = await _waitForResponse(
        timeout: const Duration(seconds: 5),
      );

      // 如果硬件正在擦除Flash，继续等待LOGO_READY
      if (response == 'LOGO_ERASING') {
        _updateStatus('Flash擦除中...');
        print('[COMPRESSED] 硬件正在擦除Flash，等待完成...');
        response = await _waitForResponse(timeout: const Duration(seconds: 15));
      }

      if (response != 'LOGO_READY') {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件未就绪: $response',
        );
      }

      // 3. 使用滑动窗口协议传输压缩数据
      state = TransmissionState.transmitting;
      _updateStatus('传输中...');

      // 执行传输
      await _transmitWithSlidingWindow();

      // 4. 发送结束命令
      state = TransmissionState.verifying;
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      var endResponse = await _waitForResponse(
        timeout: const Duration(seconds: 10),
      );

      if (!endResponse.startsWith('LOGO_OK')) {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $endResponse',
        );
      }

      // 5. 完成
      state = TransmissionState.completed;
      final stats = _getStats();
      print('[COMPRESSED] 传输完成！\n$stats');
      if (onComplete != null) {
        onComplete!(stats);
      }

      return true;
    } catch (e) {
      state = TransmissionState.error;
      print('[COMPRESSED] 传输失败: $e');
      if (onError != null) {
        onError!('传输失败: $e');
      }
      return false;
    } finally {
      _responseSub?.cancel();
    }
  }
}

// ════════════════════════════════════════════════════════════
// 包对象池 - 内存优化
// ════════════════════════════════════════════════════════════
class PacketPool {
  final List<Uint8List> _pool = [];
  final int maxPoolSize;
  final int packetSize;

  PacketPool({this.maxPoolSize = 50, this.packetSize = 16});

  Uint8List acquire() {
    if (_pool.isNotEmpty) {
      return _pool.removeLast();
    }
    return Uint8List(packetSize);
  }

  void release(Uint8List packet) {
    if (_pool.length < maxPoolSize) {
      _pool.add(packet);
    }
  }

  void clear() {
    _pool.clear();
  }

  int get poolSize => _pool.length;
}

// ════════════════════════════════════════════════════════════
// 重试策略
// ════════════════════════════════════════════════════════════
class RetryPolicy {
  final int maxRetries;
  final Duration initialDelay;
  final double backoffMultiplier;

  RetryPolicy({
    this.maxRetries = 5,
    this.initialDelay = const Duration(milliseconds: 100),
    this.backoffMultiplier = 2.0,
  });

  Duration getDelay(int retryCount) {
    final delayMs =
        initialDelay.inMilliseconds *
        pow(backoffMultiplier, retryCount).toInt();
    return Duration(milliseconds: delayMs.clamp(100, 5000));
  }

  Future<T> retryWithPolicy<T>(
    Future<T> Function() operation, {
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempt = 0;
    dynamic lastError;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;
        attempt++;

        if (attempt >= maxRetries) {
          rethrow;
        }

        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        final delay = getDelay(attempt);
        await Future.delayed(delay);
      }
    }

    throw lastError;
  }
}

// ════════════════════════════════════════════════════════════
// 性能监控
// ════════════════════════════════════════════════════════════
class TransmissionMonitor {
  final List<TransmissionStats> _history = [];
  final int maxHistorySize;

  TransmissionMonitor({this.maxHistorySize = 100});

  void recordTransmission(TransmissionStats stats) {
    _history.add(stats);
    if (_history.length > maxHistorySize) {
      _history.removeAt(0);
    }
  }

  double get averageTime {
    if (_history.isEmpty) return 0.0;
    final total = _history.fold<int>(
      0,
      (sum, stats) => sum + stats.totalTime.inSeconds,
    );
    return total / _history.length;
  }

  double get averageLossRate {
    if (_history.isEmpty) return 0.0;
    final total = _history.fold<double>(
      0.0,
      (sum, stats) => sum + stats.lossRate,
    );
    return total / _history.length;
  }

  double get successRate {
    if (_history.isEmpty) return 0.0;
    final successful = _history.where((stats) => stats.lossRate < 0.1).length;
    return successful / _history.length;
  }

  bool detectAnomaly(TransmissionStats stats) {
    if (_history.length < 10) return false;

    // 检测异常高的丢包率
    if (stats.lossRate > averageLossRate * 2) {
      return true;
    }

    // 检测异常长的传输时间
    if (stats.totalTime.inSeconds > averageTime * 1.5) {
      return true;
    }

    return false;
  }

  String generateReport() {
    if (_history.isEmpty) return '暂无传输记录';

    return '''
传输监控报告:
- 总传输次数: ${_history.length}
- 平均耗时: ${averageTime.toStringAsFixed(1)}秒
- 平均丢包率: ${(averageLossRate * 100).toStringAsFixed(2)}%
- 成功率: ${(successRate * 100).toStringAsFixed(1)}%
- 最近一次: ${_history.last.totalTime.inSeconds}秒
''';
  }

  void clear() {
    _history.clear();
  }
}

// ════════════════════════════════════════════════════════════
// 协议版本检测
// ════════════════════════════════════════════════════════════
class ProtocolVersion {
  final int major;
  final int minor;

  ProtocolVersion(this.major, this.minor);

  bool get supportsSlidingWindow => major >= 2;
  bool get supportsSACK => major >= 2;
  bool get supportsResume => major >= 2;

  static Future<ProtocolVersion> query(BluetoothProvider btProvider) async {
    try {
      await btProvider.sendCommand('LOGO_VERSION');

      // 等待响应
      await Future.delayed(const Duration(milliseconds: 500));

      // 如果没有响应,假设是旧版本
      return ProtocolVersion(1, 0);
    } catch (e) {
      return ProtocolVersion(1, 0);
    }
  }

  @override
  String toString() => 'v$major.$minor';
}
