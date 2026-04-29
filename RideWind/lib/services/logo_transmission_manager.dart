import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/bluetooth_provider.dart';
import '../utils/crc32.dart';

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
  double estimatedRTT = 100.0; // 🔥 ESP32 BLE 延迟比 F4 低，初始 100ms
  double devRTT = 30.0; // 🔥 偏差更小

  final double alpha = 0.125;
  final double beta = 0.25;

  void updateRTT(Duration measuredRTT) {
    final sampleRTT = measuredRTT.inMilliseconds.toDouble();
    estimatedRTT = (1 - alpha) * estimatedRTT + alpha * sampleRTT;
    devRTT = (1 - beta) * devRTT + beta * (sampleRTT - estimatedRTT).abs();
  }

  int getTimeout() {
    final timeout = (estimatedRTT + 4 * devRTT).toInt();
    return timeout.clamp(80, 800); // 🔥 更紧凑的超时范围
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

  /// 窗口大小，可配置（默认 40）
  int windowSize;

  /// 最大重试次数
  static const int maxRetries = 10;

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

  /// 上传完成后分配的槽位号
  int? assignedSlot;

  Function(double)? onProgress;
  Function(TransmissionState)? onStateChange;
  Function(String)? onStatusChange;
  Function(TransmissionStats)? onComplete;
  Function(String)? onError;

  String _lastResponse = '';
  bool _responseReceived = false;
  StreamSubscription<String>? _responseSub;

  int lastAckSeq = -1;
  int duplicateAckCount = 0;

  /// 是否已取消
  bool _cancelled = false;

  LogoTransmissionManager({
    required this.btProvider,
    required this.imageData,
    this.windowSize = 40,
    this.onProgress,
    this.onStateChange,
    this.onStatusChange,
    this.onComplete,
    this.onError,
  }) : totalPackets = (imageData.length / 16).ceil() {
    window = SlidingWindow(
      windowSize: windowSize,
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
          trimmed.startsWith('LOGO_START_BIN:') ||
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

  /// 上传 Logo 图片
  ///
  /// [slot] 目标槽位（0-2），null 表示自动分配
  /// [useBinaryMode] 使用二进制模式（默认 true，比 hex 模式快 ~8 倍）
  /// 返回 true 表示上传成功
  Future<bool> transmit({int? slot, bool useBinaryMode = true}) async {
    // 每次传输前重新设置响应监听器（上次传输的 finally 会 cancel 掉旧的）
    _setupResponseListener();
    if (useBinaryMode) {
      return _transmitBinary(slot: slot);
    }
    return _transmitHex(slot: slot);
  }

  /// 🚀 二进制模式传输 — 直接发原始字节，利用满 MTU
  ///
  /// 可靠性机制：分段发送 + ACK 校验 + 断点重传
  /// - 每发送 ~4KB（16 个 BLE 包 × 244 字节）等待 ESP32 确认收到的字节数
  /// - 如果 ESP32 报告的字节数 < APP 已发送的字节数，说明丢包，从断点重传
  /// - 最多重试 3 次，每次从 ESP32 实际收到的位置重传
  ///
  /// 115200 字节 / 244 字节 MTU = 472 包
  /// 分 ~30 段，每段 16 包，每段有 ACK 确认
  /// 预计传输时间：~10-15 秒
  Future<bool> _transmitBinary({int? slot}) async {
    startTime = DateTime.now();
    _cancelled = false;
    _setState(TransmissionState.starting);

    try {
      final crc32 = Crc32.calculate(imageData);
      final String startCmd;
      if (slot != null) {
        startCmd = 'LOGO_START_BIN:$slot:${imageData.length}:$crc32';
      } else {
        startCmd = 'LOGO_START_BIN:${imageData.length}:$crc32';
      }
      await btProvider.sendCommand(startCmd);

      var response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (response.contains('LOGO_ERASING')) {
        _updateStatus('Flash擦除中...');
        response = await _waitForResponse(timeout: const Duration(seconds: 15));
      }

      if (response.startsWith('LOGO_ERROR:')) {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件错误: ${response.substring(11)}',
        );
      }

      if (!response.contains('LOGO_READY')) {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件未就绪: $response',
        );
      }

      if (response.startsWith('LOGO_READY:')) {
        assignedSlot = int.tryParse(response.substring(11));
      }

      // ═══════════════════════════════════════════════════════
      // 🚀 分段二进制传输 + ACK 校验 + 断点重传
      // ═══════════════════════════════════════════════════════
      _setState(TransmissionState.transmitting);
      _updateStatus('传输中...');

      final int mtuPayload = 244;
      final int totalBytes = imageData.length;
      // 每段发 16 个 BLE 包（~3904 字节），然后等 ACK 确认
      final int segmentPackets = 16;
      final int segmentBytes = segmentPackets * mtuPayload; // ~3904 bytes
      int confirmed = 0; // ESP32 已确认收到的字节数
      int segmentRetries = 0;
      const int maxSegmentRetries = 3;

      while (confirmed < totalBytes) {
        if (_cancelled) {
          throw TransmissionException(
            error: TransmissionError.userCancelled,
            message: '用户取消上传',
          );
        }

        // 计算本段要发送的范围
        final int segmentEnd = (confirmed + segmentBytes > totalBytes)
            ? totalBytes
            : confirmed + segmentBytes;
        int sent = confirmed;

        // 发送本段的所有 BLE 包
        while (sent < segmentEnd) {
          final int chunkEnd = (sent + mtuPayload > segmentEnd)
              ? segmentEnd
              : sent + mtuPayload;
          final chunk = imageData.sublist(sent, chunkEnd);
          await btProvider.writeBytes(Uint8List.fromList(chunk));
          sent += chunk.length;

          // 每 4 包一个微延迟，给 BLE 协议栈喘息
          if ((sent - confirmed) ~/ mtuPayload % 4 == 0) {
            await Future.delayed(const Duration(milliseconds: 2));
          }
        }

        // 🔑 关键：发完一段后等 20ms，让 ESP32 BLE 协议栈有时间
        // 处理完接收缓冲区并发出 ACK notify
        await Future.delayed(const Duration(milliseconds: 20));

        // 等待 ESP32 的 ACK，确认实际收到的字节数
        // 超时 3 秒（给 BLE 拥塞重试足够时间）
        final ackResponse = await _waitForResponse(
          timeout: const Duration(seconds: 3),
        );

        if (ackResponse != 'TIMEOUT' && ackResponse.startsWith('LOGO_ACK_BIN:')) {
          final receivedBytes = int.tryParse(ackResponse.substring(13));
          if (receivedBytes != null) {
            if (receivedBytes >= segmentEnd) {
              // ✅ 本段全部收到，继续下一段
              confirmed = receivedBytes;
              segmentRetries = 0;
              progress = confirmed / totalBytes;
              onProgress?.call(progress);
              logger.logImportant(
                '✅ 段确认: $confirmed/$totalBytes (${(progress * 100).toStringAsFixed(1)}%)');
            } else if (receivedBytes > confirmed) {
              // ⚠️ 部分收到，从断点重传
              confirmed = receivedBytes;
              segmentRetries++;
              logger.logImportant(
                '⚠️ 部分收到: $confirmed/$segmentEnd, 重传剩余 (重试 $segmentRetries/$maxSegmentRetries)');
              if (segmentRetries > maxSegmentRetries) {
                throw TransmissionException(
                  error: TransmissionError.packetLost,
                  message: '段重传失败: ESP32 只收到 $confirmed/$segmentEnd 字节',
                );
              }
              // 不增加 confirmed，下一轮循环会从 confirmed 位置重发
              progress = confirmed / totalBytes;
              onProgress?.call(progress);
            } else {
              // ❌ 没有新数据收到，重传整段
              segmentRetries++;
              logger.logImportant(
                '❌ ACK 无进展: ESP32 仍在 $receivedBytes, 重传 (重试 $segmentRetries/$maxSegmentRetries)');
              if (segmentRetries > maxSegmentRetries) {
                throw TransmissionException(
                  error: TransmissionError.packetLost,
                  message: '段重传失败: ESP32 停在 $receivedBytes 字节',
                );
              }
              // 加一点延迟再重传，让 ESP32 处理完
              await Future.delayed(const Duration(milliseconds: 50));
            }
          }
        } else {
          // ACK 超时 — 可能是 notify 丢失，重试
          segmentRetries++;
          logger.logImportant(
            '⏰ ACK 超时 (段 ${confirmed ~/ segmentBytes}), 重试 $segmentRetries/$maxSegmentRetries');
          if (segmentRetries > maxSegmentRetries) {
            throw TransmissionException(
              error: TransmissionError.timeoutExceeded,
              message: 'ACK 超时 $maxSegmentRetries 次，传输中止',
            );
          }
          // 超时后不移动 confirmed，下一轮会重发这一段
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      // ═══════════════════════════════════════════════════════
      // 校验阶段
      // ═══════════════════════════════════════════════════════
      _setState(TransmissionState.verifying);
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (response.startsWith('LOGO_OK')) {
        if (response.startsWith('LOGO_OK:')) {
          assignedSlot = int.tryParse(response.substring(8));
        }
      } else if (response.startsWith('LOGO_FAIL:')) {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: ${response.substring(10)}',
        );
      } else {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $response',
        );
      }

      _setState(TransmissionState.completed);
      progress = 1.0;
      onProgress?.call(1.0);
      final elapsed = DateTime.now().difference(startTime!);
      logger.logImportant('🚀 二进制传输完成！耗时 ${elapsed.inSeconds}s, '
          '速率 ${(totalBytes / elapsed.inMilliseconds * 1000 / 1024).toStringAsFixed(1)} KB/s');
      final stats = _getStats();
      onComplete?.call(stats);
      return true;
    } catch (e) {
      _setState(TransmissionState.error);
      logger.logImportant('二进制传输失败: $e');
      onError?.call(e.toString());
      rethrow;
    } finally {
      _responseSub?.cancel();
    }
  }

  /// Hex 模式传输（兼容旧设备）
  Future<bool> _transmitHex({int? slot}) async {
    startTime = DateTime.now();
    _cancelled = false;
    _setState(TransmissionState.starting);

    try {
      // 发送LOGO_START（使用共享 Crc32 工具类）
      final crc32 = Crc32.calculate(imageData);
      final String startCmd;
      if (slot != null) {
        // 指定槽位: LOGO_START:slot:size:crc32\n
        startCmd = 'LOGO_START:$slot:${imageData.length}:$crc32';
      } else {
        // 自动分配: LOGO_START:size:crc32\n
        startCmd = 'LOGO_START:${imageData.length}:$crc32';
      }
      await btProvider.sendCommand(startCmd);

      var response = await _waitForResponse(
        timeout: const Duration(seconds: 10),
      );

      if (response.contains('LOGO_ERASING')) {
        _updateStatus('Flash擦除中...');
        response = await _waitForResponse(timeout: const Duration(seconds: 15));
      }

      if (response.startsWith('LOGO_ERROR:')) {
        final reason = response.substring(11);
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件错误: $reason',
        );
      }

      if (!response.contains('LOGO_READY')) {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件未就绪: $response',
        );
      }

      // 解析 LOGO_READY:slot 中的槽位号
      if (response.startsWith('LOGO_READY:')) {
        assignedSlot = int.tryParse(response.substring(11));
      }

      _setState(TransmissionState.transmitting);
      await _transmitWithSlidingWindow();

      _setState(TransmissionState.verifying);
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      // 等待 LOGO_OK:slot 或 LOGO_FAIL:reason，超时 10 秒
      response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (response.startsWith('LOGO_OK')) {
        // 解析 LOGO_OK:slot 中的槽位号
        if (response.startsWith('LOGO_OK:')) {
          assignedSlot = int.tryParse(response.substring(8));
        }
      } else if (response.startsWith('LOGO_FAIL:')) {
        final reason = response.substring(10);
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $reason',
        );
      } else {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $response',
        );
      }

      _setState(TransmissionState.completed);
      final stats = _getStats();
      logger.logImportant('传输完成！\n$stats');
      onComplete?.call(stats);
      return true;
    } catch (e) {
      _setState(TransmissionState.error);
      final errorMsg = e.toString();
      logger.logImportant('传输失败: $errorMsg');
      onError?.call(errorMsg);
      rethrow;
    } finally {
      _responseSub?.cancel();
    }
  }

  /// 取消上传
  void cancel() {
    _cancelled = true;
    _setState(TransmissionState.error);
    _responseSub?.cancel();
    // 通知 ESP32 结束上传会话，清理硬件端状态
    try {
      btProvider.sendCommand('LOGO_END');
    } catch (_) {
      // 忽略发送失败（可能已断连）
    }
    logger.logImportant('上传已取消');
    onError?.call('用户取消上传');
  }

  /// 更新传输状态并触发回调
  void _setState(TransmissionState newState) {
    state = newState;
    onStateChange?.call(newState);
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
        await _sendPacket(window.nextSeqNum);
        window.nextSeqNum++;
        // 🔥 每4包一个微延迟，让 BLE 协议栈有时间处理
        // 比每包 2ms 快 4 倍，ESP32 的 BLE 内部有流控不会丢
        if (window.nextSeqNum % 4 == 0) {
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      // 🎯 策略2：每发送16包才等待一次ACK（与ESP32 LOGO_BATCH_SIZE=16 对齐）
      // ESP32 每收到16包才发一次 LOGO_ACK，APP 必须匹配这个频率
      final shouldWaitForAck =
          (window.nextSeqNum - lastAckWaitSeq) >= 16 ||
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
    // 只在每 100 包打印一次，避免高频日志拖慢 UI
    if (seq % 100 == 0 || seq == totalPackets - 1) {
      logger.logPacket(seq, 'SEND', totalPackets);
    }
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
    } else if (response.startsWith('LOGO_ERROR:')) {
      final reason = response.substring(11);
      logger.logImportant('收到LOGO_ERROR: $reason');
      throw TransmissionException(
        error: TransmissionError.unknownError,
        message: '硬件错误: $reason',
      );
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
    logger.logImportant(
      '收到SACK: base=$baseSeq, bitmap=$bitmap (sendBase=${window.sendBase})',
    );

    for (int i = 0; i < bitmap.length && i < 16; i++) {
      final seq = baseSeq + i + 1;
      if (bitmap[i] == '1') {
        window.markAcked(seq);
      } else {
        window.markLost(seq);
        lossMonitor.recordLost();
      }
    }

    // 同时处理累积确认：base 之前的包都已确认
    if (baseSeq >= window.sendBase) {
      for (int seq = window.sendBase; seq <= baseSeq; seq++) {
        window.ackedPackets.add(seq);
        window.inFlightPackets.remove(seq);
        window.lostPackets.remove(seq);
      }
    }

    // 更新sendBase到最小未确认包
    while (window.sendBase < totalPackets &&
        window.ackedPackets.contains(window.sendBase)) {
      window.sendBase++;
    }

    // 确保nextSeqNum不会回退
    if (window.nextSeqNum < window.sendBase) {
      window.nextSeqNum = window.sendBase;
    }

    windowController.onSuccess();
  }

  Future<void> _handleTimeout() async {
    logger.logImportant('超时检测');
    final timeout = rttEstimator.getTimeout();

    for (final entry in window.inFlightPackets.entries) {
      final seq = entry.key;
      final packet = entry.value;

      if (!packet.acked && packet.isTimeout(timeout)) {
        packet.retryCount++;
        if (packet.retryCount > maxRetries) {
          throw TransmissionException(
            error: TransmissionError.timeoutExceeded,
            message: '包$seq重传失败,超过最大次数($maxRetries)',
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

  void dispose() {
    _responseSub?.cancel();
  }

  /// 断点续传
  Future<void> resumeTransmission(String deviceId) async {
    startTime = DateTime.now();
    _cancelled = false;
    _setState(TransmissionState.starting);

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

      _setState(TransmissionState.verifying);
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');
      response = await _waitForResponse(timeout: const Duration(seconds: 10));

      if (response.startsWith('LOGO_OK')) {
        // 解析 LOGO_OK:slot 中的槽位号
        if (response.startsWith('LOGO_OK:')) {
          assignedSlot = int.tryParse(response.substring(8));
        }
      } else if (response.startsWith('LOGO_FAIL:')) {
        final reason = response.substring(10);
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $reason',
        );
      } else {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $response',
        );
      }

      _setState(TransmissionState.completed);
      final stats = _getStats();
      logger.logImportant('传输完成！\n$stats');
      onComplete?.call(stats);

      // 清除断点进度
      await TransmissionProgress.clear(deviceId);
    } catch (e) {
      _setState(TransmissionState.error);
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
    _cancelled = false;
    _setState(TransmissionState.starting);

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

      if (response.startsWith('LOGO_ERROR:')) {
        final reason = response.substring(11);
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件错误: $reason',
        );
      }

      if (!response.contains('LOGO_READY')) {
        throw TransmissionException(
          error: TransmissionError.invalidResponse,
          message: '硬件未就绪: $response',
        );
      }

      // 解析 LOGO_READY:slot 中的槽位号
      if (response.startsWith('LOGO_READY:')) {
        assignedSlot = int.tryParse(response.substring(11));
      }

      // 3. 使用滑动窗口协议传输压缩数据
      _setState(TransmissionState.transmitting);
      _updateStatus('传输中...');

      // 执行传输
      await _transmitWithSlidingWindow();

      // 4. 发送结束命令，等待 LOGO_OK:slot 或 LOGO_FAIL:reason，超时 10 秒
      _setState(TransmissionState.verifying);
      _updateStatus('校验中...');
      await btProvider.sendCommand('LOGO_END');

      var endResponse = await _waitForResponse(
        timeout: const Duration(seconds: 10),
      );

      if (endResponse.startsWith('LOGO_OK')) {
        if (endResponse.startsWith('LOGO_OK:')) {
          assignedSlot = int.tryParse(endResponse.substring(8));
        }
      } else if (endResponse.startsWith('LOGO_FAIL:')) {
        final reason = endResponse.substring(10);
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $reason',
        );
      } else {
        throw TransmissionException(
          error: TransmissionError.checksumMismatch,
          message: '校验失败: $endResponse',
        );
      }

      // 5. 完成
      _setState(TransmissionState.completed);
      final stats = _getStats();
      print('[COMPRESSED] 传输完成！\n$stats');
      if (onComplete != null) {
        onComplete!(stats);
      }

      return true;
    } catch (e) {
      _setState(TransmissionState.error);
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
