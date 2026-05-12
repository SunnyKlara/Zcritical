import 'package:flutter/material.dart';

/// 响应式布局工具类
/// 
/// 提供屏幕尺寸计算、断点判断、动态缩放等响应式布局功能
/// 
/// 使用示例：
/// ```dart
/// final buttonSize = ResponsiveUtils.scaledSize(context, 56.0);
/// final isSmall = ResponsiveUtils.isSmallScreen(context);
/// final margin = ResponsiveUtils.width(context, 5); // 5% of screen width
/// ```
class ResponsiveUtils {
  // 私有构造函数，防止实例化
  ResponsiveUtils._();
  
  // ========== 基础屏幕信息 ==========
  
  /// 获取屏幕宽度百分比
  /// 
  /// [context] - BuildContext
  /// [percentage] - 百分比（0-100）
  /// 返回：屏幕宽度 * 百分比
  /// 
  /// 示例：`ResponsiveUtils.width(context, 50)` 返回屏幕宽度的50%
  static double width(BuildContext context, double percentage) {
    assert(percentage >= 0 && percentage <= 100, 'Percentage must be between 0 and 100');
    return MediaQuery.of(context).size.width * percentage / 100;
  }
  
  /// 获取屏幕高度百分比
  /// 
  /// [context] - BuildContext
  /// [percentage] - 百分比（0-100）
  /// 返回：屏幕高度 * 百分比
  /// 
  /// 示例：`ResponsiveUtils.height(context, 10)` 返回屏幕高度的10%
  static double height(BuildContext context, double percentage) {
    assert(percentage >= 0 && percentage <= 100, 'Percentage must be between 0 and 100');
    return MediaQuery.of(context).size.height * percentage / 100;
  }
  
