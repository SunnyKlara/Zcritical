import 'package:flutter/material.dart';

/// 📱 DeviceConnectScreen 响应式布局配置
///
/// 根据屏幕尺寸计算所有 UI 元素的位置和大小。
/// 从 DeviceConnectScreen 中提取，供主屏幕和子模式组件共用。
class DeviceConnectConfig {
  final BuildContext context;

  DeviceConnectConfig(this.context);

  // ── 屏幕信息 ──
  double get screenWidth => MediaQuery.of(context).size.width;
  double get screenHeight => MediaQuery.of(context).size.height;
  double get safeAreaTop => MediaQuery.of(context).padding.top;
  double get safeAreaBottom => MediaQuery.of(context).padding.bottom;

  bool get isSmallScreen => screenHeight < 700 || screenWidth < 380;
  bool get isLargeScreen => screenHeight > 900 || screenWidth > 428;
  bool get isCompactWidth => screenWidth <= 390; // iPhone 13 mini (375), iPhone 13/14 (390)
  bool get isTablet => screenWidth > 600;

  // ── 顶部渐变遮罩 ──
  double get topGradientHeight {
    if (isSmallScreen) return 55.0;
    if (isLargeScreen) return 80.0;
    return 70.0;
  }

  // ── 顶部按钮 ──
  double get topButtonTop {
    final base = safeAreaTop + 8;
    if (isSmallScreen) return base;
    if (isLargeScreen) return base + 4;
    return base;
  }

  double get backButtonTop => topButtonTop;
  double get menuButtonTop => topButtonTop;

  double get backButtonLeft {
    if (isSmallScreen) return 8;
    if (isTablet) return 20;
    return screenWidth * 0.02;
  }

  double get menuButtonRight {
    if (isSmallScreen) return 8;
    if (isTablet) return 20;
    return screenWidth * 0.025;
  }

  double get topButtonSize {
    if (isSmallScreen) return 40.0;
    if (isLargeScreen) return 60.0;
    if (isTablet) return 64.0;
    return 52.0;
  }

  double get backButtonSize => topButtonSize;
  double get menuButtonSize => topButtonSize;

  // ── 双击区域（汽车图片）──
  double get carImageTop {
    if (isSmallScreen) return screenHeight * 0.12;
    return screenHeight * 0.15;
  }

  double get carImageBottom {
    if (isSmallScreen) return screenHeight * 0.50;
    return screenHeight * 0.55;
  }

  double get carImageLeft => screenWidth * 0.1;
  double get carImageRight => screenWidth * 0.1;

  // ── RGB 设置界面 ──
  double get rgbSettingsTop => screenHeight * 0.57;
  double get rgbSettingsLeft => screenWidth * 0.1;
  double get rgbSettingsRight => screenWidth * 0.1;

  double get rgbSettingsButtonBottom {
    final base = safeAreaBottom + 10;
    if (isSmallScreen) return base;
    if (isLargeScreen) return base + 15;
    return base + 10;
  }

  double get rgbSettingsButtonRight => screenWidth * 0.05;

  double get rgbSettingsButtonSize {
    if (isSmallScreen) return 55.0;
    if (isLargeScreen) return 90.0;
    return 80.0;
  }

  // ── RGB 调色界面 (ui=3) ──
  double get cycleSpeedPanelBottom {
    final base = safeAreaBottom + 80;
    if (isSmallScreen) return base + 25;
    if (isLargeScreen) return base + 45;
    return base + 35;
  }

  double get cycleSpeedSliderHeight {
    if (isSmallScreen) return 36.0;
    if (isLargeScreen) return 52.0;
    return 46.0;
  }

  double get cycleSpeedPanelHeight {
    final titleFontSize = screenWidth < 360 ? 16.0 : (screenWidth > 414 ? 24.0 : 20.0);
    return titleFontSize + 15 + cycleSpeedSliderHeight + 10 + 7;
  }

