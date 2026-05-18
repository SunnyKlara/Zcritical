import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../configs/device_connect_config.dart';
import '../controllers/colorize_controller.dart';
import '../core/service_locator.dart';
import '../screens/color_ring_screen.dart';
import 'device_connect_helpers.dart';

/// Colorize RGB Detail UI — LMRB 灯区选择 + 流水灯速度 + 详细调色面板 + 亮度
///
/// 从 DeviceConnectScreen._buildRGBDetailUI + _buildDetailedTuningOverlay +
/// _buildVerticalBrightnessSlider + _buildHighQualityRGBPanel +
/// _buildMetallicColorSlider + _buildCycleSpeedPanel + _buildRGBPositionCapsulesNew 提取。
///
/// 通过 get_it 获取 ColorizeController，使用 ListenableBuilder 监听状态变化。
///
/// [overlayBuilder] 用于在 Screen 的主 Stack 中渲染详细调色覆盖层，
/// 因为覆盖层需要 Positioned.fill 覆盖整个屏幕，不能放在 PageView 子项内部。
class ColorizeRGBDetailView extends StatefulWidget {
  final GlobalKey lmrbCapsulesKey;
  final GlobalKey rgbSlidersKey;
  final GlobalKey brightnessBarKey;
  final bool debugMode;

  const ColorizeRGBDetailView({
    super.key,
    required this.lmrbCapsulesKey,
    required this.rgbSlidersKey,
    required this.brightnessBarKey,
    this.debugMode = false,
  });

  @override
  State<ColorizeRGBDetailView> createState() => _ColorizeRGBDetailViewState();
}

class _ColorizeRGBDetailViewState extends State<ColorizeRGBDetailView> {
  late final ColorizeController _colorize;

  @override
  void initState() {
    super.initState();
    _colorize = sl<ColorizeController>();
  }

