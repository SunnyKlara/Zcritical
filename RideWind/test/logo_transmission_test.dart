import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/services/logo_transmission_manager.dart';
import 'dart:typed_data';

void main() {
  group('SlidingWindow Tests', () {
    test('窗口初始化', () {
      final window = SlidingWindow(windowSize: 10, totalPackets: 100);
      expect(window.sendBase, 0);
      expect(window.nextSeqNum, 0);
      expect(window.isEmpty, true);
      expect(window.isFull, false);
    });

    test('窗口滑动', () {
      final window = SlidingWindow(windowSize: 10, totalPackets: 100);
      window.nextSeqNum = 10;
      window.slideWindow(4);
      expect(window.sendBase, 5);
      expect(window.inFlightCount, 5);
    });

    test('窗口满判断', () {
      final window = SlidingWindow(windowSize: 5, totalPackets: 100);
      window.nextSeqNum = 5;
      expect(window.isFull, true);
      window.slideWindow(2);
      expect(window.isFull, false);
    });
  });

  group('RTTEstimator Tests', () {
    test('RTT更新', () {
      final estimator = RTTEstimator();
      final initialRTT = estimator.estimatedRTT;

      estimator.updateRTT(const Duration(milliseconds: 100));
      expect(estimator.estimatedRTT, lessThan(initialRTT));

      estimator.updateRTT(const Duration(milliseconds: 150));
      estimator.updateRTT(const Duration(milliseconds: 120));

      final timeout = estimator.getTimeout();
      expect(timeout, greaterThanOrEqualTo(300));
      expect(timeout, lessThanOrEqualTo(3000));
    });

    test('超时范围限制', () {
      final estimator = RTTEstimator();
      estimator.estimatedRTT = 50.0;
      estimator.devRTT = 10.0;

      final timeout = estimator.getTimeout();
      expect(timeout, greaterThanOrEqualTo(300));
    });
  });

  group('PacketLossMonitor Tests', () {
    test('丢包率计算', () {
      final monitor = PacketLossMonitor();

      for (int i = 0; i < 100; i++) {
        monitor.recordSent();
      }
      for (int i = 0; i < 5; i++) {
        monitor.recordLost();
      }

      expect(monitor.lossRate, closeTo(0.05, 0.001));
    });

    test('统计重置', () {
      final monitor = PacketLossMonitor();

      for (int i = 0; i < 100; i++) {
        monitor.recordSent();
      }
      monitor.resetIfNeeded();

      expect(monitor.sentPackets, 0);
      expect(monitor.lostPackets, 0);
    });
  });

  group('AdaptiveRateController Tests', () {
    test('速率调整 - 低丢包率', () {
      final controller = AdaptiveRateController();
      final initialInterval = controller.sendInterval;

      controller.adjustRate(0.03);
      expect(controller.sendInterval, lessThan(initialInterval));
    });

    test('速率调整 - 高丢包率', () {
      final controller = AdaptiveRateController();
      final initialInterval = controller.sendInterval;

      controller.adjustRate(0.20);
      expect(controller.sendInterval, greaterThan(initialInterval));
    });

    test('速率范围限制', () {
      final controller = AdaptiveRateController();

      for (int i = 0; i < 20; i++) {
        controller.adjustRate(0.01);
      }
      expect(
        controller.sendInterval,
        greaterThanOrEqualTo(controller.minInterval),
      );

      for (int i = 0; i < 20; i++) {
        controller.adjustRate(0.30);
      }
      expect(
        controller.sendInterval,
        lessThanOrEqualTo(controller.maxInterval),
      );
    });
  });

  group('WindowSizeController Tests', () {
    test('窗口增大', () {
      final controller = WindowSizeController();
      final initialSize = controller.windowSize;

      for (int i = 0; i < 10; i++) {
        controller.onSuccess();
      }

      expect(controller.windowSize, greaterThan(initialSize));
    });

    test('窗口减小', () {
      final controller = WindowSizeController();
      final initialSize = controller.windowSize;

      for (int i = 0; i < 3; i++) {
        controller.onFailure();
      }

      expect(controller.windowSize, lessThan(initialSize));
    });

    test('窗口范围限制', () {
      final controller = WindowSizeController();

      for (int i = 0; i < 50; i++) {
        controller.onSuccess();
      }
      expect(controller.windowSize, lessThanOrEqualTo(controller.maxWindow));

      for (int i = 0; i < 50; i++) {
        controller.onFailure();
      }
      expect(controller.windowSize, greaterThanOrEqualTo(controller.minWindow));
    });
  });

  group('AckInfo Tests', () {
    test('SACK解析 - 无丢包', () {
      final ack = AckInfo(
        type: AckType.selective,
        seq: 100,
        bitmap: '1111111111111111',
      );

      final lost = ack.getLostPackets();
      expect(lost, isEmpty);
    });

    test('SACK解析 - 有丢包', () {
      final ack = AckInfo(
        type: AckType.selective,
        seq: 100,
        bitmap: '1101111011110111',
      );

      final lost = ack.getLostPackets();
      expect(lost, contains(102));
      expect(lost, contains(106));
      expect(lost, contains(111));
      expect(lost.length, 3);
    });

    test('累积ACK不返回丢包', () {
      final ack = AckInfo(type: AckType.cumulative, seq: 100);

      final lost = ack.getLostPackets();
      expect(lost, isEmpty);
    });
  });

  group('PacketInfo Tests', () {
    test('超时判断', () {
      final packet = PacketInfo(
        seq: 0,
        data: Uint8List(16),
        sendTime: DateTime.now().subtract(const Duration(milliseconds: 600)),
      );

      expect(packet.isTimeout(500), true);
      expect(packet.isTimeout(700), false);
    });

    test('age计算', () {
      final packet = PacketInfo(
        seq: 0,
        data: Uint8List(16),
        sendTime: DateTime.now().subtract(const Duration(milliseconds: 100)),
      );

      expect(packet.age.inMilliseconds, greaterThanOrEqualTo(100));
    });
  });
}
