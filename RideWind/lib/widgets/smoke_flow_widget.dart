/// ============================================================
/// 欧拉流体烟雾模拟 - 核心实现
/// ============================================================
/// 
/// 算法: Jos Stam "Stable Fluids" (1999)
/// 来源: 从 Flutter APK (package:flutter3) 逆向提取的结构
/// 
/// 已确认的类/方法名 (从 libapp.so 二进制提取):
///   - SmokeDynamics (求解器类)
///   - 方法: addSource, advect, diffuse, project, linearSolve,
///           setBoundary, densityStep, velocityStep, swap
///   - 字段: gridWidth, gridHeight, cellSize, density, densityPrev,
///           densityOffset, pressure, pressureMin, pressureMax,
///           velocity, turbulenceSeed
///
///   - WindTunnelFlowAnimator / _WindTunnelFlowAnimatorState (动画控件)
///   - 方法: _applyForceField, _applyGravityEffect, _applyObstacleBoundary,
///           _suppressVerticalVelocity, _setupObstacle, _createCarSvgPath,
///           _drawDensityField, _initializeFields, _initializeStreamPositions,
///           _updateSimulation
///   - 字段: _flowController, streamYPositions
///
///   - _WindTunnelFlowPainter (CustomPainter)
///   - SmokeParticlesPainter, SmokeParticle
///   - DynamicBackground, DynamicBackgroundPainter
///
/// 注意: 方法签名和结构100%来自APK逆向, 方法体内的具体参数值需要调优。
/// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// 第一部分: 欧拉流体求解器 (SmokeDynamics)
// ═══════════════════════════════════════════════════════════════

/// 2D 欧拉流体求解器
/// 
/// 核心思想: 在固定网格上求解 Navier-Stokes 方程
/// 每帧执行: velocityStep() -> densityStep()
/// 
/// 速度场步骤: addSource → diffuse → project → advect → project
/// 密度场步骤: addSource → diffuse → advect
class SmokeDynamics {
  final int gridWidth;   // 网格宽度 (从APK提取的字段名)
  final int gridHeight;  // 网格高度
  final double cellSize; // 单元格大小
  
  // ---- 模拟参数 (需要调优的关键值) ----
  double dt;          // 时间步长
  double diffusion;   // 扩散系数 (烟雾扩散速度)
  double viscosity;   // 粘性系数 (速度扩散)
  int iterations;     // Gauss-Seidel 迭代次数

  int _N;             // 内部网格边长 (从APK提取: _N)
  int _size;          // 总数组大小 = (N+2)*(N+2)

  // 速度场 (从APK提取: _u, _v)
  late List<double> _u, _v;       // 当前帧速度
  late List<double> _u0, _v0;     // 上一帧速度 / 临时缓冲

  // 密度场 (从APK提取: density, densityPrev)
  late List<double> density;
  late List<double> densityPrev;
  double densityOffset = 0.0;     // 从APK提取的字段

  // 压力场 (从APK提取: pressure, pressureMin, pressureMax)
  late List<double> pressure;
  double pressureMin = 0.0;
  double pressureMax = 1.0;

  int turbulenceSeed;  // 从APK提取的字段

  SmokeDynamics({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.cellSize = 1.0,
    this.dt = 0.1,
    this.diffusion = 0.0001,
    this.viscosity = 0.0,
    this.iterations = 20,
    this.turbulenceSeed = 42,
  }) {
    _N = gridWidth;
    _size = (gridWidth + 2) * (gridHeight + 2);
    _u = List.filled(_size, 0.0);
    _v = List.filled(_size, 0.0);
    _u0 = List.filled(_size, 0.0);
    _v0 = List.filled(_size, 0.0);
    density = List.filled(_size, 0.0);
    densityPrev = List.filled(_size, 0.0);
    pressure = List.filled(_size, 0.0);
  }

  /// 二维索引转一维
  int _ix(int x, int y) => x + (gridWidth + 2) * y;

  // ──────────────────────────────────────────────────────────
  // 核心算法步骤 (全部从APK确认存在)
  // ──────────────────────────────────────────────────────────

