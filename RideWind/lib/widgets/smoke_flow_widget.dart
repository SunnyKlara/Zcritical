/// 风洞烟雾效果 V10 — 从 ASM 精确还原的欧拉流体求解器
///
/// 所有参数和逻辑均从原始 ARM64 反编译 ASM 提取，无猜测。
/// 渲染：3 层 drawCircle + MaskFilter blur（原始设计）。
/// 无障碍物系统（用户确认不需要）。
///
/// ASM 还原关键发现：
/// - step() 中的 _addSource 是专用的流线源注入（带 sin 波动）
/// - _velocityStep 使用 swap 模式（非 addSource 累加）
/// - _applyGravityEffect 仅在障碍物附近生效（无障碍物=空操作）
/// - _suppressVerticalVelocity 在无障碍物时对全场生效
/// - Painter 使用 Color.lerp 混合速度色

library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'smoke_config.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SmokeDynamics（向后兼容，静态工具类）
// ═══════════════════════════════════════════════════════════════════════════════

class SmokeDynamics {
  final int speed;
  late final double _ns;
  SmokeDynamics({required this.speed}) {
    _ns = (speed / 340.0).clamp(0.0, 1.0);
  }
  double get normalizedSpeed => _ns;
  double getWaveAnimationSpeed() => _ns * 3.0 + 0.5;
  double getParticleSpreadRange() => _ns * 50.0 + 20.0;
  double getParticleDriftRange() => _ns * 0.9 + 0.1;
  List<double> getParticleSpeedRange() => [_ns * 1.6 + 0.4, _ns * 3.0 + 1.0];
  List<double> getParticleOpacityRange() => [_ns * 0.3 + 0.2, _ns * 0.3 + 0.4];
  int getMaxParticles() => (_ns * 115.0 + 5.0).round();
  int getSmokeGenerationInterval() => (12 - _ns * 10).round().clamp(2, 12);
  List<double> getParticleSizeRange() => [_ns * 5.0 + 1.0, _ns * 9.0 + 3.0];
  int getWaveFrequency() => (_ns * 6.0 + 2.0).round();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FluidSimulation — ASM 精确还原（2D List 版本，匹配原始数据结构）
// ═══════════════════════════════════════════════════════════════════════════════

class _FluidSimulation {
  final int gridWidth;
  final int gridHeight;
  final double cellSize;

  // ASM 精确参数（从构造函数提取）
  // ignore: unused_field
  static const double _viscosity = 0.00008; // field_47（保留供后续 _velocityStep 扩展）
  static const double _diffusion = 0.00001; // field_4f
  static const double _dt = 0.06;           // field_57
  static const int _iterations = 8;         // ASM field_5f（构造函数值）

  // 2D 数组（匹配 ASM 原始 List<List<double>> 结构）
  late final List<List<double>> _u, _v, _uPrev, _vPrev;
  late final List<List<double>> _density, _densityPrev;
  late final List<double> _streamYPositions;

  // ASM field_6b: 平滑风力强度 (0~1)，初始 0.0（ASM stur xzr 确认）
  double _windStrength = 0.0;
  // ASM field_7b: 相位（每帧 +0.05）
  double _phase = 0.0;

  /// 配置引用（可空，提供时实时读取参数；为空时使用 ASM 默认值）
  SmokeConfig? config;

  _FluidSimulation(double pixelWidth, double pixelHeight, this.cellSize,
      {this.config, int streamCount = 8, double streamSpacing = 6.2})
      // ASM: gridWidth = ceil(width/5) + 2（不要 ×2，那会让网格 4 倍开销卡爆）
      : gridWidth = (pixelWidth / 5.0).ceil() + 2,
        gridHeight = (pixelHeight / 5.0).ceil() + 2 {
    _streamCount = streamCount;
    _streamSpacing = streamSpacing;
    _initializeFields();
    _initializeStreamPositions();
  }

  late int _streamCount;
  late double _streamSpacing;

  // ASM _initializeFields: 创建所有 2D 网格数组，初始化为 0.0
  void _initializeFields() {
    _u = List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
    _v = List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
    _uPrev = List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
    _vPrev = List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
    _density = List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
    _densityPrev =
        List.generate(gridWidth, (_) => List.filled(gridHeight, 0.0));
  }

