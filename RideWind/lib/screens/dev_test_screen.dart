import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/euler_fluid_simulator.dart';

/// 烟雾粒子：沿速度场移动的点
class _SmokeParticle {
  double x; // 网格坐标
  double y;
  double age; // 0.0 ~ 1.0，1.0 = 刚生成
  final int streamIndex; // 属于哪条射流

  _SmokeParticle({
    required this.x,
    required this.y,
    this.age = 1.0,
    required this.streamIndex,
  });
}

/// 5条独立烟雾射流的粒子轨迹渲染器
class SmokeTrailPainter extends CustomPainter {
  final List<List<_SmokeParticle>> streams;
  final int gridSize;

  SmokeTrailPainter({required this.streams, required this.gridSize});

  @override
  void paint(Canvas canvas, Size size) {
    // 黑色背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF000000),
    );

    final scaleX = size.width / gridSize;
    final scaleY = size.height / gridSize;

    for (final stream in streams) {
      if (stream.length < 2) continue;

      // 按 x 坐标排序（从左到右），确保路径连续
      final sorted = List<_SmokeParticle>.from(stream)
        ..sort((a, b) => a.x.compareTo(b.x));

      // 多层渲染：宽模糊层 + 窄亮层
      _drawStreamLayer(canvas, sorted, scaleX, scaleY, 6.0, 0.15); // 宽层
      _drawStreamLayer(canvas, sorted, scaleX, scaleY, 3.0, 0.4);  // 中层
      _drawStreamLayer(canvas, sorted, scaleX, scaleY, 1.2, 0.7);  // 窄亮层
    }
  }

  void _drawStreamLayer(
    Canvas canvas,
    List<_SmokeParticle> particles,
    double scaleX,
    double scaleY,
    double strokeWidth,
    double baseAlpha,
  ) {
    if (particles.length < 2) return;

    final path = Path();
    path.moveTo(particles[0].x * scaleX, particles[0].y * scaleY);

    for (int i = 1; i < particles.length; i++) {
      final p = particles[i];
      path.lineTo(p.x * scaleX, p.y * scaleY);
    }

    // 根据粒子平均 age 调整透明度
    final avgAge = particles.fold<double>(0, (s, p) => s + p.age) / particles.length;
    final alpha = (baseAlpha * avgAge).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = Color.fromRGBO(210, 215, 240, alpha)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 模糊效果
    if (strokeWidth > 2.0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.5);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 🧪 开发测试界面 - 5股烟雾射流（粒子轨迹 + 速度场驱动）
class DevTestScreen extends StatefulWidget {
  final bool isVisible;
  const DevTestScreen({super.key, this.isVisible = true});

  @override
  State<DevTestScreen> createState() => _DevTestScreenState();
}

class _DevTestScreenState extends State<DevTestScreen> {
  late EulerFluidSimulator _simulator;
  Timer? _timer;
  final Random _random = Random();

  // 5条射流的粒子列表
  late List<List<_SmokeParticle>> _streams;

  // 5个喷嘴的 Y 坐标（网格坐标）
  late List<double> _nozzleYPositions;

  static const int gridSize = 80;
  static const int maxParticlesPerStream = 120;
  static const double ageDecay = 0.012; // 每帧衰减

  @override
  void initState() {
    super.initState();
    _simulator = EulerFluidSimulator(
      gridWidth: gridSize,
      gridHeight: gridSize,
      dt: 0.1,
      diffusion: 0.0,
      viscosity: 0.00001,
      iterations: 4,
      vorticityStrength: 0.1,
      decayRate: 0.99,
      velocityDecay: 0.995,
      densityThreshold: 0.005,
      gravityStrength: 0.06,
      boundaryLayerDecay: 0.92,
      boundaryLayerThickness: 3,
      suctionStrength: 0.3,
      suctionWidth: 4,
    );

    // 5个喷嘴均匀分布在 10%~90% 高度
    _nozzleYPositions = List.generate(5, (i) {
      return gridSize * (0.1 + 0.8 * i / 4);
    });

    _streams = List.generate(5, (_) => <_SmokeParticle>[]);

    if (widget.isVisible) _startSimulation();
  }

  @override
  void didUpdateWidget(DevTestScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _startSimulation();
      } else {
        _stopSimulation();
      }
    }
  }

  @override
  void dispose() {
    _stopSimulation();
    super.dispose();
  }

  void _stepSimulation() {
    // 1. 在喷嘴处注入速度（驱动速度场）
    for (int i = 0; i < 5; i++) {
      final ny = _nozzleYPositions[i].round();
      for (int x = 1; x <= 3; x++) {
        final vx = 2.5 + _random.nextDouble() * 1.5;
        final vy = (_random.nextDouble() - 0.5) * 0.3;
        _simulator.addVelocity(x, ny, vx, vy);
      }
    }

    // 2. 推进速度场
    _simulator.step();

    // 3. 每条射流生成新粒子
    for (int i = 0; i < 5; i++) {
      final ny = _nozzleYPositions[i];
      // 每帧生成2个粒子，带微小Y扰动
      for (int k = 0; k < 2; k++) {
        _streams[i].add(_SmokeParticle(
          x: 1.0 + _random.nextDouble() * 0.5,
          y: ny + (_random.nextDouble() - 0.5) * 0.8,
          streamIndex: i,
        ));
      }
    }

    // 4. 移动所有粒子：沿速度场采样
    for (final stream in _streams) {
      for (final p in stream) {
        // 双线性插值采样速度场
        final gx = p.x.clamp(0.0, gridSize - 1.01);
        final gy = p.y.clamp(0.0, gridSize - 1.01);
        final ix = gx.floor().clamp(0, gridSize - 2);
        final iy = gy.floor().clamp(0, gridSize - 2);
        final fx = gx - ix;
        final fy = gy - iy;

        final (u00, v00) = _simulator.getVelocity(ix, iy);
        final (u10, v10) = _simulator.getVelocity(ix + 1, iy);
        final (u01, v01) = _simulator.getVelocity(ix, iy + 1);
        final (u11, v11) = _simulator.getVelocity(ix + 1, iy + 1);

        final u = u00 * (1 - fx) * (1 - fy) +
            u10 * fx * (1 - fy) +
            u01 * (1 - fx) * fy +
            u11 * fx * fy;
        final v = v00 * (1 - fx) * (1 - fy) +
            v10 * fx * (1 - fy) +
            v01 * (1 - fx) * fy +
            v11 * fx * fy;

        // 移动粒子
        p.x += u * 0.15;
        p.y += v * 0.15;

        // 衰减
        p.age -= ageDecay;
      }
    }

    // 5. 清理死亡/出界粒子，限制数量
    for (int i = 0; i < 5; i++) {
      _streams[i].removeWhere((p) =>
          p.age <= 0 ||
          p.x < 0 ||
          p.x >= gridSize ||
          p.y < 0 ||
          p.y >= gridSize);
      // 限制最大粒子数
      if (_streams[i].length > maxParticlesPerStream) {
        _streams[i].removeRange(0, _streams[i].length - maxParticlesPerStream);
      }
    }
  }

  void _startSimulation() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _stepSimulation();
      if (mounted) setState(() {});
    });
  }

  void _stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final gridX = (details.localPosition.dx / size.width * gridSize)
        .round()
        .clamp(0, gridSize - 1);
    final gridY = (details.localPosition.dy / size.height * gridSize)
        .round()
        .clamp(0, gridSize - 1);

    final vx = details.delta.dx * 0.5;
    final vy = details.delta.dy * 0.5;
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        _simulator.addVelocity(gridX + dx, gridY + dy, vx, vy);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanUpdate: (details) =>
                _handlePanUpdate(details, constraints.biggest),
            child: CustomPaint(
              size: constraints.biggest,
              painter: SmokeTrailPainter(
                streams: _streams,
                gridSize: gridSize,
              ),
            ),
          );
        },
      ),
    );
  }
}
