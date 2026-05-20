import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';

/// 悬浮音量条 — 长按速度区域呼出
///
/// 设计：底部滑入，圆角深色半透明背景
/// 左侧喇叭图标（点击 toggle mute），中间 Slider，右侧百分比
/// 3 秒无操作自动消失，点击外部消失
class VolumeOverlay {
  static OverlayEntry? _entry;
  static Timer? _autoHideTimer;

  /// 显示音量条
  static void show(BuildContext context) {
    // 如果已经显示，先移除
    hide();

    _entry = OverlayEntry(
      builder: (ctx) => _VolumeOverlayWidget(onDismiss: hide),
    );

    Overlay.of(context).insert(_entry!);
    HapticFeedback.mediumImpact();
    _startAutoHideTimer();
  }

  /// 隐藏音量条
  static void hide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _entry?.remove();
    _entry = null;
  }

  /// 重置自动隐藏计时器（用户交互时调用）
  static void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 3), hide);
  }

  /// 用户交互时重置计时器
  static void _resetTimer() {
    _startAutoHideTimer();
  }
}

class _VolumeOverlayWidget extends StatefulWidget {
  final VoidCallback onDismiss;

  const _VolumeOverlayWidget({required this.onDismiss});

  @override
  State<_VolumeOverlayWidget> createState() => _VolumeOverlayWidgetState();
}

class _VolumeOverlayWidgetState extends State<_VolumeOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  double _volume = 70;
  bool _isMuted = false;
  double _volumeBeforeMute = 70;
  Timer? _sendThrottle;

  @override
  void initState() {
    super.initState();

    // 从 provider 获取当前音量
    final provider = Provider.of<BluetoothProvider>(context, listen: false);
    _volume = provider.currentVolume.toDouble();
    _isMuted = _volume == 0;
    if (!_isMuted) _volumeBeforeMute = _volume;

    // 滑入动画
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_animController);

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _sendThrottle?.cancel();
    super.dispose();
  }

  void _onVolumeChanged(double value) {
    setState(() {
      _volume = value;
      _isMuted = value == 0;
    });
    VolumeOverlay._resetTimer();

    // 节流发送 BLE 命令（150ms）
    _sendThrottle?.cancel();
    _sendThrottle = Timer(const Duration(milliseconds: 150), () {
      final provider = Provider.of<BluetoothProvider>(context, listen: false);
      provider.setVolume(value.round());
    });
  }

  void _toggleMute() {
    VolumeOverlay._resetTimer();
    HapticFeedback.lightImpact();

    if (_isMuted) {
      // 恢复之前的音量
      _onVolumeChanged(_volumeBeforeMute > 0 ? _volumeBeforeMute : 70);
    } else {
      // 静音
      _volumeBeforeMute = _volume;
      _onVolumeChanged(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 点击外部区域关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: Container(color: Colors.transparent),
          ),
        ),

        // 音量条本体
        Positioned(
          left: 16,
          right: 16,
          bottom: 32 + MediaQuery.of(context).padding.bottom,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                // 防止点击音量条本身触发外部关闭
                onTap: () => VolumeOverlay._resetTimer(),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xD9000000), // black 85%
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x4D000000), // black 30%
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // 左侧喇叭图标（toggle mute）
                      GestureDetector(
                        onTap: _toggleMute,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 4),
                          child: Icon(
                            _isMuted
                                ? Icons.volume_off
                                : _volume < 30
                                    ? Icons.volume_mute
                                    : _volume < 70
                                        ? Icons.volume_down
                                        : Icons.volume_up,
                            color: _isMuted
                                ? Colors.white38
                                : Colors.white,
                            size: 22,
                          ),
                        ),
                      ),

                      // 中间滑块
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white12,
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                          ),
                          child: Slider(
                            value: _volume,
                            min: 0,
                            max: 100,
                            onChanged: _onVolumeChanged,
                            onChangeStart: (_) => VolumeOverlay._resetTimer(),
                          ),
                        ),
                      ),

                      // 右侧百分比
                      Padding(
                        padding: const EdgeInsets.only(right: 16, left: 4),
                        child: SizedBox(
                          width: 36,
                          child: Text(
                            '${_volume.round()}%',
                            style: TextStyle(
                              color: _isMuted
                                  ? Colors.white38
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
