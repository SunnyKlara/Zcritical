import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/widgets/ripple_effect_painter.dart';

/// RippleEffectPainter 单元测试
///
/// **Validates: Requirements 2.2**
///
/// 测试内容:
/// 1. shouldRepaint 在属性变化时返回 true
/// 2. shouldRepaint 在属性不变时返回 false
/// 3. 默认波纹颜色为 0xFF25C485
/// 4. 绘制不抛出异常（各种 progress 值）
void main() {
  group('RippleEffectPainter', () {
    final defaultRect = const Rect.fromLTWH(100, 100, 80, 60);

    group('shouldRepaint', () {
      /// **Validates: Requirements 2.2**
      test('returns true when rippleProgress changes', () {
        final oldPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.0,
        );
        final newPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
        );

        expect(newPainter.shouldRepaint(oldPainter), isTrue);
      });

      /// **Validates: Requirements 2.2**
      test('returns true when targetRect changes', () {
        final oldPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
        );
        final newPainter = RippleEffectPainter(
          targetRect: const Rect.fromLTWH(200, 200, 80, 60),
          rippleProgress: 0.5,
        );

        expect(newPainter.shouldRepaint(oldPainter), isTrue);
      });

      /// **Validates: Requirements 2.2**
      test('returns true when rippleColor changes', () {
        final oldPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
        );
        final newPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
          rippleColor: Colors.red,
        );

        expect(newPainter.shouldRepaint(oldPainter), isTrue);
      });

      /// **Validates: Requirements 2.2**
      test('returns false when all properties are the same', () {
        final oldPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
        );
        final newPainter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.5,
        );

        expect(newPainter.shouldRepaint(oldPainter), isFalse);
      });
    });

    group('default values', () {
      /// **Validates: Requirements 2.2**
      test('default rippleColor is white', () {
        final painter = RippleEffectPainter(
          targetRect: defaultRect,
          rippleProgress: 0.0,
        );

        expect(painter.rippleColor, equals(Colors.white));
      });
    });

    group('paint', () {
      /// **Validates: Requirements 2.2**
      /// Verifies painting does not throw at boundary progress values
      testWidgets('paints without error at progress boundaries',
          (WidgetTester tester) async {
        for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CustomPaint(
                  size: const Size(400, 400),
                  painter: RippleEffectPainter(
                    targetRect: defaultRect,
                    rippleProgress: progress,
                  ),
                ),
              ),
            ),
          );
        }
        // If we get here without exceptions, the test passes
      });

      /// **Validates: Requirements 2.2**
      /// Verifies painting works with a custom color
      testWidgets('paints without error with custom color',
          (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(400, 400),
                painter: RippleEffectPainter(
                  targetRect: defaultRect,
                  rippleProgress: 0.5,
                  rippleColor: Colors.blue,
                ),
              ),
            ),
          ),
        );
        // No exception means success
      });
    });
  });
}
