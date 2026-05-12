# Implementation Plan: 应用 UX 引导升级与颜色 Bug 修复

## Overview

分两条主线实现：先修复 RGB 颜色覆盖 Bug（影响范围小、优先级高），再升级引导动画系统。每条主线内部按数据层 → 逻辑层 → UI 层的顺序推进。

## Tasks

- [x] 1. 修复 RGB 颜色覆盖 Bug - 数据层
  - [x] 1.1 在 PreferenceService 中添加自定义 RGB 颜色持久化方法
    - 添加 `saveCustomRGBColors(Map<String, Map<String, int>> zoneColors)` 方法，将区域颜色映射序列化为 JSON 存储到 SharedPreferences
    - 添加 `getCustomRGBColors()` 方法，从 SharedPreferences 读取并反序列化区域颜色映射
    - 添加 `clearCustomRGBColors()` 方法，清除已保存的自定义颜色数据
    - 添加 `saveHasCustomColors(bool value)` 和 `getHasCustomColors()` 方法，持久化颜色来源标志位
    - 使用 `clamp(0, 255)` 约束读取的 RGB 值
    - _Requirements: 4.1, 4.3, 4.4_

  - [ ]* 1.2 为 PreferenceService 自定义颜色方法编写属性测试
    - **Property 6: 自定义 RGB 颜色持久化往返一致性**
    - 使用 glados 生成随机区域颜色映射（L/M/R/B 各区域 R/G/B 值 0-255），验证 save 后 get 返回相同数据
    - **Validates: Requirements 4.1, 4.2, 4.4**

- [x] 2. 修复 RGB 颜色覆盖 Bug - 逻辑层
  - [x] 2.1 在 DeviceConnectScreen 中添加颜色来源标志位和修改返回逻辑
    - 添加 `bool _hasCustomColors = false` 状态变量
    - 在 RGB 滑块调节回调中设置 `_hasCustomColors = true` 并调用 `_preferenceService.saveCustomRGBColors()` 和 `_preferenceService.saveHasCustomColors(true)`
    - 修改返回按钮逻辑：从 rgbDetail 返回 preset 时，检查 `_hasCustomColors`，若为 true 则跳过 `_syncPresetToHardware()` 调用
    - 在 `_syncPresetToHardware()` 中（用户主动选择预设时），设置 `_hasCustomColors = false` 并调用 `_preferenceService.clearCustomRGBColors()`
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [x] 2.2 在 DeviceConnectScreen 初始化时恢复自定义颜色状态
    - 在 `initState` 或现有的偏好加载逻辑中，调用 `_preferenceService.getHasCustomColors()` 和 `_preferenceService.getCustomRGBColors()`
    - 若存在已保存的自定义颜色，恢复到 `_redValues`、`_greenValues`、`_blueValues` 并设置 `_hasCustomColors = true`
    - _Requirements: 4.2_

  - [ ]* 2.3 为颜色来源标志位逻辑编写单元测试
    - 测试：调节 RGB 后 `_hasCustomColors` 为 true
    - 测试：选择预设后 `_hasCustomColors` 为 false 且 RGB 值匹配预设
    - 测试：`_hasCustomColors` 为 true 时返回 preset 不覆盖颜色
    - **Property 5: 颜色来源标志位正确追踪**
    - **Validates: Requirements 3.3, 3.4**

- [x] 3. Checkpoint - 颜色 Bug 修复验证
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. 升级引导动画系统 - 核心组件
  - [x] 4.1 创建 RippleEffectPainter 水波纹绘制器
    - 在 `lib/widgets/` 下创建 `ripple_effect_painter.dart`
    - 实现 `CustomPainter`，绘制两圈同心波纹（相位差 0.5）
    - 波纹颜色 0xFF25C485，不透明度从 0.4 渐变到 0.0
    - 扩散半径从高亮区域边缘扩展至额外 30px
    - 接收 `rippleProgress`（0.0~1.0）驱动动画
    - _Requirements: 2.2_

  - [x] 4.2 创建 FingerPointerWidget 手指指针组件
    - 在 `lib/widgets/` 下创建 `finger_pointer_widget.dart`
    - 使用 `Icons.touch_app` 图标，主题色 0xFF25C485
    - 接收 `bounceAnimation` 驱动上下浮动（幅度 8px）
    - 定位在目标元素高亮区域的右下角偏移位置
    - _Requirements: 2.1_

  - [x] 4.3 创建 EnhancedGuideOverlay 增强引导覆盖层
    - 在 `lib/widgets/` 下创建 `enhanced_guide_overlay.dart`，替换现有 `GuideOverlay` 的功能
    - 使用 `TickerProviderStateMixin` 管理多个 AnimationController：
      - `_fadeController`：步骤切换淡入淡出（300ms）
      - `_fingerController`：手指浮动（800ms 循环，Curves.easeInOut）
      - `_rippleController`：水波纹扩散（1500ms 循环）
    - 集成 `HighlightMaskPainter`（复用现有）、`RippleEffectPainter`、`FingerPointerWidget`、Tooltip 组件
    - 实现步骤跳过逻辑：遍历步骤列表，跳过 targetKey 对应 RenderBox 为 null 的步骤
    - 支持点击高亮区域或"下一步"按钮前进
    - 提供 `showEnhancedGuideOverlay()` 便捷方法，替换现有 `showGuideOverlay()`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 1.8, 1.9, 2.3, 2.4_

  - [ ]* 4.4 为 Tooltip 定位逻辑编写属性测试
    - **Property 1: Tooltip 定位始终在屏幕可见区域内**
    - 使用 glados 生成随机 Rect（目标元素）和 Size（屏幕尺寸），验证计算出的 Tooltip 位置使提示框完全在屏幕内
    - **Validates: Requirements 1.5**

  - [ ]* 4.5 为步骤跳过逻辑编写属性测试
    - **Property 2: 不可定位步骤自动跳过**
    - 生成随机步骤列表（部分步骤标记为不可定位），验证引导系统只展示可定位步骤
    - **Validates: Requirements 1.9**

- [x] 5. 升级引导动画系统 - 集成
  - [x] 5.1 更新 DeviceConnectScreen 中的引导触发逻辑
    - 将现有的 `showGuideOverlay()` 调用替换为 `showEnhancedGuideOverlay()`
    - 确保所有 GuideType（runningMode、colorizeMode、logoUpload、deviceConnect）使用新的增强引导
    - 验证 FeatureGuideService 的 shouldShowGuide/markGuideComplete 流程正常工作
    - _Requirements: 1.1, 1.7_

  - [ ]* 5.2 为引导完成状态持久化编写属性测试
    - **Property 3: 引导完成状态持久化往返一致性**
    - 使用 glados 生成随机 GuideType，验证 markGuideComplete 后 shouldShowGuide 返回 false
    - **Validates: Requirements 1.7**

- [x] 6. Final checkpoint - 全部功能验证
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- 颜色 Bug 修复（任务 1-3）优先于引导升级（任务 4-6），因为 Bug 影响用户体验且修复范围小
- 属性测试使用 `glados` 包，需在 `pubspec.yaml` 的 `dev_dependencies` 中添加
- 每个属性测试至少运行 100 次迭代
