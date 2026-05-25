/// ============================================================
/// 欧拉流体烟雾模拟 — v3 (流体网格 + 粒子系统双层)
/// ============================================================
///
/// 严格按照反编译确认的原始架构:
///   层1: FluidSimulation — 欧拉流体网格，提供流场方向 + 背景密度渲染
///   层2: SmokeParticles — 粒子系统，提供飘逸的视觉主体
///
/// 粒子参数 (从 smoke_particles_painter.dart.asm 提取):
///   - fadeRate = normalizedSpeed * 0.015 + 0.005
///   - growRate = normalizedSpeed * 0.15 + 0.05
///   - particle.y -= particle.speed (上升/水平飘动)
///   - particle.x += particle.drift
///   - particle.opacity -= fadeRate
///   - particle.size += growRate
///   - 新粒子 x = (random - 0.5) * spreadRange + 30.0
///   - maxParticles = round(sqrt(ns) * 115 + 5)
///   - generationInterval = clamp(round(12 - ns*10), 2, 12)
/// ============================================================

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
// 粒子数据结构
// ═══════════════════════════════════════════════════════════════

class _SmokeParticle {
  double x;
  double y;
  double opacity;
  double size;
  double speed;   // 水平飘动速度
  double drift;   // 垂直漂移
  int streamIndex; // 属于哪条流线

  _SmokeParticle({
    required this.x,
    required this.y,
    required this.opacity,
    required this.size,
    required this.speed,
    required this.drift,
    required this.streamIndex,
  });
}

// ═══════════════════════════════════════════════════════════════
// 轻量流体求解器 (只用于提供流场方向，不做主要渲染)
// ═══════════════════════════════════════════════════════════════

class _LightFluidSolver {
  final int w, h;
  final int _stride;
  final int _size;

  late Float64List u, v;
  late Float64List _uTmp, _vTmp;

  _LightFluidSolver({required this.w, required this.h})
      : _stride = w + 2,
        _size = (w + 2) * (h + 2) {
    u = Float64List(_size);
    v = Float64List(_size);
    _uTmp = Float64List(_size);
    _vTmp = Float64List(_size);
  }

  int ix(int x, int y) => x + _stride * y;

  void _setBnd(int b, Float64List x) {
    for (int i = 1; i <= w; i++) {
      x[ix(i, 0)] = b == 2 ? -x[ix(i, 1)] : x[ix(i, 1)];
      x[ix(i, h + 1)] = b == 2 ? -x[ix(i, h)] : x[ix(i, h)];
    }
    for (int j = 1; j <= h; j++) {
      x[ix(0, j)] = b == 1 ? -x[ix(1, j)] : x[ix(1, j)];
      x[ix(w + 1, j)] = b == 1 ? -x[ix(w, j)] : x[ix(w, j)];
    }
  }

  void _linSolve(int b, Float64List x, Float64List x0, double a, double c) {
    final cR = 1.0 / c;
    for (int k = 0; k < 4; k++) {
      for (int j = 1; j <= h; j++) {
        for (int i = 1; i <= w; i++) {
          final idx = ix(i, j);
          x[idx] = (x0[idx] +
              a * (x[ix(i + 1, j)] + x[ix(i - 1, j)] +
                  x[ix(i, j + 1)] + x[ix(i, j - 1)])) * cR;
        }
      }
      _setBnd(b, x);
    }
  }

  void _diffuse(int b, Float64List x, Float64List x0, double diff, double dt) {
    final a = dt * diff * w * h;
    _linSolve(b, x, x0, a, 1 + 4 * a);
  }

  void _advect(int b, Float64List d, Float64List d0, Float64List u, Float64List v, double dt) {
    final dt0x = dt * w;
    final dt0y = dt * h;
    for (int j = 1; j <= h; j++) {
      for (int i = 1; i <= w; i++) {
        double x = i - dt0x * u[ix(i, j)];
        double y = j - dt0y * v[ix(i, j)];
        x = x.clamp(0.5, w + 0.5);
        y = y.clamp(0.5, h + 0.5);
        final i0 = x.floor(), i1 = i0 + 1;
        final j0 = y.floor(), j1 = j0 + 1;
        final s1 = x - i0, s0 = 1.0 - s1;
        final t1 = y - j0, t0 = 1.0 - t1;
        d[ix(i, j)] = s0 * (t0 * d0[ix(i0, j0)] + t1 * d0[ix(i0, j1)]) +
            s1 * (t0 * d0[ix(i1, j0)] + t1 * d0[ix(i1, j1)]);
      }
    }
    _setBnd(b, d);
  }