  /// 获取屏幕宽度（像素）
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }
  
  /// 获取屏幕高度（像素）
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
  
  /// 获取屏幕尺寸
  static Size screenSize(BuildContext context) {
    return MediaQuery.of(context).size;
  }
  
  /// 获取设备像素比
  static double devicePixelRatio(BuildContext context) {
    return MediaQuery.of(context).devicePixelRatio;
  }
  
  // ========== 动态缩放 ==========
  
  /// 基于设计稿宽度的缩放计算
  /// 
  /// [context] - BuildContext
  /// [baseSize] - 基础尺寸（基于375px宽度的设计稿）
  /// 返回：适配当前屏幕的尺寸
  /// 
  /// 示例：设计稿上按钮宽度为60px
  /// `ResponsiveUtils.scaledSize(context, 60)` 
  /// 在iPhone 11 (390px) 上返回 62.4px
  static double scaledSize(BuildContext context, double baseSize, {double baseWidth = 375.0}) {
    final screenWidth = MediaQuery.of(context).size.width;
    return baseSize * screenWidth / baseWidth;
  }
  
  /// 基于设计稿高度的缩放计算
  /// 
  /// [context] - BuildContext
  /// [baseSize] - 基础尺寸（基于812px高度的设计稿）
  /// 返回：适配当前屏幕的尺寸
  static double scaledHeight(BuildContext context, double baseSize, {double baseHeight = 812.0}) {
    final screenHeight = MediaQuery.of(context).size.height;
    return baseSize * screenHeight / baseHeight;
  }
  
  /// 缩放字体大小
  /// 
  /// 根据屏幕宽度动态调整字体大小，但限制最小/最大值
  static double scaledFontSize(BuildContext context, double baseSize, {
    double? minSize,
    double? maxSize,
  }) {
    final scaled = scaledSize(context, baseSize);
    if (minSize != null && maxSize != null) {
      return scaled.clamp(minSize, maxSize);
    }
    return scaled;
  }
  
  // ========== 屏幕尺寸断点判断 ==========
  
  /// 是否为小屏幕设备
  /// 
  /// 定义：高度 < 700px 或 宽度 < 375px
  /// 示例设备：iPhone SE (375×667)
  static bool isSmallScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height < 700 || size.width < 375;
  }
  
  /// 是否为中等屏幕设备
  /// 
  /// 定义：700 <= 高度 <= 900 且 375 <= 宽度 <= 430
  /// 示例设备：iPhone 11/12/13 (390×844)
  static bool isMediumScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height >= 700 && 
           size.height <= 900 && 
           size.width >= 375 && 
           size.width <= 430;
  }
  
  /// 是否为大屏幕设备
  /// 
  /// 定义：高度 > 900 或 宽度 > 430
  /// 示例设备：iPhone 14 Pro Max (428×926), iPad Mini
  static bool isLargeScreen(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height > 900 || size.width > 430;
  }
  
  /// 是否为平板设备
  /// 
  /// 定义：宽度 > 600px
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width > 600;
  }
  
  /// 是否为横屏模式
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }
  
  /// 是否为竖屏模式
  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }
  
  // ========== 根据屏幕尺寸获取不同值 ==========
  
  /// 根据屏幕尺寸返回不同的值
  /// 
  /// [context] - BuildContext
  /// [small] - 小屏幕时的值
  /// [medium] - 中等屏幕时的值（可选，默认使用small）
  /// [large] - 大屏幕时的值（可选，默认使用medium或small）
  /// 
  /// 示例：
  /// ```dart
  /// final padding = ResponsiveUtils.valueBySize(
  ///   context,
  ///   small: 16.0,
  ///   medium: 20.0,
  ///   large: 24.0,
  /// );
  /// ```
  static T valueBySize<T>(
    BuildContext context, {
    required T small,
    T? medium,
    T? large,
  }) {
    if (isLargeScreen(context)) {
      return large ?? medium ?? small;
    } else if (isMediumScreen(context)) {
      return medium ?? small;
    } else {
      return small;
    }
  }
  
  /// 根据是否为平板返回不同的值
  static T valueByDevice<T>(
    BuildContext context, {
    required T mobile,
    required T tablet,
  }) {
    return isTablet(context) ? tablet : mobile;
  }
  
  // ========== 常用尺寸计算 ==========
  
  /// 获取安全区域的顶部padding
  static double safeAreaTop(BuildContext context) {
    return MediaQuery.of(context).padding.top;
  }
  
  /// 获取安全区域的底部padding
  static double safeAreaBottom(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }
  
  /// 获取可用屏幕高度（减去状态栏和底部安全区）
  static double availableHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.height - 
           mediaQuery.padding.top - 
           mediaQuery.padding.bottom;
  }
  
  /// 获取可用屏幕宽度（减去左右安全区）
  static double availableWidth(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width - 
           mediaQuery.padding.left - 
           mediaQuery.padding.right;
  }
  
  // ========== 动态间距 ==========
  
  /// 获取响应式水平padding
  /// 
  /// 小屏幕: 16px
  /// 中屏幕: 20px
  /// 大屏幕: 24px
  static double horizontalPadding(BuildContext context) {
    return valueBySize(
      context,
      small: 16.0,
      medium: 20.0,
      large: 24.0,
    );
  }
  
  /// 获取响应式垂直padding
  /// 
  /// 小屏幕: 12px
  /// 中屏幕: 16px
  /// 大屏幕: 20px
  static double verticalPadding(BuildContext context) {
    return valueBySize(
      context,
      small: 12.0,
      medium: 16.0,
      large: 20.0,
    );
  }
  
  /// 获取响应式边距
  static EdgeInsets responsivePadding(BuildContext context, {
    double? horizontal,
    double? vertical,
  }) {
    return EdgeInsets.symmetric(
      horizontal: horizontal ?? horizontalPadding(context),
      vertical: vertical ?? verticalPadding(context),
    );
  }
  
  // ========== 按钮尺寸 ==========
  
  /// 获取最小可触摸尺寸
  /// 
  /// Apple HIG: 44pt
  /// Material Design: 48dp
  /// 
  /// 返回两者的平均值：46px
  static double minTouchTargetSize(BuildContext context) {
    return 46.0;
  }
  
  /// 获取标准按钮高度
  /// 
  /// 小屏幕: 48px
  /// 中屏幕: 52px
  /// 大屏幕: 56px
  static double buttonHeight(BuildContext context) {
    return valueBySize(
      context,
      small: 48.0,
      medium: 52.0,
      large: 56.0,
    );
  }
  
  /// 获取标准按钮宽度（百分比）
  /// 
  /// 返回屏幕宽度的80%，但最大不超过400px
  static double buttonWidth(BuildContext context) {
    return (screenWidth(context) * 0.8).clamp(200.0, 400.0);
  }
  
  // ========== 调试工具 ==========
  
  /// 打印当前屏幕信息（用于调试）
  static void debugPrintScreenInfo(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    debugPrint('========== 屏幕信息 ==========');
    debugPrint('宽度: ${mediaQuery.size.width}px');
    debugPrint('高度: ${mediaQuery.size.height}px');
    debugPrint('像素比: ${mediaQuery.devicePixelRatio}');
    debugPrint('方向: ${mediaQuery.orientation}');
    debugPrint('顶部安全区: ${mediaQuery.padding.top}px');
    debugPrint('底部安全区: ${mediaQuery.padding.bottom}px');
    debugPrint('屏幕类型: ${_getScreenType(context)}');
    debugPrint('============================');
  }
  
  static String _getScreenType(BuildContext context) {
    if (isSmallScreen(context)) return '小屏幕';
    if (isMediumScreen(context)) return '中等屏幕';
    if (isLargeScreen(context)) return '大屏幕';
    return '未知';
  }
}

/// 设备尺寸枚举
enum DeviceSize {
  /// 小屏幕设备（高度 < 700 或 宽度 < 375）
  small,
  
  /// 中等屏幕设备（标准手机）
  medium,
  
  /// 大屏幕设备（大手机或平板）
  large,
}

/// 设备尺寸辅助类
class DeviceSizeHelper {
  /// 获取当前设备尺寸类型
  static DeviceSize getDeviceSize(BuildContext context) {
    if (ResponsiveUtils.isSmallScreen(context)) {
      return DeviceSize.small;
    } else if (ResponsiveUtils.isLargeScreen(context)) {
      return DeviceSize.large;
    } else {
      return DeviceSize.medium;
    }
  }
  
  /// 根据设备尺寸返回不同的值
  static T getValueByDeviceSize<T>(
    BuildContext context, {
    required T small,
    required T medium,
    required T large,
  }) {
    final size = getDeviceSize(context);
    switch (size) {
      case DeviceSize.small:
        return small;
      case DeviceSize.large:
        return large;
      default:
        return medium;
    }
  }
}

