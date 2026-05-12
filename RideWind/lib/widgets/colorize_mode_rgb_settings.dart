import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colorize Mode - RGB 设置界面组件
/// 
/// 功能：
/// - L/M/R/B 四个灯光位置选择
/// - 循环速度调节（渐变滑动条）
/// - 5个灰度快捷选择点
class ColorizeModeRGBSettings extends StatefulWidget {
  final String initialLightPosition; // 初始灯光位置
  final double initialLoopSpeed; // 初始循环速度
  final Function(String position) onPositionChanged; // 位置变化回调
  final Function(double speed) onSpeedChanged; // 速度变化回调
  final VoidCallback onClose; // 关闭回调

  const ColorizeModeRGBSettings({
    super.key,
    required this.initialLightPosition,
    required this.initialLoopSpeed,
    required this.onPositionChanged,
    required this.onSpeedChanged,
    required this.onClose,
  });

  @override
  State<ColorizeModeRGBSettings> createState() => _ColorizeModeRGBSettingsState();
}

class _ColorizeModeRGBSettingsState extends State<ColorizeModeRGBSettings> {
  late String _selectedLightPosition;
  late double _loopSpeed;

  @override
  void initState() {
    super.initState();
    _selectedLightPosition = widget.initialLightPosition;
    _loopSpeed = widget.initialLoopSpeed;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 480,
      left: 50,
      right: 50,
      child: GestureDetector(
        onTap: () {}, // 阻止点击穿透
        child: SizedBox(
          height: 230,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // L M R B 细长颜色条 + 下方字母
              _buildPositionSelector(),
              
              const SizedBox(height: 12),
              
              const Text(
                '循环速度',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 渐变滑动条
              _buildSpeedSlider(),
            ],
          ),
        ),
      ),
    );
  }

  /// L M R B 位置选择器
  Widget _buildPositionSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['L', 'M', 'R', 'B'].map((pos) {
        final isSelected = _selectedLightPosition == pos;
        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _selectedLightPosition = pos);
            widget.onPositionChanged(pos);
          },
          child: Container(
            width: 60,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 100,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFD32F2F) : Colors.white,
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(64),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pos,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFD32F2F) : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 循环速度滑动条
  Widget _buildSpeedSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: GestureDetector(
        // 点击定位
        onTapDown: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final containerWidth = MediaQuery.of(context).size.width - 60;
          final newSpeed = (localPosition.dx / containerWidth).clamp(0.0, 1.0);
          setState(() {
            _loopSpeed = newSpeed;
          });
          widget.onSpeedChanged(newSpeed);
          HapticFeedback.selectionClick();
          debugPrint('🎨 点击设置速度: ${(_loopSpeed * 100).toInt()}%');
        },
        // 拖动改变速度
        onHorizontalDragUpdate: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localPosition = box.globalToLocal(details.globalPosition);
          final containerWidth = MediaQuery.of(context).size.width - 60;
          final newSpeed = (localPosition.dx / containerWidth).clamp(0.0, 1.0);
          setState(() {
            _loopSpeed = newSpeed;
          });
          widget.onSpeedChanged(newSpeed);
          HapticFeedback.selectionClick();
        },
        child: SizedBox(
          height: 48,
          child: Stack(
            children: [
              // 顶部渐变条
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0x00FFFFFF), // 左侧透明
                        Color(0x87FFFFFF), // 中间半透明
                        Color(0xFFE0E0E0), // 右侧白色
                      ],
                      stops: [0.0, 0.21, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(64),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
              
              // 动态白色遮罩
              Positioned(
                top: 0,
                left: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = MediaQuery.of(context).size.width - 60;
                    final currentWidth = maxWidth * _loopSpeed;
                    return Container(
                      width: currentWidth.clamp(0.0, maxWidth),
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(64),
                            offset: const Offset(0, 2),
                            blurRadius: 9,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              // 底部5个灰度圆点
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGrayDot(0, const Color(0xFF545252)),
                    _buildGrayDot(1, const Color(0xFF696969)),
                    _buildGrayDot(2, const Color(0xFF999999)),
                    _buildGrayDot(3, const Color(0xFFCCCCCC)),
                    _buildGrayDot(4, const Color(0xFFFFFFFF)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 灰度快捷选择圆点
  Widget _buildGrayDot(int index, Color color) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _loopSpeed = index / 4.0; // 0, 0.25, 0.5, 0.75, 1.0
        });
        widget.onSpeedChanged(_loopSpeed);
        debugPrint('🎨 快捷选择灰度: $index (速度: $_loopSpeed)');
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

