import '../services/logo_transmission_manager.dart';

/// 传输性能基准测试工具
class TransmissionBenchmark {
  final List<TransmissionStats> _history = [];

  /// 记录一次传输统计
  void recordTransmission(TransmissionStats stats) {
    _history.add(stats);

    // 保留最近100次记录
    if (_history.length > 100) {
      _history.removeAt(0);
    }
  }

  /// 获取平均统计
  BenchmarkReport getReport() {
    if (_history.isEmpty) {
      return BenchmarkReport.empty();
    }

    final totalTransmissions = _history.length;
    final successfulTransmissions = _history
        .where((s) => s.lossRate < 0.10)
        .length;

    final avgTime =
        _history.map((s) => s.totalTime.inSeconds).reduce((a, b) => a + b) /
        _history.length;

    final avgLossRate =
        _history.map((s) => s.lossRate).reduce((a, b) => a + b) /
        _history.length;

    final avgRTT =
        _history.map((s) => s.averageRTT).reduce((a, b) => a + b) /
        _history.length;

    final avgRetransmits =
        _history.map((s) => s.retransmittedPackets).reduce((a, b) => a + b) /
        _history.length;

    return BenchmarkReport(
      totalTransmissions: totalTransmissions,
      successRate: successfulTransmissions / totalTransmissions,
      averageTime: avgTime,
      averageLossRate: avgLossRate,
      averageRTT: avgRTT,
      averageRetransmits: avgRetransmits,
    );
  }

  /// 清除历史记录
  void clear() {
    _history.clear();
  }

  /// 导出详细报告
  String exportDetailedReport() {
    final report = getReport();
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('       传输性能基准测试报告');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();
    buffer.writeln('总传输次数: ${report.totalTransmissions}');
    buffer.writeln('成功率: ${(report.successRate * 100).toStringAsFixed(2)}%');
    buffer.writeln('平均传输时间: ${report.averageTime.toStringAsFixed(1)}秒');
    buffer.writeln(
      '平均丢包率: ${(report.averageLossRate * 100).toStringAsFixed(2)}%',
    );
    buffer.writeln('平均RTT: ${report.averageRTT.toStringAsFixed(1)}ms');
    buffer.writeln('平均重传包数: ${report.averageRetransmits.toStringAsFixed(1)}');
    buffer.writeln();

    if (_history.length >= 10) {
      buffer.writeln('最近10次传输:');
      buffer.writeln('─────────────────────────────────────');
      final recent = _history.sublist(_history.length - 10);
      for (int i = 0; i < recent.length; i++) {
        final s = recent[i];
        buffer.writeln(
          '${i + 1}. ${s.totalTime.inSeconds}秒 | '
          '丢包${(s.lossRate * 100).toStringAsFixed(1)}% | '
          'RTT${s.averageRTT.toStringAsFixed(0)}ms | '
          '重传${s.retransmittedPackets}包',
        );
      }
    }

    buffer.writeln('═══════════════════════════════════════');

    return buffer.toString();
  }

  /// 分析趋势
  TrendAnalysis analyzeTrends() {
    if (_history.length < 10) {
      return TrendAnalysis(
        trend: 'insufficient_data',
        message: '数据不足，需要至少10次传输记录',
      );
    }

    final recent = _history.sublist(_history.length - 10);
    final avgTime =
        recent.map((s) => s.totalTime.inSeconds).reduce((a, b) => a + b) / 10;
    final avgLoss = recent.map((s) => s.lossRate).reduce((a, b) => a + b) / 10;

    final warnings = <String>[];

    if (avgTime > 80) {
      warnings.add('⚠️ 传输时间异常偏高 (${avgTime.toStringAsFixed(1)}秒)');
    }

    if (avgLoss > 0.20) {
      warnings.add('⚠️ 丢包率异常偏高 (${(avgLoss * 100).toStringAsFixed(2)}%)');
    }

    if (warnings.isEmpty) {
      return TrendAnalysis(trend: 'good', message: '✅ 传输性能良好');
    } else {
      return TrendAnalysis(trend: 'warning', message: warnings.join('\n'));
    }
  }
}

/// 基准测试报告
class BenchmarkReport {
  final int totalTransmissions;
  final double successRate;
  final double averageTime;
  final double averageLossRate;
  final double averageRTT;
  final double averageRetransmits;

  BenchmarkReport({
    required this.totalTransmissions,
    required this.successRate,
    required this.averageTime,
    required this.averageLossRate,
    required this.averageRTT,
    required this.averageRetransmits,
  });

  factory BenchmarkReport.empty() {
    return BenchmarkReport(
      totalTransmissions: 0,
      successRate: 0.0,
      averageTime: 0.0,
      averageLossRate: 0.0,
      averageRTT: 0.0,
      averageRetransmits: 0.0,
    );
  }
}

/// 趋势分析结果
class TrendAnalysis {
  final String trend; // 'good', 'warning', 'insufficient_data'
  final String message;

  TrendAnalysis({required this.trend, required this.message});
}

/// 全局基准测试实例
final globalBenchmark = TransmissionBenchmark();
