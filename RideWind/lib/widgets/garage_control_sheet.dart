import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/car_model.dart';
import '../providers/bluetooth_provider.dart';

/// 🚗 车库联动控制弹窗
///
/// 长按紧急停止按钮后弹出。
/// 上方：赛车轮播（中间大两边小，左右滑动选择）
/// 下方：速度范围 + 音量调节，与硬件实时联动
///
/// 使用方式：
/// ```dart
/// GarageControlSheet.show(context, onSettingsApplied: (settings) { ... });
/// ```
class GarageControlSheet extends StatefulWidget {
  /// 设置应用回调 — 返回选中的车辆和参数
  final void Function(GarageSettings settings)? onSettingsApplied;

  const GarageControlSheet({super.key, this.onSettingsApplied});

  /// 显示车库控制弹窗
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
        maxHeight: MediaQuery.of(context).size.height * 0.72,
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
  //  色彩
  // ═══════════════════════════════════════════════════════════════

  static const _sheetBg = Color(0xFF1A1A1A);
  static const _accent = Color(0xFF00C8FF); // 科技蓝
  static const _accentSoft = Color(0x3300C8FF);

  // ═══════════════════════════════════════════════════════════════
  //  状态
  // ═══════════════════════════════════════════════════════════════

  List<CarModel> _cars = [];
  bool _isLoading = true;
  int _selectedCarIndex = 0;
  late PageController _pageController;

  // 参数
  double _maxSpeed = 340;
  double _currentFanSpeed = 0; // 当前风速 %
  double _volume = 70;

