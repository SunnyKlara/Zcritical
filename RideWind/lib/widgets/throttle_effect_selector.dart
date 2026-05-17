import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';

/// 油门灯效选择弹窗
///
/// 6 种速度响应 LED 效果，选择后通过 BLE 发送到 ESP32。
/// 从 Color 界面的"涂色"按钮触发。
class ThrottleEffectSelector {
  static const List<_EffectOption> _effects = [
    _EffectOption(
      mode: 1,
      icon: Icons.speed,
      name: '转速条',
      description: '逐颗点亮，像转速表',
    ),
    _EffectOption(
      mode: 2,
      icon: Icons.favorite,
      name: '脉冲波',
      description: '从中心向两端扩散',
    ),
    _EffectOption(
      mode: 3,
      icon: Icons.directions_run,
      name: '追逐流光',
      description: '光点奔跑穿越灯带',
    ),
    _EffectOption(
      mode: 4,
      icon: Icons.flash_on,
      name: '交替闪烁',
      description: 'Main↔Tail 交替亮灭',
    ),
    _EffectOption(
      mode: 5,
      icon: Icons.waves,
      name: '波浪呼吸',
      description: '亮度波蛇形游动',
    ),
    _EffectOption(
      mode: 6,
      icon: Icons.bolt,
      name: '闪电爆发',
      description: '随机白色闪光',
    ),
  ];

  /// 显示效果选择弹窗
  static Future<void> show(BuildContext context, {int currentMode = 4}) async {
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _EffectSheet(currentMode: currentMode),
    );

    if (result != null && context.mounted) {
      final bt = Provider.of<BluetoothProvider>(context, listen: false);
      await bt.setThrottleEffect(result);
    }
  }
}

class _EffectOption {
  final int mode;
  final IconData icon;
  final String name;
  final String description;

  const _EffectOption({
    required this.mode,
    required this.icon,
    required this.name,
    required this.description,
  });
}

class _EffectSheet extends StatefulWidget {
  final int currentMode;

  const _EffectSheet({required this.currentMode});

  @override
  State<_EffectSheet> createState() => _EffectSheetState();
}

class _EffectSheetState extends State<_EffectSheet> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              '油门灯效',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 效果列表
          ...ThrottleEffectSelector._effects.map((effect) {
            final isSelected = effect.mode == _selected;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selected = effect.mode);
                Navigator.of(context).pop(effect.mode);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFC62828).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFC62828)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      effect.icon,
                      color: isSelected ? const Color(0xFFC62828) : Colors.white60,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            effect.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            effect.description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFFC62828),
                        size: 22,
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          // 提示文字
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '进入油门模式后自动激活选中的灯效',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
