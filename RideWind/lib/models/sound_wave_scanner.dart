import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 声波扫描动画组件
/// 模仿蓝牙扫描时的声波效果
class SoundWaveScanner extends StatefulWidget {
  /// 是否正在扫描
  final bool isScanning;
  
  /// 声波宽度
  final double width;
  
  /// 声波高度
  final double height;
  
  const SoundWaveScanner({
    super.key,
    required this.isScanning,
    this.width = 280,
    this.height = 200,
  });

  @override
  State<SoundWaveScanner> createState() => _SoundWaveScannerState();
}

class _SoundWaveScannerState extends State<SoundWaveScanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500), // 放慢速度，更优雅
      vsync: this,
    );
    
    // 立即启动动画并持续循环
    _controller.repeat();
    
    // 调试：打印确认动画已启动
    debugPrint('🎵 声波动画已启动');
  }

  @override
  void didUpdateWidget(SoundWaveScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 确保动画始终运行
    if (!_controller.isAnimating) {
      _controller.repeat();
      debugPrint('🎵 声波动画重新启动');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _SoundWavePainter(
              progress: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

/// 声波绘制器 - 简化版本，确保动画明显
class _SoundWavePainter extends CustomPainter {
  final double progress; // 动画进度 0-1

  // 声波条数量
  static const int barCount = 9;
  
  // 每个条的宽度
  static const double barWidth = 6.0;
  
  // 条之间的间距
  static const double barSpacing = 14.0;

  _SoundWavePainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final totalWidth = barCount * barWidth + (barCount - 1) * barSpacing;
    final startX = center.dx - totalWidth / 2;

    // 绘制每个声波条
    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barWidth + barSpacing);
      final barHeight = _getBarHeight(i, size.height);
      final color = _getBarColor(i, barHeight, size.height);
      
      // 绘制圆角矩形条
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, center.dy),
          width: barWidth,
          height: barHeight,
        ),
        const Radius.circular(3),
      );

      // 计算强度，决定是否添加发光效果
      final intensity = barHeight / size.height;
      
      // 添加适度的发光效果，红色更明显
      if (intensity > 0.7) {
        // 判断是否为红色系
        final redValue = (color.r * 255.0).round() & 0xff;
        final blueValue = (color.b * 255.0).round() & 0xff;
        final isReddish = redValue > blueValue && redValue > 200;
        
        final glowPaint = Paint()
          ..color = color.withValues(alpha: isReddish ? 0.4 : 0.2) // 红色光晕更强
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isReddish ? 8 : 5) // 红色光晕更大
          ..style = PaintingStyle.fill;
        
        canvas.drawRRect(rect, glowPaint);
      }
      
      // 绘制主条形
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rect, paint);
    }
  }

  /// 获取声波条的高度 - 优化的声波效果
  double _getBarHeight(int index, double maxHeight) {
    // 为每个条设置不同的相位，创造波浪般的传播效果
    final phase = index * 0.35; // 减小相位差，让波动更协调
    
    // 使用平滑的正弦波
    final wave = math.sin((progress + phase) * 2 * math.pi);
    
    // 计算距离中心的位置
    final centerIndex = 4;
    final distanceFromCenter = (index - centerIndex).abs();
    
    // 中间的红色条（索引4）波动最明显
    if (index == 4) {
      // 使用缓动函数让波动更平滑
      final easeWave = _easeInOutSine(wave.abs());
      // 高度在 35% 到 85% 之间平滑波动
      return maxHeight * (0.35 + easeWave * 0.50);
    }
    
    // 其他条：越靠近中心，波动越大，形成渐变效果
    final baseHeight = 0.25 + (1.0 - distanceFromCenter / 5.0) * 0.15; // 0.25 到 0.40
    final amplitude = 0.40 - (distanceFromCenter * 0.05);  // 0.20 到 0.40
    
    // 应用缓动函数让波动更优雅
    final easeWave = _easeInOutSine(wave.abs());
    
    return maxHeight * (baseHeight + easeWave * amplitude);
  }
  
  /// 缓动函数：让波动更平滑
  double _easeInOutSine(double t) {
    return -(math.cos(math.pi * t) - 1) / 2;
  }

  /// 获取声波条的颜色 - 动态颜色变化（鲜艳红色版）
  Color _getBarColor(int index, double barHeight, double maxHeight) {
    // 计算当前条的波动强度（0-1）
    final intensity = barHeight / maxHeight;
    
    // 方案：组合效果 - 波动强度 + 波浪扫描
    
    // 1. 基于进度的波浪扫描效果
    // 红色像波浪一样从左到右，再从右到左扫过
    final scanPosition = (progress * 2) % 2.0; // 0-2循环
    final normalizedScanPos = scanPosition > 1.0 
        ? 2.0 - scanPosition  // 1-2时反向
        : scanPosition;       // 0-1时正向
    
    final indexNormalized = index / (barCount - 1); // 0-1
    final distanceFromScan = (indexNormalized - normalizedScanPos).abs();
    
    // 扫描波的影响范围
    final scanInfluence = (1.0 - (distanceFromScan * 3).clamp(0.0, 1.0));
    
    // 2. 基于波动强度的颜色
    final intensityInfluence = intensity > 0.5 
        ? (intensity - 0.5) / 0.5  // 0.5-1.0 映射到 0-1
        : 0.0;
    
    // 3. 组合两种影响
    final redInfluence = (scanInfluence * 0.6 + intensityInfluence * 0.4).clamp(0.0, 1.0);
    
    // 4. 混合颜色 - 使用更鲜艳的红色
    if (redInfluence > 0.1) {
      // 使用非线性混合，让红色更快达到饱和
      final enhancedInfluence = math.pow(redInfluence, 0.7).toDouble(); // 加速曲线
      
      return Color.lerp(
        Colors.white,
        const Color(0xFFFF3333), // 更鲜艳的红色（增加饱和度）
        enhancedInfluence, // 100%混合，不限制
      )!;
    }
    
    return Colors.white;
  }

  @override
  bool shouldRepaint(_SoundWavePainter oldDelegate) {
    // 每次 progress 变化都重绘
    return oldDelegate.progress != progress;
  }
}
