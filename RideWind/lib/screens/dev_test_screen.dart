import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
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

/// BLE 通信日志条目
class _BleLogEntry {
  final DateTime timestamp;
  final String data;

  _BleLogEntry({required this.timestamp, required this.data});
}

/// 🧪 开发测试界面 - 5股烟雾射流（粒子轨迹 + 速度场驱动）
/// 包含 BLE 通信日志查看功能 (需求 13.5)
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

  // 🐛 BLE 通信日志 (需求 13.5)
  bool _showBleLog = false;
  final List<_BleLogEntry> _bleLogEntries = [];
  static const int _maxLogEntries = 200;
  StreamSubscription? _rawDataSub;
  final ScrollController _logScrollController = ScrollController();
  bool _autoScroll = true;

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

    // 🐛 订阅 BLE 原始数据流 (需求 13.5)
    _subscribeBleLog();
  }

  /// 🐛 订阅 BLE 原始数据流用于日志显示 (需求 13.5)
  void _subscribeBleLog() {
    // 延迟到 build 后获取 Provider，避免 initState 中直接访问
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final bt = Provider.of<BluetoothProvider>(context, listen: false);
        _rawDataSub = bt.rawDataStream.listen((data) {
          if (!mounted) return;
          setState(() {
            _bleLogEntries.add(_BleLogEntry(
              timestamp: DateTime.now(),
              data: data,
            ));
            // 限制日志条目数量
            if (_bleLogEntries.length > _maxLogEntries) {
              _bleLogEntries.removeRange(
                  0, _bleLogEntries.length - _maxLogEntries);
            }
          });
          // 自动滚动到底部
          if (_autoScroll && _showBleLog) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_logScrollController.hasClients) {
                _logScrollController.animateTo(
                  _logScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        });
      } catch (e) {
        debugPrint('⚠️ BLE 日志订阅失败: $e');
      }
    });
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
    _rawDataSub?.cancel();
    _logScrollController.dispose();
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

  /// 🐛 构建 BLE 通信日志面板 (需求 13.5)
  Widget _buildBleLogPanel() {
    return Container(
      color: Colors.black.withAlpha(220),
      child: Column(
        children: [
          // 日志面板标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              border: Border(
                bottom: BorderSide(color: Colors.white.withAlpha(20)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text('BLE 通信日志',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                // 日志条目计数
                Text('${_bleLogEntries.length}',
                    style: TextStyle(
                        color: Colors.white.withAlpha(100), fontSize: 11)),
                const SizedBox(width: 12),
                // 自动滚动切换
                GestureDetector(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  child: Icon(
                    _autoScroll
                        ? Icons.vertical_align_bottom
                        : Icons.vertical_align_center,
                    color: _autoScroll ? Colors.green : Colors.white38,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                // 清空日志
                GestureDetector(
                  onTap: () => setState(() => _bleLogEntries.clear()),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.white38, size: 16),
                ),
                const SizedBox(width: 12),
                // 关闭面板
                GestureDetector(
                  onTap: () => setState(() => _showBleLog = false),
                  child: const Icon(Icons.close,
                      color: Colors.white38, size: 16),
                ),
              ],
            ),
          ),
          // 日志列表
          Expanded(
            child: _bleLogEntries.isEmpty
                ? Center(
                    child: Text('等待 BLE 数据...',
                        style: TextStyle(
                            color: Colors.white.withAlpha(60),
                            fontSize: 12)),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: _bleLogEntries.length,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    itemBuilder: (ctx, i) {
                      final entry = _bleLogEntries[i];
                      final timeStr =
                          '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                          '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                          '${entry.timestamp.second.toString().padLeft(2, '0')}.'
                          '${entry.timestamp.millisecond.toString().padLeft(3, '0')}';

                      // 根据内容类型着色
                      Color dataColor = Colors.white70;
                      if (entry.data.startsWith('OK:')) {
                        dataColor = Colors.green;
                      } else if (entry.data.contains('ERR') ||
                          entry.data.contains('FAIL')) {
                        dataColor = Colors.red;
                      } else if (entry.data.startsWith('WIFI_')) {
                        dataColor = Colors.cyan;
                      } else if (entry.data.startsWith('LOGO_')) {
                        dataColor = Colors.orange;
                      } else if (entry.data.startsWith('OTA_')) {
                        dataColor = Colors.amber;
                      } else if (entry.data.startsWith('PRESET_') ||
                          entry.data.startsWith('SPEED_') ||
                          entry.data.startsWith('STATUS:')) {
                        dataColor = Colors.lightBlue;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(timeStr,
                                style: TextStyle(
                                    color: Colors.white.withAlpha(80),
                                    fontSize: 10,
                                    fontFamily: 'monospace')),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(entry.data,
                                  style: TextStyle(
                                      color: dataColor,
                                      fontSize: 11,
                                      fontFamily: 'monospace')),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // 烟雾模拟层
          LayoutBuilder(
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

          // 🐛 BLE 日志切换按钮 (需求 13.5)
          if (!_showBleLog)
            Positioned(
              bottom: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _showBleLog = true),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(150),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.terminal,
                          color: Colors.green, size: 14),
                      const SizedBox(width: 4),
                      const Text('BLE Log',
                          style: TextStyle(
                              color: Colors.green, fontSize: 11)),
                      if (_bleLogEntries.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${_bleLogEntries.length}',
                              style: const TextStyle(
                                  color: Colors.green, fontSize: 9)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 🐛 BLE 通信日志面板 (需求 13.5)
          if (_showBleLog)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.5,
              child: _buildBleLogPanel(),
            ),
        ],
      ),
    );
  }
}
