import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcritical_t1/widgets/enhanced_guide_overlay.dart';
import 'package:zcritical_t1/models/guide_models.dart';

/// EnhancedGuideOverlay Widget 测试
///
/// 新流程：演示阶段（系统自动操作）�?用户上手阶段（自由探索）�?用户点击下一�?
void main() {
  group('EnhancedGuideOverlay', () {
    late GlobalKey targetKey1;
    late GlobalKey targetKey2;

    setUp(() {
      targetKey1 = GlobalKey();
      targetKey2 = GlobalKey();
    });

    /// Helper: pump for fade animation + post-frame callback
    Future<void> pumpForAnimations(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Helper: pump for _waitForTarget timeout
    Future<void> pumpForWaitTimeout(WidgetTester tester,
        {int steps = 1}) async {
      for (int i = 0; i < steps; i++) {
        for (int j = 0; j < 22; j++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// Helper: pump through demo phase (no demoAction �?3500ms wait)
    /// then into userTrying phase
    Future<void> pumpThroughDemo(WidgetTester tester) async {
      // 1000ms initial delay + 3500ms no-demoAction wait + buffer
      for (int i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Helper: pump through demo phase with demoAction
    Future<void> pumpThroughDemoWithAction(WidgetTester tester) async {
      // 1000ms pre-delay + demoAction * 3 repeats + 1200ms gaps + 1000ms post
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Helper: pump for step transition
    Future<void> pumpForTransition(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
    }

    Widget createTestWidget({
      required List<GuideStep> steps,
      required VoidCallback onComplete,
      VoidCallback? onSkip,
      bool canSkip = true,
      List<GlobalKey>? targetKeys,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              if (targetKeys != null)
                ...targetKeys.asMap().entries.map((entry) {
                  final index = entry.key;
                  final key = entry.value;
                  return Positioned(
                    left: 50.0 + index * 100,
                    top: 100.0,
                    child: Container(
                      key: key,
                      width: 80,
                      height: 80,
                      color: Colors.blue,
                      child: Center(child: Text('Target ${index + 1}')),
                    ),
                  );
                }),
              EnhancedGuideOverlay(
                steps: steps,
                onComplete: onComplete,
                onSkip: onSkip,
                canSkip: canSkip,
              ),
            ],
          ),
        ),
      );
    }

    // ============================================================
    // 演示 �?用户上手 �?手动推进
    // ============================================================
    group('Demo �?User Trying �?Manual Advance', () {
      testWidgets('demo phase shows tooltip, then user trying shows continue',
          (tester) async {
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述 1',
            gestureType: GestureType.tap,
          ),
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '描述 2',
            gestureType: GestureType.tap,
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);

        // Demo phase: tooltip visible
        expect(find.text('描述 1'), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget);

        // Pump through demo �?user trying
        await pumpThroughDemo(tester);

        // User trying: continue button visible
        expect(find.text('下一�?), findsOneWidget);
        expect(find.text('试试看，自由操作体验一�?), findsOneWidget);
      });

      testWidgets('tapping continue advances to next step', (tester) async {
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述 1',
          ),
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '描述 2',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);
        await pumpThroughDemo(tester);

        // Tap continue
        await tester.tap(find.text('下一�?));
        await pumpForTransition(tester);
        // Pump through next step's demo phase too
        await pumpThroughDemo(tester);

        // Step 2 user trying phase
        expect(find.text('下一�?), findsNothing); // last step shows '完成'
        expect(find.text('完成'), findsOneWidget);
      });

      testWidgets('last step shows complete button', (tester) async {
        bool completed = false;
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '唯一步骤',
            description: '描述',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);
        await pumpThroughDemo(tester);

        // Last step �?"完成" button
        expect(find.text('完成'), findsOneWidget);

        await tester.tap(find.text('完成'));
        await pumpForTransition(tester);

        expect(completed, true);
      });

      testWidgets('demoAction is called during demo phase', (tester) async {
        int demoCallCount = 0;
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述',
            demoAction: () async {
              demoCallCount++;
            },
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);
        // Pump through full demo: 1000ms pre + (action + 1200ms gap) * 3 + 1000ms post
        for (int i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // demoAction should be called 3 times (repeat count)
        expect(demoCallCount, 3);
      });
    });

    // ============================================================
    // 跳过回调测试
    // ============================================================
    group('Skip Callback', () {
      testWidgets('skip button calls onSkip during demo phase',
          (tester) async {
        bool skipped = false;
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述 1',
          ),
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '描述 2',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          onSkip: () => skipped = true,
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);

        await tester.tap(find.text('跳过引导'));
        await pumpForTransition(tester);
        // Pump through remaining demo timer
        await pumpThroughDemo(tester);

        expect(skipped, true);
      });

      testWidgets('skip in user trying phase works', (tester) async {
        bool skipped = false;
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述 1',
          ),
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '描述 2',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          onSkip: () => skipped = true,
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);
        await pumpThroughDemo(tester);

        // Skip in user trying bar
        await tester.tap(find.text('跳过'));
        await pumpForTransition(tester);

        expect(skipped, true);
      });

      testWidgets('skip hidden when canSkip is false', (tester) async {
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述 1',
          ),
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '描述 2',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          canSkip: false,
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);

        expect(find.text('跳过引导'), findsNothing);

        // Pump through demo timer to avoid pending timer error
        await pumpThroughDemo(tester);
      });
    });

    // ============================================================
    // 步骤跳过逻辑测试（不可定位步骤）
    // ============================================================
    group('Step Skipping', () {
      testWidgets('calls onComplete when all steps are non-locatable',
          (tester) async {
        bool completed = false;
        final orphanKey1 = GlobalKey();
        final orphanKey2 = GlobalKey();
        final steps = [
          GuideStep(
            targetKey: orphanKey1,
            title: '不可�?1',
            description: '描述',
          ),
          GuideStep(
            targetKey: orphanKey2,
            title: '不可�?2',
            description: '描述',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
        ));
        await tester.pump();
        await pumpForWaitTimeout(tester, steps: 2);

        expect(completed, true);
      });
    });

    // ============================================================
    // 动画组件测试
    // ============================================================
    group('Animation Components', () {
      testWidgets('renders finger pointer and mask during demo',
          (tester) async {
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);

        // FingerPointerWidget uses emoji '👆'
        expect(find.text('👆'), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);

        // Pump through demo to avoid pending timer
        await pumpThroughDemo(tester);
      });

      testWidgets('no mask during user trying phase', (tester) async {
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '步骤 1',
            description: '描述',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));
        await pumpForAnimations(tester);
        await pumpThroughDemo(tester);

        // Finger pointer should be gone
        expect(find.text('👆'), findsNothing);
        // Continue button should be visible
        expect(find.text('完成'), findsOneWidget);
      });
    });

    // ============================================================
    // showEnhancedGuideOverlay 便捷方法测试
    // ============================================================
    group('showEnhancedGuideOverlay', () {
      testWidgets('empty steps calls onComplete immediately',
          (tester) async {
        bool completed = false;

        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showEnhancedGuideOverlay(
                    context: context,
                    steps: [],
                    onComplete: () => completed = true,
                  );
                },
                child: const Text('Show'),
              );
            },
          ),
        ));

        await tester.tap(find.text('Show'));
        await tester.pumpAndSettle();

        expect(completed, true);
      });
    });
  });

  // ============================================================
  // Tooltip 定位逻辑单元测试
  // ============================================================
  group('calculateTooltipPosition', () {
    const tooltipSize = Size(300, 120);
    const screenSize = Size(400, 800);

    test('target in upper half �?tooltip below target', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(100, 100, 80, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
      );
      expect(position.dy, greaterThan(140.0));
    });

    test('target in lower half �?tooltip above target', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(100, 600, 80, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
      );
      expect(position.dy + tooltipSize.height, lessThan(600.0));
    });

    test('tooltip horizontally centered on target', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(150, 100, 80, 40),
        screenSize: screenSize,
        tooltipSize: const Size(100, 80),
      );
      expect(position.dx + 50, closeTo(190.0, 0.1));
    });

    test('tooltip clamped to left screen edge', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(0, 100, 20, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
      );
      expect(position.dx, greaterThanOrEqualTo(16.0));
    });

    test('tooltip clamped to right screen edge', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(380, 100, 20, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
      );
      expect(
        position.dx + tooltipSize.width,
        lessThanOrEqualTo(400 - 16.0),
      );
    });

    test('tooltip stays within screen bounds vertically', () {
      final position = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(100, 100, 80, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
      );
      expect(position.dy, greaterThanOrEqualTo(16.0));
      expect(
        position.dy + tooltipSize.height,
        lessThanOrEqualTo(800 - 16.0),
      );
    });

    test('minimum spacing maintained', () {
      const minSpacing = 80.0;

      final posBelow = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(100, 100, 80, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
        minSpacing: minSpacing,
      );
      expect(posBelow.dy - 140.0, greaterThanOrEqualTo(minSpacing));

      final posAbove = calculateTooltipPosition(
        targetRect: const Rect.fromLTWH(100, 600, 80, 40),
        screenSize: screenSize,
        tooltipSize: tooltipSize,
        minSpacing: minSpacing,
      );
      expect(
        600.0 - (posAbove.dy + tooltipSize.height),
        greaterThanOrEqualTo(minSpacing),
      );
    });
  });
}