  double get cycleSpeedPanelTop =>
      screenHeight - cycleSpeedPanelBottom - cycleSpeedPanelHeight;

  double get availableSpaceForCapsules {
    final topBoundary = screenHeight * 0.50;
    final bottomBoundary = cycleSpeedPanelTop - 20;
    final available = bottomBoundary - topBoundary;
    return available > 0 ? available : 200.0;
  }

  double get rgbCapsuleHeight {
    final availableForCapsule = availableSpaceForCapsules - 40;
    double targetHeight;
    if (isSmallScreen) {
      targetHeight = 140.0;
    } else if (isLargeScreen) {
      targetHeight = 200.0;
    } else if (isTablet) {
      targetHeight = 220.0;
    } else {
      targetHeight = 170.0;
    }
    final safeAvailable = availableForCapsule > 100 ? availableForCapsule : 200.0;
    final maxHeight = safeAvailable * 0.85;
    return targetHeight.clamp(100.0, maxHeight > 100 ? maxHeight : 200.0);
  }

  double get rgbCapsuleWidth {
    final baseWidth = rgbCapsuleHeight * 0.38;
    if (isSmallScreen) return baseWidth.clamp(45.0, 55.0);
    if (isLargeScreen) return baseWidth.clamp(60.0, 75.0);
    if (isTablet) return baseWidth.clamp(65.0, 80.0);
    return baseWidth.clamp(50.0, 65.0);
  }

  double get rgbCapsulesTop {
    final topBoundary = screenHeight * 0.50;
    final bottomBoundary = cycleSpeedPanelTop - 20;
    final totalCapsuleAreaHeight = rgbCapsuleHeight + 40;
    final centerY = (topBoundary + bottomBoundary) / 2;
    return centerY - totalCapsuleAreaHeight / 2;
  }

  double get verticalBrightnessHeight {
    final baseHeight = screenHeight * 0.22;
    return baseHeight.clamp(150.0, 220.0);
  }

  double get verticalBrightnessWidth {
    final baseWidth = screenWidth * 0.14;
    return baseWidth.clamp(50.0, 65.0);
  }

  double get verticalBrightnessTop {
    final base = screenHeight * 0.15;
    return base.clamp(100.0, 160.0);
  }

  double get metallicSliderHeight {
    if (isSmallScreen) return 36.0;
    if (isLargeScreen) return 52.0;
    return 46.0;
  }

  // ── 颜色胶囊条 ──
  double get colorCapsuleWidth {
    if (isSmallScreen) return 42.0;
    if (isLargeScreen) return 55.0;
    return 47.0;
  }

  double get colorCapsuleHeight {
    if (isSmallScreen) return 135.0;
    if (isLargeScreen) return 170.0;
    return 153.0;
  }

  double get colorCapsuleContainerHeight {
    if (isSmallScreen) return 185.0;
    if (isLargeScreen) return 240.0;
    return 220.0;
  }

  // ── 对话框字体 ──
  double get dialogTitleFontSize {
    if (isSmallScreen) return 18.0;
    if (isLargeScreen) return 24.0;
    return 22.0;
  }

  double get dialogContentFontSize {
    if (isSmallScreen) return 14.0;
    if (isLargeScreen) return 18.0;
    return 16.0;
  }

  double get dialogButtonFontSize {
    if (isSmallScreen) return 14.0;
    if (isLargeScreen) return 18.0;
    return 16.0;
  }

  double get startColoringButtonTapHeight {
    if (isSmallScreen) return 55.0;
    if (isLargeScreen) return 70.0;
    return 62.0;
  }

  double get paletteButtonSize {
    if (isSmallScreen) return 65.0;
    if (isLargeScreen) return 90.0;
    return 78.0;
  }

  double get bottomButtonsMarginBottom {
    final base = safeAreaBottom + 15;
    if (isSmallScreen) return base + 5;
    if (isLargeScreen) return base + 15;
    return base + 10;
  }
}
