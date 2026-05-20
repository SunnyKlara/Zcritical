import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/bluetooth_provider.dart';

/// 灯光模式选择弹窗（Pro 版）
///
/// 4 个选项：静态 / 波浪呼吸 / 风浪联动PRO / 流水灯
/// 选中即预览（立即发 THROTTLE_FX:mode）
/// PRO 标签 + 10 秒预览回退
/// SharedPreferences 记忆选择
class ThrottleEffectSelector {
  static const String _prefKey = 'throttle_fx_mode';

  static const List<_EffectOption> _effects = [
    _EffectOption(
      mode: 0,
      icon: Icons.lightbulb_outline,
      name: '静态',
      description: '保持当前预设颜色，不播放动画效果',
      isPro: false,
    ),
    _EffectOption(
      mode: 5,
      icon: Icons.waves,
      name: '波浪呼吸',
      description: '柔和的明暗起伏，固定节奏，像海浪轻拍',
      isPro: false,
    ),
    _EffectOption(
      mode: 7,
      icon: Icons.air,
      name: '风浪联动',
      description: '波浪随风速变化 — 风越大浪越急',
      isPro: true,
    ),
    _EffectOption(
      mode: 3,
      icon: Icons.auto_awesome,
      name: '流水灯',
      description: '光点追逐奔跑，穿越整条灯带',
      isPro: false,
    ),
  ];

  /// 从 SharedPreferences 读取上次选择的 mode
  static Future<int> getSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefKey) ?? 0; // 默认静态
  }

  /// 保存选择到 SharedPreferences
  static Future<void> _saveMode(int mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, mode);
  }

  /// 显示灯光模式选择弹窗
  static Future<void> show(BuildContext context) async {
    final savedMode = await getSavedMode();

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _EffectSheet(savedMode: savedMode),
    );
  }
}

class _EffectOption {
  final int mode;
  final IconData icon;
  final String name;
  final String description;
  final bool isPro;

  const _EffectOption({
    required this.mode,
    required this.icon,
    required this.name,
    required this.description,
    required this.isPro,
  });
}

class _EffectSheet extends StatefulWidget {
  final int savedMode;

  const _EffectSheet({required this.savedMode});

  @override
  State<_EffectSheet> createState() => _EffectSheetState();
}

class _EffectSheetState extends State<_EffectSheet> {
  late int _confirmed; // 已确认保存的 mode
  late int _previewing; // 当前预览中的 mode（可能未确认）
  Timer? _proTimer;
  int _proCountdown = 0;
  bool _isProPreviewing = false;

  @override
  void initState() {
    super.initState();
    _confirmed = widget.savedMode;
    _previewing = widget.savedMode;
  }

  @override
  void dispose() {
    _proTimer?.cancel();
    // 如果正在 PRO 预览中退出弹窗，回退到已确认的 mode
    if (_isProPreviewing && _previewing != _confirmed) {
      _sendMode(_confirmed);
    }
    super.dispose();
  }

  Future<void> _sendMode(int mode) async {
    if (!mounted) return;
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    await bt.setThrottleEffect(mode);
  }

  void _onTap(_EffectOption effect) {
    HapticFeedback.lightImpact();

    // 立即发送预览
    _sendMode(effect.mode);

    if (effect.isPro) {
      // PRO 选项：10 秒预览后回退
      setState(() {
        _previewing = effect.mode;
        _isProPreviewing = true;
        _proCountdown = 10;
      });
      _proTimer?.cancel();
      _proTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _proCountdown--;
        });
        if (_proCountdown <= 0) {
          timer.cancel();
          // 回退到之前确认的 mode
          setState(() {
            _isProPreviewing = false;
            _previewing = _confirmed;
          });
          _sendMode(_confirmed);
        }
      });
    } else {
      // 非 PRO 选项：直接确认
      _proTimer?.cancel();
      setState(() {
        _isProPreviewing = false;
        _confirmed = effect.mode;
        _previewing = effect.mode;
      });
      ThrottleEffectSelector._saveMode(effect.mode);
    }
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
              '灯光模式',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 效果列表
          ...ThrottleEffectSelector._effects.map((effect) {
            final isSelected = effect.mode == _previewing;
            return GestureDetector(
              onTap: () => _onTap(effect),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      color: isSelected
                          ? const Color(0xFFC62828)
                          : Colors.white60,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                effect.name,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (effect.isPro) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B00),
                                        Color(0xFFFF2D00),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'PRO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
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
                    if (isSelected && !_isProPreviewing)
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFFC62828),
                        size: 22,
                      ),
                    if (isSelected && _isProPreviewing && effect.isPro)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFF6B00),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_proCountdown',
                          style: const TextStyle(
                            color: Color(0xFFFF6B00),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          // PRO 预览提示
          if (_isProPreviewing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '预览中… ${_proCountdown}秒后自动恢复',
                style: const TextStyle(
                  color: Color(0xFFFF6B00),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '点击即可预览效果，进入 Speed 界面后自动激活',
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