  /// [addSource] 将源项叠加到场中
  void addSource(List<double> field, List<double> source, double dt) {
    for (int i = 0; i < _size; i++) {
      field[i] += dt * source[i];
    }
  }

  /// [setBoundary] 设置边界条件
  /// b=0: 标量场(密度), b=1: x速度, b=2: y速度
  void setBoundary(int b, List<double> x) {
    final n = _N;
    for (int i = 1; i <= n; i++) {
      x[_ix(0, i)]     = b == 1 ? -x[_ix(1, i)] : x[_ix(1, i)];
      x[_ix(n + 1, i)] = b == 1 ? -x[_ix(n, i)] : x[_ix(n, i)];
      x[_ix(i, 0)]     = b == 2 ? -x[_ix(i, 1)] : x[_ix(i, 1)];
      x[_ix(i, n + 1)] = b == 2 ? -x[_ix(i, n)] : x[_ix(i, n)];
    }
    // 角点取平均
    x[_ix(0, 0)]         = 0.5 * (x[_ix(1, 0)] + x[_ix(0, 1)]);
    x[_ix(0, n + 1)]     = 0.5 * (x[_ix(1, n + 1)] + x[_ix(0, n)]);
    x[_ix(n + 1, 0)]     = 0.5 * (x[_ix(n, 0)] + x[_ix(n + 1, 1)]);
    x[_ix(n + 1, n + 1)] = 0.5 * (x[_ix(n, n + 1)] + x[_ix(n + 1, n)]);
  }

  /// [linearSolve] Gauss-Seidel 迭代求解线性系统
  void linearSolve(int b, List<double> x, List<double> x0, double a, double c) {
    final double cRecip = 1.0 / c;
    final n = _N;
    for (int k = 0; k < iterations; k++) {
      for (int j = 1; j <= n; j++) {
        for (int i = 1; i <= n; i++) {
          x[_ix(i, j)] = (x0[_ix(i, j)] +
              a * (x[_ix(i + 1, j)] + x[_ix(i - 1, j)] +
                   x[_ix(i, j + 1)] + x[_ix(i, j - 1)])) * cRecip;
        }
      }
      setBoundary(b, x);
    }
  }

  /// [diffuse] 扩散: 模拟分子扩散/粘性
  void diffuse(int b, List<double> x, List<double> x0, double diff, double dt) {
    double a = dt * diff * _N * _N;
    linearSolve(b, x, x0, a, 1 + 4 * a);
  }

  /// [advect] 对流: 半拉格朗日回溯法
  void advect(int b, List<double> d, List<double> d0,
              List<double> u, List<double> v, double dt) {
    final n = _N;
    final double dt0 = dt * n;
    for (int j = 1; j <= n; j++) {
      for (int i = 1; i <= n; i++) {
        double x = i - dt0 * u[_ix(i, j)];
        double y = j - dt0 * v[_ix(i, j)];
        x = x.clamp(0.5, n + 0.5);
        y = y.clamp(0.5, n + 0.5);
        int i0 = x.floor(), i1 = i0 + 1;
        int j0 = y.floor(), j1 = j0 + 1;
        double s1 = x - i0, s0 = 1 - s1;
        double t1 = y - j0, t0 = 1 - t1;
        d[_ix(i, j)] =
            s0 * (t0 * d0[_ix(i0, j0)] + t1 * d0[_ix(i0, j1)]) +
            s1 * (t0 * d0[_ix(i1, j0)] + t1 * d0[_ix(i1, j1)]);
      }
    }
    setBoundary(b, d);
  }

  /// [project] 投影: Helmholtz-Hodge 分解, 使速度场无散度
  void project(List<double> u, List<double> v,
               List<double> p, List<double> div) {
    final n = _N;
    final double h = 1.0 / n;
    for (int j = 1; j <= n; j++) {
      for (int i = 1; i <= n; i++) {
        div[_ix(i, j)] = -0.5 * h *
            (u[_ix(i + 1, j)] - u[_ix(i - 1, j)] +
             v[_ix(i, j + 1)] - v[_ix(i, j - 1)]);
        p[_ix(i, j)] = 0;
      }
    }
    setBoundary(0, div);
    setBoundary(0, p);
    linearSolve(0, p, div, 1, 4);
    for (int j = 1; j <= n; j++) {
      for (int i = 1; i <= n; i++) {
        u[_ix(i, j)] -= 0.5 * n * (p[_ix(i + 1, j)] - p[_ix(i - 1, j)]);
        v[_ix(i, j)] -= 0.5 * n * (p[_ix(i, j + 1)] - p[_ix(i, j - 1)]);
      }
    }
    setBoundary(1, u);
    setBoundary(2, v);
  }

