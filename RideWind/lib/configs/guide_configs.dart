import 'package:flutter/material.dart';
import '../models/guide_models.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║          🎯 Running Mode 引导配置                              ║
// ║          Requirements: 3.1                                    ║
// ╚══════════════════════════════════════════════════════════════╝

/// Running Mode 目标元素的 GlobalKey 定义
/// 这些 Key 需要在 Running Mode 界面中分配给对应的 Widget
/// 
/// 使用示例:
/// ```dart
/// Container(
///   key: runningModeSpeedControlKey,
///   child: SpeedControlWidget(),
/// )
/// ```

/// 速度控制区域的 GlobalKey
/// 用于高亮显示速度滚轮控制区域
final GlobalKey runningModeSpeedControlKey = GlobalKey(debugLabel: 'runningModeSpeedControl');

/// 雾化器开关按钮的 GlobalKey
/// 用于高亮显示双击切换雾化器的区域（汽车图片区域）
final GlobalKey runningModeAtomizerButtonKey = GlobalKey(debugLabel: 'runningModeAtomizerButton');

/// 最大速度设置的 GlobalKey
/// 用于高亮显示最大速度限制设置区域
final GlobalKey runningModeMaxSpeedKey = GlobalKey(debugLabel: 'runningModeMaxSpeed');

/// Running Mode 引导配置
/// 
/// 包含三个引导步骤：
/// 1. 速度控制 - 上下滑动调节速度
/// 2. 雾化器开关 - 双击切换雾化器状态
/// 3. 最大速度 - 设置最大速度限制
/// 
/// Requirements: 3.1
final GuideConfiguration runningModeGuide = GuideConfiguration(
  featureId: 'running_mode',
  steps: [
    GuideStep(
      targetKey: runningModeSpeedControlKey,
      title: '速度控制',
      description: '上下滑动调节速度，数值会实时同步到设备',
      icon: Icons.swap_vert,
      position: TooltipPosition.right,
    ),
    GuideStep(
      targetKey: runningModeAtomizerButtonKey,
      title: '雾化器开关',
      description: '双击此区域可快速切换雾化器开关状态',
      icon: Icons.touch_app,
      position: TooltipPosition.bottom,
    ),
    GuideStep(
      targetKey: runningModeMaxSpeedKey,
      title: '最大速度',
      description: '点击设置最大速度限制',
      icon: Icons.speed,
      position: TooltipPosition.top,
    ),
  ],
  canSkip: true,
  stepDelay: const Duration(milliseconds: 300),
);

// ╔══════════════════════════════════════════════════════════════╗
// ║          🎨 Colorize Mode 引导配置                             ║
// ║          Requirements: 3.2                                    ║
// ╚══════════════════════════════════════════════════════════════╝

/// Colorize Mode 目标元素的 GlobalKey 定义
/// 这些 Key 需要在 Colorize Mode 界面中分配给对应的 Widget
/// 
/// 使用示例:
/// ```dart
/// Container(
///   key: colorizeModeColorPresetsKey,
///   child: ColorPresetsWidget(),
/// )
/// ```

/// 颜色预设区域的 GlobalKey
/// 用于高亮显示颜色预设选择区域
final GlobalKey colorizeModeColorPresetsKey = GlobalKey(debugLabel: 'colorizeModeColorPresets');

/// RGB 详细调色区域的 GlobalKey
/// 用于高亮显示长按进入详细调色的区域
final GlobalKey colorizeModeRgbDetailKey = GlobalKey(debugLabel: 'colorizeModeRgbDetail');

/// 亮度调节滑块的 GlobalKey
/// 用于高亮显示亮度调节滑块区域
final GlobalKey colorizeModeBrightnessKey = GlobalKey(debugLabel: 'colorizeModeBrightness');

/// Colorize Mode 引导配置
/// 
/// 包含三个引导步骤：
/// 1. 颜色预设 - 左右滑动选择预设颜色方案
/// 2. 详细调色 - 长按预设进入 RGB 详细调色模式
/// 3. 亮度调节 - 拖动滑块调节整体亮度
/// 
/// Requirements: 3.2
final GuideConfiguration colorizeModeGuide = GuideConfiguration(
  featureId: 'colorize_mode',
  steps: [
    GuideStep(
      targetKey: colorizeModeColorPresetsKey,
      title: '颜色预设',
      description: '左右滑动选择预设颜色方案',
      icon: Icons.swipe,
      position: TooltipPosition.bottom,
    ),
    GuideStep(
      targetKey: colorizeModeRgbDetailKey,
      title: '详细调色',
      description: '长按预设进入 RGB 详细调色模式',
      icon: Icons.palette,
      position: TooltipPosition.bottom,
    ),
    GuideStep(
      targetKey: colorizeModeBrightnessKey,
      title: '亮度调节',
      description: '拖动滑块调节整体亮度',
      icon: Icons.brightness_6,
      position: TooltipPosition.top,
    ),
  ],
  canSkip: true,
  stepDelay: const Duration(milliseconds: 300),
);

// ╔══════════════════════════════════════════════════════════════╗
// ║          📷 Logo 上传引导配置                                   ║
// ║          Requirements: 3.3                                    ║
// ╚══════════════════════════════════════════════════════════════╝

/// Logo 上传目标元素的 GlobalKey 定义
/// 这些 Key 需要在 Logo 上传界面中分配给对应的 Widget
/// 
/// 使用示例:
/// ```dart
/// Container(
///   key: logoUploadImageSelectionKey,
///   child: ImageSelectionWidget(),
/// )
/// ```

/// 图片选择区域的 GlobalKey
/// 用于高亮显示图片选择按钮或区域
final GlobalKey logoUploadImageSelectionKey = GlobalKey(debugLabel: 'logoUploadImageSelection');

/// 图片裁剪区域的 GlobalKey
/// 用于高亮显示图片裁剪操作区域
final GlobalKey logoUploadCropAreaKey = GlobalKey(debugLabel: 'logoUploadCropArea');

/// 上传按钮的 GlobalKey
/// 用于高亮显示上传按钮
final GlobalKey logoUploadButtonKey = GlobalKey(debugLabel: 'logoUploadButton');

/// Logo 上传引导配置
/// 
/// 包含三个引导步骤：
/// 1. 图片选择 - 如何选择要上传的图片
/// 2. 图片裁剪 - 如何裁剪图片以适应 Logo 尺寸
/// 3. 上传按钮 - 如何上传 Logo 到设备
/// 
/// Requirements: 3.3
final GuideConfiguration logoUploadGuide = GuideConfiguration(
  featureId: 'logo_upload',
  steps: [
    GuideStep(
      targetKey: logoUploadImageSelectionKey,
      title: '图片选择',
      description: '点击此处从相册选择图片或拍照获取 Logo 图片',
      icon: Icons.add_photo_alternate,
      position: TooltipPosition.bottom,
    ),
    GuideStep(
      targetKey: logoUploadCropAreaKey,
      title: '图片裁剪',
      description: '拖动和缩放图片，调整到合适的位置和大小',
      icon: Icons.crop,
      position: TooltipPosition.bottom,
    ),
    GuideStep(
      targetKey: logoUploadButtonKey,
      title: '上传 Logo',
      description: '点击上传按钮将 Logo 传输到设备',
      icon: Icons.cloud_upload,
      position: TooltipPosition.top,
    ),
  ],
  canSkip: true,
  stepDelay: const Duration(milliseconds: 300),
);
