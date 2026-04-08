import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preference_service.dart';
import 'triangle_indicator_painter.dart';

/// Colorize Mode - 调色界面组件
/// 
/// 功能：
/// - 9种预设颜色（4纯色 + 5渐变）
/// - PageView 水平滑动选择
/// - 倒三角指示器（动态颜色）
/// - 舞台灯光效果（近亮远暗）
class ColorizeModeColorPicker extends StatefulWidget {
  final Function(Color color, int r, int g, int b) onColorSelected; // 颜色选择回调
  final VoidCallback onClose; // 关闭回调
  final bool debugMode; // 调试模式

  const ColorizeModeColorPicker({
    super.key,
    required this.onColorSelected,
    required this.onClose,
    this.debugMode = false,
  });

  @override
  State<ColorizeModeColorPicker> createState() => _ColorizeModeColorPickerState();
}

class _ColorizeModeColorPickerState extends State<ColorizeModeColorPicker> {
  PageController? _colorPageController;
  int _selectedColorIndex = 0;
  bool _initialized = false;
  final PreferenceService _prefService = PreferenceService();

  // UI 参数
  static const double capsuleWidth = 47.0;
  static const double capsuleHeight = 153.0;
  static const double triangleTopOffset = 163.0;
  static const double triangleLeftPosition = 30.0;
  static const double triangleWidth = 26.0;
  static const double triangleHeight = 9.5;
  static const double firstCapsuleLeftEdge = 17.5;

  // 颜色配置
  final List<Map<String, dynamic>> _colorCapsules = [
    // 9种真实颜色
    {'type': 'solid', 'color': Colors.white},
    {'type': 'solid', 'color': const Color(0xFFE53935)},
    {'type': 'solid', 'color': const Color(0xFF1E88E5)},
    {'type': 'solid', 'color': const Color(0xFFFF6F40)},
    {'type': 'gradient', 'colors': [const Color(0xFFE91E63), const Color(0xFF2196F3)]},
    {'type': 'gradient', 'colors': [const Color(0xFF9C27B0), Colors.white, const Color(0xFF9C27B0)]},
    {'type': 'gradient', 'colors': [const Color(0xFF00BCD4), const Color(0xFF4CAF50)]},
    {'type': 'gradient', 'colors': [const Color(0xFF673AB7), const Color(0xFF4CAF50)]},
    {'type': 'gradient', 'colors': [const Color(0xFFFF5722), const Color(0xFFFFEB3B), const Color(0xFF4CAF50), const Color(0xFF2196F3)]},
    // 6个透明占位条
    {'type': 'solid', 'color': Colors.transparent},
    {'type': 'solid', 'color': Colors.transparent},
    {'type': 'solid', 'color': Colors.transparent},
    {'type': 'solid', 'color': Colors.transparent},
    {'type': 'solid', 'color': Colors.transparent},
    {'type': 'solid', 'color': Colors.transparent},
  ];

  @override
  void initState() {
    super.initState();
    _initWithSavedPreset();
  }

