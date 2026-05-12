# Implementation Plan: 交互式引导系统重构

## 概述

将 RideWind 应用的引导系统从固定位置覆盖层重构为精确定位目标元素、手势验证推进的交互式引导系统。按照数据模型 → 核心逻辑 → 视觉组件 → GlobalKey 暴露 → 引导流程配置 → 集成的顺序递增实现。

## Tasks

- [x] 1. 扩展引导步骤数据模型
  - [x] 1.1 在 `lib/models/guide_models.dart` 中添加 `GestureType` 枚举（tap、longPress、swipeLeft、swipeRight、swipeUp、swipeDown、dragHorizontal、dragVertical），并在 `GuideStep` 类中添加 `gestureType` 字段，默认值为 `GestureType.tap`
    - 保留现有 targetKey、title、description、position、icon 字段不变
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - [ ]* 1.2 为 GuideStep 模型编写属性测试
    - **Property 1: GuideStep default gestureType**
    - **Validates: Requirements 1.3**

- [x] 2. 实现提示框动态定位逻辑
  - [x] 2.1 重构 `lib/widgets/enhanced_guide_overlay.dart` 中的 `calculateTooltipPosition` 函数
    - 目标在屏幕上半部分时提示框显示在下方，下半部分时显示在上方
    - 水平居中对齐目标，超出屏幕边界时自动裁剪
    - 与目标保持最小间距，避免与手指动画重叠
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  - [ ]* 2.2 为提示框定位编写属性测试
    - **Property 2: Tooltip positioning correctness**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

- [x] 3. 实现手势感知的手指动画
  - [x] 3.1 重构 `lib/widgets/finger_pointer_widget.dart`，添加 `gestureType` 参数
    - 根据 gestureType 实现不同的 `calculatePosition` 逻辑
    - tap: 上下弹跳（保留现有行为）
    - longPress: 下压 → 停顿 → 抬起
    - swipeLeft/swipeRight: 水平方向滑动
    - swipeUp/swipeDown: 垂直方向滑动
    - dragHorizontal/dragVertical: 对应方向来回拖动
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_
  - [ ]* 3.2 为手指动画方向编写属性测试
    - **Property 3: Finger animation direction matches gesture type**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7**

- [x] 4. 实现手势验证器
  - [x] 4.1 创建 `lib/widgets/gesture_validator_widget.dart`
    - 实现 `GestureValidatorWidget`，接收 targetRect、expectedGesture、onGestureMatched
    - 实现纯函数 `matchesGesture(GestureType expected, GestureData actual)` 用于手势匹配判断
    - tap: onTap 触发匹配
    - longPress: onLongPress 触发匹配
    - swipeLeft/swipeRight: onHorizontalDragEnd 检查速度方向
    - swipeUp/swipeDown: onVerticalDragEnd 检查速度方向
    - dragHorizontal/dragVertical: 累计位移超过 30px 阈值匹配
    - 使用 HitTestBehavior.translucent 确保事件传递给底层组件
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8_
  - [ ]* 4.2 为手势匹配逻辑编写属性测试
    - **Property 4: Gesture matching correctness**
    - **Validates: Requirements 5.3, 5.4, 5.5, 5.6, 5.7**

