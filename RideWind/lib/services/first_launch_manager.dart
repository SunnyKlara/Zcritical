import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动管理器
/// 负责检测和管理应用的首次启动状态
/// 
/// 该服务使用 SharedPreferences 持久化存储用户的引导完成状态，
/// 支持版本化的引导流程，当引导版本更新时会重新显示引导。
/// 
/// 使用示例:
/// ```dart
/// final manager = FirstLaunchManager();
/// 
/// // 检查是否需要显示引导
/// if (await manager.isFirstLaunch()) {
///   // 显示引导流程
/// }
/// 
/// // 用户完成引导后标记完成
/// await manager.markOnboardingComplete();
/// ```
class FirstLaunchManager {
  /// SharedPreferences 键：引导完成状态
  static const String _keyFirstLaunchComplete = 'first_launch_complete';
  
  /// SharedPreferences 键：引导版本号
  static const String _keyOnboardingVersion = 'onboarding_version';
  
  /// 当前引导版本号
  /// 当需要强制用户重新查看引导时，增加此版本号
  static const int _currentOnboardingVersion = 1;

  /// 检查是否为首次启动
  /// 
  /// 返回 `true` 表示需要显示引导流程，包括以下情况：
  /// - 用户从未完成过引导
  /// - 引导版本已更新，需要重新显示
  /// 
  /// 返回 `false` 表示用户已完成当前版本的引导，可以跳过引导流程
  /// 
  /// 如果读取 SharedPreferences 失败，默认返回 `true` 以确保新用户能看到引导
  Future<bool> isFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_keyFirstLaunchComplete) ?? false;
      final version = prefs.getInt(_keyOnboardingVersion) ?? 0;

      // 如果未完成或版本更新，需要显示引导
      return !completed || version < _currentOnboardingVersion;
    } catch (e) {
      // 出错时默认显示引导，确保新用户体验
      return true;
    }
  }

  /// 标记引导流程已完成
  /// 
  /// 将完成状态和当前版本号持久化存储到 SharedPreferences。
  /// 调用此方法后，`isFirstLaunch()` 将返回 `false`（除非版本号更新）。
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> markOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFirstLaunchComplete, true);
      await prefs.setInt(_keyOnboardingVersion, _currentOnboardingVersion);
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
      // 下次启动时会重新显示引导，这是可接受的降级行为
    }
  }

  /// 重置首次启动状态（用于测试和调试）
  /// 
  /// 清除所有引导相关的持久化数据，使 `isFirstLaunch()` 返回 `true`。
  /// 主要用于：
  /// - 开发调试时重新测试引导流程
  /// - 单元测试中重置状态
  /// 
  /// 如果清除失败，会静默处理错误。
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFirstLaunchComplete);
      await prefs.remove(_keyOnboardingVersion);
    } catch (e) {
      // 重置失败时静默处理
    }
  }
}