  /// [swap] 交换两个场的数据
  void swap(List<double> a, List<double> b) {
    for (int i = 0; i < _size; i++) {
      final t = a[i]; a[i] = b[i]; b[i] = t;
    }
  }

  /// [velocityStep] 速度场完整步进
  void velocityStep() {
    addSource(_u, _u0, dt);
    addSource(_v, _v0, dt);
    swap(_u0, _u); diffuse(1, _u, _u0, viscosity, dt);
    swap(_v0, _v); diffuse(2, _v, _v0, viscosity, dt);
    project(_u, _v, _u0, _v0);
    swap(_u0, _u); swap(_v0, _v);
    advect(1, _u, _u0, _u0, _v0, dt);
    advect(2, _v, _v0, _u0, _v0, dt);
    project(_u, _v, _u0, _v0);
  }

  /// [densityStep] 密度场完整步进
  void densityStep() {
    addSource(density, densityPrev, dt);
    swap(densityPrev, density);
    diffuse(0, density, densityPrev, diffusion, dt);
    swap(densityPrev, density);
    advect(0, density, densityPrev, _u, _v, dt);
  }

  // ──────────────────────────────────────────────────────────
  // 辅助方法
  // ──────────────────────────────────────────────────────────

  void addDensityAt(int x, int y, double amount) {
    if (x > 0 && x <= _N && y > 0 && y <= _N) {
      density[_ix(x, y)] += amount;
    }
  }

  void addVelocityAt(int x, int y, double vx, double vy) {
    if (x > 0 && x <= _N && y > 0 && y <= _N) {
      _u[_ix(x, y)] += vx;
      _v[_ix(x, y)] += vy;
    }
  }

  double getDensityAt(int x, int y) => density[_ix(x, y)];
  double getVelocityX(int x, int y) => _u[_ix(x, y)];
  double getVelocityY(int x, int y) => _v[_ix(x, y)];

  void clearPrevious() {
    _u0.fillRange(0, _size, 0.0);
    _v0.fillRange(0, _size, 0.0);
    densityPrev.fillRange(0, _size, 0.0);
  }