- [x] 5. Checkpoint - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 6. 重构 EnhancedGuideOverlay 核心逻辑
  - [x] 6.1 重构 `lib/widgets/enhanced_guide_overlay.dart` 的 `EnhancedGuideOverlayState`
    - 移除"点击任意位置推进"逻辑，替换为 GestureValidatorWidget
    - 将 Finger_Pointer 定位改为基于 targetRect 中心
    - 将 Ripple_Effect 中心改为 targetRect 中心
    - 将 Tooltip 定位改为调用重构后的 calculateTooltipPosition
    - 传递当前步骤的 gestureType 给 FingerPointerWidget 和 GestureValidatorWidget
    - _Requirements: 2.1, 2.2, 2.3, 2.5, 5.1, 5.2_
  - [x] 6.2 实现步骤间 UI 状态等待机制
    - 添加 `_waitForTarget` 方法：轮询间隔 100ms，超时 2000ms
    - 在 `_nextStep` 中，如果下一步的 targetKey 对应的 RenderBox 不可用，调用 `_waitForTarget`
    - 超时后跳过该步骤
    - 处理 GlobalKey 无法获取 RenderBox 的情况（跳过步骤）
    - _Requirements: 2.4, 9.1, 9.2, 9.3_
  - [ ]* 6.3 为步骤指示器格式编写属性测试
    - **Property 5: Step indicator format correctness**
    - **Validates: Requirements 10.4**

- [x] 7. 暴露 GlobalKey 并绑定到实际 UI 组件
  - [x] 7.1 修改 `lib/widgets/running_mode_widget.dart`
    - 为速度滚轮、单位标签、油门按钮、紧急停止按钮创建 GlobalKey
    - 将 GlobalKey 绑定到对应的 Widget（作为 key 参数）
    - 添加 `onKeysReady` 回调，在 postFrameCallback 中将 key map 传递给父组件
    - _Requirements: 6.1_
  - [x] 7.2 修改 `lib/screens/device_connect_screen.dart`
    - 为汽车图片区域、下半部分区域、颜色胶囊条、开始涂色按钮、调色盘按钮、LMRB 胶囊区域、RGB 滑条区域、亮度调节条创建 GlobalKey
    - 将 GlobalKey 绑定到对应的 Widget
    - 存储 RunningModeWidget 通过 onKeysReady 回调传递的 key
    - _Requirements: 6.2, 6.3_

- [x] 8. 配置引导流程步骤
  - [x] 8.1 重写 `_showRunningModeGuide` 方法
    - 使用实际 GlobalKey 替换占位 GlobalKey
    - 为每个步骤设置正确的 gestureType（参照设计文档中的 Running Mode 步骤配置表）
    - 8 个步骤，使用 glassmorphism 提示框样式
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 7.10_
  - [x] 8.2 重写 `_showColorizeModeGuide` 方法
    - 使用实际 GlobalKey 替换占位 GlobalKey
    - 为每个步骤设置正确的 gestureType（参照设计文档中的 Colorize Mode 步骤配置表）
    - 7 个步骤，使用 glowBorder 提示框样式
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9_
  - [ ]* 8.3 为引导流程配置编写单元测试
    - 验证 Running Mode 引导包含 8 个步骤，每个步骤的 gestureType 和 description 正确
    - 验证 Colorize Mode 引导包含 7 个步骤，每个步骤的 gestureType 和 description 正确
    - _Requirements: 7.1, 8.1_

- [x] 9. 集成与引导流程控制
  - [x] 9.1 确保引导流程控制功能完整
    - 验证跳过引导按钮正常工作
    - 验证 FeatureGuideService 的 markGuideComplete 在完成/跳过时被调用
    - 验证步骤指示器（"N / M"）正确显示
    - 恢复 `_checkAndShowRunningModeGuide` 和 `_checkAndShowColorizeModeGuide` 中被注释的 shouldShowGuide 检查
    - _Requirements: 10.1, 10.2, 10.3, 10.4_
  - [ ]* 9.2 编写 Widget 测试验证集成
    - 测试 EnhancedGuideOverlay 正确渲染手指、波纹、提示框
    - 测试正确手势推进步骤，错误手势不推进
    - 测试跳过引导功能
    - _Requirements: 5.1, 5.2, 10.1_

- [x] 10. Final checkpoint - 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

## 备注

- 标记 `*` 的任务为可选任务，可跳过以加快 MVP 进度
- 每个任务引用了具体的需求编号以确保可追溯性
- 属性测试使用 `glados` 库，每个属性至少运行 100 次迭代
- Checkpoint 任务确保增量验证
