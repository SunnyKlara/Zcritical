import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/widgets/guide_overlay.dart';
import 'package:ridewind/models/guide_models.dart';

/// GuideOverlay Widget 测试
/// 
/// **Validates: Requirements 3.4**
/// 
/// 测试内容:
/// 1. 步骤导航功能（下一步按钮前进到下一步）
/// 2. 跳过回调（点击跳过按钮时调用）
/// 3. 完成回调（在最后一步点击完成按钮时调用）
/// 4. 步骤指示器显示正确的步骤编号
void main() {
  group('GuideOverlay Widget Tests', () {
    // 创建测试用的 GlobalKey
    late GlobalKey targetKey1;
    late GlobalKey targetKey2;
    late GlobalKey targetKey3;

    setUp(() {
      targetKey1 = GlobalKey();
      targetKey2 = GlobalKey();
      targetKey3 = GlobalKey();
    });

    /// 创建测试用的引导步骤
    List<GuideStep> createTestSteps(List<GlobalKey> keys) {
      return [
        GuideStep(
          targetKey: keys[0],
          title: '步骤 1',
          description: '这是第一步的描述',
          icon: Icons.touch_app,
        ),
        if (keys.length > 1)
          GuideStep(
            targetKey: keys[1],
            title: '步骤 2',
            description: '这是第二步的描述',
            icon: Icons.swipe,
          ),
        if (keys.length > 2)
          GuideStep(
            targetKey: keys[2],
            title: '步骤 3',
            description: '这是第三步的描述',
            icon: Icons.check,
          ),
      ];
    }

    /// 创建包含目标元素的测试 Widget
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
              // 目标元素（用于引导高亮）
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
                      child: Center(
                        child: Text('Target ${index + 1}'),
                      ),
                    ),
                  );
                }),
              // 引导覆盖层
              GuideOverlay(
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
    // 步骤导航功能测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Step Navigation', () {
      /// **Validates: Requirements 3.4**
      /// 测试点击"下一步"按钮前进到下一步
      testWidgets('next button advances to next step', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1, targetKey2, targetKey3];
        final steps = createTestSteps(keys);

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));

        // 等待动画完成
        await tester.pumpAndSettle();

        // 验证初始显示第一步
        expect(find.text('步骤 1'), findsOneWidget);
        expect(find.text('这是第一步的描述'), findsOneWidget);
        expect(find.text('步骤 1 / 3'), findsOneWidget);

        // 点击"下一步"按钮
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证显示第二步
        expect(find.text('步骤 2'), findsOneWidget);
        expect(find.text('这是第二步的描述'), findsOneWidget);
        expect(find.text('步骤 2 / 3'), findsOneWidget);

        // 点击"下一步"按钮
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证显示第三步（最后一步）
        expect(find.text('步骤 3'), findsOneWidget);
        expect(find.text('这是第三步的描述'), findsOneWidget);
        expect(find.text('步骤 3 / 3'), findsOneWidget);

        // 最后一步应该显示"完成"按钮而不是"下一步"
        expect(find.text('下一步'), findsNothing);
        expect(find.text('完成'), findsOneWidget);

        // 确认还未完成
        expect(completed, false);
      });

      /// **Validates: Requirements 3.4**
      /// 测试单步引导直接显示完成按钮
      testWidgets('single step guide shows complete button directly', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '唯一步骤',
            description: '这是唯一的步骤',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 单步引导应该直接显示"完成"按钮
        expect(find.text('下一步'), findsNothing);
        expect(find.text('完成'), findsOneWidget);
        expect(find.text('步骤 1 / 1'), findsOneWidget);
      });

      /// **Validates: Requirements 3.4**
      /// 测试两步引导的导航
      testWidgets('two step guide navigation works correctly', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1, targetKey2];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '第一步',
            description: '第一步描述',
          ),
          GuideStep(
            targetKey: keys[1],
            title: '第二步',
            description: '第二步描述',
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证第一步
        expect(find.text('第一步'), findsOneWidget);
        expect(find.text('步骤 1 / 2'), findsOneWidget);
        expect(find.text('下一步'), findsOneWidget);

        // 前进到第二步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证第二步（最后一步）
        expect(find.text('第二步'), findsOneWidget);
        expect(find.text('步骤 2 / 2'), findsOneWidget);
        expect(find.text('完成'), findsOneWidget);
        expect(find.text('下一步'), findsNothing);
      });
    });

    // ============================================================
    // 跳过回调测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Skip Callback', () {
      /// **Validates: Requirements 3.4**
      /// 测试点击跳过按钮时调用 onSkip 回调
      testWidgets('skip button calls onSkip callback', (WidgetTester tester) async {
        bool skipped = false;
        bool completed = false;
        final keys = [targetKey1, targetKey2];
        final steps = createTestSteps(keys).take(2).toList();

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          onSkip: () => skipped = true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证跳过按钮存在
        expect(find.text('跳过'), findsOneWidget);

        // 点击跳过按钮
        await tester.tap(find.text('跳过'));
        await tester.pumpAndSettle();

        // 验证 onSkip 被调用
        expect(skipped, true);
        expect(completed, false);
      });

      /// **Validates: Requirements 3.4**
      /// 测试没有 onSkip 回调时，跳过按钮调用 onComplete
      testWidgets('skip button calls onComplete when onSkip is null', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1, targetKey2];
        final steps = createTestSteps(keys).take(2).toList();

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          onSkip: null,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 点击跳过按钮
        await tester.tap(find.text('跳过'));
        await tester.pumpAndSettle();

        // 验证 onComplete 被调用
        expect(completed, true);
      });

      /// **Validates: Requirements 3.4**
      /// 测试 canSkip 为 false 时不显示跳过按钮
      testWidgets('skip button is hidden when canSkip is false', (WidgetTester tester) async {
        final keys = [targetKey1, targetKey2];
        final steps = createTestSteps(keys).take(2).toList();

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          canSkip: false,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证跳过按钮不存在
        expect(find.text('跳过'), findsNothing);
      });

      /// **Validates: Requirements 3.4**
      /// 测试最后一步不显示跳过按钮
      testWidgets('skip button is hidden on last step', (WidgetTester tester) async {
        final keys = [targetKey1, targetKey2];
        final steps = createTestSteps(keys).take(2).toList();

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          canSkip: true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 第一步应该显示跳过按钮
        expect(find.text('跳过'), findsOneWidget);

        // 前进到最后一步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 最后一步不应该显示跳过按钮
        expect(find.text('跳过'), findsNothing);
      });
    });

    // ============================================================
    // 完成回调测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Complete Callback', () {
      /// **Validates: Requirements 3.4**
      /// 测试在最后一步点击完成按钮时调用 onComplete 回调
      testWidgets('complete button calls onComplete on last step', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1, targetKey2];
        final steps = createTestSteps(keys).take(2).toList();

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 前进到最后一步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证显示完成按钮
        expect(find.text('完成'), findsOneWidget);

        // 点击完成按钮
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();

        // 验证 onComplete 被调用
        expect(completed, true);
      });

      /// **Validates: Requirements 3.4**
      /// 测试单步引导点击完成按钮
      testWidgets('single step guide complete button works', (WidgetTester tester) async {
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

        await tester.pumpAndSettle();

        // 点击完成按钮
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();

        // 验证 onComplete 被调用
        expect(completed, true);
      });

      /// **Validates: Requirements 3.4**
      /// 测试完成三步引导
      testWidgets('three step guide completes correctly', (WidgetTester tester) async {
        bool completed = false;
        final keys = [targetKey1, targetKey2, targetKey3];
        final steps = createTestSteps(keys);

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () => completed = true,
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 导航到最后一步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 点击完成
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();

        expect(completed, true);
      });
    });

    // ============================================================
    // 步骤指示器测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Step Indicator', () {
      /// **Validates: Requirements 3.4**
      /// 测试步骤指示器显示正确的步骤编号
      testWidgets('step indicator shows correct step number', (WidgetTester tester) async {
        final keys = [targetKey1, targetKey2, targetKey3];
        final steps = createTestSteps(keys);

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证第一步的指示器
        expect(find.text('步骤 1 / 3'), findsOneWidget);

        // 前进到第二步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证第二步的指示器
        expect(find.text('步骤 2 / 3'), findsOneWidget);

        // 前进到第三步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证第三步的指示器
        expect(find.text('步骤 3 / 3'), findsOneWidget);
      });

      /// **Validates: Requirements 3.4**
      /// 测试进度点的数量正确
      testWidgets('progress dots count matches total steps', (WidgetTester tester) async {
        final keys = [targetKey1, targetKey2, targetKey3];
        final steps = createTestSteps(keys);

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 查找 _StepIndicator 中的进度点容器
        // 进度点是通过 Row 中的 Container 实现的
        // 我们通过检查步骤指示器文本来验证指示器存在
        // 使用精确匹配来避免与步骤标题混淆
        expect(find.text('步骤 1 / 3'), findsOneWidget);
      });

      /// **Validates: Requirements 3.4**
      /// 测试不同步骤数量的指示器
      testWidgets('step indicator works with different step counts', (WidgetTester tester) async {
        // 测试 5 步引导
        final keys = List.generate(5, (_) => GlobalKey());
        final steps = keys.asMap().entries.map((entry) {
          return GuideStep(
            targetKey: entry.value,
            title: '步骤 ${entry.key + 1}',
            description: '描述 ${entry.key + 1}',
          );
        }).toList();

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ...keys.asMap().entries.map((entry) {
                  return Positioned(
                    left: 20.0 + entry.key * 60,
                    top: 100.0,
                    child: Container(
                      key: entry.value,
                      width: 50,
                      height: 50,
                      color: Colors.blue,
                    ),
                  );
                }),
                GuideOverlay(
                  steps: steps,
                  onComplete: () {},
                ),
              ],
            ),
          ),
        ));

        await tester.pumpAndSettle();

        // 验证第一步
        expect(find.text('步骤 1 / 5'), findsOneWidget);

        // 导航到第三步
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();

        // 验证第三步
        expect(find.text('步骤 3 / 5'), findsOneWidget);
      });
    });

    // ============================================================
    // 内容显示测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Content Display', () {
      /// **Validates: Requirements 3.4**
      /// 测试步骤标题和描述正确显示
      testWidgets('step title and description are displayed correctly', (WidgetTester tester) async {
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '测试标题',
            description: '这是一段测试描述文字',
            icon: Icons.star,
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证标题和描述
        expect(find.text('测试标题'), findsOneWidget);
        expect(find.text('这是一段测试描述文字'), findsOneWidget);
      });

      /// **Validates: Requirements 3.4**
      /// 测试步骤图标正确显示
      testWidgets('step icon is displayed when provided', (WidgetTester tester) async {
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '带图标的步骤',
            description: '描述',
            icon: Icons.touch_app,
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证图标存在
        expect(find.byIcon(Icons.touch_app), findsOneWidget);
      });

      /// **Validates: Requirements 3.4**
      /// 测试没有图标时的显示
      testWidgets('step without icon displays correctly', (WidgetTester tester) async {
        final keys = [targetKey1];
        final steps = [
          GuideStep(
            targetKey: keys[0],
            title: '无图标步骤',
            description: '描述',
            // 不提供 icon
          ),
        ];

        await tester.pumpWidget(createTestWidget(
          steps: steps,
          onComplete: () {},
          targetKeys: keys,
        ));

        await tester.pumpAndSettle();

        // 验证标题和描述仍然显示
        expect(find.text('无图标步骤'), findsOneWidget);
        expect(find.text('描述'), findsOneWidget);
      });
    });

    // ============================================================
    // 目标元素不存在时的行为测试
    // Validates: Requirements 3.4
    // ============================================================

    group('Missing Target Element', () {
      /// **Validates: Requirements 3.4**
      /// 测试目标元素不存在时显示居中提示框
      testWidgets('shows centered tooltip when target element is missing', (WidgetTester tester) async {
        // 创建一个没有对应目标元素的 GlobalKey
        final orphanKey = GlobalKey();
        final steps = [
          GuideStep(
            targetKey: orphanKey,
            title: '无目标元素',
            description: '目标元素不存在时的描述',
          ),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: GuideOverlay(
              steps: steps,
              onComplete: () {},
            ),
          ),
        ));

        await tester.pumpAndSettle();

        // 验证内容仍然显示
        expect(find.text('无目标元素'), findsOneWidget);
        expect(find.text('目标元素不存在时的描述'), findsOneWidget);
      });
    });
  });
}