  // 音量调节中标记（用于硬件联动）
  bool _isAdjustingVolume = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.55, // 让三辆车同时可见
      initialPage: 0,
    );
    _loadCarData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    // 如果正在调音量，松手时恢复硬件界面
    if (_isAdjustingVolume) {
      _onVolumeAdjustEnd();
    }
    super.dispose();
  }

  /// 加载车辆数据（优先从收藏/最近使用，否则加载全部）
  Future<void> _loadCarData() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_specs.json',
      );
      final List<dynamic> jsonList = json.decode(jsonStr);
      final allCars = jsonList.map((e) => CarModel.fromJson(e)).toList();

      // 只取有 specs 数据的车辆（有马力信息的）
      final carsWithSpecs = allCars.where((c) =>
        c.specs != null && c.specs!.horsepower != null
      ).toList();

      // 按马力排序，取前 50 辆作为精选（后续可改为收藏/最近）
      carsWithSpecs.sort((a, b) =>
        (b.specs!.horsepower ?? 0).compareTo(a.specs!.horsepower ?? 0));

      setState(() {
        _cars = carsWithSpecs.take(50).toList();
        _isLoading = false;
        if (_cars.isNotEmpty) {
          _applyCarProfile(_cars[0]);
        }
      });
    } catch (e) {
      debugPrint('❌ 加载车辆数据失败: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 根据车辆参数自动计算推荐设置
  void _applyCarProfile(CarModel car) {
    final specs = car.specs;
    if (specs == null) return;

    final hp = specs.horsepower ?? 200;

    // 马力 → 推荐极速范围
    double suggestedMaxSpeed;
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

    // 马力 → 推荐风速
    double suggestedFan;
    if (hp < 150) {
      suggestedFan = 30;
    } else if (hp < 300) {
      suggestedFan = 50;
    } else if (hp < 600) {
      suggestedFan = 70;
    } else {
      suggestedFan = 85;
    }

    // 马力 → 推荐音量
    double suggestedVolume;
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
      _currentFanSpeed = suggestedFan;
      _volume = suggestedVolume;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  硬件联动
  // ═══════════════════════════════════════════════════════════════

  /// 音量开始调节 — 通知硬件切到音量界面
  void _onVolumeAdjustStart() {
    _isAdjustingVolume = true;
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) {
      bt.sendCommand('UI:7'); // 切到音量界面
    }
  }

  /// 音量调节中 — 实时同步到硬件
  void _onVolumeChanged(double value) {
    setState(() => _volume = value);
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) {
      bt.setVolume(value.round());
    }
  }

  /// 音量调节结束 — 延迟后切回速度界面
  void _onVolumeAdjustEnd() {
    _isAdjustingVolume = false;
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final bt = Provider.of<BluetoothProvider>(context, listen: false);
      if (bt.isConnected) {
        bt.sendCommand('UI:1'); // 切回速度界面
      }
    });
  }

  /// 应用全部设置
  void _applySettings() {
    HapticFeedback.mediumImpact();

    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    if (bt.isConnected) {
      // 发送风速
      bt.setRunningSpeed(_currentFanSpeed.round());
      // 发送音量
      bt.setVolume(_volume.round());
      // 确保硬件在速度界面
      bt.sendCommand('UI:1');
    }

    // 回调通知父组件
    final car = _cars.isNotEmpty ? _cars[_selectedCarIndex] : null;
    widget.onSettingsApplied?.call(GarageSettings(
      selectedCar: car,
      maxSpeed: _maxSpeed.round(),
      fanSpeed: _currentFanSpeed.round(),
      volume: _volume.round(),
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
        color: _sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ═══ 赛车轮播区域 ═══
          SizedBox(
            height: 180,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white24),
                  )
                : _buildCarCarousel(),
          ),

          const SizedBox(height: 8),

          // ═══ 参数调控区域 ═══
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // 速度范围
                _buildSpeedRangeSection(),
                const SizedBox(height: 20),
                // 风速
                _buildFanSpeedSection(),
                const SizedBox(height: 20),
                // 音量
                _buildVolumeSection(),
                const SizedBox(height: 24),
                // 确认按钮
                _buildApplyButton(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  赛车轮播 — 中间大两边小
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCarCarousel() {
    return Column(
      children: [
        // 轮播
        Expanded(
          child: PageView.builder(
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
                  double value = 0;
                  if (_pageController.position.haveDimensions) {
                    value = index - (_pageController.page ?? 0);
                    value = (value * 0.3).clamp(-1.0, 1.0);
                  }
                  // 中间 1.0，两边 0.75
                  final scale = 1.0 - value.abs() * 0.25;
                  final opacity = 1.0 - value.abs() * 0.4;

                  return Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity.clamp(0.3, 1.0),
                      child: _buildCarCard(_cars[index]),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // 车辆信息
        if (_cars.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _cars[_selectedCarIndex].brand.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _cars[_selectedCarIndex].model,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_cars[_selectedCarIndex].specs?.horsepower != null)
            Text(
              '${_cars[_selectedCarIndex].specs!.horsepower} HP  •  ${_cars[_selectedCarIndex].specs!.engine ?? ""}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCarCard(CarModel car) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: car == _cars[_selectedCarIndex]
              ? _accent.withOpacity(0.4)
              : Colors.white.withOpacity(0.06),
          width: car == _cars[_selectedCarIndex] ? 1.5 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset(
          car.assetPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(
              Icons.directions_car,
              color: Colors.white.withOpacity(0.1),
              size: 40,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  速度范围调节
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSpeedRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '速度范围',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '0 – ${_maxSpeed.round()} km/h',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SliderTheme(
                data: _sliderTheme(),
                child: Slider(
                  value: _maxSpeed,
                  min: 100,
                  max: 500,
                  divisions: 40,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _maxSpeed = v);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('100', style: _labelStyle),
                  Text('500 km/h', style: _labelStyle),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  风速调节
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFanSpeedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('风速', style: _sectionTitleStyle),
            Text(
              '${_currentFanSpeed.round()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _currentFanSpeed,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) {
                setState(() => _currentFanSpeed = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  音量调节 — 触摸时硬件弹出音量界面
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVolumeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('音量', style: _sectionTitleStyle),
                const SizedBox(width: 8),
                Icon(
                  _volume > 0 ? Icons.volume_up : Icons.volume_off,
                  color: Colors.white.withOpacity(0.4),
                  size: 16,
                ),
              ],
            ),
            Text(
              '${_volume.round()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '触摸滑块时硬件同步显示音量',
          style: TextStyle(
            color: Colors.white.withOpacity(0.25),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: _isAdjustingVolume
                ? Border.all(color: _accent.withOpacity(0.3), width: 1)
                : null,
          ),
          child: SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _volume,
              min: 0,
              max: 100,
              divisions: 100,
              onChangeStart: (_) => _onVolumeAdjustStart(),
              onChanged: _onVolumeChanged,
              onChangeEnd: (_) => _onVolumeAdjustEnd(),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  确认按钮
  // ═══════════════════════════════════════════════════════════════

  Widget _buildApplyButton() {
    return GestureDetector(
      onTap: _applySettings,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00C8FF), Color(0xFF0088CC)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              '启动风洞',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  样式
  // ═══════════════════════════════════════════════════════════════

  TextStyle get _sectionTitleStyle => TextStyle(
    color: Colors.white.withOpacity(0.5),
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  TextStyle get _labelStyle => TextStyle(
    color: Colors.white.withOpacity(0.3),
    fontSize: 11,
  );

  SliderThemeData _sliderTheme() {
    return SliderThemeData(
      activeTrackColor: _accent,
      inactiveTrackColor: Colors.white.withOpacity(0.1),
      thumbColor: Colors.white,
      overlayColor: _accent.withOpacity(0.1),
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    );
  }
}

/// 车库设置结果
class GarageSettings {
  final CarModel? selectedCar;
  final int maxSpeed;
  final int fanSpeed;
  final int volume;

  const GarageSettings({
    this.selectedCar,
    required this.maxSpeed,
    required this.fanSpeed,
    required this.volume,
  });
}
