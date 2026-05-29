/// 烟雾参数面板（DraggableScrollableSheet 形式）
///
/// 风格参考 GarageControlSheet：
/// - 纯黑背景 + 顶部圆角
/// - 顶部拖拽条
/// - 可上下拖拽调整高度（30%~95%）
/// - 滚动浏览所有参数
///
/// 使用：
///   SmokeConfigPanel.show(context, config: smokeConfig);

import 'package:flutter/material.dart';
import 'smoke_config.dart';

class SmokeConfigPanel extends StatefulWidget {
  final SmokeConfig config;
  final ScrollController? scrollController;

  const SmokeConfigPanel({
    super.key,
    required this.config,
    this.scrollController,
  });

  /// 弹出面板（外部调用入口）
  static Future<void> show(
    BuildContext context, {
    required SmokeConfig config,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      // 透明遮罩：烟雾区域完全可见，方便调参时实时观察效果
      barrierColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,  // 默认 50%（更小，留更多烟雾区域可见）
        minChildSize: 0.15,     // 最小 15%（几乎缩到底部，烟雾完全展示）
        maxChildSize: 0.95,
        expand: false,
        snap: true,
        snapSizes: const [0.15, 0.5, 0.95],
        builder: (_, scrollController) => SmokeConfigPanel(
          config: config,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<SmokeConfigPanel> createState() => _SmokeConfigPanelState();
}

class _SmokeConfigPanelState extends State<SmokeConfigPanel> {
  @override
  void initState() {
    super.initState();
    widget.config.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.config.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ═══ 拖拽条 ═══
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ═══ 标题栏 ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '烟雾参数',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => cfg.resetToDefaults(),
                  icon: const Icon(Icons.refresh,
                      size: 16, color: Colors.white60),
                  label: const Text('重置',
                      style: TextStyle(color: Colors.white60)),
                ),
              ],
            ),
          ),

          // ═══ 内容区域（可滚动） ═══
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                // 基础
                _section('基础'),
                _colorRow('颜色', cfg.smokeColor, (c) => cfg.smokeColor = c),
                _slider('密度倍率', cfg.densityScale, 0.0, 2.0,
                    (v) => cfg.densityScale = v),

                // 物理
                _section('物理'),
                _slider('重力强度', cfg.gravityStrength, 0.0, 2.0,
                    (v) => cfg.gravityStrength = v),
                _slider('缭绕强度', cfg.swayStrength, 0.0, 1.0,
                    (v) => cfg.swayStrength = v),
                _slider('衰减速率', cfg.decayRate, 0.0, 0.1,
                    (v) => cfg.decayRate = v, decimals: 3),
                _slider('笔直压制', cfg.straightnessStrength, 0.0, 0.5,
                    (v) => cfg.straightnessStrength = v),

                // 障碍
                _section('障碍'),
                _switchRow('启用障碍', cfg.obstacleEnabled,
                    (v) => cfg.obstacleEnabled = v),
                _slider('位置 X', cfg.obstacleX, 0.0, 1.0,
                    (v) => cfg.obstacleX = v),
                _slider('位置 Y', cfg.obstacleY, 0.0, 1.0,
                    (v) => cfg.obstacleY = v),
                _slider('半轴 X', cfg.obstacleRx, 0.05, 0.30,
                    (v) => cfg.obstacleRx = v),
                _slider('半轴 Y', cfg.obstacleRy, 0.05, 0.30,
                    (v) => cfg.obstacleRy = v),

                // 渲染
                _section('渲染'),
                _slider('外层模糊', cfg.blur1Sigma, 0.0, 10.0,
                    (v) => cfg.blur1Sigma = v),
                _slider('核心模糊', cfg.blur2Sigma, 0.0, 10.0,
                    (v) => cfg.blur2Sigma = v),
                _slider('亮暗度', cfg.opacityScale, 0.0, 2.0,
                    (v) => cfg.opacityScale = v),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════

extension _PanelHelpers on _SmokeConfigPanelState {
  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Colors.tealAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.tealAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {int decimals = 2}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.tealAccent,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.tealAccent,
                trackHeight: 2.0,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              value.toStringAsFixed(decimals),
              style: const TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 12,
                  fontFamily: 'monospace'),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.tealAccent,
          ),
        ],
      ),
    );
  }

  Widget _colorRow(String label, Color color, ValueChanged<Color> onChanged) {
    final List<Color> presets = [
      const Color(0xFFFFFFFF),
      const Color(0xFFCCCCCC),
      const Color(0xFF999999),
      const Color(0xFFFFD700),
      const Color(0xFFFF8C00),
      const Color(0xFFFF4500),
      const Color(0xFF00BFFF),
      const Color(0xFF98FB98),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets.map((c) {
                    final selected = c == color;
                    return GestureDetector(
                      onTap: () => onChanged(c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? Colors.tealAccent
                                : Colors.white24,
                            width: selected ? 2.5 : 1.0,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 80),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _rgbSlider('R', color.red, Colors.redAccent, (v) {
                      onChanged(
                          Color.fromARGB(255, v, color.green, color.blue));
                    }),
                    _rgbSlider('G', color.green, Colors.greenAccent, (v) {
                      onChanged(
                          Color.fromARGB(255, color.red, v, color.blue));
                    }),
                    _rgbSlider('B', color.blue, Colors.blueAccent, (v) {
                      onChanged(
                          Color.fromARGB(255, color.red, color.green, v));
                    }),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rgbSlider(
      String label, int value, Color tint, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(label,
              style: TextStyle(
                  color: tint,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tint,
              inactiveTrackColor: Colors.white12,
              thumbColor: tint,
              trackHeight: 2.0,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value.toString(),
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
