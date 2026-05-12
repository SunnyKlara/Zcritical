# 实现计划：逼真烟雾效果（风洞水雾模拟）

## 概述

将 DevTestScreen 从当前的 Canvas 路径绘制方案重构为基于 `EulerFluidSimulator` 的欧拉流体模拟方案。按照"模拟器增强 → 渲染器实现 → 界面重构 → 集成调优"的顺序递进实现。

## 任务

- [x] 1. 增强 EulerFluidSimulator 风洞管道物理
  - [x] 1.1 实现无滑移壁面条件和重力场
    - 修改 `lib/utils/euler_fluid_simulator.dart` 中的 `_setBoundary()` 方法
    - 上下边界：u 分量归零（无滑移），v 分量取反（反射），密度使用 Neumann 条件
    - 左右边界：保持现有 Neumann 开放边界条件不变
    - 新增 `gravityStrength` 构造函数参数（默认 0.05）
    - 新增 `_applyGravity()` 方法：对所有内部网格 v 分量施加 `gravityStrength * dt` 正向增量
    - 在 `step()` 中涡度约束和湍流之后调用 `_applyGravity()`
    - _Requirements: 2.9, 2.11_

  - [x] 1.2 实现粘性边界层和右侧抽气风场
    - 新增 `boundaryLayerDecay`（默认 0.9）、`boundaryLayerThickness`（默认 3）构造函数参数
    - 新增 `_applyBoundaryLayer()` 方法：距上下壁面 1~boundaryLayerThickness 个网格内，对速度施加递进衰减
    - 新增 `suctionStrength`（默认 1.5）、`suctionWidth`（默认 3）构造函数参数
    - 新增 `_applySuctionWind()` 方法：距右边界 1~suctionWidth 个网格内，对 u 施加 `suctionStrength * dt` 正向增量
    - 在 `step()` 中重力之后调用 `_applySuctionWind()` 和 `_applyBoundaryLayer()`
    - _Requirements: 2.7, 2.8, 2.10_

  - [x] 1.3 更新 step() 流程顺序
    - 确保 `step()` 按以下顺序执行：扩散→投影→平流→投影→涡度约束→湍流→重力→抽气风场→边界层→密度演化→衰减→清理
    - 确认 iterations=4，gridSize≥80，dt=0.15
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [ ]* 1.4 编写属性测试：无滑移壁面条件
    - **Property 7: 无滑移壁面条件**
    - 生成随机速度场，验证边界设置后上下壁面 u=0，v 取反
    - **Validates: Requirements 2.9**

  - [ ]* 1.5 编写属性测试：重力场增加下向速度
    - **Property 9: 重力场增加下向速度**
    - 生成随机速度场，验证重力后所有内部单元 v 增加 gravityStrength × dt
    - **Validates: Requirements 2.11**

  - [ ]* 1.6 编写属性测试：密度管理不变量
    - **Property 4: 密度管理不变量**
    - 生成随机非零密度场，验证一步模拟后密度不增加且无 0 < d < 0.005 的值
    - **Validates: Requirements 2.4, 2.5**

  - [ ]* 1.7 编写属性测试：开放边界和抽气风场
    - **Property 5: 开放边界 Neumann 条件**
    - 生成随机场状态，验证左右边界值等于相邻内部单元值
    - **Property 6: 抽气风场增加右向速度**
    - 生成随机速度场，验证抽气后右侧区域 u 分量增加
    - **Validates: Requirements 2.6, 2.7**

  - [ ]* 1.8 编写属性测试：边界层速度衰减
    - **Property 8: 粘性边界层速度衰减**
    - 生成随机非零速度场，验证边界层处理后壁面附近速度幅值减小
    - **Validates: Requirements 2.10**

- [x] 2. Checkpoint - 确保模拟器增强测试通过
  - 确保所有测试通过，如有问题请向用户确认。