  /// 先读取持久化索引，再初始化 PageController
  Future<void> _initWithSavedPreset() async {
    final savedIndex = await _prefService.getColorPreset();
    if (!mounted) return;
    setState(() {
      _selectedColorIndex = (savedIndex >= 0 && savedIndex < 9) ? savedIndex : 0;
      _colorPageController = PageController(
        initialPage: _selectedColorIndex,
        viewportFraction: 0.155,
      );
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _colorPageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Positioned(
        top: 540,
        left: 0,
        right: 0,
        child: SizedBox.shrink(),
      );
    }

    return Positioned(
      top: 540,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          debugPrint('🔙 点击调色界面背景 → 关闭调色界面');
          widget.onClose();
        },
        child: Container(
          height: 230,
          color: widget.debugMode ? Colors.black.withAlpha(26) : Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // PageView 颜色条
              _buildColorPageView(),
              
              // 倒三角指示器
              _buildTriangleIndicator(),
              
              // 调试信息
              if (widget.debugMode) _buildDebugInfo(),
            ],
          ),
        ),
      ),
    );
  }

  /// 颜色条 PageView
  Widget _buildColorPageView() {
    return Positioned(
      top: -12,
      left: -10,
      right: -10,
      child: Padding(
        padding: EdgeInsets.only(left: firstCapsuleLeftEdge + 10, right: 25),
        child: SizedBox(
          height: 153,
          child: PageView.builder(
            controller: _colorPageController!,
            padEnds: false,
            clipBehavior: Clip.none,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _selectedColorIndex = index;
              });
              HapticFeedback.selectionClick();
              // 持久化保存选择的颜色预设索引
              if (index < 9) {
                _prefService.saveColorPreset(index);
              }
              debugPrint('✅ 页面切换到索引: $index');
            },
            itemCount: _colorCapsules.length,
            itemBuilder: (context, index) {
              // 透明占位条不显示
              if (index >= 9) {
                return const SizedBox.shrink();
              }
              
              return _buildColorCapsule(index);
            },
          ),
        ),
      ),
    );
  }

  /// 单个颜色胶囊
  Widget _buildColorCapsule(int index) {
    final capsule = _colorCapsules[index];
    final isSolid = capsule['type'] == 'solid';
    final Color? solidColor = isSolid ? capsule['color'] as Color : null;
    final List<Color>? gradientColors = !isSolid ? capsule['colors'] as List<Color> : null;
    
    // 舞台灯光效果
    final distanceFromCenter = (index - _selectedColorIndex).abs();
    final brightness = distanceFromCenter == 0 
        ? 1.0
        : distanceFromCenter == 1
            ? 0.7
            : distanceFromCenter == 2
                ? 0.5
                : 0.3;
    
    return GestureDetector(
      onTap: () {
        if (index >= 9) {
          debugPrint('🎨 点击了透明占位条，忽略');
          return;
        }
        
        HapticFeedback.mediumImpact();
        debugPrint('🎨 选择颜色：索引 $index');
        
        // 持久化保存选择的颜色预设索引
        _prefService.saveColorPreset(index);
        
        // 提取颜色值
        Color selectedColor;
        if (isSolid) {
          selectedColor = solidColor!;
        } else {
          selectedColor = gradientColors!.first;
        }
        
        // 回调
        widget.onColorSelected(
          selectedColor,
          selectedColor.red,
          selectedColor.green,
          selectedColor.blue,
        );
        
        // 延迟关闭
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            widget.onClose();
          }
        });
      },
      child: Align(
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(
            horizontal: distanceFromCenter == 0 ? 10.0 : 0.0,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: distanceFromCenter == 0 ? 1.15 : 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, scale, child) {
              return OverflowBox(
                maxWidth: capsuleWidth * 1.5,
                maxHeight: capsuleHeight * 1.5,
                alignment: Alignment.center,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: child!,
                ),
              );
            },
            child: SizedBox(
              width: capsuleWidth,
              height: capsuleHeight,
              child: Stack(
                children: [
                  // 颜色条主体
                  Container(
                    width: capsuleWidth,
                    height: capsuleHeight,
                    decoration: BoxDecoration(
                      color: isSolid ? solidColor : null,
                      gradient: isSolid ? null : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: gradientColors!,
                      ),
                      borderRadius: BorderRadius.circular(23.5),
                      boxShadow: distanceFromCenter == 0 
                        ? [
                            BoxShadow(
                              color: Colors.black.withAlpha(102),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: (isSolid ? solidColor! : gradientColors!.first).withAlpha(51),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withAlpha(51),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                    ),
                  ),
                  // 舞台灯光遮罩
                  Container(
                    width: capsuleWidth,
                    height: capsuleHeight,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(((1.0 - brightness) * 255).round()),
                      borderRadius: BorderRadius.circular(23.5),
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

  /// 倒三角指示器
  Widget _buildTriangleIndicator() {
    return Positioned(
      top: triangleTopOffset,
      left: triangleLeftPosition,
      child: CustomPaint(
        size: const Size(triangleWidth, triangleHeight),
        painter: TriangleIndicatorPainter(
          isActive: true,
          currentColor: _getCurrentColorForTriangle(),
        ),
      ),
    );
  }

  /// 获取倒三角当前颜色
  Color _getCurrentColorForTriangle() {
    if (_selectedColorIndex < 0 || _selectedColorIndex >= _colorCapsules.length) {
      return Colors.white;
    }
    
    final capsule = _colorCapsules[_selectedColorIndex];
    final isSolid = capsule['type'] == 'solid';
    
    if (isSolid) {
      return capsule['color'] as Color;
    } else {
      final gradientColors = capsule['colors'] as List<Color>;
      return gradientColors.first;
    }
  }

  /// 调试信息
  Widget _buildDebugInfo() {
    return Positioned(
      top: 185,
      left: 15,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(179),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.yellow, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '🎯 精准对齐参数',
              style: TextStyle(
                color: Colors.yellow,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '倒三角中心: ${triangleLeftPosition + triangleWidth / 2}px',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            Text(
              '颜色条中心: ${firstCapsuleLeftEdge + capsuleWidth / 2}px',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            Text(
              '对齐误差: ${((triangleLeftPosition + triangleWidth / 2) - (firstCapsuleLeftEdge + capsuleWidth / 2)).abs()}px',
              style: TextStyle(
                color: ((triangleLeftPosition + triangleWidth / 2) - (firstCapsuleLeftEdge + capsuleWidth / 2)).abs() < 0.1 
                    ? Colors.greenAccent 
                    : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '当前颜色索引: $_selectedColorIndex',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