  void _project() {
    final hVal = 1.0 / max(w, h);
    for (int j = 1; j <= h; j++) {
      for (int i = 1; i <= w; i++) {
        _vTmp[ix(i, j)] = -0.5 * hVal *
            (u[ix(i + 1, j)] - u[ix(i - 1, j)] + v[ix(i, j + 1)] - v[ix(i, j - 1)]);
        _uTmp[ix(i, j)] = 0;
      }
    }
    _setBnd(0, _vTmp);
    _setBnd(0, _uTmp);
    _linSolve(0, _uTmp, _vTmp, 1, 4);
    for (int j = 1; j <= h; j++) {
      for (int i = 1; i <= w; i++) {
        u[ix(i, j)] -= 0.5 * w * (_uTmp[ix(i + 1, j)] - _uTmp[ix(i - 1, j)]);
        v[ix(i, j)] -= 0.5 * h * (_uTmp[ix(i, j + 1)] - _uTmp[ix(i, j - 1)]);
      }
    }
    _setBnd(1, u);
    _setBnd(2, v);
  }

  /// 步进速度场
  void step(double dt) {
    _uTmp.setAll(0, u);
    _diffuse(1, u, _uTmp, 0.00001, dt);
    _vTmp.setAll(0, v);
    _diffuse(2, v, _vTmp, 0.00001, dt);
    _project();
    _uTmp.setAll(0, u);
    _vTmp.setAll(0, v);
    _advect(1, u, _uTmp, _uTmp, _vTmp, dt);
    _advect(2, v, _vTmp, _uTmp, _vTmp, dt);
    _project();
  }

  /// 获取某像素位置的速度（双线性插值）
  Offset getVelocityAt(double px, double py, double cellW, double cellH) {
    // 像素坐标转网格坐标
    final gx = (px / cellW).clamp(0.5, w + 0.5);
    final gy = (py / cellH).clamp(0.5, h + 0.5);
    final i0 = gx.floor().clamp(0, w);
    final j0 = gy.floor().clamp(0, h);
    final i1 = (i0 + 1).clamp(0, w + 1);
    final j1 = (j0 + 1).clamp(0, h + 1);
    final sx = gx - i0, sy = gy - j0;

    final vx = (1 - sx) * (1 - sy) * u[ix(i0, j0)] +
        sx * (1 - sy) * u[ix(i1, j0)] +
        (1 - sx) * sy * u[ix(i0, j1)] +
        sx * sy * u[ix(i1, j1)];
    final vy = (1 - sx) * (1 - sy) * v[ix(i0, j0)] +
        sx * (1 - sy) * v[ix(i1, j0)] +
        (1 - sx) * sy * v[ix(i0, j1)] +
        sx * sy * v[ix(i1, j1)];
    return Offset(vx, vy);
  }
}