- [x] 3. 实现 SmokeRenderer 直接渲染器
  - [x] 3.1 创建 SmokeRenderer 和 RenderMode
    - 在 `lib/screens/dev_test_screen.dart` 中新增 `RenderMode` 枚举（direct, blur）
    - 新增 `SmokeRenderer extends CustomPainter`，接收 simulator、gridWidth、gridHeight、renderMode 参数
    - 实现 `_renderDirect()` 方法：遍历网格，密度 < 0.01 跳过，密度线性映射为透明度，颜色从深灰 (0xFF404050) 到亮白 (0xFFe0e0ff) 线性插值
    - 实现 `_renderBlur()` 方法：暂时回退到 `_renderDirect()`，预留后期模糊渲染
    - 使用 `Canvas.drawRect` 批量绘制
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ]* 3.2 编写属性测试：渲染输出正确性
    - **Property 10: 渲染输出正确性**
    - 生成随机密度值 [0.01, 1.0]，验证透明度等于密度（线性），颜色在深灰和亮白之间
    - **Validates: Requirements 3.1, 3.2**

- [x] 4. 重构 DevTestScreen 使用 Euler 模拟器
  - [x] 4.1 移除旧的路径绘制代码，集成 EulerFluidSimulator
    - 移除 `_SmokeStream` 类、`_SmokeStreamPainter` 类
    - 在 `_DevTestScreenState` 中创建 `EulerFluidSimulator` 实例（gridSize=80, dt=0.15, iterations=4, 含所有新参数）
    - 初始化 5 个喷嘴 Y 坐标：均匀分布在 gridSize × 0.1 到 gridSize × 0.9
    - 实现 `_addSmokeFromNozzles()` 方法：每个喷嘴在 x=1~3 列注入密度 [0.6,1.0]、水平速度 [2.0,4.0]、垂直扰动 [±0.15]
    - Timer 每帧调用 `_addSmokeFromNozzles()` → `_simulator.step()` → `setState()`
    - 使用 `SmokeRenderer` 替代 `_SmokeStreamPainter`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 4.1_

  - [ ]* 4.2 编写属性测试：喷嘴位置和注入参数
    - **Property 1: 喷嘴位置约束**
    - 验证 5 个喷嘴 Y 坐标在 gridSize × 0.1 到 gridSize × 0.9 之间且均匀分布
    - **Property 2: 喷嘴注入参数范围**
    - 验证密度 [0.6,1.0]、水平速度 [2.0,4.0]、垂直扰动 [±0.15]
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4**

- [x] 5. Checkpoint - 确保渲染和喷嘴测试通过
  - 确保所有测试通过，如有问题请向用户确认。

- [x] 6. 集成触摸交互和生命周期管理
  - [x] 6.1 实现触摸交互
    - 实现 `_handlePanUpdate()` 方法：将触摸坐标转换为网格坐标，在 5×5 区域注入密度 0.5
    - 根据手指移动方向和速度注入对应速度（delta × 0.5）
    - `onPanEnd` 时停止注入（无需额外操作，因为不再调用 _handlePanUpdate）
    - _Requirements: 5.1, 5.2, 5.3_

  - [x] 6.2 实现 PageView 可见性和生命周期管理
    - 保持现有 `isVisible` 参数和 `didUpdateWidget` 逻辑
    - 确保 dispose 时取消 Timer
    - 确保 setState 前检查 mounted
    - _Requirements: 4.4, 6.1, 6.3_

  - [ ]* 6.3 编写属性测试：触摸交互注入
    - **Property 11: 触摸交互注入**
    - 生成随机触摸位置和方向，验证 5×5 区域密度增加且速度方向一致
    - **Validates: Requirements 5.1, 5.2**

- [x] 7. 性能调优与最终验证
  - [x] 7.1 确认性能参数
    - 确认 gridSize=80, dt=0.15, iterations=4
    - 确认所有场数据使用 Float64List
    - 确认 Timer 间隔 16ms
    - 确认渲染使用 Canvas.drawRect 批量绘制
    - _Requirements: 4.1, 4.2, 4.3, 4.5_

  - [x] 7.2 确认 PageView 集成
    - 确认 `DeviceConnectScreen` 中 `DevTestScreen(isVisible: _currentModeIndex == 0)` 正确传递可见性
    - _Requirements: 4.4, 6.3_

- [x] 8. 最终 Checkpoint - 确保所有测试通过
  - 确保所有测试通过，如有问题请向用户确认。

## 备注

- 标记 `*` 的任务为可选任务，可跳过以加速 MVP
- 每个任务引用了具体的需求编号以保证可追溯性
- Checkpoint 任务确保增量验证
- 属性测试使用 Dart `test` 包 + `dart:math.Random` 循环 100 次迭代实现
- 单元测试验证具体示例和边界情况
