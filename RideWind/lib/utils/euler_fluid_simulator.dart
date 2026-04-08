import 'dart:math';
import 'dart:typed_data';

/// 欧拉视角流体模拟器
/// 基于 Navier-Stokes 方程的简化实现
/// 将空间划分为网格，追踪每个格子的速度场和密度场
class EulerFluidSimulator {
  final int gridWidth;
  final int gridHeight;
  final double dt; // 时间步长
  final double diffusion; // 扩散系数
  final double viscosity; // 粘性系数

  // 速度场 (u, v) - 每个格子的速度向量
  late Float64List _u; // x方向速度
  late Float64List _v; // y方向速度
  late Float64List _uPrev;
  late Float64List _vPrev;

  // 密度场 - 用于可视化（如烟雾浓度）
  late Float64List _density;
  late Float64List _densityPrev;

  // 涡度场（用于涡度约束）
  late Float64List _curl;

  // 涡度约束强度
  double vorticityStrength;

  // 衰减参数
  final double decayRate;
  final double velocityDecay;
  final double densityThreshold;

  // 迭代次数（用于求解泊松方程）
  final int iterations;

  // 重力场强度
  final double gravityStrength;

  // 粘性边界层参数
  double boundaryLayerDecay;
  int boundaryLayerThickness;

  // 右侧抽气风场参数
  double suctionStrength;
  int suctionWidth;

  // 湍流相关
  int _frameCount = 0;
  final Random _random = Random();

  EulerFluidSimulator({
    this.gridWidth = 64,
    this.gridHeight = 64,
    this.dt = 0.1,
    this.diffusion = 0.0001,
    this.viscosity = 0.0001,
    this.iterations = 20,
    this.vorticityStrength = 0.1,
    this.decayRate = 0.99,
    this.velocityDecay = 0.998,
    this.densityThreshold = 0.005,
    this.gravityStrength = 0.05,
    this.boundaryLayerDecay = 0.9,
    this.boundaryLayerThickness = 3,
    this.suctionStrength = 1.5,
    this.suctionWidth = 3,
  }) {
    final size = gridWidth * gridHeight;
    _u = Float64List(size);
    _v = Float64List(size);
    _uPrev = Float64List(size);
    _vPrev = Float64List(size);
    _density = Float64List(size);
    _densityPrev = Float64List(size);
    _curl = Float64List(size);
  }

  /// 获取一维索引
  int _idx(int x, int y) {
    x = x.clamp(0, gridWidth - 1);
    y = y.clamp(0, gridHeight - 1);
    return x + y * gridWidth;
  }

  /// 添加密度源（如烟雾源）
  void addDensity(int x, int y, double amount) {
    if (x >= 0 && x < gridWidth && y >= 0 && y < gridHeight) {
      _density[_idx(x, y)] += amount;
    }
  }

  /// 添加速度（外力）
  void addVelocity(int x, int y, double amountX, double amountY) {
    if (x >= 0 && x < gridWidth && y >= 0 && y < gridHeight) {
      final idx = _idx(x, y);
      _u[idx] += amountX;
      _v[idx] += amountY;
    }
  }

  /// 模拟一步
  void step() {
    // 1. 速度场扩散
    _diffuse(1, _uPrev, _u, viscosity);
    _diffuse(2, _vPrev, _v, viscosity);

    // 2. 投影（扩散后）
    _project(_uPrev, _vPrev, _u, _v);

    // 3. 速度场平流
    _advect(1, _u, _uPrev, _uPrev, _vPrev);
    _advect(2, _v, _vPrev, _uPrev, _vPrev);

    // 4. 投影（平流后）
    _project(_u, _v, _uPrev, _vPrev);

    // 5. 涡度约束
    _applyVorticityConfinement();

    // 6. 湍流扰动
    _applyTurbulence();

    // 7. 重力场
    _applyGravity();

    // 8. 右侧抽气风场
    _applySuctionWind();

    // 9. 粘性边界层
    _applyBoundaryLayer();

    // 10. 密度场演化
    _diffuse(0, _densityPrev, _density, diffusion);
    _advect(0, _density, _densityPrev, _u, _v);

    // 11. 衰减
    _applyDecay();

    // 12. 清理低密度
    _cleanupLowDensity();
  }