  @override
  Widget build(BuildContext context) {
    final config = DeviceConnectConfig(context);

    return ListenableBuilder(
      listenable: _colorize,
      builder: (context, _) {
        try {
          // 🔧 现在 RGB 面板被嵌入到下半部容器中（约 55% 屏高），
          // 而非原本的全屏覆盖。为防止 LMRB 胶囊或循环速度面板超出容器导致
          // 黄黑条溢出警告，使用 FittedBox 让胶囊区在空间不足时整体缩放，
          // 并把底部 padding 收紧。
          return Column(
            children: [
              // 上部分：LMRB 胶囊选择区
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: config.isSmallScreen ? 5 : 10),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: KeyedSubtree(
                        key: widget.lmrbCapsulesKey,
                        child: _buildRGBPositionCapsules(config),
                      ),
                    ),
                  ),
                ),
              ),
              // 底部：循环速度控制面板
              Padding(
                padding: EdgeInsets.only(
                  bottom: config.safeAreaBottom +
                      (config.isSmallScreen ? 12 : 20),
                ),
                child: _buildCycleSpeedPanel(config),
              ),
            ],
          );
        } catch (e, stackTrace) {
          debugPrint('❌ RGB Detail UI 渲染错误: $e');
          debugPrint('📍 堆栈: $stackTrace');
          return Center(
            child: Text(
              '加载失败: $e',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          );
        }
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  LMRB 灯区胶囊选择
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRGBPositionCapsules(DeviceConnectConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final horizontalPadding = screenWidth * 0.035;
    final letterFontSize = screenWidth < 360
        ? 20.0
        : (screenWidth > 414 ? 30.0 : 24.0);
    final letterSpacing = screenHeight < 700 ? 8.0 : 12.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['L', 'M', 'R', 'B'].map((pos) {
        final isSelected = _colorize.selectedLightPosition == pos;
        return GestureDetector(
          // 🔑 单击 = 选中灯区 + 打开详细调色面板（原长按行为合并到单击）
          onTap: () async {
            HapticFeedback.mediumImpact();
            _colorize.stopCycleAnimation();
            _colorize.setSelectedLightPosition(pos);
            _colorize.setShowDetailedTuning(true);
            _colorize.syncLEDColor();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: config.rgbCapsuleWidth,
                  height: config.rgbCapsuleHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFC62828)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(
                      config.rgbCapsuleWidth / 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFC62828)
                                  .withValues(alpha: 0.6),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                ),
                SizedBox(height: letterSpacing),
                Text(
                  pos,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: letterFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  流水灯速度面板
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCycleSpeedPanel(DeviceConnectConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final labelFontSize = screenWidth < 360
        ? 14.0
        : (screenWidth > 414 ? 18.0 : 16.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
          child: Row(
            children: [
              SizedBox(width: screenWidth * 0.02),
              Text(
                '慢',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Expanded(
                child: Container(
                  height: config.cycleSpeedSliderHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(
                      config.cycleSpeedSliderHeight / 2,
                    ),
                    border: Border.all(
                      color: _colorize.isCycling
                          ? const Color(0xFFC62828).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: config.cycleSpeedSliderHeight,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: _colorize.isCycling
                          ? const Color(0xFFC62828)
                          : Colors.white,
                      thumbShape: CustomSliderThumbShape(
                        radius: config.cycleSpeedSliderHeight / 2,
                        color: _colorize.isCycling
                            ? const Color(0xFFC62828)
                            : Colors.white,
                      ),
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _colorize.cycleSpeed,
                      onChanged: (val) {
                        _colorize.updateCycleSpeed(val);
                        if (!_colorize.isCycling) {
                          _colorize.startCycleAnimation();
                        }
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Text(
                '快',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: screenWidth * 0.02),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  详细调色覆盖层（独立 Widget，在 Screen 的主 Stack 中使用）
// ═══════════════════════════════════════════════════════════════════════

/// 详细调色覆盖层 — 亮度滑条 + RGB 三通道滑条 + 色环入口
///
/// 从 DeviceConnectScreen._buildDetailedTuningOverlay 提取。
/// 需要在 Screen 的主 Stack 中使用（Positioned.fill），因为它覆盖整个屏幕。
class ColorizeDetailedTuningOverlay extends StatefulWidget {
  final GlobalKey rgbSlidersKey;
  final GlobalKey brightnessBarKey;

  const ColorizeDetailedTuningOverlay({
    super.key,
    required this.rgbSlidersKey,
    required this.brightnessBarKey,
  });

  @override
  State<ColorizeDetailedTuningOverlay> createState() =>
      _ColorizeDetailedTuningOverlayState();
}

class _ColorizeDetailedTuningOverlayState
    extends State<ColorizeDetailedTuningOverlay> {
  late final ColorizeController _colorize;

  @override
  void initState() {
    super.initState();
    _colorize = sl<ColorizeController>();
  }

  @override
  Widget build(BuildContext context) {
    final config = DeviceConnectConfig(context);

    return ListenableBuilder(
      listenable: _colorize,
      builder: (context, _) {
        return Stack(
          children: [
            // 半透明背景，点击关闭
            GestureDetector(
              onTap: () {
                _colorize.setShowDetailedTuning(false);
                _colorize.syncLEDColor();
              },
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            // 右侧亮度滑条
            Positioned(
              top: config.verticalBrightnessTop,
              right: config.menuButtonRight,
              child: KeyedSubtree(
                key: widget.brightnessBarKey,
                child: _buildVerticalBrightnessSlider(config),
              ),
            ),
            // 底部 RGB 面板
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: KeyedSubtree(
                key: widget.rgbSlidersKey,
                child: _buildHighQualityRGBPanel(config),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  垂直亮度滑条
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVerticalBrightnessSlider(DeviceConnectConfig config) {
    final fillHeight =
        config.verticalBrightnessHeight * _colorize.brightnessValue;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final newVal =
            (_colorize.brightnessValue - details.delta.dy / 200)
                .clamp(0.0, 1.0);
        _colorize.setBrightnessValue(newVal);
        _colorize.syncBrightness();
      },
      child: Container(
        width: config.verticalBrightnessWidth,
        height: config.verticalBrightnessHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(
            config.verticalBrightnessWidth / 2,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
            // 🌟 亮度越高，外发光越强
            if (_colorize.brightnessValue > 0.5)
              BoxShadow(
                color: Colors.white.withValues(
                  alpha: (_colorize.brightnessValue - 0.5) * 0.4,
                ),
                blurRadius: 20 * _colorize.brightnessValue,
                spreadRadius: 2 * _colorize.brightnessValue,
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 亮度填充条
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: fillHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
            // 🔆 底部动态图标：随亮度变化
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 光晕层（亮度高时显示）
                    if (_colorize.brightnessValue > 0.5)
                      Container(
                        width: 28 + (_colorize.brightnessValue * 12),
                        height: 28 + (_colorize.brightnessValue * 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.amber.withValues(
                                alpha:
                                    (_colorize.brightnessValue - 0.5) * 0.5,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    // 图标本体
                    Transform.scale(
                      scale: 0.85 +
                          (_colorize.brightnessValue * 0.35), // 0.85 ~ 1.2
                      child: Icon(
                        _colorize.brightnessValue > 0.5
                            ? Icons.wb_sunny
                            : Icons.wb_sunny_outlined,
                        color: _colorize.brightnessValue > 0.6
                            ? Colors.amber
                            : _colorize.brightnessValue > 0.3
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  高品质 RGB 面板
  // ═══════════════════════════════════════════════════════════════

  Widget _buildHighQualityRGBPanel(DeviceConnectConfig config) {
    final currentPos = _colorize.selectedLightPosition;
    final posName = {
      'L': '左侧灯带',
      'M': '中间灯带',
      'R': '右侧灯带',
      'B': '后部灯带',
    }[currentPos];

    return Container(
      padding: const EdgeInsets.fromLTRB(30, 35, 30, 50),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151515), Color(0xFF0A0A0A)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 40,
            offset: const Offset(0, -15),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 25),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题行：色环按钮 + 灯区名称
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🎨 传统色彩圆盘入口按钮
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openChineseColorWheel(),
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 1.5),
                    gradient: const SweepGradient(
                      colors: [
                        Color(0xFFFF4500),
                        Color(0xFFE2C100),
                        Color(0xFF2BAE66),
                        Color(0xFF1661AB),
                        Color(0xFF8B2671),
                        Color(0xFFFF4500),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.palette_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              Text(
                posName!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // R 通道
          _buildMetallicColorSlider(
            config,
            'R',
            const Color(0xFFFF3D00),
            _colorize.redValues[currentPos]!,
            (val) {
              _colorize.setRedValue(currentPos, val.toInt());
              _colorize.syncLEDColor();
              _colorize.markCustomColors();
            },
          ),
          const SizedBox(height: 15),
          // G 通道
          _buildMetallicColorSlider(
            config,
            'G',
            const Color(0xFF00E676),
            _colorize.greenValues[currentPos]!,
            (val) {
              _colorize.setGreenValue(currentPos, val.toInt());
              _colorize.syncLEDColor();
              _colorize.markCustomColors();
            },
          ),
          const SizedBox(height: 15),
          // B 通道
          _buildMetallicColorSlider(
            config,
            'B',
            const Color(0xFF2979FF),
            _colorize.blueValues[currentPos]!,
            (val) {
              _colorize.setBlueValue(currentPos, val.toInt());
              _colorize.syncLEDColor();
              _colorize.markCustomColors();
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  机械风格 RGB 滑条
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMetallicColorSlider(
    DeviceConnectConfig config,
    String label,
    Color color,
    int value,
    ValueChanged<double> onChanged,
  ) {
    const int segments = 25;
    final int litSegments = (value / 255 * segments).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _colorize.editingRGBChannel == label
                      ? Colors.white30
                      : Colors.white10,
                ),
              ),
              child: _colorize.editingRGBChannel == label
                  ? SizedBox(
                      width: 48,
                      height: 22,
                      child: TextField(
                        controller: _colorize.rgbValueController,
                        focusNode: _colorize.rgbValueFocusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _colorize.commitRGBValueEdit(),
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        _colorize.startRGBValueEdit(label, value);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _colorize.rgbValueFocusNode.requestFocus();
                          _colorize.rgbValueController.selection =
                              TextSelection(
                            baseOffset: 0,
                            extentOffset:
                                _colorize.rgbValueController.text.length,
                          );
                        });
                      },
                      child: Text(
                        value.toString().padLeft(3, '0'),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: config.metallicSliderHeight,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(segments, (index) {
                  final isLit = index < litSegments;
                  return Container(
                    width: 6,
                    height: config.metallicSliderHeight / 2,
                    decoration: BoxDecoration(
                      color: isLit
                          ? color
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(1),
                      boxShadow: isLit
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: config.metallicSliderHeight,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
                thumbShape: MechanicalThumbShape(color: color),
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  色彩圆环导航
  // ═══════════════════════════════════════════════════════════════

  void _openChineseColorWheel() {
    debugPrint('🎨 _openChineseColorWheel 开始导航');
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            return ColorRingScreen(
              onColorSelected: (r, g, b) {
                final pos = _colorize.selectedLightPosition;
                _colorize.setRedValue(pos, r);
                _colorize.setGreenValue(pos, g);
                _colorize.setBlueValue(pos, b);
                _colorize.syncLEDColor();
                _colorize.markCustomColors();
              },
            );
          },
        ),
      );
    } catch (e, stack) {
      debugPrint('🎨 导航异常: $e');
      debugPrint('📍 堆栈: $stack');
    }
  }
}
