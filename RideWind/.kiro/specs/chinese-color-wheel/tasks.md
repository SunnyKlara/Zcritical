# Implementation Plan: 中华传统色彩圆盘

## Overview

基于设计文档，按数据层 → 核心绘制 → UI 集成 → 交互功能的顺序逐步实现中华传统色彩圆盘功能。每个任务构建在前一个任务之上，确保增量可验证。

## Tasks

- [x] 1. 创建传统色数据模型和数据集
  - [x] 1.1 创建 `lib/data/traditional_chinese_colors.dart`，定义 `ChineseColor` 和 `ColorFamily` 数据类
    - 实现 `ChineseColor`：name, r, g, b, family 字段，`toColor()` 方法，`textColor` getter（基于亮度阈值 128）
    - 实现 `ColorFamily`：id, name, colors 字段
    - _Requirements: 6.4, 3.4_
  - [x] 1.2 填充 `TraditionalChineseColors` 静态数据集
    - 包含六个色系：红色系、黄色系、绿色系、蓝色系、紫色系、白灰黑系
    - 每个色系至少 8 种颜色，按明度从深到浅排列
    - 使用真实的中华传统色名称和准确 RGB 值
    - _Requirements: 6.1, 6.2, 6.3_
  - [ ]* 1.3 编写传统色数据完整性属性测试
    - **Property 6: 传统色数据完整性**
    - 验证每个色系至少 8 种颜色，每种颜色名称非空且 RGB 值在 [0, 255]
    - **Validates: Requirements 6.2, 6.3**
  - [ ]* 1.4 编写 textColor 属性测试
    - **Property 3: 文字颜色对比度**
    - 生成随机 RGB 值，验证 textColor 与亮度阈值计算一致
    - **Validates: Requirements 3.4**

- [x] 2. Checkpoint - 确保数据层测试通过
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. 实现色彩圆盘绘制器
  - [x] 3.1 创建 `lib/widgets/chinese_color_wheel_painter.dart`
    - 实现 `ChineseColorWheelPainter extends CustomPainter`
    - 绘制径向扇形布局：每个 ColorFamily 占据 360°/N 的扇形区域
    - 同一扇形内颜色从内圈（深色）到外圈（浅色）排列
    - 在色块上绘制中文颜色名称，文字颜色根据 `textColor` 自动适配
    - 选中色块高亮显示（描边或放大效果）
    - _Requirements: 2.2, 2.3, 3.1, 3.2, 3.4_
  - [x] 3.2 实现 `hitTest` 方法
    - 根据触摸坐标（相对于圆心的极坐标）计算命中的 ColorFamily 和 ChineseColor
    - 处理圆心区域（无色块）和圆盘外部（无命中）的情况
    - _Requirements: 5.1_
  - [x] 3.3 实现 snap-to-sector 对齐函数
    - 输入任意旋转角度，输出最近的扇形边界角度（360°/N 的整数倍）
    - _Requirements: 4.3_
  - [ ]* 3.4 编写扇形角度均分属性测试
    - **Property 1: 扇形角度均分**
    - 生成随机数量色系，验证每个扇形角度 = 360°/N 且总和 = 360°
    - **Validates: Requirements 2.2**
  - [ ]* 3.5 编写明度排序属性测试
    - **Property 2: 色块明度排序（内深外浅）**
    - 对每个色系验证颜色按明度非递减排列
    - **Validates: Requirements 2.3**
  - [ ]* 3.6 编写旋转对齐属性测试
    - **Property 4: 旋转对齐（Snap-to-sector）**
    - 生成随机角度和色系数量，验证 snap 结果为最近的扇形边界
    - **Validates: Requirements 4.3**

- [x] 4. 实现色彩圆盘覆盖层
  - [x] 4.1 创建 `lib/widgets/chinese_color_wheel_overlay.dart`
    - 实现 `ChineseColorWheelOverlay` StatefulWidget
    - 全屏黑色半透明背景 + 居中圆盘
    - 使用 `CustomPaint` 配合 `ChineseColorWheelPainter` 绘制圆盘
    - 顶部或中心显示选中颜色预览（名称 + RGB 值）
    - 提供关闭按钮（右上角 X）和确认按钮
    - 使用 `ResponsiveUtils` 适配不同屏幕尺寸
    - _Requirements: 2.1, 2.4, 2.5, 9.1, 9.2, 9.3_
  - [x] 4.2 实现旋转手势交互
    - 使用 `GestureDetector` 的 `onPanUpdate`/`onPanEnd` 处理圆弧拖动
    - 计算触摸点相对于圆心的角度变化量，更新 `rotationAngle`
    - 释放手势后使用 `AnimationController` 平滑对齐到最近扇形
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 4.3 实现色块点击选择
    - 使用 `GestureDetector` 的 `onTapUp` 获取点击坐标
    - 调用 `hitTest` 确定命中的颜色，更新选中状态和预览区域
    - 双击或点击确认按钮触发 `onColorSelected` 回调并关闭覆盖层
    - _Requirements: 3.3, 5.1, 5.2, 5.3_

- [x] 5. Checkpoint - 确保圆盘组件可独立运行
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. 集成到 RGBColorScreen
  - [x] 6.1 在 RGBColorScreen 左上角添加 Entry Button
    - 在顶部栏返回按钮旁添加圆形按钮（简洁圆圈样式，带彩色渐变提示）
    - 单击调用 `Navigator.push` 打开 `ChineseColorWheelOverlay`
    - 传入 `onColorSelected` 回调，接收选中颜色的 RGB 值
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_
  - [x] 6.2 实现颜色回填逻辑
    - `onColorSelected` 回调中更新当前选中 Zone 的 `_rgbValues[_selectedZone]`
    - 调用 `setState` 刷新滑块和区域按钮颜色
    - _Requirements: 5.2, 5.4_
  - [x] 6.3 实现 RGB 滑块数值手动输入
    - 将滑块右侧数值 `Text` 改为可点击组件
    - 点击后切换为 `TextField`（数字键盘，`FilteringTextInputFormatter.digitsOnly`）
    - 输入完成后校验并 clamp 到 [0, 255]，更新滑块值
    - 失焦或按回车确认，恢复为 Text 显示
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  - [ ]* 6.4 编写颜色回填一致性属性测试
    - **Property 5: 颜色选择回填一致性**
    - 生成随机 ChineseColor，模拟选择后验证滑块值匹配
    - **Validates: Requirements 5.2**
  - [ ]* 6.5 编写 RGB 输入值域校验属性测试
    - **Property 7: RGB 输入值域校验**
    - 生成随机整数（-1000 到 1000），验证 clamp 结果在 [0, 255]
    - **Validates: Requirements 7.2, 7.3**

- [x] 7. Final checkpoint - 确保所有测试通过
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- 需求 8（RGB 圆弧调色器）标记为可选功能，不包含在本实现计划中，可后续迭代添加
- 每个属性测试引用设计文档中的 Property 编号和对应需求
- Checkpoints 确保增量验证，避免问题累积
- 传统色数据应使用经过考证的真实中华传统色 RGB 值
