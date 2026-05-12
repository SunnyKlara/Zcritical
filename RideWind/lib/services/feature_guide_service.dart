import 'package:shared_preferences/shared_preferences.dart';

/// 功能引导类型枚举
/// 
/// 定义应用中需要新手引导的各个功能模块
enum GuideType {
  /// Running Mode 操作引导
  /// 包含速度控制、雾化器开关等操作提示
  runningMode,
  
  /// Colorize Mode 操作引导
  /// 包含颜色预设选择、详细调色等操作提示
  colorizeMode,
  
  /// Logo 上传引导
  /// 包含图片选择、裁剪、上传流程的操作提示
  logoUpload,
  
  /// 设备连接引导
  /// 包含蓝牙扫描、设备配对等操作提示
  deviceConnect,
}

/// 功能引导服务
/// 
/// 管理各功能模块的新手引导状态和显示逻辑。
/// 使用 SharedPreferences 持久化存储每个功能的引导完成状态，
/// 确保用户只在首次使用某功能时看到引导提示。
/// 
/// 使用示例:
/// ```dart
/// final guideService = FeatureGuideService();
/// 
/// // 检查是否需要显示 Running Mode 引导
/// if (await guideService.shouldShowGuide(GuideType.runningMode)) {
///   // 显示引导覆盖层
/// }
/// 
/// // 用户完成引导后标记完成
/// await guideService.markGuideComplete(GuideType.runningMode);
/// ```
class FeatureGuideService {
  /// SharedPreferences 键前缀
  /// 每个功能的完成状态键为: feature_guide_{功能名}
  static const String _keyPrefix = 'feature_guide_';

  /// 检查指定功能是否需要显示引导
  /// 
  /// [type] 要检查的功能引导类型
  /// 
  /// 返回 `true` 表示该功能的引导尚未完成，需要显示引导。
  /// 返回 `false` 表示用户已完成该功能的引导，不需要再次显示。
  /// 
  /// 如果读取 SharedPreferences 失败，默认返回 `true` 以确保新用户能看到引导。
  Future<bool> shouldShowGuide(GuideType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 如果键不存在或值为 false，表示未完成引导，需要显示
      return !(prefs.getBool('$_keyPrefix${type.name}') ?? false);
    } catch (e) {
      // 出错时默认显示引导，确保新用户体验
      return true;
    }
  }

  /// 标记指定功能的引导已完成
  /// 
  /// [type] 要标记完成的功能引导类型
  /// 
  /// 将该功能的完成状态持久化存储到 SharedPreferences。
  /// 调用此方法后，`shouldShowGuide(type)` 将返回 `false`。
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> markGuideComplete(GuideType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_keyPrefix${type.name}', true);
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
      // 下次进入该功能时会重新显示引导，这是可接受的降级行为
    }
  }

  /// 重置所有功能引导状态
  /// 
  /// 清除所有功能的引导完成状态，使所有 `shouldShowGuide()` 调用返回 `true`。
  /// 主要用于：
  /// - 开发调试时重新测试引导流程
  /// - 单元测试中重置状态
  /// - 用户主动选择重新查看所有引导（如设置页面中的选项）
  /// 
  /// 如果清除失败，会静默处理错误。
  Future<void> resetAllGuides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final type in GuideType.values) {
        await prefs.remove('$_keyPrefix${type.name}');
      }
    } catch (e) {
      // 重置失败时静默处理
    }
  }
}
