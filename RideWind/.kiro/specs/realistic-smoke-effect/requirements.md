# 需求文档：逼真烟雾效果（风洞水雾模拟）

## 简介

为 RideWind Flutter APP 的 DevTestScreen（开发测试界面，PageView index=0）实现一个高度逼真的烟雾视觉效果，模拟风洞玩具中水雾从左侧喷嘴射出、在封闭管道内向右飘散的真实物理行为。模拟区域为二维管状结构：左右边界开放（进出流），上下边界封闭（管壁），管壁附近有摩擦/粘性边界层效果。水雾受恒定重力场影响会自然下沉。需在移动设备上保持 60fps 流畅运行。

## 术语表

- **Fluid_Simulator**：基于 Navier-Stokes 方程的欧拉流体模拟器，负责计算速度场和密度场
- **Density_Field**：密度场，表示每个网格单元的烟雾浓度值（0.0~1.0）
- **Velocity_Field**：速度场，表示每个网格单元的流体速度向量 (u, v)
- **Smoke_Source**：烟雾源，在屏幕左侧边缘持续注入密度和速度的区域
- **Turbulence**：湍流扰动，通过随机扰动使烟雾运动更自然
- **Smoke_Renderer**：烟雾渲染器，将密度场转换为屏幕像素的 CustomPainter 组件
- **Vorticity_Confinement**：涡度约束，一种补偿数值耗散、保持烟雾卷曲细节的技术
- **DevTestScreen**：开发测试界面，PageView 最左侧页面（index=0），承载烟雾效果
- **Wind_Tunnel**：风洞管道，二维封闭管状模拟区域，上下为固体壁面，左右为开放边界
- **Boundary_Layer**：边界层，管壁附近因摩擦/粘性导致流速降低的区域
- **Gravity_Field**：重力场，恒定向下的加速度场，使水雾粒子自然下沉

## 需求

### 需求 1：烟雾源配置（风洞喷嘴）

**用户故事：** 作为用户，我希望看到水雾从屏幕左侧的风洞喷嘴自然地向右喷射，形成 5 股清晰分明的射流。

#### 验收标准

1. THE Smoke_Source SHALL 由 5 个独立喷嘴组成，均匀分布在屏幕左侧边缘，垂直方向覆盖管道高度的 10%~90% 区域
2. WHEN Fluid_Simulator 执行每一步模拟时，EACH 喷嘴 SHALL 持续向 Density_Field 注入密度值，注入强度在 0.6~1.0 之间随机波动
3. WHEN Fluid_Simulator 执行每一步模拟时，EACH 喷嘴 SHALL 向 Velocity_Field 注入主方向为正 x 轴（从左至右）的速度，水平速度分量在 2.0~4.0 之间
4. EACH 喷嘴 SHALL 在垂直方向施加极小的随机扰动速度（±0.15 以内），使射流保持基本笔直但有微小的自然波动
5. THE 5 股射流之间 SHALL 保持清晰的间距，不应在喷嘴附近合并为一团

### 需求 2：流体模拟物理增强（风洞管道物理）

**用户故事：** 作为用户，我希望水雾的运动行为接近真实风洞中的物理表现，包含重力下沉、管壁摩擦和自然消散。

#### 验收标准

1. THE Fluid_Simulator SHALL 使用不低于 80×80 的网格分辨率进行模拟
2. THE Fluid_Simulator SHALL 实现 Vorticity_Confinement 算法，在每步模拟中补偿数值耗散导致的涡旋细节丢失
3. THE Fluid_Simulator SHALL 在每步模拟中对 Velocity_Field 施加 Turbulence 扰动，扰动幅度随时间变化以避免重复模式
4. THE Fluid_Simulator SHALL 对 Density_Field 施加逐帧衰减系数（0.97~0.995 之间），使水雾在远离源头后自然消散
5. WHEN 烟雾密度值低于 0.005 时，THE Fluid_Simulator SHALL 将该网格单元的密度归零以避免残留伪影
6. THE Fluid_Simulator SHALL 在左侧边界使用开放入流条件（Neumann 条件），在右侧边界使用开放出流条件（Neumann 条件），允许水雾自然流入和流出
7. THE Fluid_Simulator SHALL 在右侧边界附近（距右边界 1~5 个网格单元内）施加恒定的向右"抽气"风场，对 Velocity_Field 的水平分量施加正向增量，模拟风洞抽风机的抽吸效果，加速水雾向右侧出口流出
8. THE 抽气风场的强度 SHALL 可配置，默认值使右侧边界附近的水平流速增加 30%~50%
9. THE Fluid_Simulator SHALL 在上下边界使用无滑移壁面条件（No-Slip Wall）：壁面处速度为零，垂直速度分量取反（反射），水平速度分量也归零
10. THE Fluid_Simulator SHALL 在上下壁面附近实现粘性边界层效果：距壁面 1~3 个网格单元内，对速度场施加额外的衰减系数（0.85~0.95），模拟管壁摩擦导致的流速降低
11. THE Fluid_Simulator SHALL 施加恒定的向下重力场（Gravity_Field），在每步模拟中对 Velocity_Field 的垂直分量施加恒定的正向增量（重力加速度），使水雾自然下沉
12. THE Gravity_Field 的强度 SHALL 可配置，默认值使水雾在横穿屏幕宽度后下沉约 10%~20% 的屏幕高度