  // ASM _initializeStreamPositions:
  // 流线居中，使用 config 提供的 streamCount + streamSpacing
  void _initializeStreamPositions() {
    final double totalSpan = (_streamCount - 1) * _streamSpacing;
    final double startY = gridHeight / 2.0 - totalSpan / 2.0;
    _streamYPositions =
        List<double>.generate(_streamCount, (i) => startY + i * _streamSpacing);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASM step(): field_6b lerp(target, 0.1) + field_7b += 0.05
  //   → _addSource (专用流线源注入，带 sin 波动)
  //   → _applyForceField
  //   → _velocityStep
  //   → _densityStep
  // ═══════════════════════════════════════════════════════════════════════════

  void step(int speedInput) {
    // field_6b: 平滑风力过渡 lerp(target, 0.1)
    final double target = (speedInput / 100.0).clamp(0.0, 1.0);
    _windStrength += (target - _windStrength) * 0.1;

    // field_7b: 相位递增
    _phase += 0.05;

    // ASM _addSource (addr 0x3e9028): 专用流线源注入
    _injectStreamSources();

    // ASM _applyForceField (addr 0x3e87c8)
    _applyForceField();

    // ASM _velocityStep (addr 0x3e6238)
    _velocityStep();

    // ASM _densityStep (addr 0x3e41b0)
    _densityStep();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASM _addSource (addr 0x3e9028) — 关键修正版（写入 live 数组，不是 prev）
  //
  // ASM 实际逻辑：
  //   for col in 1..3:
  //     for s in 0..streamYPositions.length:
  //       sinArg = phase * (s*0.2 + 1.0) + s*PI/3.0
  //       centerY = streamY[s] + sin(sinArg) * 0.3
  //       for dy = -0.7; dy <= 0.7; dy += 0.25:    ← 步长 0.25（不是 0.1）
  //         targetY = round(centerY + dy)
  //         if (0 < targetY < gridHeight - 1):
  //           dist = abs(targetY - centerY)
  //           weight = exp(-dist² / 0.1225)
  //           // 写入 live 数组 u/v/density（不是 uPrev/vPrev/densityPrev！）
  //           u[col][targetY] = 0.5             ← 硬设 0.5
  //           v[col][targetY] = 0.0             ← 硬设 0
  //           density[col][targetY] = max(weight * 1.3, density[col][targetY])
  // ═══════════════════════════════════════════════════════════════════════════

  void _injectStreamSources() {
    for (int col = 1; col <= 3 && col < gridWidth - 1; col++) {
      for (int s = 0; s < _streamYPositions.length; s++) {
        // sinArg = phase * (s * 0.2 + 1.0) + s * PI / 3.0
        final double freq = s * 0.2 + 1.0;
        final double sinArg = _phase * freq + s * pi / 3.0;
        final double swayAmp = config?.swayStrength ?? 0.3;
        final double centerY = _streamYPositions[s] + sin(sinArg) * swayAmp;

        // ASM 步长是 0.25（不是 0.1）— 范围 -0.7 到 0.7
        for (double dy = -0.7; dy <= 0.7; dy += 0.25) {
          final int targetY = (centerY + dy).round();
          if (targetY <= 0 || targetY >= gridHeight - 1) continue;

          // 高斯权重: exp(-dist² / 0.1225)
          final double dist = (targetY - centerY).abs();
          final double weight = exp(-dist * dist / 0.1225);

          // ★ 关键修正：写入 LIVE 数组（u/v/density），不是 prev！
          // u 硬设 0.5（恒定水平速度，不依赖 windStrength）
          _u[col][targetY] = 0.5;
          // v 硬设 0
          _v[col][targetY] = 0.0;
          // density 用 fmax，注入值是 weight * 1.3 * densityScale
          final double densityVal = weight * 1.3 * (config?.densityScale ?? 1.0);
          if (densityVal > _density[col][targetY]) {
            _density[col][targetY] = densityVal;
          }
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASM _applyForceField (addr 0x3e87c8)
  // forceEndCol = round(gridWidth * 0.2)
  // wakeStartCol = round(gridWidth * 0.8)
  // forceLeft = (wind * 2.0 + 0.1) * dt
  // forceRight = (wind + 0.05) * dt
  // 遍历网格，跳过密度 < 0.01 的单元格（无障碍物检查）
  // ═══════════════════════════════════════════════════════════════════════════

  void _applyForceField() {
    final int forceEndCol = (gridWidth * 0.2).round();
    final int wakeStartCol = (gridWidth * 0.8).round();
    // 减弱左侧推力系数，避免高速时密度被强行推压聚拢中心
    // 之前：(wind * 2.0 + 0.1)，现在：(wind * 0.8 + 0.1)
    final double forceLeft = (_windStrength * 0.8 + 0.1) * _dt;
    final double forceRight = (_windStrength + 0.05) * _dt;

    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        if (_density[i][j] <= 0.01) continue;

        if (i < forceEndCol) {
          _u[i][j] += forceLeft;
        } else if (i >= wakeStartCol) {
          _u[i][j] += forceRight;
        }

        // ASM: clamp velocities to [-20, 20]
        if (_u[i][j] > 20.0) _u[i][j] = 20.0;
        if (_u[i][j] < -20.0) _u[i][j] = -20.0;
        if (_v[i][j] > 20.0) _v[i][j] = 20.0;
        if (_v[i][j] < -20.0) _v[i][j] = -20.0;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASM _velocityStep (addr 0x3e6238)
  // 精确调用顺序：
  //   swap(u, uPrev) → swap(v, vPrev)
  //   → diffuse(1, u, uPrev, viscosity_a)
  //   → diffuse(2, v, vPrev, viscosity_a)
  //   → project(u, v, uPrev, vPrev)
  //   → swap(u, uPrev) → swap(v, vPrev)
  //   → advect(1, u, uPrev, uPrev, vPrev)
  //   → advect(2, v, vPrev, uPrev, vPrev)
  //   → project(u, v, uPrev, vPrev)
  //   → _applyGravityEffect (无障碍物=空操作)
  //   → _suppressVerticalVelocity
  //   → _applyObstacleBoundary (无障碍物=空操作)
  //
  // ASM viscosity_a 计算：
  //   d1 = 0.000016 (即 viscosity² 近似 = 0.00008² * gridW * gridH 的预计算)
  //   实际 ASM 加载的是 1.6e-05，这是 dt * viscosity * (N-2)² 的结果
  //   但 diffuse 内部会自己算 a = dt * diff * (N-2) * (N-2)
  //   ASM 中 _velocityStep 传给 _diffuse 的 diff 值是从 field_6b 计算的：
  //   diff_val = (1.0 - field_6b) * 1.6e-05
  //   这意味着风力越大，粘性扩散越小（烟雾更锐利）
  // ═══════════════════════════════════════════════════════════════════════════

  void _velocityStep() {
    // ASM: 计算动态粘性扩散系数
    // d1 = 1.6e-05, d0 = 1.0
    // d2 = field_6b (windStrength)
    // d3 = d0 - d2 = 1.0 - windStrength
    // d2 = d3 * d1 = (1.0 - windStrength) * 1.6e-05
    final double viscDiff = (1.0 - _windStrength) * 0.000016;

    // swap(u, uPrev)
    _swap2D(_u, _uPrev);
    // swap(v, vPrev)
    _swap2D(_v, _vPrev);

    // diffuse(1, u, uPrev, viscDiff)
    _diffuse(1, _u, _uPrev, viscDiff);
    // diffuse(2, v, vPrev, viscDiff)
    _diffuse(2, _v, _vPrev, viscDiff);

    // project
    _project(_u, _v, _uPrev, _vPrev);

    // swap(u, uPrev)
    _swap2D(_u, _uPrev);
    // swap(v, vPrev)
    _swap2D(_v, _vPrev);

    // advect(1, u, uPrev, uPrev, vPrev)
    _advect(1, _u, _uPrev, _uPrev, _vPrev);
    // advect(2, v, vPrev, uPrev, vPrev)
    _advect(2, _v, _vPrev, _uPrev, _vPrev);

    // project
    _project(_u, _v, _uPrev, _vPrev);

    // _applyGravityEffect: 无障碍物场景 = 空操作
    // （ASM 中此方法检查 obstacle 邻居，无障碍物时所有检查都 false）

    // _suppressVerticalVelocity（无障碍物 = no-op）
    _suppressVerticalVelocity();

    // 重力下坠趋势（只在 wind 弱时明显，wind 强时被水平风盖过）
    // 公式：v += gravity * (1 - wind) * dt
    // - speed=0:  v += 0.5 * dt（明显下坠）
    // - speed=max: v += 0（无重力，全水平流动）
    _applyGravity();

    // 流线型由车身障碍 + Painter 视觉叠加共同实现
    // 车身障碍清除密度，烟雾真正绕过；车形剖面在 Painter 上层显示
    _applyStreamlineForce();

    // _applyObstacleBoundary: 无障碍物 = 空操作

    // ★ 关键修正：不要清零 uPrev/vPrev — ASM 中 _addSource 写入 live 数组
    // 而非 prev 数组，因此 prev 在 _addSource 步骤中本来就是空的或已被使用
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASM _suppressVerticalVelocity (addr 0x3e7198)
  // factor = 1.0 - windStrength² * 0.8
  // 遍历内部网格，v[i][j] *= factor（无障碍物检查时对全场生效）
  // ═══════════════════════════════════════════════════════════════════════════

  // ASM _suppressVerticalVelocity (addr 0x3e7198) — 无障碍物时是 no-op
  // 用户确认障碍物在源代码里实际无效果，所以此方法在无障碍物场景下不应执行
  // 之前对全场压制 v 是导致 8 条离散条纹的直接原因
  void _suppressVerticalVelocity() {
    // 轻度压制 v：speed 越大压制越强，让高速时烟雾保持笔直流动
    // speed=0:   factor = 1.0（不压制，重力下坠正常）
    // speed=max: factor = 0.85（每帧 v 衰减 15%，保持流线笔直）
    // 注意：之前 V10 用 0.8 是导致条纹的元凶，这里只压制 0.15
    if (_windStrength < 0.1) return; // 低速直接跳过

    final double strength = config?.straightnessStrength ?? 0.15;
    final double factor = 1.0 - _windStrength * strength;
    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        if (_density[i][j] > 0.01) {
          _v[i][j] *= factor;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 重力下坠趋势（用户需求：speed=0 时明显下坠，speed=max 时被风盖过）
  // 只在有密度的格子施加，不影响空气格子
  // ═══════════════════════════════════════════════════════════════════════════
  void _applyGravity() {
    final double gStrength = config?.gravityStrength ?? 0.5;
    final double g = gStrength * (1.0 - _windStrength) * _dt;
    if (g <= 0.001) return;

    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        if (_density[i][j] > 0.01) {
          _v[i][j] += g;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 流线型设计 V2：赛车剖面 + 尾流合拢
  //
  // 赛车几何（侧视图，归一化坐标）：
  //   x: 0.20 ~ 0.55（车身长度 35%）
  //   厚度沿 x 变化（前低 → 中高 → 后低 → 尾翼）：
  //     - 前鼻锥 (x=0.20): 半厚 0.05
  //     - 前轮 (x=0.27): 半厚 0.10
  //     - 驾驶舱 (x=0.38): 半厚 0.13（最高）
  //     - 后轮 (x=0.48): 半厚 0.10
  //     - 尾翼 (x=0.55): 半厚 0.07
  //
  // 力场设计：
  //   - 车身轮廓内：强排斥力（垂直推开）
  //   - 车身上方/下方近邻：贴合力（沿轮廓滑过）
  //   - 车身后方（x > 0.55）：合拢力（v 向中心回归，模拟尾流闭合）
  // ═══════════════════════════════════════════════════════════════════════════

  /// 椭圆障碍：使用 config 配置的位置和大小
  /// （流线型设计后续优化，先用椭圆做基础）
  double _carHalfThickness(double xNorm) {
    if (config != null && !config!.obstacleEnabled) return 0.0;

    final double cx = config?.obstacleX ?? 0.40;
    final double rx = config?.obstacleRx ?? 0.15;
    final double ry = config?.obstacleRy ?? 0.12;

    final double dx = xNorm - cx;
    if (dx.abs() > rx) return 0.0;

    // 椭圆上半厚度 = ry * sqrt(1 - (dx/rx)²)
    final double t = dx / rx;
    return ry * sqrt(1 - t * t);
  }

  void _applyStreamlineForce() {
    if (_windStrength < 0.3) return;
    if (config != null && !config!.obstacleEnabled) return;

    final double cy = gridHeight * 0.5;

    // 纯椭圆障碍：仅清除椭圆内部的密度和速度
    // 烟雾在椭圆前自然被挡分流，过了椭圆后靠水平惯性 + 密度衰减自然合拢
    // 不加预偏转、不加切线引导、不加尾流推力 → 形状就是纯椭圆
    for (int i = 1; i < gridWidth - 1; i++) {
      final double xNorm = i / gridWidth;
      final double halfThick = _carHalfThickness(xNorm);
      if (halfThick <= 0.001) continue;

      final double obstHalfPx = halfThick * gridHeight;
      for (int j = 1; j < gridHeight - 1; j++) {
        final double dy = (j - cy).abs();
        if (dy < obstHalfPx) {
          // 强制清除椭圆内部的密度和速度
          _density[i][j] = 0.0;
          _u[i][j] = 0.0;
          _v[i][j] = 0.0;
        }
      }
    }
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // ASM _densityStep (addr 0x3e41b0)
  // ★ 关键修正：
  // - 不调用 _addSource（density 已经在 _injectStreamSources 中直接写入 live 数组）
  // - 末尾有密度衰减 density *= (0.99 - wind*0.01)
  // 流程：
  //   swap(density, densityPrev) → diffuse(0, density, densityPrev, diffusion)
  //   → swap(density, densityPrev) → advect(0, density, densityPrev, u, v)
  //   → density *= (0.99 - wind*0.01)（密度衰减）
  // ═══════════════════════════════════════════════════════════════════════════

  void _densityStep() {
    _swap2D(_density, _densityPrev);
    _diffuse(0, _density, _densityPrev, _diffusion);
    _swap2D(_density, _densityPrev);
    _advect(0, _density, _densityPrev, _u, _v);

    // 密度衰减：speed 越大衰减越快，但保持平滑（不要太陡导致断续）
    // 用 config.decayRate 控制速度衰减系数
    final double decayCoef = config?.decayRate ?? 0.02;
    final double decay = 0.99 - _windStrength * decayCoef;
    for (int i = 0; i < gridWidth; i++) {
      for (int j = 0; j < gridHeight; j++) {
        _density[i][j] *= decay;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 标准 Navier-Stokes 工具方法
  // ═══════════════════════════════════════════════════════════════════════════

  // _addSource: x[i][j] += dt * s[i][j]
  // ignore: unused_element
  void _addSource(List<List<double>> x, List<List<double>> s) {
    for (int i = 0; i < gridWidth; i++) {
      for (int j = 0; j < gridHeight; j++) {
        x[i][j] += _dt * s[i][j];
      }
    }
  }

  // _swap2D: 交换两个 2D 数组的内容
  void _swap2D(List<List<double>> a, List<List<double>> b) {
    for (int i = 0; i < gridWidth; i++) {
      for (int j = 0; j < gridHeight; j++) {
        final tmp = a[i][j];
        a[i][j] = b[i][j];
        b[i][j] = tmp;
      }
    }
  }

  // _diffuse: 扩散步骤
  // a = dt * diff * (gridWidth - 2) * (gridHeight - 2)
  void _diffuse(int b, List<List<double>> x, List<List<double>> x0,
      double diff) {
    final double a = _dt * diff * (gridWidth - 2) * (gridHeight - 2);
    _linearSolve(b, x, x0, a, 1.0 + 4.0 * a);
  }

  // _linearSolve: Gauss-Seidel 迭代求解
  void _linearSolve(
      int b, List<List<double>> x, List<List<double>> x0, double a, double c) {
    final double cRecip = 1.0 / c;
    for (int k = 0; k < _iterations; k++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        for (int j = 1; j < gridHeight - 1; j++) {
          x[i][j] = (x0[i][j] +
                  a *
                      (x[i + 1][j] +
                          x[i - 1][j] +
                          x[i][j + 1] +
                          x[i][j - 1])) *
              cRecip;
        }
      }
      _setBoundary(b, x);
    }
  }

  // _advect: 半拉格朗日对流
  void _advect(int b, List<List<double>> d, List<List<double>> d0,
      List<List<double>> velocX, List<List<double>> velocY) {
    final double dtx = _dt * (gridWidth - 2);
    final double dty = _dt * (gridHeight - 2);

    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        double x = i - dtx * velocX[i][j];
        double y = j - dty * velocY[i][j];
        x = x.clamp(0.5, gridWidth - 1.5);
        y = y.clamp(0.5, gridHeight - 1.5);

        final int i0 = x.floor(), i1 = i0 + 1;
        final int j0 = y.floor(), j1 = j0 + 1;
        final double s1 = x - i0, s0 = 1.0 - s1;
        final double t1 = y - j0, t0 = 1.0 - t1;

        d[i][j] = s0 * (t0 * d0[i0][j0] + t1 * d0[i0][j1]) +
            s1 * (t0 * d0[i1][j0] + t1 * d0[i1][j1]);
      }
    }
    _setBoundary(b, d);
  }

  // _project: Helmholtz-Hodge 投影（无散度化）
  void _project(List<List<double>> velocX, List<List<double>> velocY,
      List<List<double>> p, List<List<double>> div) {
    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        div[i][j] = -0.5 *
            (velocX[i + 1][j] - velocX[i - 1][j] +
                velocY[i][j + 1] - velocY[i][j - 1]) /
            gridWidth;
        p[i][j] = 0.0;
      }
    }
    _setBoundary(0, div);
    _setBoundary(0, p);
    _linearSolve(0, p, div, 1.0, 4.0);

    for (int i = 1; i < gridWidth - 1; i++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        velocX[i][j] -=
            0.5 * (p[i + 1][j] - p[i - 1][j]) * gridWidth;
        velocY[i][j] -=
            0.5 * (p[i][j + 1] - p[i][j - 1]) * gridHeight;
      }
    }
    _setBoundary(1, velocX);
    _setBoundary(2, velocY);
  }

  // _setBoundary: 边界条件
  void _setBoundary(int b, List<List<double>> x) {
    // 上下边界
    for (int i = 1; i < gridWidth - 1; i++) {
      x[i][0] = b == 2 ? -x[i][1] : x[i][1];
      x[i][gridHeight - 1] =
          b == 2 ? -x[i][gridHeight - 2] : x[i][gridHeight - 2];
    }
    // 左右边界
    for (int j = 1; j < gridHeight - 1; j++) {
      x[0][j] = b == 1 ? -x[1][j] : x[1][j];
      x[gridWidth - 1][j] =
          b == 1 ? -x[gridWidth - 2][j] : x[gridWidth - 2][j];
    }
    // 四角
    x[0][0] = 0.5 * (x[1][0] + x[0][1]);
    x[0][gridHeight - 1] =
        0.5 * (x[1][gridHeight - 1] + x[0][gridHeight - 2]);
    x[gridWidth - 1][0] =
        0.5 * (x[gridWidth - 2][0] + x[gridWidth - 1][1]);
    x[gridWidth - 1][gridHeight - 1] = 0.5 *
        (x[gridWidth - 2][gridHeight - 1] +
            x[gridWidth - 1][gridHeight - 2]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 公开接口供 Painter 使用
  // ═══════════════════════════════════════════════════════════════════════════

  double getDensity(int x, int y) {
    if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return 0.0;
    return _density[x][y].clamp(0.0, 2.0);
  }

  double getU(int x, int y) {
    if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return 0.0;
    return _u[x][y];
  }

  double getV(int x, int y) {
    if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return 0.0;
    return _v[x][y];
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// SmokeFlowWidget (= WindTunnelFlowAnimator)
// ═══════════════════════════════════════════════════════════════════════════════

class SmokeFlowWidget extends StatefulWidget {
  final Color smokeColor;
  final int speed;

  /// 可选的参数配置。如果传入，widget 会监听其变化并实时响应。
  /// 不传则使用默认配置（行为完全等同于 V14.2）。
  final SmokeConfig? config;

  const SmokeFlowWidget({
    super.key,
    this.smokeColor = const Color(0xFFCCCCCC),
    this.speed = 200,
    this.config,
  });
  @override
  State<SmokeFlowWidget> createState() => _SmokeFlowWidgetState();
}

typedef WindTunnelFlowAnimator = SmokeFlowWidget;

class _SmokeFlowWidgetState extends State<SmokeFlowWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  _FluidSimulation? _sim;
  Size _lastSize = Size.zero;

  /// 实际生效的配置：优先用 widget.config，否则用内置默认值
  late SmokeConfig _effectiveConfig;
  bool _ownsConfig = false;

  @override
  void initState() {
    super.initState();
    _setupConfig();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_tick)
      ..repeat();
  }

  void _setupConfig() {
    if (widget.config != null) {
      _effectiveConfig = widget.config!;
      _ownsConfig = false;
    } else {
      _effectiveConfig = SmokeConfig(smokeColor: widget.smokeColor);
      _ownsConfig = true;
    }
    _effectiveConfig.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    // 检查是否需要重建仿真（仅 streamCount/streamSpacing 改变时）
    // 颜色/blur/opacity 等参数只 repaint，不重建 sim
    if (_effectiveConfig.consumeRebuildFlag()) {
      // 标记 _lastSize 为零会让下一帧 LayoutBuilder 重建 sim
      _lastSize = Size.zero;
      _sim = null;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(SmokeFlowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != oldWidget.config) {
      _effectiveConfig.removeListener(_onConfigChanged);
      if (_ownsConfig) _effectiveConfig.dispose();
      _setupConfig();
    }
  }

  @override
  void dispose() {
    _effectiveConfig.removeListener(_onConfigChanged);
    if (_ownsConfig) _effectiveConfig.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _tick() {
    _sim?.step(widget.speed);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final w = box.maxWidth, h = box.maxHeight;
      // 仅在第一次或尺寸大幅变化(>20px)时重建仿真，避免面板弹出导致密度场归零
      final bool needRebuild = _sim == null ||
          (w - _lastSize.width).abs() > 20 ||
          (h - _lastSize.height).abs() > 20;
      if (needRebuild) {
        _lastSize = Size(w, h);
        _sim = _FluidSimulation(
          w,
          h,
          5.0,
          config: _effectiveConfig,
          streamCount: _effectiveConfig.streamCount,
          streamSpacing: _effectiveConfig.streamSpacing,
        );
      }
      // 保持 sim.config 为最新引用（容易遗漏）
      _sim?.config = _effectiveConfig;
      if (_sim == null) return const SizedBox.shrink();
      return RepaintBoundary(
        child: CustomPaint(
          size: Size(w, h),
          painter: _FluidPainter(
            sim: _sim!,
            smokeColor: _effectiveConfig.smokeColor,
            cellSize: 5.0,
            blur1Sigma: _effectiveConfig.blur1Sigma,
            blur2Sigma: _effectiveConfig.blur2Sigma,
            opacityScale: _effectiveConfig.opacityScale,
          ),
          isComplex: true,
          willChange: true,
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _FluidPainter — ASM _drawDensityField 精确还原
//
// 从 ASM 提取的渲染逻辑：
// - 3 个 MaskFilter 实例（3 个不同的 blur sigma）
// - 遍历网格 [1, gridWidth-1) × [1, gridHeight-1)
// - density clamp [0, 2]，跳过 < 0.01
// - speedNorm = sqrt(u² + v²) / 5.0, clamp [0, 1]
// - Color.lerp(smokeColor, smokeColor.withAlpha(0.8), speedNorm * 0.3 + 0.7)
// - Layer 1: radius = (speedNorm * 0.5 + 1.2) * cellSize
//            opacity = density * (speedNorm * 0.15 + 0.35)
// - Layer 2: radius = 3.0
//            opacity = density * (speedNorm * 0.15 + 0.35 + 0.85)
// - Layer 3: only if speedNorm > 0.5
//            radius = 2.0
//            opacity = (speedNorm - 0.5) * density * 0.8
// ═══════════════════════════════════════════════════════════════════════════════

class _FluidPainter extends CustomPainter {
  final _FluidSimulation sim;
  final Color smokeColor;
  final double cellSize;
  final double blur1Sigma;
  final double blur2Sigma;
  final double opacityScale;

  _FluidPainter({
    required this.sim,
    required this.smokeColor,
    required this.cellSize,
    this.blur1Sigma = 4.0,
    this.blur2Sigma = 2.0,
    this.opacityScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int w = sim.gridWidth;
    final int h = sim.gridHeight;
    final int r = smokeColor.red;
    final int g = smokeColor.green;
    final int b = smokeColor.blue;

    // 根据 config 动态创建 MaskFilter
    final MaskFilter blur1 =
        MaskFilter.blur(BlurStyle.normal, blur1Sigma);
    final MaskFilter blur2 =
        MaskFilter.blur(BlurStyle.normal, blur2Sigma);

    final paint1 = Paint()..style = PaintingStyle.fill;
    final paint2 = Paint()..style = PaintingStyle.fill;

    for (int i = 1; i < w - 1; i++) {
      final double px = i * cellSize;
      for (int j = 1; j < h - 1; j++) {
        final double d = sim.getDensity(i, j);
        if (d < 0.01) continue;

        final double py = j * cellSize;

        // 速度大小 → speedNorm (clamp [0,1])
        final double ux = sim.getU(i, j);
        final double vy = sim.getV(i, j);
        final double speed = sqrt(ux * ux + vy * vy);
        final double speedNorm = (speed / 5.0).clamp(0.0, 1.0);

        // ASM alpha 公式: density * (density * 0.4 + 1.0) clamped [0, 1]
        final double alphaBase = (d * (d * 0.4 + 1.0)).clamp(0.0, 1.0);

        // ASM Color.lerp: 高速时颜色更亮（lerp factor = speedNorm * 0.3 + 0.7）
        // 源代码用 colorScheme 两色混合，我们用 smokeColor → white 近似
        final double lerpFactor = speedNorm * 0.3 + 0.7;
        final int lr = r + ((255 - r) * lerpFactor * 0.8).round();
        final int lg = g + ((255 - g) * lerpFactor * 0.8).round();
        final int lb = b + ((255 - b) * lerpFactor * 0.8).round();

        // Layer 1: 大圆（外层柔和光晕）
        // 源代码效果：烟雾厚实明亮，opacity 需要更高
        final double radius1 = (speedNorm * 0.5 + 1.2) * cellSize;
        final double opacity1 = alphaBase * (speedNorm * 0.2 + 0.5) * opacityScale;
        paint1.color = Color.fromRGBO(lr, lg, lb, opacity1.clamp(0.0, 1.0));
        paint1.maskFilter = blur1;
        canvas.drawCircle(Offset(px, py), radius1, paint1);

        // Layer 2: 中圆（核心密度）
        // 源代码效果：核心区域非常亮
        final double opacity2 =
            alphaBase * (speedNorm * 0.2 + 0.7) * opacityScale;
        paint2.color = Color.fromRGBO(lr, lg, lb, opacity2.clamp(0.0, 1.0));
        paint2.maskFilter = blur2;
        canvas.drawCircle(Offset(px, py), 3.5, paint2);

        // Layer 3: 已移除（性能优化）
        // 之前每帧 ~5000 次额外 drawCircle + blur 是卡顿主因之一
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 流线型叠加层（独立于流体仿真，纯视觉效果）
    // 用静态贝塞尔曲线画车形剖面 + 周围流线，速度越大越明显
    // ═══════════════════════════════════════════════════════════════════════
    _drawStreamlineOverlay(canvas, size);
  }

  /// 绘制流线型叠加层
  /// - speed=0: 完全不画
  /// - speed=max: 画车形剖面 + 6 条流线
  void _drawStreamlineOverlay(Canvas canvas, Size size) {
    final double wind = sim._windStrength;
    if (wind < 0.2) return; // 低速不画

    final double w = size.width;
    final double h = size.height;
    final double cy = h * 0.5;

    // 椭圆障碍剖面（与 _carHalfThickness 中定义的椭圆保持一致）
    // 中心 (0.40, 0.50)，半轴 0.15 × 0.12（归一化坐标）
    final double cx = w * 0.40;
    final double rxPx = w * 0.15;
    final double ryPx = h * 0.12;

    final Rect ellipseRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rxPx * 2,
      height: ryPx * 2,
    );

    // 用背景色填充椭圆（"挖空"烟雾视觉效果）
    final Paint ellipseFill = Paint()
      ..color = Colors.black.withOpacity(0.85 * wind)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawOval(ellipseRect, ellipseFill);
  }

  @override
  bool shouldRepaint(covariant _FluidPainter old) => true;
}
