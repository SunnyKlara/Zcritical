import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcritical_t1/services/feature_guide_service.dart';

/// FeatureGuideService 属性测�?
/// 
/// **Feature: ux-experience-optimization, Property 2: Feature Guide State Round-Trip**
/// 
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
/// 
/// Property Description:
/// *For any* `GuideType` value, if `markGuideComplete(type)` is called, 
/// then `shouldShowGuide(type)` should return `false`. Before any completion 
/// is marked, `shouldShowGuide(type)` should return `true`.
void main() {
  group('FeatureGuideService', () {
    setUp(() {
      // 每个测试前重�?SharedPreferences 模拟�?
      SharedPreferences.setMockInitialValues({});
    });

    // ============================================================
    // Property 2: Feature Guide State Round-Trip
    // Feature: ux-experience-optimization, Property 2: Feature Guide State Round-Trip
    // ============================================================

    group('Property 2: Feature Guide State Round-Trip', () {
      /// **Validates: Requirements 3.1, 3.2, 3.3**
      /// 测试初始状态：所�?GuideType �?shouldShowGuide() 应返�?true
      test('initial state: shouldShowGuide returns true for all GuideTypes', () async {
        final service = FeatureGuideService();
        
        // 验证所�?GuideType 初始状态都应该显示引导
        for (final type in GuideType.values) {
          expect(await service.shouldShowGuide(type), true,
              reason: 'GuideType.${type.name} should show guide initially');
        }
      });

      /// **Validates: Requirements 3.1, 3.5**
      /// 测试 Running Mode 引导�?round-trip
      test('round-trip: runningMode - mark complete then check returns false', () async {
        final service = FeatureGuideService();
        
        // 初始状态应该显示引�?
        expect(await service.shouldShowGuide(GuideType.runningMode), true);
        
        // 标记完成
        await service.markGuideComplete(GuideType.runningMode);
        
        // 应该不再显示引导
        expect(await service.shouldShowGuide(GuideType.runningMode), false);
      });

      /// **Validates: Requirements 3.2, 3.5**
      /// 测试 Colorize Mode 引导�?round-trip
      test('round-trip: colorizeMode - mark complete then check returns false', () async {
        final service = FeatureGuideService();
        
        // 初始状态应该显示引�?
        expect(await service.shouldShowGuide(GuideType.colorizeMode), true);
        
        // 标记完成
        await service.markGuideComplete(GuideType.colorizeMode);
        
        // 应该不再显示引导
        expect(await service.shouldShowGuide(GuideType.colorizeMode), false);
      });

      /// **Validates: Requirements 3.3, 3.5**
      /// 测试 Logo Upload 引导�?round-trip
      test('round-trip: logoUpload - mark complete then check returns false', () async {
        final service = FeatureGuideService();
        
        // 初始状态应该显示引�?
        expect(await service.shouldShowGuide(GuideType.logoUpload), true);
        
        // 标记完成
        await service.markGuideComplete(GuideType.logoUpload);
        
        // 应该不再显示引导
        expect(await service.shouldShowGuide(GuideType.logoUpload), false);
      });

      /// **Validates: Requirements 3.5**
      /// 测试 Device Connect 引导�?round-trip
      test('round-trip: deviceConnect - mark complete then check returns false', () async {
        final service = FeatureGuideService();
        
        // 初始状态应该显示引�?
        expect(await service.shouldShowGuide(GuideType.deviceConnect), true);
        
        // 标记完成
        await service.markGuideComplete(GuideType.deviceConnect);
        
        // 应该不再显示引导
        expect(await service.shouldShowGuide(GuideType.deviceConnect), false);
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：对所�?GuideType 值进�?round-trip 验证
      /// 最�?100 次迭�?
      test('property: round-trip holds for all GuideTypes (100 iterations)', () async {
        final service = FeatureGuideService();
        
        // 对每�?GuideType 执行 100 次迭�?
        for (int iteration = 0; iteration < 100; iteration++) {
          // 重置所有引导状�?
          await service.resetAllGuides();
          
          // 验证所有类型初始状态都应该显示引导
          for (final type in GuideType.values) {
            expect(await service.shouldShowGuide(type), true,
                reason: 'Iteration $iteration: GuideType.${type.name} should show guide before marking complete');
          }
          
          // 逐个标记完成并验�?
          for (final type in GuideType.values) {
            await service.markGuideComplete(type);
            expect(await service.shouldShowGuide(type), false,
                reason: 'Iteration $iteration: GuideType.${type.name} should not show guide after marking complete');
          }
        }
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：标记一�?GuideType 完成不影响其他类�?
      test('property: marking one GuideType complete does not affect others', () async {
        final service = FeatureGuideService();
        
        // 对每�?GuideType 进行测试
        for (final targetType in GuideType.values) {
          // 重置所有引导状�?
          await service.resetAllGuides();
          
          // 只标记目标类型完�?
          await service.markGuideComplete(targetType);
          
          // 验证目标类型不再显示引导
          expect(await service.shouldShowGuide(targetType), false,
              reason: 'GuideType.${targetType.name} should not show guide after marking complete');
          
          // 验证其他类型仍然显示引导
          for (final otherType in GuideType.values) {
            if (otherType != targetType) {
              expect(await service.shouldShowGuide(otherType), true,
                  reason: 'GuideType.${otherType.name} should still show guide when only ${targetType.name} is marked complete');
            }
          }
        }
      });

      /// **Validates: Requirements 3.5**
      /// 属性测试：markGuideComplete 是幂等的
      test('property: markGuideComplete is idempotent (100 iterations)', () async {
        final service = FeatureGuideService();
        
        for (final type in GuideType.values) {
          // 重置状�?
          await service.resetAllGuides();
          
          // 初始状�?
          expect(await service.shouldShowGuide(type), true);
          
          // 多次调用 markGuideComplete
          for (int i = 0; i < 100; i++) {
            await service.markGuideComplete(type);
            expect(await service.shouldShowGuide(type), false,
                reason: 'Call $i for GuideType.${type.name}: should remain false after multiple markGuideComplete calls');
          }
        }
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：resetAllGuides 后所有类型恢复初始状�?
      test('property: resetAllGuides restores initial state for all types', () async {
        final service = FeatureGuideService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 标记所有类型完�?
          for (final type in GuideType.values) {
            await service.markGuideComplete(type);
          }
          
          // 验证所有类型都不显示引�?
          for (final type in GuideType.values) {
            expect(await service.shouldShowGuide(type), false,
                reason: 'Iteration $iteration: GuideType.${type.name} should not show guide after marking complete');
          }
          
          // 重置所有引�?
          await service.resetAllGuides();
          
          // 验证所有类型恢复显示引�?
          for (final type in GuideType.values) {
            expect(await service.shouldShowGuide(type), true,
                reason: 'Iteration $iteration: GuideType.${type.name} should show guide after reset');
          }
        }
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：不同 FeatureGuideService 实例共享状�?
      test('property: different instances share state via SharedPreferences', () async {
        final service1 = FeatureGuideService();
        final service2 = FeatureGuideService();
        
        for (final type in GuideType.values) {
          // 重置状�?
          await service1.resetAllGuides();
          
          // 初始状态两个实例都应该返回 true
          expect(await service1.shouldShowGuide(type), true);
          expect(await service2.shouldShowGuide(type), true);
          
          // 通过 service1 标记完成
          await service1.markGuideComplete(type);
          
          // 两个实例都应该返�?false
          expect(await service1.shouldShowGuide(type), false);
          expect(await service2.shouldShowGuide(type), false);
          
          // 通过 service2 重置
          await service2.resetAllGuides();
          
          // 两个实例都应该返�?true
          expect(await service1.shouldShowGuide(type), true);
          expect(await service2.shouldShowGuide(type), true);
        }
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：完整状态转换覆�?
      test('property: complete state transition coverage for all GuideTypes', () async {
        final service = FeatureGuideService();
        
        for (final type in GuideType.values) {
          // 重置状�?
          await service.resetAllGuides();
          
          // 状�?A: 初始状�?(shouldShowGuide = true)
          expect(await service.shouldShowGuide(type), true,
              reason: 'GuideType.${type.name}: initial state should show guide');
          
          // 转换 A -> B: markGuideComplete
          await service.markGuideComplete(type);
          
          // 状�?B: 已完成状�?(shouldShowGuide = false)
          expect(await service.shouldShowGuide(type), false,
              reason: 'GuideType.${type.name}: after marking complete should not show guide');
          
          // 转换 B -> A: resetAllGuides
          await service.resetAllGuides();
          
          // 回到状�?A
          expect(await service.shouldShowGuide(type), true,
              reason: 'GuideType.${type.name}: after reset should show guide again');
          
          // 验证从状�?A 调用 resetAllGuides 仍然保持状�?A
          await service.resetAllGuides();
          expect(await service.shouldShowGuide(type), true,
              reason: 'GuideType.${type.name}: reset on initial state should remain showing guide');
          
          // 转换到状�?B
          await service.markGuideComplete(type);
          expect(await service.shouldShowGuide(type), false,
              reason: 'GuideType.${type.name}: after marking complete should not show guide');
          
          // 验证从状�?B 调用 markGuideComplete 仍然保持状�?B
          await service.markGuideComplete(type);
          expect(await service.shouldShowGuide(type), false,
              reason: 'GuideType.${type.name}: multiple markGuideComplete calls should remain not showing guide');
        }
      });

      /// **Validates: Requirements 3.1, 3.2, 3.3, 3.5**
      /// 属性测试：随机顺序标记完成的一致�?
      test('property: marking complete in any order maintains consistency (100 iterations)', () async {
        final service = FeatureGuideService();
        final types = GuideType.values.toList();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 重置所有引导状�?
          await service.resetAllGuides();
          
          // 使用不同的顺序标记完成（通过旋转列表模拟不同顺序�?
          final rotatedTypes = [...types.sublist(iteration % types.length), ...types.sublist(0, iteration % types.length)];
          
          // 逐个标记完成
          for (int i = 0; i < rotatedTypes.length; i++) {
            final type = rotatedTypes[i];
            
            // 标记前应该显示引�?
            expect(await service.shouldShowGuide(type), true,
                reason: 'Iteration $iteration: GuideType.${type.name} should show guide before marking');
            
            await service.markGuideComplete(type);
            
            // 标记后不应该显示引导
            expect(await service.shouldShowGuide(type), false,
                reason: 'Iteration $iteration: GuideType.${type.name} should not show guide after marking');
            
            // 验证之前标记的类型仍然不显示引导
            for (int j = 0; j < i; j++) {
              expect(await service.shouldShowGuide(rotatedTypes[j]), false,
                  reason: 'Iteration $iteration: Previously marked GuideType.${rotatedTypes[j].name} should still not show guide');
            }
            
            // 验证之后未标记的类型仍然显示引导
            for (int j = i + 1; j < rotatedTypes.length; j++) {
              expect(await service.shouldShowGuide(rotatedTypes[j]), true,
                  reason: 'Iteration $iteration: Not yet marked GuideType.${rotatedTypes[j].name} should still show guide');
            }
          }
        }
      });
    });

    // ============================================================
    // 边界情况测试
    // ============================================================

    group('Edge Cases', () {
      /// 测试带有预设值的 SharedPreferences
      test('handles pre-existing completed state', () async {
        // 模拟已完成部分引导的状�?
        SharedPreferences.setMockInitialValues({
          'feature_guide_runningMode': true,
          'feature_guide_colorizeMode': true,
        });
        
        final service = FeatureGuideService();
        
        // 已完成的类型不应该显示引�?
        expect(await service.shouldShowGuide(GuideType.runningMode), false);
        expect(await service.shouldShowGuide(GuideType.colorizeMode), false);
        
        // 未完成的类型应该显示引导
        expect(await service.shouldShowGuide(GuideType.logoUpload), true);
        expect(await service.shouldShowGuide(GuideType.deviceConnect), true);
      });

      /// 测试所有类型都已完成的状�?
      test('handles all guides completed state', () async {
        SharedPreferences.setMockInitialValues({
          'feature_guide_runningMode': true,
          'feature_guide_colorizeMode': true,
          'feature_guide_logoUpload': true,
          'feature_guide_deviceConnect': true,
        });
        
        final service = FeatureGuideService();
        
        // 所有类型都不应该显示引�?
        for (final type in GuideType.values) {
          expect(await service.shouldShowGuide(type), false,
              reason: 'GuideType.${type.name} should not show guide when pre-completed');
        }
      });

      /// 测试值为 false 的情况（显式设置为未完成�?
      test('handles explicit false values', () async {
        SharedPreferences.setMockInitialValues({
          'feature_guide_runningMode': false,
          'feature_guide_colorizeMode': false,
        });
        
        final service = FeatureGuideService();
        
        // 显式设置�?false 的类型应该显示引�?
        expect(await service.shouldShowGuide(GuideType.runningMode), true);
        expect(await service.shouldShowGuide(GuideType.colorizeMode), true);
      });

      /// 测试混合状�?
      test('handles mixed completion states', () async {
        SharedPreferences.setMockInitialValues({
          'feature_guide_runningMode': true,
          'feature_guide_colorizeMode': false,
          // logoUpload �?deviceConnect 未设�?
        });
        
        final service = FeatureGuideService();
        
        expect(await service.shouldShowGuide(GuideType.runningMode), false);
        expect(await service.shouldShowGuide(GuideType.colorizeMode), true);
        expect(await service.shouldShowGuide(GuideType.logoUpload), true);
        expect(await service.shouldShowGuide(GuideType.deviceConnect), true);
      });

      /// 测试 resetAllGuides 只清除功能引导相关的�?
      test('resetAllGuides only clears feature guide keys', () async {
        SharedPreferences.setMockInitialValues({
          'feature_guide_runningMode': true,
          'feature_guide_colorizeMode': true,
          'other_key': 'should_remain',
          'first_launch_complete': true,
        });
        
        final service = FeatureGuideService();
        await service.resetAllGuides();
        
        // 功能引导状态应该被重置
        expect(await service.shouldShowGuide(GuideType.runningMode), true);
        expect(await service.shouldShowGuide(GuideType.colorizeMode), true);
        
        // 其他键应该保持不�?
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('other_key'), 'should_remain');
        expect(prefs.getBool('first_launch_complete'), true);
      });
    });
  });
}