### 需求 3：烟雾渲染效果

**用户故事：** 作为用户，我希望烟雾的视觉外观清晰可辨，便于观测和调试风洞模拟效果。

#### 验收标准

<!-- 暂时关闭模糊渲染，使用直接渲染以便观测调试。后期效果确认后再启用。
1. THE Smoke_Renderer SHALL 使用多层渲染策略，至少包含 2 层不同模糊半径的烟雾层叠加
2. THE Smoke_Renderer SHALL 将密度值映射为非线性透明度曲线（如 gamma 校正），使低密度区域更加柔和透明
5. THE Smoke_Renderer SHALL 对相邻网格单元的密度值进行双线性插值，消除明显的网格化方块感
-->

1. THE Smoke_Renderer SHALL 使用直接渲染模式：将密度值线性映射为透明度，不施加模糊滤镜，以便清晰观测烟雾流动路径和物理行为
2. THE Smoke_Renderer SHALL 使用从深灰色（低密度）到亮白色（高密度）的颜色渐变，背景为纯黑色
3. WHEN 密度值低于 0.01 时，THE Smoke_Renderer SHALL 跳过该网格单元的渲染以优化性能
4. THE Smoke_Renderer SHALL 支持通过参数开关在"直接渲染模式"和"模糊渲染模式"之间切换，便于后期启用模糊效果

### 需求 4：性能优化

**用户故事：** 作为用户，我希望烟雾效果在移动设备上流畅运行，不出现卡顿或掉帧。

#### 验收标准

1. THE DevTestScreen SHALL 以不超过 16ms 的帧间隔驱动模拟和渲染循环（目标 60fps）
2. THE Fluid_Simulator SHALL 将 Gauss-Seidel 迭代次数控制在 4~6 次之间，平衡精度与性能
3. THE Smoke_Renderer SHALL 使用 Canvas API 批量绘制操作，避免逐像素绘制
4. WHEN DevTestScreen 不在可视区域时（PageView 切换到其他页面），THE DevTestScreen SHALL 暂停模拟和渲染循环以释放 CPU 资源
5. THE Fluid_Simulator SHALL 使用 Float64List 类型的连续内存数组存储场数据，避免频繁的内存分配

### 需求 5：触摸交互

**用户故事：** 作为用户，我希望通过触摸屏幕与烟雾互动，增加趣味性。

#### 验收标准

1. WHEN 用户在屏幕上拖动手指时，THE DevTestScreen SHALL 在触摸位置周围的 5×5 网格区域内注入额外密度
2. WHEN 用户在屏幕上拖动手指时，THE DevTestScreen SHALL 根据手指移动方向和速度向 Velocity_Field 注入对应方向的速度
3. WHEN 用户抬起手指时，THE DevTestScreen SHALL 停止注入触摸产生的额外密度和速度，已注入的烟雾继续按物理规律演化

### 需求 6：生命周期管理

**用户故事：** 作为开发者，我希望烟雾效果正确管理资源，不造成内存泄漏或后台资源浪费。

#### 验收标准

1. WHEN DevTestScreen 被销毁时（dispose），THE DevTestScreen SHALL 取消所有定时器并释放模拟器资源
2. WHEN DevTestScreen 首次构建时，THE Fluid_Simulator SHALL 在 100ms 内完成初始化并开始首帧模拟
3. WHEN 用户从其他页面切换回 DevTestScreen 时，THE DevTestScreen SHALL 恢复模拟循环，烟雾从当前状态继续演化
