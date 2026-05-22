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
  int _windMin = 0;    // 风力下限
  int _windMax = 100;  // 风力上限

  // 音量调节中
  bool _isAdjustingVolume = false;

  // ACTIVATE 应用中
  bool _isApplying = false;

  // 波形动画
  late AnimationController _waveController;
  bool _isPlaying = false;
  double _wavePhase = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.72,
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
      _windMin = suggestedWind;
      _windMax = 100;
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

  void _onWindRangeChanged(RangeValues values) {
    setState(() {
      _windMin = values.start.round();
      _windMax = values.end.round();
    });
    // 风力只在 ACTIVATE 时发送，拖动仅更新 UI 预览
  }

  Future<void> _applySettings() async {
    if (_isApplying) return; // 防止重复点击

    HapticFeedback.mediumImpact();
    setState(() => _isApplying = true);

    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) {
      // 发送并等待固件确认，每条等 OK 回复
      final ok1 = await bt.sendCommandWithRetry(
        'SPEED_MAX:$_maxSpeed',
        expectedPrefix: 'OK:SPEED_MAX',
        timeout: const Duration(seconds: 2),
      );
      final ok2 = await bt.sendCommandWithRetry(
        'FAN_RANGE:$_windMin,$_windMax',
        expectedPrefix: 'OK:FAN_RANGE',
        timeout: const Duration(seconds: 2),
      );
      final ok3 = await bt.sendCommandWithRetry(
        'VOL:$_volume',
        expectedPrefix: 'OK:VOL',
        timeout: const Duration(seconds: 2),
      );
      bt.sendCommand('UI:1');

      // 检查是否全部成功
      if (ok1 == null || ok2 == null || ok3 == null) {
        if (mounted) {
          setState(() => _isApplying = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('部分设置未确认，请重试'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final car = _cars.isNotEmpty ? _cars[_selectedCarIndex] : null;
    widget.onSettingsApplied?.call(GarageSettings(
      selectedCar: car,
      maxSpeed: _maxSpeed,
      volume: _volume,
      windMin: _windMin,
      windMax: _windMax,
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
      child: Column(
        children: [
          // 可滚动内容区域
          Expanded(
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

                const SizedBox(height: 20),
              ],
            ),
          ),

          // ═══ 固定底部：ACTIVATE 按钮 ═══
          Padding(
            padding: EdgeInsets.only(
              left: 40,
              right: 40,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: _buildActivateButton(),
          ),
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
            if (_pageController.hasClients &&
                _pageController.position.haveDimensions) {
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
  //  控制面板 — 速度/音量/风力 竖列排列，参考 _buildStatBar 风格
  //  每项：标签(左)+数字(右) 一行，下面全宽 Slider（带动画）
  // ═══════════════════════════════════════════════════════════════

  Widget _buildControlRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildControlSlider(
            label: '速度',
            value: _maxSpeed.toDouble(),
            displayText: '$_maxSpeed km/h',
            min: 0,
            max: 999,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _maxSpeed = v.round());
            },
          ),
          const SizedBox(height: 20),
          _buildControlSlider(
            label: '音量',
            value: _volume.toDouble(),
            displayText: '$_volume%',
            min: 0,
            max: 100,
            onChangeStart: (_) => _onVolumeAdjustStart(),
            onChanged: (v) => _onVolumeChanged(v.round()),
            onChangeEnd: (_) => _onVolumeAdjustEnd(),
          ),
          const SizedBox(height: 20),
          // 风力区间 RangeSlider
          _buildWindRangeSlider(),
        ],
      ),
    );
  }

  /// 风力区间双滑块
  Widget _buildWindRangeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '风力区间',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
            Text(
              '$_windMin% — $_windMax%',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: _sliderTheme(context).copyWith(
            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: RangeSlider(
            values: RangeValues(_windMin.toDouble(), _windMax.toDouble()),
            min: 0,
            max: 100,
            divisions: 20,
            onChanged: _onWindRangeChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildControlSlider({
    required String label,
    required double value,
    required String displayText,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 9,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
            )),
            Text(displayText, style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            )),
          ],
        ),
        const SizedBox(height: 8),
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
                onChangeStart: onChangeStart,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  启动按钮 — 极简白色描边
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActivateButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GestureDetector(
        onTap: _isApplying ? null : _applySettings,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 50,
          decoration: BoxDecoration(
            color: _isApplying ? Colors.white.withOpacity(0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: _isApplying
                  ? Colors.greenAccent.withOpacity(0.4)
                  : Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: _isApplying
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.greenAccent.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'APPLYING...',
                      style: TextStyle(
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                )
              : Text(
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
  final int windMin;
  final int windMax;

  const GarageSettings({
    this.selectedCar,
    required this.maxSpeed,
    required this.volume,
    this.windMin = 0,
    this.windMax = 100,
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
