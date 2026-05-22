import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/car_model.dart';
import '../providers/bluetooth_provider.dart';

/// 🚗 车库联动控制弹窗
///
/// 长按紧急停止按钮后弹出。
/// 纯黑极简设计，沉浸式选车体验。
/// 上方：赛车轮播（中间大+浮起，两边小+下沉）
/// 下方：引擎波形 + 速度/音量/风力 Slider
///
/// 音量联动：触摸音量 Slider 时硬件切到音量界面，松手后自动切回速度界面。
class GarageControlSheet extends StatefulWidget {
  final void Function(GarageSettings settings)? onSettingsApplied;
  final ScrollController? scrollController;

  const GarageControlSheet({super.key, this.onSettingsApplied, this.scrollController});

  static Future<void> show(
    BuildContext context, {
    void Function(GarageSettings settings)? onSettingsApplied,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => GarageControlSheet(
          onSettingsApplied: onSettingsApplied,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<GarageControlSheet> createState() => _GarageControlSheetState();
}

class _GarageControlSheetState extends State<GarageControlSheet>
    with TickerProviderStateMixin {
  // ═══════════════════════════════════════════════════════════════
  //  状态
  // ═══════════════════════════════════════════════════════════════

  List<CarModel> _cars = [];
  bool _isLoading = true;
  int _selectedCarIndex = 0;
  late PageController _pageController;
  Map<String, double> _scaleMap = {};

  // 参数
  int _maxSpeed = 340;
  int _volume = 70;
  int _windPower = 0;

  // 音量调节中
  bool _isAdjustingVolume = false;

  // 波形动画
  late AnimationController _waveController;
  bool _isPlaying = false;
  double _wavePhase = 0;

  // 控制轮播
  late PageController _controlPageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.72,
      initialPage: 0,
    );
    _controlPageController = PageController(
      viewportFraction: 0.45,
      initialPage: 0,
    );

    // 正弦波相位动画控制器 — 持续循环
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addListener(() {
      setState(() {
        _wavePhase = _waveController.value * 2 * pi;
      });
    });

    _loadCarData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controlPageController.dispose();
    _waveController.dispose();
    if (_isAdjustingVolume) _onVolumeAdjustEnd();
    super.dispose();
  }

  void _startWaveAnimation() {
    setState(() => _isPlaying = true);
    _waveController.repeat();
  }

  void _stopWaveAnimation() {
    _waveController.stop();
    setState(() {
      _isPlaying = false;
      _wavePhase = 0;
    });
  }

  Future<void> _loadCarData() async {
    try {
      // 加载 scale map
      final scaleStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_scale_map.json',
      );
      final Map<String, dynamic> scaleJson = json.decode(scaleStr);
      _scaleMap = scaleJson.map((k, v) => MapEntry(k, (v as num).toDouble()));

      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_specs.json',
      );
      final List<dynamic> jsonList = json.decode(jsonStr);
      final allCars = jsonList.map((e) => CarModel.fromJson(e)).toList();

      final carsWithSpecs = allCars.where((c) =>
        c.specs != null && c.specs!.horsepower != null
      ).toList();

      // 过滤非赛车车辆（拖车、卡车、越野车、工程车等）
      const excludeKeywords = ['Flatbed', 'Truck', 'Van', 'Bus', 'Semi', 'Unimog', 'Tankpool'];
      final racingCars = carsWithSpecs.where((c) {
        final name = c.fullName;
        final specs = c.specs!;
        // 必须四个关键参数都有数据
        if (specs.horsepower == null || specs.torqueLbft == null ||
            specs.topSpeedKmh == null || specs.acceleration0100 == null) {
          return false;
        }
        // 必须有引擎信息
        if ((specs.engine == null || specs.engine!.isEmpty) &&
            (specs.displacement == null || specs.displacement!.isEmpty)) {
          return false;
        }
        // 排除非赛车
        return !excludeKeywords.any((kw) => name.contains(kw));
      }).toList();

      racingCars.shuffle();

      setState(() {
        _cars = racingCars.take(50).toList();
        _isLoading = false;
        if (_cars.isNotEmpty) _applyCarProfile(_cars[0]);
      });
    } catch (e) {
      debugPrint('❌ 加载车辆数据失败: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyCarProfile(CarModel car) {
    final specs = car.specs;
    if (specs == null) return;
    final hp = specs.horsepower ?? 200;
    final torque = specs.torqueLbft ?? 200;

    // 速度 = 极速值
    // 音量 = 马力线性映射到 20-100（100hp→20%, 2000hp→100%）
    // 风力 = 扭矩线性映射到 15-100（100lb·ft→15%, 1200lb·ft→100%）
    final int suggestedVolume = ((hp - 100) / 1900.0 * 80 + 20).round().clamp(20, 100);
    final int suggestedWind = ((torque - 100) / 1100.0 * 85 + 15).round().clamp(15, 100);

    setState(() {
      _maxSpeed = specs.topSpeedKmh ?? 340;
      _volume = suggestedVolume;
      _windPower = suggestedWind;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  硬件联动
  // ═══════════════════════════════════════════════════════════════

  void _onVolumeAdjustStart() {
    _isAdjustingVolume = true;
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) bt.sendCommand('UI:7');
  }

  void _onVolumeChanged(int newVolume) {
    setState(() => _volume = newVolume);
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) bt.setVolume(newVolume);
  }

  void _onVolumeAdjustEnd() {
    _isAdjustingVolume = false;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final bt = Provider.of<BluetoothProvider>(context, listen: false);
      if (bt.isConnected) bt.sendCommand('UI:1');
    });
  }

