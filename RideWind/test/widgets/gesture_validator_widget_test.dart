import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/models/guide_models.dart';
import 'package:ridewind/widgets/gesture_validator_widget.dart';

/// GestureValidatorWidget 单元测试
///
/// **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8**
///
/// 测试内容:
/// 1. matchesGesture 纯函数对所有 8 种手势类型的正确匹配
/// 2. 不匹配手势返回 false
/// 3. 边界情况（零速度、阈值边界位移等）
void main() {
  group('matchesGesture', () {
    group('tap', () {
      /// **Validates: Requirements 5.3**
      test('matches when gestureType is tap', () {
        const data = GestureData(gestureType: GestureType.tap);
        expect(matchesGesture(GestureType.tap, data), isTrue);
      });

      test('does not match other gesture types', () {
        const data = GestureData(gestureType: GestureType.tap);
        for (final type in GestureType.values) {
          if (type == GestureType.tap) continue;
          expect(matchesGesture(type, data), isFalse);
        }
      });
    });

    group('longPress', () {
      /// **Validates: Requirements 5.4**
      test('matches when gestureType is longPress', () {
        const data = GestureData(gestureType: GestureType.longPress);
        expect(matchesGesture(GestureType.longPress, data), isTrue);
      });

      test('does not match other gesture types', () {
        const data = GestureData(gestureType: GestureType.longPress);
        for (final type in GestureType.values) {
          if (type == GestureType.longPress) continue;
          expect(matchesGesture(type, data), isFalse);
        }
      });
    });

    group('swipeLeft', () {
      /// **Validates: Requirements 5.5**
      test('matches with negative dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeLeft,
          velocity: Offset(-500, 0),
        );
        expect(matchesGesture(GestureType.swipeLeft, data), isTrue);
      });

      test('does not match with zero dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeLeft,
          velocity: Offset(0, 0),
        );
        expect(matchesGesture(GestureType.swipeLeft, data), isFalse);
      });

      test('does not match with positive dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeLeft,
          velocity: Offset(500, 0),
        );
        expect(matchesGesture(GestureType.swipeLeft, data), isFalse);
      });

      test('does not match swipeRight expected type', () {
        const data = GestureData(
          gestureType: GestureType.swipeLeft,
          velocity: Offset(-500, 0),
        );
        expect(matchesGesture(GestureType.swipeRight, data), isFalse);
      });
    });

    group('swipeRight', () {
      /// **Validates: Requirements 5.5**
      test('matches with positive dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeRight,
          velocity: Offset(500, 0),
        );
        expect(matchesGesture(GestureType.swipeRight, data), isTrue);
      });

      test('does not match with zero dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeRight,
          velocity: Offset(0, 0),
        );
        expect(matchesGesture(GestureType.swipeRight, data), isFalse);
      });

      test('does not match with negative dx velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeRight,
          velocity: Offset(-500, 0),
        );
        expect(matchesGesture(GestureType.swipeRight, data), isFalse);
      });
    });

    group('swipeUp', () {
      /// **Validates: Requirements 5.6**
      test('matches with negative dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeUp,
          velocity: Offset(0, -500),
        );
        expect(matchesGesture(GestureType.swipeUp, data), isTrue);
      });

      test('does not match with zero dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeUp,
          velocity: Offset(0, 0),
        );
        expect(matchesGesture(GestureType.swipeUp, data), isFalse);
      });

      test('does not match with positive dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeUp,
          velocity: Offset(0, 500),
        );
        expect(matchesGesture(GestureType.swipeUp, data), isFalse);
      });
    });

    group('swipeDown', () {
      /// **Validates: Requirements 5.6**
      test('matches with positive dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeDown,
          velocity: Offset(0, 500),
        );
        expect(matchesGesture(GestureType.swipeDown, data), isTrue);
      });

      test('does not match with zero dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeDown,
          velocity: Offset(0, 0),
        );
        expect(matchesGesture(GestureType.swipeDown, data), isFalse);
      });

      test('does not match with negative dy velocity', () {
        const data = GestureData(
          gestureType: GestureType.swipeDown,
          velocity: Offset(0, -500),
        );
        expect(matchesGesture(GestureType.swipeDown, data), isFalse);
      });
    });

    group('dragHorizontal', () {
      /// **Validates: Requirements 5.7**
      test('matches when displacement exceeds threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragHorizontal,
          displacement: Offset(30, 0),
        );
        expect(matchesGesture(GestureType.dragHorizontal, data), isTrue);
      });

      test('matches with negative displacement exceeding threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragHorizontal,
          displacement: Offset(-35, 0),
        );
        expect(matchesGesture(GestureType.dragHorizontal, data), isTrue);
      });

      test('does not match when displacement is below threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragHorizontal,
          displacement: Offset(29.9, 0),
        );
        expect(matchesGesture(GestureType.dragHorizontal, data), isFalse);
      });

      test('does not match with zero displacement', () {
        const data = GestureData(
          gestureType: GestureType.dragHorizontal,
          displacement: Offset.zero,
        );
        expect(matchesGesture(GestureType.dragHorizontal, data), isFalse);
      });
    });

    group('dragVertical', () {
      /// **Validates: Requirements 5.7**
      test('matches when displacement exceeds threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragVertical,
          displacement: Offset(0, 30),
        );
        expect(matchesGesture(GestureType.dragVertical, data), isTrue);
      });

      test('matches with negative displacement exceeding threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragVertical,
          displacement: Offset(0, -45),
        );
        expect(matchesGesture(GestureType.dragVertical, data), isTrue);
      });

      test('does not match when displacement is below threshold', () {
        const data = GestureData(
          gestureType: GestureType.dragVertical,
          displacement: Offset(0, 29.9),
        );
        expect(matchesGesture(GestureType.dragVertical, data), isFalse);
      });

      test('does not match with zero displacement', () {
        const data = GestureData(
          gestureType: GestureType.dragVertical,
          displacement: Offset.zero,
        );
        expect(matchesGesture(GestureType.dragVertical, data), isFalse);
      });
    });

    group('cross-type rejection', () {
      test('tap data does not match any swipe or drag type', () {
        const data = GestureData(gestureType: GestureType.tap);
        expect(matchesGesture(GestureType.swipeLeft, data), isFalse);
        expect(matchesGesture(GestureType.swipeRight, data), isFalse);
        expect(matchesGesture(GestureType.swipeUp, data), isFalse);
        expect(matchesGesture(GestureType.swipeDown, data), isFalse);
        expect(matchesGesture(GestureType.dragHorizontal, data), isFalse);
        expect(matchesGesture(GestureType.dragVertical, data), isFalse);
        expect(matchesGesture(GestureType.longPress, data), isFalse);
      });

      test('dragHorizontal data does not match dragVertical', () {
        const data = GestureData(
          gestureType: GestureType.dragHorizontal,
          displacement: Offset(50, 0),
        );
        expect(matchesGesture(GestureType.dragVertical, data), isFalse);
      });

      test('dragVertical data does not match dragHorizontal', () {
        const data = GestureData(
          gestureType: GestureType.dragVertical,
          displacement: Offset(0, 50),
        );
        expect(matchesGesture(GestureType.dragHorizontal, data), isFalse);
      });
    });
  });

  group('GestureData', () {
    test('default velocity is Offset.zero', () {
      const data = GestureData(gestureType: GestureType.tap);
      expect(data.velocity, equals(Offset.zero));
    });

    test('default displacement is Offset.zero', () {
      const data = GestureData(gestureType: GestureType.tap);
      expect(data.displacement, equals(Offset.zero));
    });
  });

  group('dragDisplacementThreshold', () {
    test('threshold is 30.0', () {
      expect(dragDisplacementThreshold, equals(30.0));
    });
  });
}
