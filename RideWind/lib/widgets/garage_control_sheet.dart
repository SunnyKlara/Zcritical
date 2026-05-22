import 'dart:convert';
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
/// 下方：速度范围数字 + 音量点阵指示器
///
/// 音量联动：触摸音量区域时硬件切到音量界面，松手后自动切回速度界面。
class GarageControlSheet extends StatefulWidget {
  final void Function(GarageSettings settings)? onSettingsApplied;

  const GarageControlSheet({super.key, this.onSettingsApplied});

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
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (context) => GarageControlSheet(
        onSettingsApplied: onSettingsApplied,
      ),
    );
  }

  @override
  State<GarageControlSheet> createState() => _GarageControlSheetState();
}

class _GarageControlSheetState extends State<GarageControlSheet> {
  // ═══════════════════════════════════════════════════════════════
  //  状态
  // ═══════════════════════════════════════════════════════════════

  List<CarModel> _cars = [];
  bool _isLoading = true;
  int _selectedCarIndex = 0;
  late PageController _pageController;

  // 参数
  int _maxSpeed = 340;
  int _volume = 70;

  // 音量调节中
  bool _isAdjustingVolume = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.72,
      initialPage: 0,
    );
    _loadCarData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (_isAdjustingVolume) _onVolumeAdjustEnd();
    super.dispose();
  }

  Future<void> _loadCarData() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_specs.json',
      );
      final List<dynamic> jsonList = json.decode(jsonStr);
      final allCars = jsonList.map((e) => CarModel.fromJson(e)).toList();

      final carsWithSpecs = allCars.where((c) =>
        c.specs != null && c.specs!.horsepower != null
      ).toList();

      carsWithSpecs.sort((a, b) =>
        (b.specs!.horsepower ?? 0).compareTo(a.specs!.horsepower ?? 0));

      setState(() {
        _cars = carsWithSpecs.take(50).toList();
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

    int suggestedMaxSpeed;
    if (hp < 150) {
      suggestedMaxSpeed = 180;
    } else if (hp < 300) {
      suggestedMaxSpeed = 250;
    } else if (hp < 500) {
      suggestedMaxSpeed = 320;
    } else if (hp < 700) {
      suggestedMaxSpeed = 360;
    } else {
      suggestedMaxSpeed = 420;
    }

    int suggestedVolume;
    if (hp < 150) {
      suggestedVolume = 45;
    } else if (hp < 300) {
      suggestedVolume = 60;
    } else if (hp < 600) {
      suggestedVolume = 75;
    } else {
      suggestedVolume = 85;
    }

    setState(() {
      _maxSpeed = suggestedMaxSpeed;
      _volume = suggestedVolume;
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
          // 拖拽条
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ═══ 赛车轮播 ═══
          SizedBox(
            height: 250,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(
                    color: Colors.white12, strokeWidth: 1.5))
                : _buildCarCarousel(),
          ),

          const SizedBox(height: 28),

          // ═══ 速度范围 ═══
          _buildSpeedDisplay(),

          const SizedBox(height: 28),

          // ═══ 音量 ═══
          _buildVolumeControl(),

          const Spacer(),

          // ═══ 启动按钮 ═══
          _buildActivateButton(),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  赛车轮播 — 文字在上，图片悬浮无边框
  //  去掉卡片容器，图片直接浮在纯黑背景上，大小差异不再明显
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

  /// 单个车辆项：上方文字 + 下方悬浮图片（无边框无卡片）
  Widget _buildCarItem(CarModel car, bool isSelected) {
    final specs = car.specs;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 文字信息 — 在图片上方
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
        const SizedBox(height: 8),

        // 图片 — fitWidth 让所有车宽度统一，高度自然适应
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.asset(
              car.assetPath,
              fit: BoxFit.fitWidth,
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
  //  速度范围 — 大号数字居中显示
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSpeedDisplay() {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        setState(() {
          _maxSpeed = (_maxSpeed + (delta * 0.5).round()).clamp(100, 500);
        });
      },
      child: Column(
        children: [
          Text(
            '速度范围',
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_maxSpeed',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'km/h',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '← 左右滑动调整 →',
            style: TextStyle(
              color: Colors.white.withOpacity(0.1),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  音量 — 点阵指示器 + 触摸联动硬件
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVolumeControl() {
    final int dots = 10;
    final int filledDots = (_volume / 10).round().clamp(0, 10);

    return GestureDetector(
      onHorizontalDragStart: (_) => _onVolumeAdjustStart(),
      onHorizontalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        final newVol = (_volume + (delta * 0.3).round()).clamp(0, 100);
        _onVolumeChanged(newVol);
      },
      onHorizontalDragEnd: (_) => _onVolumeAdjustEnd(),
      onTapDown: (_) => _onVolumeAdjustStart(),
      onTapUp: (_) => _onVolumeAdjustEnd(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '音量',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  '$_volume%',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 点阵
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(dots, (i) {
                final isFilled = i < filledDots;
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? Colors.white.withOpacity(0.8)
                        : Colors.white.withOpacity(0.08),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            if (_isAdjustingVolume)
              Text(
                '硬件同步中',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.15),
                  fontSize: 9,
                ),
              )
            else
              Text(
                '← 左右滑动调节 →',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.08),
                  fontSize: 9,
                ),
              ),
          ],
        ),
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
}

/// 车库设置结果
class GarageSettings {
  final CarModel? selectedCar;
  final int maxSpeed;
  final int volume;

  const GarageSettings({
    this.selectedCar,
    required this.maxSpeed,
    required this.volume,
  });
}