  void _onWindChanged(int value) {
    setState(() => _windPower = value);
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) bt.sendCommand('FAN:$value');
  }

  void _applySettings() {
    HapticFeedback.mediumImpact();
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) {
      bt.setVolume(_volume);
      bt.sendCommand('UI:1');
    }

    final car = _cars.isNotEmpty ? _cars[_selectedCarIndex] : null;
    widget.onSettingsApplied?.call(GarageSettings(
      selectedCar: car,
      maxSpeed: _maxSpeed,
      volume: _volume,
      windPower: _windPower,
    ));
    Navigator.of(context).pop();
  }

  // ═══════════════════════════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: widget.scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          // 拖拽条
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ═══ 赛车轮播 ═══
          SizedBox(
            height: 180,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(
                    color: Colors.white12, strokeWidth: 1.5))
                : _buildCarCarousel(),
          ),

          const SizedBox(height: 28),

          // ═══ 参数面板 (2×2 进度条) ═══
          if (_cars.isNotEmpty) _buildStatsGrid(),

          const SizedBox(height: 36),

          // ═══ 引擎波形（充当分隔线，全宽拉长） ═══
          if (_cars.isNotEmpty) _buildEngineWaveform(),

          const SizedBox(height: 36),

          // ═══ 控制轮播 — 速度/音量/风力 中间大两边小 ═══
          _buildControlRow(),

          const SizedBox(height: 32),

          // ═══ 启动按钮 ═══
          _buildActivateButton(),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  赛车轮播 — 文字在上，图片悬浮无边框
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCarCarousel() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _cars.length,
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        setState(() => _selectedCarIndex = index);
        _applyCarProfile(_cars[index]);
      },
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _pageController,
          builder: (context, child) {
            double page = 0;
            if (_pageController.position.haveDimensions) {
              page = _pageController.page ?? 0;
            }
            final double diff = (index - page);
            final double absDiff = diff.abs().clamp(0.0, 2.0);

            final double scale = 1.0 - absDiff * 0.3;
            final double translateY = absDiff * 16.0;
            final double opacity = (1.0 - absDiff * 0.6).clamp(0.3, 1.0);

            return Transform.translate(
              offset: Offset(0, translateY),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: _buildCarItem(_cars[index], index == _selectedCarIndex),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 单个车辆项：上方文字 + 下方图片（精准缩放，尽可能大）
  Widget _buildCarItem(CarModel car, bool isSelected) {
    final specs = car.specs;
    final double imageScale = _scaleMap[car.filename] ?? 1.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          car.brand.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(isSelected ? 0.35 : 0.15),
            fontSize: 9,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          car.model,
          style: TextStyle(
            color: Colors.white.withOpacity(isSelected ? 1.0 : 0.5),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (specs?.horsepower != null) ...[
          const SizedBox(height: 1),
          Text(
            '${specs!.horsepower} HP',
            style: TextStyle(
              color: Colors.white.withOpacity(isSelected ? 0.3 : 0.12),
              fontSize: 10,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Expanded(
          child: Transform.scale(
            scale: imageScale,
            child: Image.asset(
              car.assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(
                  Icons.directions_car_outlined,
                  color: Colors.white.withOpacity(0.04),
                  size: 40,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  参数面板 — 2×2 网格 + 动画进度条
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatsGrid() {
    final car = _cars[_selectedCarIndex];
    final specs = car.specs;
    if (specs == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatBar(label: 'HP', value: specs.horsepower ?? 0, maxValue: 2000, displayText: '${specs.horsepower ?? "—"} hp')),
              const SizedBox(width: 16),
              Expanded(child: _buildStatBar(label: 'TORQUE', value: specs.torqueLbft ?? 0, maxValue: 1200, displayText: '${specs.torqueLbft ?? "—"} lb·ft')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildStatBar(label: 'TOP SPEED', value: specs.topSpeedKmh ?? 0, maxValue: 450, displayText: '${specs.topSpeedKmh ?? "—"} km/h')),
              const SizedBox(width: 16),
              Expanded(child: _buildStatBar(
                label: '0-100',
                value: specs.acceleration0100 != null ? (14.0 - specs.acceleration0100!).clamp(0, 14).toInt() : 0,
                maxValue: 12,
                displayText: specs.acceleration0100 != null ? '${specs.acceleration0100}s' : '—',
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBar({
    required String label,
    required int value,
    required int maxValue,
    required String displayText,
  }) {
    final double progress = (value / maxValue).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 1.5)),
            Text(displayText, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final double barWidth = constraints.maxWidth * progress;
            return Container(
              height: 5,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(2.5)),
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                width: barWidth,
                height: 5,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(2.5)),
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  引擎波形 — 全宽正弦波，充当视觉分隔线
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEngineWaveform() {
    final car = _cars[_selectedCarIndex];
    final specs = car.specs;
    if (specs == null) return const SizedBox.shrink();

    // 引擎类型文字
    final engineParts = <String>[];
    if (specs.displacement != null && specs.displacement!.isNotEmpty) {
      engineParts.add(specs.displacement!);
    }
    if (specs.engine != null && specs.engine!.isNotEmpty) {
      engineParts.add(specs.engine!);
    }
    if (specs.aspiration != null && specs.aspiration!.isNotEmpty) {
      engineParts.add(specs.aspiration!);
    }
    final engineLabel = engineParts.isNotEmpty
        ? engineParts.join(' ')
        : 'Unknown Engine';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (_isPlaying) {
          _stopWaveAnimation();
        } else {
          _startWaveAnimation();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            // 引擎类型 + 播放按钮（小字居中）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white.withOpacity(0.35),
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  engineLabel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 全宽正弦波
            SizedBox(
              height: 24,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(double.infinity, 24),
                    painter: _SineWavePainter(
                      phase: _wavePhase,
                      isPlaying: _isPlaying,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  控制轮播 — 速度/音量/风力 中间大两边小，3项循环滚动
  //  Slider 用 TweenAnimationBuilder 实现切换车辆时的伸缩动画
  // ═══════════════════════════════════════════════════════════════

  Widget _buildControlRow() {
    return SizedBox(
      height: 100,
      child: PageView.builder(
        controller: _controlPageController,
        itemCount: 300,
        onPageChanged: (_) => HapticFeedback.selectionClick(),
        itemBuilder: (context, index) {
          final int realIndex = index % 3;
          return AnimatedBuilder(
            animation: _controlPageController,
            builder: (context, child) {
              double page = 0;
              if (_controlPageController.position.haveDimensions) {
                page = _controlPageController.page ?? 0;
              }
              final double diff = (index - page);
              final double absDiff = diff.abs().clamp(0.0, 2.0);
              final double scale = 1.0 - absDiff * 0.15;
              final double opacity = (1.0 - absDiff * 0.4).clamp(0.3, 1.0);

              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: _buildControlCard(realIndex),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildControlCard(int index) {
    late String label;
    late double value;
    late double min;
    late double max;
    late String unit;
    late ValueChanged<double> onChanged;
    late VoidCallback? onStart;
    late VoidCallback? onEnd;

    switch (index) {
      case 0:
        label = '速度';
        value = _maxSpeed.toDouble();
        min = 0; max = 999;
        unit = 'km/h';
        onChanged = (v) { HapticFeedback.selectionClick(); setState(() => _maxSpeed = v.round()); };
        onStart = null; onEnd = null;
        break;
      case 1:
        label = '音量';
        value = _volume.toDouble();
        min = 0; max = 100;
        unit = '%';
        onChanged = (v) => _onVolumeChanged(v.round());
        onStart = _onVolumeAdjustStart; onEnd = _onVolumeAdjustEnd;
        break;
      case 2:
        label = '风力';
        value = _windPower.toDouble();
        min = 0; max = 100;
        unit = '%';
        onChanged = (v) => _onWindChanged(v.round());
        onStart = null; onEnd = null;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 标签
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 6),
          // Slider with animation
          TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, animatedValue, _) {
              return SliderTheme(
                data: _sliderTheme(context),
                child: Slider(
                  value: animatedValue.clamp(min, max),
                  min: min,
                  max: max,
                  onChangeStart: onStart != null ? (_) => onStart!() : null,
                  onChanged: onChanged,
                  onChangeEnd: onEnd != null ? (_) => onEnd!() : null,
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          // 大数字 — 参考 RunningMode 风格
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${value.round()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 3),
              Text(unit, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  启动按钮 — 极简白色描边
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActivateButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GestureDetector(
        onTap: _applySettings,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'ACTIVATE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Slider 统一主题 — 纯白轨道 + 白色圆形 thumb
  // ═══════════════════════════════════════════════════════════════

  SliderThemeData _sliderTheme(BuildContext context) {
    return SliderThemeData(
      trackHeight: 2,
      activeTrackColor: Colors.white.withOpacity(0.8),
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      thumbColor: Colors.white,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayColor: Colors.white.withOpacity(0.05),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
    );
  }
}

/// 车库设置结果
class GarageSettings {
  final CarModel? selectedCar;
  final int maxSpeed;
  final int volume;
  final int windPower;

  const GarageSettings({
    this.selectedCar,
    required this.maxSpeed,
    required this.volume,
    this.windPower = 0,
  });
}

/// 正弦波绘制器 — 连绵起伏的荡漾效果
class _SineWavePainter extends CustomPainter {
  final double phase;
  final bool isPlaying;

  _SineWavePainter({required this.phase, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(isPlaying ? 0.7 : 0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final double midY = size.height / 2;
    final double amplitude = isPlaying ? size.height * 0.35 : 0;
    final double frequency = 2.5; // 波浪数量

    path.moveTo(0, midY);

    for (double x = 0; x <= size.width; x += 1) {
      final double normalizedX = x / size.width;
      final double y = midY +
          amplitude * sin(normalizedX * frequency * 2 * pi + phase);
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);

    // 播放时加一条更淡的副波（叠加丰富感）
    if (isPlaying) {
      final paint2 = Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path2 = Path();
      path2.moveTo(0, midY);

      for (double x = 0; x <= size.width; x += 1) {
        final double normalizedX = x / size.width;
        final double y = midY +
            amplitude * 0.5 * sin(normalizedX * frequency * 3.2 * pi + phase * 1.7);
        path2.lineTo(x, y);
      }

      canvas.drawPath(path2, paint2);
    }
  }

  @override
  bool shouldRepaint(_SineWavePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.isPlaying != isPlaying;
  }
}
