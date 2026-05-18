import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../configs/device_connect_config.dart';
import '../controllers/colorize_controller.dart';
import '../core/service_locator.dart';
import 'custom_preset_editor_sheet.dart';
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
                  // 智能分发：preset → PRESET:n / custom → 4×LED:strip:r:g:b / plus → no-op
                  _colorize.syncCapsuleToHardware(index);
                  _colorize.saveColorPreset(index);
                },
                itemCount: _colorize.allCapsules.length,
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
    final capsules = _colorize.allCapsules;
    final idx = _colorize.selectedColorIndex.clamp(0, capsules.length - 1);
    final cap = capsules[idx];
    if (cap['kind'] == 'plus') return Colors.white;
    if (cap['type'] == 'solid') return cap['color'] as Color;
    return (cap['colors'] as List<Color>).first;
  }

  Widget _buildCapsuleItem(
    DeviceConnectConfig config,
    int index,
    double capsuleWidth,
    double capsuleHeight,
  ) {
    final capsule = _colorize.allCapsules[index];
    final kind = capsule['kind'] as String? ?? 'preset';
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

    // 🆕 末尾的 "+" 加号占位
    if (kind == 'plus') {
      return _buildPlusCapsule(
        config: config,
        index: index,
        capsuleWidth: capsuleWidth,
        capsuleHeight: capsuleHeight,
        capsuleMargin: capsuleMargin,
        capsuleBorderRadius: capsuleBorderRadius,
        scale: scale,
        brightness: brightness,
        distance: distance,
      );
    }

    final isSolid = capsule['type'] == 'solid';
    final isCustom = kind == 'custom';
    final customId = capsule['customId'] as String?;

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
      // 🆕 自定义胶囊：长按弹菜单（编辑/删除）
      onLongPress: isCustom && customId != null
          ? () => _showCustomCapsuleMenu(customId)
          : null,
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
                  // 🆕 自定义胶囊右上角放一个小标记
                  if (isCustom)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white70,
                        ),
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

  /// "+" 加号胶囊：点击进入新建自定义胶囊的编辑器
  Widget _buildPlusCapsule({
    required DeviceConnectConfig config,
    required int index,
    required double capsuleWidth,
    required double capsuleHeight,
    required double capsuleMargin,
    required double capsuleBorderRadius,
    required double scale,
    required double brightness,
    required int distance,
  }) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        if (distance != 0) {
          // 先把视觉滚到 "+"，但不打开编辑器（避免误触）；用户再点一次才打开
          widget.colorPageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          return;
        }
        await _openCreateCustomSheet();
      },
      child: Center(
        child: Transform.scale(
          scale: distance == 0 ? 1.15 : scale,
          child: Container(
            width: capsuleWidth,
            height: capsuleHeight,
            margin: EdgeInsets.symmetric(horizontal: capsuleMargin),
            decoration: BoxDecoration(
              color: Colors.white
                  .withValues(alpha: distance == 0 ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(capsuleBorderRadius),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: distance == 0 ? 0.7 : 0.35),
                width: distance == 0 ? 2.2 : 1.5,
              ),
              boxShadow: distance == 0
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.25),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                Icons.add,
                color: Colors.white
                    .withValues(alpha: distance == 0 ? 1.0 : 0.6),
                size: capsuleWidth * 0.55,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开"新建自定义胶囊"的底部 Sheet
  Future<void> _openCreateCustomSheet() async {
    final result = await CustomPresetEditorSheet.show(context);
    if (result == null) return;
    // 创建并保存（带重复检测）
    final id = await _colorize.addCustomPreset(
      type: result.type,
      r1: result.r1,
      g1: result.g1,
      b1: result.b1,
      r2: result.r2,
      g2: result.g2,
      b2: result.b2,
    );
    if (id == null) {
      _showDuplicateToast();
      return;
    }
    // 自动滚动到新增的自定义胶囊位置
    final newIndex = _colorize.customPresets.indexWhere((p) => p.id == id);
    if (newIndex >= 0) {
      final absIndex = _colorize.presetCount + newIndex;
      if (mounted) {
        widget.colorPageController.animateToPage(
          absIndex,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        _colorize.setSelectedColorIndex(absIndex);
        _colorize.saveColorPreset(absIndex);
        _colorize.syncCapsuleToHardware(absIndex);
      }
    }
  }

  /// 重复颜色时的提示
  void _showDuplicateToast() {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '这个颜色已经存在啦，换一个吧',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// 长按自定义胶囊的菜单（编辑/删除）
  void _showCustomCapsuleMenu(String customId) {
    HapticFeedback.mediumImpact();
    final preset = _colorize.findCustomPreset(customId);
    if (preset == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading:
                    const Icon(Icons.edit, color: Colors.white),
                title: const Text('编辑',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final updated = await CustomPresetEditorSheet.show(
                    context,
                    initial: preset,
                  );
                  if (updated == null) return;
                  final status = await _colorize.updateCustomPreset(
                    customId,
                    preset.copyWith(
                      type: updated.type,
                      r1: updated.r1,
                      g1: updated.g1,
                      b1: updated.b1,
                      r2: updated.r2,
                      g2: updated.g2,
                      b2: updated.b2,
                    ),
                  );
                  if (status == 'duplicate') {
                    _showDuplicateToast();
                    return;
                  }
                  if (status != 'ok') return;
                  // 如果正显示这个胶囊则重新同步硬件
                  final newIndex = _colorize.customPresets
                      .indexWhere((p) => p.id == customId);
                  if (newIndex >= 0) {
                    final absIndex =
                        _colorize.presetCount + newIndex;
                    if (_colorize.selectedColorIndex == absIndex) {
                      _colorize.syncCapsuleToHardware(absIndex);
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                title: const Text('删除',
                    style:
                        TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final wasSelected =
                      _colorize.allCapsules[_colorize.selectedColorIndex]
                              ['customId'] ==
                          customId;
                  await _colorize.removeCustomPreset(customId);
                  HapticFeedback.heavyImpact();
                  // 删除后，让 PageView 跟随 controller 当前页（可能因列表收缩偏移）
                  // 并把硬件 LED 同步到新的选中胶囊，避免硬件停留在已删除颜色
                  if (mounted) {
                    final newIdx = _colorize.selectedColorIndex;
                    widget.colorPageController.animateToPage(
                      newIdx,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                    if (wasSelected) {
                      _colorize.syncCapsuleToHardware(newIdx);
                      _colorize.saveColorPreset(newIdx);
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