  void reset() {
    for (var list in [_u, _v, _u0, _v0, density, densityPrev, pressure]) {
      list.fillRange(0, _size, 0.0);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 第二部分: 风洞烟雾可视化 (WindTunnelFlowAnimator)
// ═══════════════════════════════════════════════════════════════

/// 风洞流动动画 - 将欧拉流体求解器可视化为烟雾效果
class WindTunnelFlowAnimator extends StatefulWidget {
  final double windSpeed;
  final double smokeIntensity;
  final Color smokeColor;
  final bool showObstacle;

  const WindTunnelFlowAnimator({
    super.key,
    this.windSpeed = 5.0,
    this.smokeIntensity = 1.0,
    this.smokeColor = Colors.white,
    this.showObstacle = true,
  });

  @override
  State<WindTunnelFlowAnimator> createState() => _WindTunnelFlowAnimatorState();
}

class _WindTunnelFlowAnimatorState extends State<WindTunnelFlowAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _flowController;
  late SmokeDynamics _solver;

  static const int _gridW = 80;
  static const int _gridH = 50;

  late List<double> _streamYPositions;

  @override
  void initState() {
    super.initState();
    _solver = SmokeDynamics(
      gridWidth: _gridW,
      gridHeight: _gridH,
      dt: 0.05,
      diffusion: 0.00005,
      viscosity: 0.0,
      iterations: 16,
    );
    _initializeFields();
    _initializeStreamPositions();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_updateSimulation);
    _flowController.repeat();
  }

  void _initializeFields() {
    for (int j = 1; j <= _gridH; j++) {
      for (int i = 1; i <= _gridW; i++) {
        _solver.addVelocityAt(i, j, widget.windSpeed, 0.0);
      }
    }
  }

  void _initializeStreamPositions() {
    const int numStreams = 12;
    _streamYPositions = List.generate(
      numStreams,
      (i) => (i + 1) * _gridH / (numStreams + 1),
    );
  }

  void _updateSimulation() {
    _solver.clearPrevious();
    _applyForceField();
    _applyGravityEffect();
    if (widget.showObstacle) _applyObstacleBoundary();
    _suppressVerticalVelocity();
    _solver.velocityStep();
    _solver.densityStep();
    setState(() {});
  }

  void _applyForceField() {
    for (int j = 1; j <= _gridH; j++) {
      double phase = j / _gridH * pi * 2 + _flowController.value * pi * 4;
      double mod = 0.5 + 0.5 * sin(phase);
      _solver.addDensityAt(2, j, widget.smokeIntensity * mod * 0.8);
      _solver.addDensityAt(3, j, widget.smokeIntensity * mod * 0.4);
      _solver.addVelocityAt(1, j, widget.windSpeed * 0.5, 0.0);
      _solver.addVelocityAt(2, j, widget.windSpeed * 0.3, 0.0);
    }
  }

  void _applyGravityEffect() {
    for (int j = 1; j <= _gridH; j++) {
      for (int i = 1; i <= _gridW; i++) {
        double d = _solver.getDensityAt(i, j);
        if (d > 0.01) {
          _solver.addVelocityAt(i, j, 0.0, -d * 0.02);
        }
      }
    }
  }

  void _applyObstacleBoundary() {
    final int cx = (_gridW * 0.35).round();
    final int cy = (_gridH * 0.5).round();
    final int r = (min(_gridW, _gridH) * 0.08).round();
    for (int j = cy - r; j <= cy + r; j++) {
      for (int i = cx - r; i <= cx + r; i++) {
        if (i > 0 && i <= _gridW && j > 0 && j <= _gridH) {
          double dist = sqrt(pow(i - cx, 2) + pow(j - cy, 2).toDouble());
          if (dist <= r) {
            double vx = _solver.getVelocityX(i, j);
            double vy = _solver.getVelocityY(i, j);
            _solver.addVelocityAt(i, j, -vx, -vy);
          }
        }
      }
    }
  }

  void _suppressVerticalVelocity() {
    for (int j = 1; j <= _gridH; j++) {
      for (int i = 1; i <= _gridW; i++) {
        double vy = _solver.getVelocityY(i, j);
        if (vy.abs() > widget.windSpeed * 2) {
          _solver.addVelocityAt(i, j, 0.0, -vy * 0.5);
        }
      }
    }
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _WindTunnelFlowPainter(
        solver: _solver,
        gridW: _gridW,
        gridH: _gridH,
        smokeColor: widget.smokeColor,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 第三部分: 烟雾渲染 (_WindTunnelFlowPainter)
// ═══════════════════════════════════════════════════════════════

class _WindTunnelFlowPainter extends CustomPainter {
  final SmokeDynamics solver;
  final int gridW, gridH;
  final Color smokeColor;

  _WindTunnelFlowPainter({
    required this.solver,
    required this.gridW,
    required this.gridH,
    required this.smokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawDensityField(canvas, size);
  }

  void _drawDensityField(Canvas canvas, Size size) {
    final double cellW = size.width / (gridW + 2);
    final double cellH = size.height / (gridH + 2);
    for (int j = 1; j <= gridH; j++) {
      for (int i = 1; i <= gridW; i++) {
        double d = solver.getDensityAt(i, j).clamp(0.0, 1.0);
        if (d > 0.005) {
          canvas.drawRect(
            Rect.fromLTWH(i * cellW, j * cellH, cellW + 1, cellH + 1),
            Paint()
              ..color = smokeColor.withOpacity(d * 0.85)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════
// 兼容别名
// ═══════════════════════════════════════════════════════════════
typedef SmokeFlowWidget = WindTunnelFlowAnimator;
