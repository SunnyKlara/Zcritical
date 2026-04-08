import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/models/guide_models.dart';
import 'package:ridewind/widgets/finger_pointer_widget.dart';

/// FingerPointerWidget 单元测试
///
/// **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7**
///
/// 测试内容:
/// 1. calculatePosition 静态方法对所有 8 种手势类型的正确性
/// 2. 默认参数值
/// 3. Widget 渲染
void main() {
  group('FingerPointerWidget', () {
    final defaultRect = const Rect.fromLTWH(100, 100, 80, 60);

    group('calculatePosition - static method', () {
      group('tap gesture', () {
        /// **Validates: Requirements 4.1**
        test('at animation 0.0, finger is at target bottom (no bounce)', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.tap,
            defaultRect,
            0.0,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, equals(defaultRect.bottom));
        });

        test('at animation 1.0, finger moves up by bounceAmplitude', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.tap,
            defaultRect,
            1.0,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(
            pos.dy,
            equals(defaultRect.bottom - FingerPointerWidget.bounceAmplitude),
          );
        });

        test('at animation 0.5, finger moves up by half bounceAmplitude', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.tap,
            defaultRect,
            0.5,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(
            pos.dy,
            closeTo(defaultRect.bottom - FingerPointerWidget.bounceAmplitude * 0.5, 0.01),
          );
        });

        test('x stays constant across animation', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.tap, defaultRect, 0.0);
          final pos5 = FingerPointerWidget.calculatePosition(GestureType.tap, defaultRect, 0.5);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.tap, defaultRect, 1.0);
          expect(pos0.dx, equals(pos5.dx));
          expect(pos5.dx, equals(pos1.dx));
        });
      });

      group('longPress gesture', () {
        /// **Validates: Requirements 4.2**
        test('at animation 0.0, finger is at target bottom (not pressed)', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.longPress,
            defaultRect,
            0.0,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, equals(defaultRect.bottom));
        });

        test('at animation 0.25, finger is fully pressed down', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.longPress,
            defaultRect,
            0.25,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, equals(defaultRect.bottom + FingerPointerWidget.longPressDepth));
        });

        test('at animation 0.5, finger stays pressed (hold phase)', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.longPress,
            defaultRect,
            0.5,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, equals(defaultRect.bottom + FingerPointerWidget.longPressDepth));
        });

        test('at animation 0.75, finger is still pressed (end of hold)', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.longPress,
            defaultRect,
            0.75,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, equals(defaultRect.bottom + FingerPointerWidget.longPressDepth));
        });

        test('at animation 1.0, finger returns to start position', () {
          final pos = FingerPointerWidget.calculatePosition(
            GestureType.longPress,
            defaultRect,
            1.0,
          );
          expect(pos.dx, equals(defaultRect.center.dx));
          expect(pos.dy, closeTo(defaultRect.bottom, 0.01));
        });

        test('x stays constant across animation', () {
          for (final t in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]) {
            final pos = FingerPointerWidget.calculatePosition(
              GestureType.longPress,
              defaultRect,
              t,
            );
            expect(pos.dx, equals(defaultRect.center.dx));
          }
        });
      });

      group('swipeLeft gesture', () {
        /// **Validates: Requirements 4.3**
        test('x decreases as animation progresses', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 0.0);
          final pos5 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 0.5);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 1.0);
          expect(pos5.dx, lessThan(pos0.dx));
          expect(pos1.dx, lessThan(pos5.dx));
        });

        test('y stays at center', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 0.0);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 1.0);
          expect(pos0.dy, equals(defaultRect.center.dy));
          expect(pos1.dy, equals(defaultRect.center.dy));
        });

        test('total horizontal displacement is swipeDistance', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 0.0);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeLeft, defaultRect, 1.0);
          expect((pos0.dx - pos1.dx).abs(), closeTo(FingerPointerWidget.swipeDistance, 0.01));
        });
      });

      group('swipeRight gesture', () {
        /// **Validates: Requirements 4.4**
        test('x increases as animation progresses', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeRight, defaultRect, 0.0);
          final pos5 = FingerPointerWidget.calculatePosition(GestureType.swipeRight, defaultRect, 0.5);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeRight, defaultRect, 1.0);
          expect(pos5.dx, greaterThan(pos0.dx));
          expect(pos1.dx, greaterThan(pos5.dx));
        });

        test('y stays at center', () {
          final pos = FingerPointerWidget.calculatePosition(GestureType.swipeRight, defaultRect, 0.5);
          expect(pos.dy, equals(defaultRect.center.dy));
        });
      });

      group('swipeUp gesture', () {
        /// **Validates: Requirements 4.5**
        test('y decreases as animation progresses', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeUp, defaultRect, 0.0);
          final pos5 = FingerPointerWidget.calculatePosition(GestureType.swipeUp, defaultRect, 0.5);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeUp, defaultRect, 1.0);
          expect(pos5.dy, lessThan(pos0.dy));
          expect(pos1.dy, lessThan(pos5.dy));
        });

        test('x stays at center', () {
          final pos = FingerPointerWidget.calculatePosition(GestureType.swipeUp, defaultRect, 0.5);
          expect(pos.dx, equals(defaultRect.center.dx));
        });
      });

      group('swipeDown gesture', () {
        /// **Validates: Requirements 4.5**
        test('y increases as animation progresses', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.swipeDown, defaultRect, 0.0);
          final pos5 = FingerPointerWidget.calculatePosition(GestureType.swipeDown, defaultRect, 0.5);
          final pos1 = FingerPointerWidget.calculatePosition(GestureType.swipeDown, defaultRect, 1.0);
          expect(pos5.dy, greaterThan(pos0.dy));
          expect(pos1.dy, greaterThan(pos5.dy));
        });

        test('x stays at center', () {
          final pos = FingerPointerWidget.calculatePosition(GestureType.swipeDown, defaultRect, 0.5);
          expect(pos.dx, equals(defaultRect.center.dx));
        });
      });

      group('dragHorizontal gesture', () {
        /// **Validates: Requirements 4.6**
        test('x varies with sin curve (oscillates)', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.dragHorizontal, defaultRect, 0.0);
          final pos25 = FingerPointerWidget.calculatePosition(GestureType.dragHorizontal, defaultRect, 0.25);
          final pos50 = FingerPointerWidget.calculatePosition(GestureType.dragHorizontal, defaultRect, 0.5);
          final pos75 = FingerPointerWidget.calculatePosition(GestureType.dragHorizontal, defaultRect, 0.75);

          // At 0.0: sin(0) = 0, at center
          expect(pos0.dx, closeTo(defaultRect.center.dx, 0.01));
          // At 0.25: sin(π/2) = 1, max right
          expect(pos25.dx, closeTo(defaultRect.center.dx + FingerPointerWidget.dragDistance, 0.01));
          // At 0.5: sin(π) ≈ 0, back to center
          expect(pos50.dx, closeTo(defaultRect.center.dx, 0.01));
          // At 0.75: sin(3π/2) = -1, max left
          expect(pos75.dx, closeTo(defaultRect.center.dx - FingerPointerWidget.dragDistance, 0.01));
        });

        test('y stays at center', () {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final pos = FingerPointerWidget.calculatePosition(GestureType.dragHorizontal, defaultRect, t);
            expect(pos.dy, equals(defaultRect.center.dy));
          }
        });
      });

      group('dragVertical gesture', () {
        /// **Validates: Requirements 4.7**
        test('y varies with sin curve (oscillates)', () {
          final pos0 = FingerPointerWidget.calculatePosition(GestureType.dragVertical, defaultRect, 0.0);
          final pos25 = FingerPointerWidget.calculatePosition(GestureType.dragVertical, defaultRect, 0.25);
          final pos50 = FingerPointerWidget.calculatePosition(GestureType.dragVertical, defaultRect, 0.5);
          final pos75 = FingerPointerWidget.calculatePosition(GestureType.dragVertical, defaultRect, 0.75);

          // At 0.0: sin(0) = 0, at center
          expect(pos0.dy, closeTo(defaultRect.center.dy, 0.01));
          // At 0.25: sin(π/2) = 1, max down
          expect(pos25.dy, closeTo(defaultRect.center.dy + FingerPointerWidget.dragDistance, 0.01));
          // At 0.5: sin(π) ≈ 0, back to center
          expect(pos50.dy, closeTo(defaultRect.center.dy, 0.01));
          // At 0.75: sin(3π/2) = -1, max up
          expect(pos75.dy, closeTo(defaultRect.center.dy - FingerPointerWidget.dragDistance, 0.01));
        });

        test('x stays at center', () {
          for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            final pos = FingerPointerWidget.calculatePosition(GestureType.dragVertical, defaultRect, t);
            expect(pos.dx, equals(defaultRect.center.dx));
          }
        });
      });
    });

    group('default values', () {
      test('default gestureType is tap', () {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 800),
        );
        addTearDown(controller.dispose);

        final widget = FingerPointerWidget(
          targetRect: defaultRect,
          bounceAnimation: controller,
        );

        expect(widget.gestureType, equals(GestureType.tap));
      });

      test('default color is white', () {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 800),
        );
        addTearDown(controller.dispose);

        final widget = FingerPointerWidget(
          targetRect: defaultRect,
          bounceAnimation: controller,
        );

        expect(widget.color, equals(Colors.white));
      });

      test('default icon size is 64', () {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 800),
        );
        addTearDown(controller.dispose);

        final widget = FingerPointerWidget(
          targetRect: defaultRect,
          bounceAnimation: controller,
        );

        expect(widget.iconSize, equals(64.0));
      });

      test('bounce amplitude is 14px', () {
        expect(FingerPointerWidget.bounceAmplitude, equals(14.0));
      });

      test('swipe distance is 100px', () {
        expect(FingerPointerWidget.swipeDistance, equals(100.0));
      });

      test('drag distance is 70px', () {
        expect(FingerPointerWidget.dragDistance, equals(70.0));
      });
    });

    group('rendering', () {
      testWidgets('renders emoji finger pointer', (WidgetTester tester) async {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 800),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FingerPointerWidget(
                    targetRect: defaultRect,
                    bounceAnimation: controller,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('👆'), findsOneWidget);
      });

      testWidgets('animates bounce for tap gesture', (WidgetTester tester) async {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 800),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FingerPointerWidget(
                    targetRect: defaultRect,
                    bounceAnimation: controller,
                    gestureType: GestureType.tap,
                  ),
                ],
              ),
            ),
          ),
        );

        var positioned = tester.widget<Positioned>(find.byType(Positioned));
        final initialTop = positioned.top!;

        controller.value = 1.0;
        await tester.pump();

        positioned = tester.widget<Positioned>(find.byType(Positioned));
        final endTop = positioned.top!;

        expect(initialTop - endTop, closeTo(FingerPointerWidget.bounceAmplitude, 0.01));
      });

      testWidgets('renders with swipeLeft gesture type', (WidgetTester tester) async {
        final controller = AnimationController(
          vsync: const TestVSync(),
          duration: const Duration(milliseconds: 1000),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FingerPointerWidget(
                    targetRect: defaultRect,
                    bounceAnimation: controller,
                    gestureType: GestureType.swipeLeft,
                  ),
                ],
              ),
            ),
          ),
        );

        var positioned = tester.widget<Positioned>(find.byType(Positioned));
        final initialLeft = positioned.left!;

        controller.value = 1.0;
        await tester.pump();

        positioned = tester.widget<Positioned>(find.byType(Positioned));
        final endLeft = positioned.left!;

        // swipeLeft: x should decrease
        expect(endLeft, lessThan(initialLeft));
      });
    });
  });
}