  /// 扩散（热传导/粘性扩散）
  /// 求解: x' = x + a * Laplacian(x) * dt
  void _diffuse(int b, Float64List x, Float64List x0, double diff) {
    final a = dt * diff * (gridWidth - 2) * (gridHeight - 2);

    for (int k = 0; k < iterations; k++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        for (int i = 1; i < gridWidth - 1; i++) {
          x[_idx(i, j)] = (x0[_idx(i, j)] +
                  a *
                      (x[_idx(i + 1, j)] +
                          x[_idx(i - 1, j)] +
                          x[_idx(i, j + 1)] +
                          x[_idx(i, j - 1)])) /
              (1 + 4 * a);
        }
      }
      _setBoundary(b, x);
    }
  }

  /// 平流（物质随速度场移动）
  /// 使用半拉格朗日方法：回溯粒子位置
  void _advect(int b, Float64List d, Float64List d0, Float64List u, Float64List v) {
    final dt0x = dt * (gridWidth - 2);
    final dt0y = dt * (gridHeight - 2);

    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        // 回溯位置
        var x = i - dt0x * u[_idx(i, j)];
        var y = j - dt0y * v[_idx(i, j)];

        // 边界限制
        x = x.clamp(0.5, gridWidth - 1.5);
        y = y.clamp(0.5, gridHeight - 1.5);

        // 双线性插值
        final i0 = x.floor();
        final i1 = i0 + 1;
        final j0 = y.floor();
        final j1 = j0 + 1;

        final s1 = x - i0;
        final s0 = 1 - s1;
        final t1 = y - j0;
        final t0 = 1 - t1;

        d[_idx(i, j)] = s0 * (t0 * d0[_idx(i0, j0)] + t1 * d0[_idx(i0, j1)]) +
            s1 * (t0 * d0[_idx(i1, j0)] + t1 * d0[_idx(i1, j1)]);
      }
    }
    _setBoundary(b, d);
  }

  /// 投影（保持速度场无散度，满足不可压缩条件）
  /// 求解泊松方程: Laplacian(p) = div(u)
  /// 然后: u = u - grad(p)
  void _project(Float64List u, Float64List v, Float64List p, Float64List div) {
    final h = 1.0 / ((gridWidth + gridHeight) / 2);

    // 计算散度
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        div[_idx(i, j)] = -0.5 *
            h *
            (u[_idx(i + 1, j)] -
                u[_idx(i - 1, j)] +
                v[_idx(i, j + 1)] -
                v[_idx(i, j - 1)]);
        p[_idx(i, j)] = 0;
      }
    }
    _setBoundary(0, div);
    _setBoundary(0, p);

    // 求解泊松方程（Gauss-Seidel迭代）
    for (int k = 0; k < iterations; k++) {
      for (int j = 1; j < gridHeight - 1; j++) {
        for (int i = 1; i < gridWidth - 1; i++) {
          p[_idx(i, j)] = (div[_idx(i, j)] +
                  p[_idx(i + 1, j)] +
                  p[_idx(i - 1, j)] +
                  p[_idx(i, j + 1)] +
                  p[_idx(i, j - 1)]) /
              4;
        }
      }
      _setBoundary(0, p);
    }

    // 减去压力梯度
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        u[_idx(i, j)] -= 0.5 * (p[_idx(i + 1, j)] - p[_idx(i - 1, j)]) / h;
        v[_idx(i, j)] -= 0.5 * (p[_idx(i, j + 1)] - p[_idx(i, j - 1)]) / h;
      }
    }
    _setBoundary(1, u);
    _setBoundary(2, v);
  }

  /// 设置边界条件
  void _setBoundary(int b, Float64List x) {
    // 上下边界：无滑移壁面
    for (int i = 1; i < gridWidth - 1; i++) {
      if (b == 1) {
        // u 分量：壁面处归零（无滑移）
        x[_idx(i, 0)] = 0;
        x[_idx(i, gridHeight - 1)] = 0;
      } else if (b == 2) {
        // v 分量：壁面处取反（反射）
        x[_idx(i, 0)] = -x[_idx(i, 1)];
        x[_idx(i, gridHeight - 1)] = -x[_idx(i, gridHeight - 2)];
      } else {
        // 密度等标量：Neumann 条件
        x[_idx(i, 0)] = x[_idx(i, 1)];
        x[_idx(i, gridHeight - 1)] = x[_idx(i, gridHeight - 2)];
      }
    }

    // 左右边界：开放 Neumann 条件（保持不变）
    for (int j = 1; j < gridHeight - 1; j++) {
      x[_idx(0, j)] = x[_idx(1, j)];
      x[_idx(gridWidth - 1, j)] = x[_idx(gridWidth - 2, j)];
    }

    // 四个角
    x[_idx(0, 0)] = 0.5 * (x[_idx(1, 0)] + x[_idx(0, 1)]);
    x[_idx(0, gridHeight - 1)] =
        0.5 * (x[_idx(1, gridHeight - 1)] + x[_idx(0, gridHeight - 2)]);
    x[_idx(gridWidth - 1, 0)] =
        0.5 * (x[_idx(gridWidth - 2, 0)] + x[_idx(gridWidth - 1, 1)]);
    x[_idx(gridWidth - 1, gridHeight - 1)] = 0.5 *
        (x[_idx(gridWidth - 2, gridHeight - 1)] +
            x[_idx(gridWidth - 1, gridHeight - 2)]);
  }

  /// 湍流扰动：仅在有密度的区域施加随机扰动
  void _applyTurbulence() {
    final amplitude = 0.03 * (0.8 + 0.2 * sin(_frameCount * 0.1));
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        final idx = _idx(i, j);
        if (_density[idx] < densityThreshold) continue;
        _u[idx] += amplitude * (_random.nextDouble() - 0.5);
        _v[idx] += amplitude * (_random.nextDouble() - 0.5);
      }
    }
    _frameCount++;
  }

  /// 重力场：对所有内部网格施加向下速度（物理场，与密度无关）
  void _applyGravity() {
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        _v[_idx(i, j)] += gravityStrength * dt;
      }
    }
  }

  /// 右侧抽气风场：距右边界 1~suctionWidth 个网格内，对 u 施加正向增量
  void _applySuctionWind() {
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int layer = 1; layer <= suctionWidth; layer++) {
        final x = gridWidth - 1 - layer;
        if (x > 0) {
          _u[_idx(x, j)] += suctionStrength * dt;
        }
      }
    }
  }

  /// 粘性边界层：距上下壁面 1~boundaryLayerThickness 个网格内，对速度施加递进衰减
  void _applyBoundaryLayer() {
    for (int i = 0; i < gridWidth; i++) {
      for (int layer = 1; layer <= boundaryLayerThickness; layer++) {
        final decay = boundaryLayerDecay +
            (1.0 - boundaryLayerDecay) * (layer / (boundaryLayerThickness + 1));
        // 上壁面附近
        final topIdx = _idx(i, layer);
        _u[topIdx] *= decay;
        _v[topIdx] *= decay;
        // 下壁面附近
        final bottomIdx = _idx(i, gridHeight - 1 - layer);
        _u[bottomIdx] *= decay;
        _v[bottomIdx] *= decay;
      }
    }
  }

  /// 衰减：对密度场和速度场施加逐帧衰减
  void _applyDecay() {
    for (int i = 0; i < _density.length; i++) {
      _density[i] *= decayRate;
      _u[i] *= velocityDecay;
      _v[i] *= velocityDecay;
    }
  }

  /// 清理低密度：将低于阈值的密度归零
  void _cleanupLowDensity() {
    for (int i = 0; i < _density.length; i++) {
      if (_density[i] > 0 && _density[i] < densityThreshold) {
        _density[i] = 0;
      }
    }
  }

  /// 涡度约束（Vorticity Confinement）
  /// 补偿数值耗散导致的涡旋细节丢失
  void _applyVorticityConfinement() {
    // 1. 计算涡度场 curl = ∂v/∂x - ∂u/∂y
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        _curl[_idx(i, j)] =
            (_v[_idx(i + 1, j)] - _v[_idx(i - 1, j)] -
             _u[_idx(i, j + 1)] + _u[_idx(i, j - 1)]) * 0.5;
      }
    }

    // 2. 计算涡度梯度方向并施加约束力
    for (int j = 1; j < gridHeight - 1; j++) {
      for (int i = 1; i < gridWidth - 1; i++) {
        final dwDx = (_curl[_idx(i + 1, j)].abs() - _curl[_idx(i - 1, j)].abs()) * 0.5;
        final dwDy = (_curl[_idx(i, j + 1)].abs() - _curl[_idx(i, j - 1)].abs()) * 0.5;
        final len = sqrt(dwDx * dwDx + dwDy * dwDy) + 1e-5;
        final nx = dwDx / len;
        final ny = dwDy / len;

        final curlVal = _curl[_idx(i, j)];
        _u[_idx(i, j)] += vorticityStrength * (ny * curlVal);
        _v[_idx(i, j)] -= vorticityStrength * (nx * curlVal);
      }
    }
  }

  /// 获取密度场（用于渲染）
  double getDensity(int x, int y) {
    return _density[_idx(x, y)].clamp(0.0, 1.0);
  }

  /// 获取速度场
  (double, double) getVelocity(int x, int y) {
    final idx = _idx(x, y);
    return (_u[idx], _v[idx]);
  }

  /// 重置模拟器
  void reset() {
    _u.fillRange(0, _u.length, 0);
    _v.fillRange(0, _v.length, 0);
    _uPrev.fillRange(0, _uPrev.length, 0);
    _vPrev.fillRange(0, _vPrev.length, 0);
    _density.fillRange(0, _density.length, 0);
    _densityPrev.fillRange(0, _densityPrev.length, 0);
    _curl.fillRange(0, _curl.length, 0);
    _frameCount = 0;
  }
}
