---
inclusion: auto
---

# 🚨 烟雾效果复刻 — 最高优先级任务，绝对不可敷衍

> **用户已经尝试了几千次都没成功复刻出来。这不是"写个差不多的效果"，这是精确还原。**

## 核心要求

**目标**：复刻竞品 APK 中的欧拉流体烟雾效果。

**正确的方法论（2026-05-25 确认）**：
- ❌ 不要一上来就照搬全部 ASM 参数做完整求解器 — 效果死板、卡顿、不飘逸
- ✅ 从"一缕完美的飘逸烟雾"开始，逐步加复杂度
- ✅ 像当初写源代码一样：先做出好看的基础效果，再叠加物理特性
- ✅ 动态效果比静态截图重要 — 静态看着像但动起来完全不对

**已验证失败的方案（避免重复）**：
1. 完整欧拉求解器 + 逐 cell 画圆 → 卡顿 + 颗粒感 + 厚重
2. 跳格渲染(步长2) + 大模糊圆 → 仍卡 + 仍有颗粒感
3. 逐行扫描画水平矩形 → 死板横条，完全没有飘逸感
4. 密度注入太多(1.3) → 浓雾堆积
5. 力场注入密度 → 全屏白雾
6. 像素缓冲区渲染(ui.Image) + 简化求解器 → 密度仍然饱和全屏白
   - 根因：advect 的 dt0 计算错误（dt0*gridWidth*u 回溯太远）+ diffuse 在低系数时无效
   - 渲染架构(drawImage)是对的，但求解器逻辑有 bug

**下一步正确方向**：
- 渲染用 ui.Image（1次drawCall）— 这个方向已验证是对的
- 求解器要从最简单开始：**不用 diffuse，不用 advect，只用"每帧把密度数组向右移动1格"**
- 先验证渲染管线能正确显示"6条水平线从左向右移动"
- 确认基础管线工作后，再逐步加 advect、diffuse、正弦扰动等

**来源**：通过 blutter 反编译竞品 APK 得到的 ARM64 汇编伪代码，存放在 `smoke-ref/` 子仓库。

**难度认知**：
- 这是 Jos Stam "Stable Fluids" 完整欧拉流体求解器，不是简单粒子系统
- 包含 Navier-Stokes 方程近似求解（扩散 + 对流 + 投影）
- 包含障碍物碰撞（车辆轮廓 Path）
- 包含 3 层密度场渲染（大圆模糊 + 中圆 + 小圆高光）
- 所有参数都是从 ARM64 浮点指令中逐个提取的精确值
- **任何一个参数错误、任何一个调用顺序错误，效果就完全不对**

## 绝对禁止

- ❌ 不要用"简化版"替代 — 用户试过了，效果不对
- ❌ 不要用粒子系统模拟 — 原版是网格密度场，视觉本质不同
- ❌ 不要猜参数 — 所有参数都在 `smoke-ref/PROMPT_FOR_TRANSLATION.md` 中精确列出
- ❌ 不要改调用顺序 — ASM 中的顺序就是正确顺序
- ❌ 不要"优化"算法 — 原版怎么写就怎么写，哪怕看起来低效
- ❌ 不要省略任何步骤（gravity、suppressVertical、obstacleBoundary 一个都不能少）

## 精确参数来源

所有参数见 `smoke-ref/PROMPT_FOR_TRANSLATION.md`，关键值：
- dt=0.06, diffusion=0.00001, viscosity=0.00008, iterations=10, cellSize=5.0
- 8条流线，起始位置 gridHeight/2 - 22.3 + 0.6，间距 6.2
- 3列注入，正弦振荡 sin(phase*streamY[i] + index*pi/3)*0.3
- 密度衰减 0.99 - progress*0.01
- 重力 (1-progress)²*0.25*dt
- 渲染 3 层圆（大圆 radius=(vel*0.5+1.2)*5，中圆 3.0，小圆 2.0）

## ASM 反编译文件

- `smoke-ref/decompiled/wind_tunnel_flow_animator.dart.asm` — 11677行，核心求解器
- `smoke-ref/decompiled/smoke_dynamics.dart.asm` — 689行，参数计算（已还原✅）
- `smoke-ref/decompiled/smoke_particles_painter.dart.asm` — 1949行，渲染
- `smoke-ref/decompiled/dynamic_background.dart.asm` — 3415行，动态背景

## 实现文件

- `RideWind/lib/widgets/smoke_flow_widget.dart` — 主文件（FluidSimulation + Widget + Painter）
- `RideWind/lib/utils/smoke_dynamics.dart` — 参数计算（已完成✅，参数正确）

## 验证标准

效果正确的标志：
1. 烟雾从左侧 3 列注入，呈现连续流线（不是离散粒子）
2. 流线经过中央障碍物时分流绕行
3. 高速时流线更紧密、更亮、更快
4. 低速时有明显的重力下沉效果
5. 密度场渲染有层次感（模糊大圆 + 清晰小圆）
6. 整体视觉与竞品 APK 一致
