import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../configs/device_connect_config.dart';
import '../controllers/colorize_controller.dart';
import '../core/service_locator.dart';
import 'device_connect_helpers.dart';
import 'throttle_effect_selector.dart';

/// Colorize Preset UI — 颜色胶囊条 + 转盘动画 + 底部按钮
///
/// 从 DeviceConnectScreen._buildPresetUI + _buildColorCapsulesLayer 提取。
/// 通过 get_it 获取 ColorizeController，使用 ListenableBuilder 监听状态变化。
class ColorizePresetView extends StatefulWidget {
  final PageController colorPageController;
  final Key colorPageViewKey;
  final GlobalKey colorCapsuleStripKey;
  final GlobalKey startColoringButtonKey;
  final GlobalKey paletteButtonKey;
  final bool debugMode;
  /// 🎨 点击调色盘按钮时的回调：导航到 RGB 面板（顶层 PageView 右侧页）
  final VoidCallback? onPaletteTap;

  const ColorizePresetView({
    super.key,
    required this.colorPageController,
    required this.colorPageViewKey,
    required this.colorCapsuleStripKey,
    required this.startColoringButtonKey,
    required this.paletteButtonKey,
    this.debugMode = false,
    this.onPaletteTap,
  });

  @override
  State<ColorizePresetView> createState() => _ColorizePresetViewState();
}

class _ColorizePresetViewState extends State<ColorizePresetView> {
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
            // 上部分：颜色胶囊条
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: config.bottomButtonsMarginBottom +
                  config.paletteButtonSize + 20,
              child: Center(
                child: KeyedSubtree(
                  key: widget.colorCapsuleStripKey,
                  child: _buildColorCapsulesLayer(config),
                ),
              ),
            ),
            // 底部：按钮区域
            Positioned(
              left: config.isSmallScreen ? 15 : 20,
              right: config.isSmallScreen ? 10 : 15,
              bottom: config.bottomButtonsMarginBottom,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // "油门灯效" 按钮（原"开始涂色"）
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        ThrottleEffectSelector.show(context);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        key: widget.startColoringButtonKey,
                        height: config.startColoringButtonTapHeight,
                        decoration: BoxDecoration(
                          color: widget.debugMode
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            config.startColoringButtonTapHeight / 2,
                          ),
                        ),
                        child: widget.debugMode
                            ? const Center(
                                child: Text(
                                  '油门灯效',
                                  style: TextStyle(color: Colors.white),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: config.isSmallScreen ? 6 : 8),
                  // "调色盘" 按钮
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      // 🔑 RGB 面板现为独立顶层页，通过回调导航到右侧页
                      widget.onPaletteTap?.call();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      key: widget.paletteButtonKey,
                      width: config.paletteButtonSize,
                      height: config.paletteButtonSize,
                      decoration: BoxDecoration(
                        color: widget.debugMode
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: widget.debugMode
                          ? const Center(
                              child: Text(
                                '调色盘',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColorCapsulesLayer(DeviceConnectConfig config) {
    final double capsuleWidth = config.colorCapsuleWidth;
    final double capsuleHeight = config.colorCapsuleHeight;
    final double containerHeight = config.colorCapsuleContainerHeight;
    final double triangleTopOffset = capsuleHeight + 35;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double triangleLeftPosition =
        screenWidth / 2 - 14;

    return SizedBox(
      height: containerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            top: triangleTopOffset,
            left: triangleLeftPosition,
            child: CustomPaint(
              size: const Size(28, 12),
              painter: TriangleIndicatorPainter(
                isActive: true,
                currentColor: _getSelectedColor(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: capsuleHeight + 30,
              child: PageView.builder(
                key: widget.colorPageViewKey,
                controller: widget.colorPageController,
                padEnds: true,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  _colorize.setSelectedColorIndex(index);
                  HapticFeedback.selectionClick();
                  _colorize.syncPresetToHardware(index);
                  _colorize.saveColorPreset(index);
                },
                itemCount: _colorize.ledColorCapsules.length,
                itemBuilder: (context, index) =>
                    _buildCapsuleItem(config, index, capsuleWidth, capsuleHeight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSelectedColor() {
    final capsules = _colorize.ledColorCapsules;
    final idx = _colorize.selectedColorIndex;
    if (capsules[idx]['type'] == 'solid') {
      return capsules[idx]['color'] as Color;
    }
    return (capsules[idx]['colors'] as List<Color>).first;
  }

  Widget _buildCapsuleItem(
    DeviceConnectConfig config,
    int index,
    double capsuleWidth,
    double capsuleHeight,
  ) {
    final capsule = _colorize.ledColorCapsules[index];
    final isSolid = capsule['type'] == 'solid';
    final distance = (index - _colorize.selectedColorIndex).abs();

    double brightness;
    if (distance == 0) {
      brightness = 1.0;
    } else if (distance == 1) {
      brightness = 0.7;
    } else if (distance == 2) {
      brightness = 0.5;
    } else {
      brightness = 0.3;
    }

    final double scale = distance == 0 ? 1.15 : 1.0;
    final double capsuleBorderRadius = capsuleWidth / 2;
    final double capsuleMargin = config.isSmallScreen ? 6.0 : 10.0;

    return GestureDetector(
      onTap: () {
        if (distance != 0) {
          widget.colorPageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Center(
        child: Transform.translate(
          offset: Offset.zero,
          child: Transform.scale(
            scale: distance == 0 ? 1.15 : scale,
            child: Container(
              width: capsuleWidth,
              height: capsuleHeight,
              margin: EdgeInsets.symmetric(horizontal: capsuleMargin),
              decoration: BoxDecoration(
                color: isSolid ? capsule['color'] as Color : null,
                gradient: !isSolid
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: (capsule['colors'] as List<Color>),
                      )
                    : null,
                borderRadius: BorderRadius.circular(capsuleBorderRadius),
                boxShadow: distance == 0
                    ? [
                        BoxShadow(
                          color: Colors.black.withAlpha(102),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: (isSolid
                                  ? capsule['color'] as Color
                                  : (capsule['colors'] as List<Color>).first)
                              .withAlpha(89),
                          blurRadius: 15,
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(
                        ((1.0 - brightness) * 255).round(),
                      ),
                      borderRadius: BorderRadius.circular(capsuleBorderRadius),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
