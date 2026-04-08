import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridewind/services/first_launch_manager.dart';

/// FirstLaunchManager 属性测试
/// 
/// **Feature: ux-experience-optimization, Property 1: First Launch State Round-Trip**
/// 
/// **Validates: Requirements 1.1, 1.2, 1.4**
/// 
/// Property Description:
/// *For any* application state, if `markOnboardingComplete()` is called, 
/// then `isFirstLaunch()` should return `false`. Conversely, after `reset()` 
/// is called, `isFirstLaunch()` should return `true`.
void main() {
  group('FirstLaunchManager', () {
    setUp(() {
      // 每个测试前重置 SharedPreferences 模拟值
      SharedPreferences.setMockInitialValues({});
    });

    // ============================================================
    // Property 1: First Launch State Round-Trip
    // Feature: ux-experience-optimization, Property 1: First Launch State Round-Trip
    // ============================================================

    group('Property 1: First Launch State Round-Trip', () {
      /// **Validates: Requirements 1.1**
      /// 测试初始状态：首次启动时 isFirstLaunch() 应返回 true
      test('initial state: isFirstLaunch returns true for fresh install', () async {
        final manager = FirstLaunchManager();
        
        // 初始状态应该是首次启动
        expect(await manager.isFirstLaunch(), true);
      });

      /// **Validates: Requirements 1.2**
      /// 测试 round-trip: markOnboardingComplete() 后 isFirstLaunch() 返回 false
      test('round-trip: mark complete then check returns false', () async {
        final manager = FirstLaunchManager();
        
        // 初始状态应该是首次启动
        expect(await manager.isFirstLaunch(), true);
        
        // 标记完成
        await manager.markOnboardingComplete();
        
        // 应该不再是首次启动
        expect(await manager.isFirstLaunch(), false);
      });

      /// **Validates: Requirements 1.4**
      /// 测试 round-trip: reset() 后 isFirstLaunch() 返回 true
      test('round-trip: reset then check returns true', () async {
        final manager = FirstLaunchManager();
        
        // 先标记完成
        await manager.markOnboardingComplete();
        expect(await manager.isFirstLaunch(), false);
        
        // 重置
        await manager.reset();
        
        // 应该恢复为首次启动
        expect(await manager.isFirstLaunch(), true);
      });

      /// **Validates: Requirements 1.1, 1.2, 1.4**
      /// 属性测试：多次 round-trip 循环验证状态一致性
      /// 对于任意次数的 mark/reset 循环，状态应保持一致
      test('property: multiple round-trips maintain state consistency', () async {
        final manager = FirstLaunchManager();
        
        // 执行多次 round-trip 循环
        for (int i = 0; i < 100; i++) {
          // 初始或重置后应该是首次启动
          expect(await manager.isFirstLaunch(), true,
              reason: 'Iteration $i: should be first launch before marking complete');
          
          // 标记完成后不再是首次启动
          await manager.markOnboardingComplete();
          expect(await manager.isFirstLaunch(), false,
              reason: 'Iteration $i: should not be first launch after marking complete');
          
          // 重置后恢复为首次启动
          await manager.reset();
        }
        
        // 最终状态验证
        expect(await manager.isFirstLaunch(), true);
      });

      /// **Validates: Requirements 1.2**
      /// 属性测试：多次调用 markOnboardingComplete() 应该是幂等的
      test('property: markOnboardingComplete is idempotent', () async {
        final manager = FirstLaunchManager();
        
        // 初始状态
        expect(await manager.isFirstLaunch(), true);
        
        // 多次调用 markOnboardingComplete
        for (int i = 0; i < 100; i++) {
          await manager.markOnboardingComplete();
          expect(await manager.isFirstLaunch(), false,
              reason: 'Call $i: should remain false after multiple markOnboardingComplete calls');
        }
      });

      /// **Validates: Requirements 1.4**
      /// 属性测试：多次调用 reset() 应该是幂等的
      test('property: reset is idempotent', () async {
        final manager = FirstLaunchManager();
        
        // 先标记完成
        await manager.markOnboardingComplete();
        expect(await manager.isFirstLaunch(), false);
        
        // 多次调用 reset
        for (int i = 0; i < 100; i++) {
          await manager.reset();
          expect(await manager.isFirstLaunch(), true,
              reason: 'Call $i: should remain true after multiple reset calls');
        }
      });

      /// **Validates: Requirements 1.1, 1.2**
      /// 属性测试：不同 FirstLaunchManager 实例共享状态
      /// 因为状态存储在 SharedPreferences 中，不同实例应该看到相同状态
      test('property: different instances share state via SharedPreferences', () async {
        final manager1 = FirstLaunchManager();
        final manager2 = FirstLaunchManager();
        
        // 初始状态两个实例都应该返回 true
        expect(await manager1.isFirstLaunch(), true);
        expect(await manager2.isFirstLaunch(), true);
        
        // 通过 manager1 标记完成
        await manager1.markOnboardingComplete();
        
        // 两个实例都应该返回 false
        expect(await manager1.isFirstLaunch(), false);
        expect(await manager2.isFirstLaunch(), false);
        
        // 通过 manager2 重置
        await manager2.reset();
        
        // 两个实例都应该返回 true
        expect(await manager1.isFirstLaunch(), true);
        expect(await manager2.isFirstLaunch(), true);
      });

      /// **Validates: Requirements 1.1, 1.2, 1.4**
      /// 属性测试：状态转换的完整性
      /// 验证所有可能的状态转换路径
      test('property: complete state transition coverage', () async {
        final manager = FirstLaunchManager();
        
        // 状态 A: 初始状态 (isFirstLaunch = true)
        expect(await manager.isFirstLaunch(), true);
        
        // 转换 A -> B: markOnboardingComplete
        await manager.markOnboardingComplete();
        
        // 状态 B: 已完成状态 (isFirstLaunch = false)
        expect(await manager.isFirstLaunch(), false);
        
        // 转换 B -> A: reset
        await manager.reset();
        
        // 回到状态 A
        expect(await manager.isFirstLaunch(), true);
        
        // 验证从状态 A 调用 reset 仍然保持状态 A
        await manager.reset();
        expect(await manager.isFirstLaunch(), true);
        
        // 转换到状态 B
        await manager.markOnboardingComplete();
        expect(await manager.isFirstLaunch(), false);
        
        // 验证从状态 B 调用 markOnboardingComplete 仍然保持状态 B
        await manager.markOnboardingComplete();
        expect(await manager.isFirstLaunch(), false);
      });
    });

    // ============================================================
    // 边界情况测试
    // ============================================================

    group('Edge Cases', () {
      /// 测试带有预设值的 SharedPreferences
      test('handles pre-existing completed state', () async {
        // 模拟已完成引导的状态
        SharedPreferences.setMockInitialValues({
          'first_launch_complete': true,
          'onboarding_version': 1,
        });
        
        final manager = FirstLaunchManager();
        expect(await manager.isFirstLaunch(), false);
      });

      /// 测试版本号为 0 的情况（旧版本）
      test('handles old version requiring re-onboarding', () async {
        // 模拟旧版本完成状态
        SharedPreferences.setMockInitialValues({
          'first_launch_complete': true,
          'onboarding_version': 0,
        });
        
        final manager = FirstLaunchManager();
        // 版本号低于当前版本，应该需要重新引导
        expect(await manager.isFirstLaunch(), true);
      });

      /// 测试只有 first_launch_complete 没有版本号的情况
      test('handles missing version number', () async {
        SharedPreferences.setMockInitialValues({
          'first_launch_complete': true,
        });
        
        final manager = FirstLaunchManager();
        // 没有版本号默认为 0，低于当前版本，需要重新引导
        expect(await manager.isFirstLaunch(), true);
      });

      /// 测试只有版本号没有 first_launch_complete 的情况
      test('handles missing completion flag', () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_version': 1,
        });
        
        final manager = FirstLaunchManager();
        // 没有完成标志，应该是首次启动
        expect(await manager.isFirstLaunch(), true);
      });
    });
  });
}