// ═══════════════════════════════════════════════════════════════
// 主 Widget: 风洞烟雾动画
// ═══════════════════════════════════════════════════════════════

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
  late AnimationController _controller;
  late _LightFluidSolver _fluid;
  final List<_SmokeParticle> _particles = [];
  final Random _rng = Random();

  // 流体网格（小网格，只提供方向）
  static const int _fluidW = 24;
  static const int _fluidH = 16;

  // 8 条流线的 Y 位置（像素坐标，在 build 时根据 size 计算）
  List<double> _streamYPixels = [];
  Size _lastSize = Size.zero;

  int _frame = 0;

  // 反编译参数
  late double _fadeRate;
  late double _growRate;
  late int _maxParticles;
  late int _genInterval;
  late double _spreadRange;

  @override
  void initState() {
    super.initState();
    _fluid = _LightFluidSolver(w: _fluidW, h: _fluidH);

    // 初始化流体场 — 全场水平风
    for (int j = 1; j <= _fluidH; j++) {
      for (int i = 1; i <= _fluidW; i++) {
        _fluid.u[_fluid.ix(i, j)] = widget.windSpeed;
      }
    }

    // 粒子视觉参数 — 直接设定合理值（不再用归一化公式，那是基于真实车速的）
    _fadeRate = 0.008;       // 慢慢消散
    _growRate = 0.3;         // 粒子逐渐变大
    _maxParticles = 120;     // 足够多的粒子
    _genInterval = 2;        // 每 2 帧生成一批
    _spreadRange = 30.0;     // 垂直散布范围

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _controller.repeat();
  }

  void _tick() {
    _frame++;

    // 流体步进（慢速，只提供方向场）
    if (_frame % 3 == 0) {
      // 维持左边界风
      for (int j = 1; j <= _fluidH; j++) {
        _fluid.u[_fluid.ix(1, j)] = widget.windSpeed;
      }
      _fluid.step(0.03);
    }

    // 生成新粒子
    if (_frame % _genInterval == 0 && _lastSize != Size.zero) {
      _spawnParticles();
    }

    // 更新粒子
    _updateParticles();

    if (mounted) setState(() {});
  }

  void _spawnParticles() {
    if (_particles.length >= _maxParticles) {
      // 超过上限，移除最老的
      final excess = _particles.length - _maxParticles + 8;
      if (excess > 0) {
        _particles.sort((a, b) => a.opacity.compareTo(b.opacity));
        _particles.removeRange(0, min(excess, _particles.length));
      }
    }

    // 每条流线生成 1 个粒子
    for (int s = 0; s < _streamYPixels.length; s++) {
      if (_particles.length >= _maxParticles) break;

      final baseY = _streamYPixels[s];
      // 反编译: x = (random - 0.5) * spreadRange + 30.0
      // 这里 30.0 是源区域的 x 偏移，我们用左边 5% 位置
      final spawnX = _lastSize.width * 0.02 + _rng.nextDouble() * _lastSize.width * 0.03;
      final spawnY = baseY + (_rng.nextDouble() - 0.5) * _spreadRange * 0.3;

      // 粒子初始大小：8-20 像素（在手机上清晰可见）
      final size = 8.0 + _rng.nextDouble() * 12.0;

      // 粒子初始透明度：0.4-0.7（明显可见）
      final opacity = 0.4 + _rng.nextDouble() * 0.3;

      // 水平速度：1.5-3.5 像素/帧
      final speed = 1.5 + _rng.nextDouble() * 2.0;

      // 垂直漂移：轻微随机
      final drift = (_rng.nextDouble() - 0.5) * 0.5;

      _particles.add(_SmokeParticle(
        x: spawnX,
        y: spawnY,
        opacity: opacity,
        size: size,
        speed: speed,
        drift: drift,
        streamIndex: s,
      ));
    }
  }

  void _updateParticles() {
    if (_lastSize == Size.zero) return;

    final cellW = _lastSize.width / _fluidW;
    final cellH = _lastSize.height / _fluidH;

    for (final p in _particles) {
      // 获取流体场在粒子位置的速度
      final vel = _fluid.getVelocityAt(p.x, p.y, cellW, cellH);

      // 粒子运动 = 基础速度 + 流场影响
      p.x += p.speed * 1.5 + vel.dx * 0.3; // 主要向右飘
      p.y += p.drift + vel.dy * 0.2;        // 轻微垂直漂移

      // 反编译: opacity -= fadeRate, size += growRate
      p.opacity -= _fadeRate;
      p.size += _growRate;
    }

    // 移除消失的粒子（opacity <= 0 或飘出屏幕）
    _particles.removeWhere((p) =>
        p.opacity <= 0 || p.x > _lastSize.width * 1.1 || p.y < -20 || p.y > _lastSize.height + 20);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _lastSize && size.width > 0 && size.height > 0) {
            _lastSize = size;
            // 8 条流线均匀分布
            const numStreams = 8;
            final spacing = size.height / (numStreams + 1);
            _streamYPixels = List.generate(numStreams, (i) => (i + 1) * spacing);
          }
          return CustomPaint(
            size: size,
            painter: _SmokeParticlePainter(
              particles: _particles,
              smokeColor: widget.smokeColor,
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 粒子渲染器
// ═══════════════════════════════════════════════════════════════

class _SmokeParticlePainter extends CustomPainter {
  final List<_SmokeParticle> particles;
  final Color smokeColor;

  _SmokeParticlePainter({
    required this.particles,
    required this.smokeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final p in particles) {
      if (p.opacity <= 0) continue;

      final opacity = p.opacity.clamp(0.0, 1.0);
      final radius = p.size;

      // 每个粒子画成一个模糊的圆 — 自然的烟雾感
      paint
        ..color = smokeColor.withOpacity(opacity * 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.2);

      canvas.drawCircle(Offset(p.x, p.y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════
// 兼容别名
// ═══════════════════════════════════════════════════════════════
typedef SmokeFlowWidget = WindTunnelFlowAnimator;
