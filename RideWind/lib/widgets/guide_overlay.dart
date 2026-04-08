import 'package:flutter/material.dart';
import '../models/guide_models.dart';

/// 引导覆盖层组件
/// 用于显示功能操作提示，支持高亮目标元素
/// 
/// Requirements: 3.4, 3.6
class GuideOverlay extends StatefulWidget {
  /// 引导步骤列表
  final List<GuideStep> steps;

  /// 完成所有步骤时的回调
  final VoidCallback onComplete;

  /// 跳过引导时的回调（可选）
  final VoidCallback? onSkip;

  /// 是否允许跳过引导，默认为 true
  final bool canSkip;

  const GuideOverlay({
    super.key,
    required this.steps,
    required this.onComplete,
    this.onSkip,
    this.canSkip = true,
  });

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay>
    with SingleTickerProviderStateMixin {
  /// 当前步骤索引
  int _currentStepIndex = 0;

  /// 动画控制器
  late AnimationController _animationController;

  /// 淡入淡出动画
  late Animation<double> _fadeAnimation;

  /// 目标元素的位置和大小
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // 初始化后计算目标位置并开始动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetRect();
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 获取当前步骤
  GuideStep get _currentStep => widget.steps[_currentStepIndex];

  /// 是否为最后一步
  bool get _isLastStep => _currentStepIndex >= widget.steps.length - 1;

  /// 更新目标元素的位置和大小
  void _updateTargetRect() {
    try {
      final renderBox = _currentStep.targetKey.currentContext
          ?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        setState(() {
          _targetRect = Rect.fromLTWH(
            position.dx,
            position.dy,
            size.width,
            size.height,
          );
        });
      } else {
        // 如果目标元素不存在，使用屏幕中心作为默认位置
        setState(() {
          _targetRect = null;
        });
      }
    } catch (e) {
      debugPrint('Error updating target rect: $e');
      setState(() {
        _targetRect = null;
      });
    }
  }

  /// 前进到下一步
  Future<void> _nextStep() async {
    if (_isLastStep) {
      await _complete();
      return;
    }

    // 淡出动画
    await _animationController.reverse();

    setState(() {
      _currentStepIndex++;
    });

    // 更新目标位置并淡入
    _updateTargetRect();
    await _animationController.forward();
  }

  /// 完成引导
  Future<void> _complete() async {
    await _animationController.reverse();
    widget.onComplete();
  }

  /// 跳过引导
  Future<void> _skip() async {
    await _animationController.reverse();
    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // 高亮遮罩层
            Positioned.fill(
              child: CustomPaint(
                painter: HighlightMaskPainter(
                  targetRect: _targetRect,
                  overlayColor: Colors.black.withAlpha(191),
                  highlightPadding: 8.0,
                  highlightBorderRadius: 8.0,
                ),
              ),
            ),
            // 提示框
            if (_targetRect != null)
              _TooltipWidget(
                step: _currentStep,
                targetRect: _targetRect!,
                currentStepIndex: _currentStepIndex,
                totalSteps: widget.steps.length,
                isLastStep: _isLastStep,
                canSkip: widget.canSkip,
                onNext: _nextStep,
                onSkip: _skip,
                onComplete: _complete,
              ),
            // 如果目标元素不存在，显示居中的提示框
            if (_targetRect == null)
              _CenteredTooltipWidget(
                step: _currentStep,
                currentStepIndex: _currentStepIndex,
                totalSteps: widget.steps.length,
                isLastStep: _isLastStep,
                canSkip: widget.canSkip,
                onNext: _nextStep,
                onSkip: _skip,
                onComplete: _complete,
              ),
          ],
        ),
      ),
    );
  }
}

/// 高亮遮罩层绘制器
/// 创建一个带有透明"洞"的深色遮罩层，用于高亮目标元素
class HighlightMaskPainter extends CustomPainter {
  /// 目标元素的矩形区域
  final Rect? targetRect;

  /// 遮罩层颜色
  final Color overlayColor;

  /// 高亮区域的内边距
  final double highlightPadding;

  /// 高亮区域的圆角半径
  final double highlightBorderRadius;

  HighlightMaskPainter({
    this.targetRect,
    this.overlayColor = const Color(0xBF000000),
    this.highlightPadding = 8.0,
    this.highlightBorderRadius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    // 创建全屏路径
    final fullScreenPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (targetRect != null) {
      // 创建高亮区域路径（带内边距和圆角）
      final highlightRect = Rect.fromLTWH(
        targetRect!.left - highlightPadding,
        targetRect!.top - highlightPadding,
        targetRect!.width + highlightPadding * 2,
        targetRect!.height + highlightPadding * 2,
      );

      final highlightPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          highlightRect,
          Radius.circular(highlightBorderRadius),
        ));

      // 使用路径差集创建带洞的遮罩
      final combinedPath = Path.combine(
        PathOperation.difference,
        fullScreenPath,
        highlightPath,
      );

      canvas.drawPath(combinedPath, paint);

      // 绘制高亮边框 — 双层发光效果，让目标区域更醒目
      final highlightRRect = RRect.fromRectAndRadius(
        highlightRect,
        Radius.circular(highlightBorderRadius),
      );

      // 外层发光
      final glowPaint = Paint()
        ..color = const Color(0xFF25C485).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawRRect(highlightRRect, glowPaint);

      // 内层实线边框
      final borderPaint = Paint()
        ..color = const Color(0xFF25C485)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(highlightRRect, borderPaint);
    } else {
      // 如果没有目标元素，绘制全屏遮罩
      canvas.drawPath(fullScreenPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant HighlightMaskPainter oldDelegate) {
    return targetRect != oldDelegate.targetRect ||
        overlayColor != oldDelegate.overlayColor ||
        highlightPadding != oldDelegate.highlightPadding ||
        highlightBorderRadius != oldDelegate.highlightBorderRadius;
  }
}

/// 提示框组件
/// 显示步骤标题、描述和导航按钮
class _TooltipWidget extends StatelessWidget {
  final GuideStep step;
  final Rect targetRect;
  final int currentStepIndex;
  final int totalSteps;
  final bool isLastStep;
  final bool canSkip;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onComplete;

  const _TooltipWidget({
    required this.step,
    required this.targetRect,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.isLastStep,
    required this.canSkip,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final tooltipWidth = screenSize.width * 0.85;
    const tooltipMaxWidth = 320.0;
    final actualWidth =
        tooltipWidth > tooltipMaxWidth ? tooltipMaxWidth : tooltipWidth;

    // 计算提示框位置
    final position = _calculateTooltipPosition(
      targetRect: targetRect,
      tooltipPosition: step.position,
      screenSize: screenSize,
      tooltipWidth: actualWidth,
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: _TooltipContent(
        step: step,
        width: actualWidth,
        currentStepIndex: currentStepIndex,
        totalSteps: totalSteps,
        isLastStep: isLastStep,
        canSkip: canSkip,
        onNext: onNext,
        onSkip: onSkip,
        onComplete: onComplete,
        tooltipPosition: step.position,
      ),
    );
  }

  /// 计算提示框位置
  Offset _calculateTooltipPosition({
    required Rect targetRect,
    required TooltipPosition tooltipPosition,
    required Size screenSize,
    required double tooltipWidth,
  }) {
    const padding = 16.0;
    const arrowHeight = 12.0;
    const estimatedTooltipHeight = 180.0;

    double left;
    double top;

    switch (tooltipPosition) {
      case TooltipPosition.top:
        left = targetRect.center.dx - tooltipWidth / 2;
        top = targetRect.top - estimatedTooltipHeight - arrowHeight - padding;
        break;
      case TooltipPosition.bottom:
        left = targetRect.center.dx - tooltipWidth / 2;
        top = targetRect.bottom + arrowHeight + padding;
        break;
      case TooltipPosition.left:
        left = targetRect.left - tooltipWidth - arrowHeight - padding;
        top = targetRect.center.dy - estimatedTooltipHeight / 2;
        break;
      case TooltipPosition.right:
        left = targetRect.right + arrowHeight + padding;
        top = targetRect.center.dy - estimatedTooltipHeight / 2;
        break;
    }

    // 确保提示框在屏幕内
    left = left.clamp(padding, screenSize.width - tooltipWidth - padding);
    top = top.clamp(padding, screenSize.height - estimatedTooltipHeight - padding);

    return Offset(left, top);
  }
}

/// 居中提示框组件（当目标元素不存在时使用）
class _CenteredTooltipWidget extends StatelessWidget {
  final GuideStep step;
  final int currentStepIndex;
  final int totalSteps;
  final bool isLastStep;
  final bool canSkip;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onComplete;

  const _CenteredTooltipWidget({
    required this.step,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.isLastStep,
    required this.canSkip,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final tooltipWidth = screenSize.width * 0.85;
    const tooltipMaxWidth = 320.0;
    final actualWidth =
        tooltipWidth > tooltipMaxWidth ? tooltipMaxWidth : tooltipWidth;

    return Center(
      child: _TooltipContent(
        step: step,
        width: actualWidth,
        currentStepIndex: currentStepIndex,
        totalSteps: totalSteps,
        isLastStep: isLastStep,
        canSkip: canSkip,
        onNext: onNext,
        onSkip: onSkip,
        onComplete: onComplete,
        tooltipPosition: TooltipPosition.bottom,
      ),
    );
  }
}

/// 提示框内容组件
class _TooltipContent extends StatelessWidget {
  final GuideStep step;
  final double width;
  final int currentStepIndex;
  final int totalSteps;
  final bool isLastStep;
  final bool canSkip;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onComplete;
  final TooltipPosition tooltipPosition;

  const _TooltipContent({
    required this.step,
    required this.width,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.isLastStep,
    required this.canSkip,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
    required this.tooltipPosition,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF25C485).withAlpha(77),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(77),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤指示器
          _StepIndicator(
            currentStep: currentStepIndex + 1,
            totalSteps: totalSteps,
          ),
          const SizedBox(height: 12),
          // 标题行（带图标）
          Row(
            children: [
              if (step.icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25C485).withAlpha(38),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    step.icon,
                    color: const Color(0xFF25C485),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 描述
          Text(
            step.description,
            style: TextStyle(
              color: Colors.white.withAlpha(204),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // 导航按钮
          _NavigationButtons(
            isLastStep: isLastStep,
            canSkip: canSkip,
            onNext: onNext,
            onSkip: onSkip,
            onComplete: onComplete,
          ),
        ],
      ),
    );
  }
}

/// 步骤指示器组件
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '步骤 $currentStep / $totalSteps',
          style: TextStyle(
            color: Colors.white.withAlpha(153),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        // 进度点
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalSteps, (index) {
            final isActive = index < currentStep;
            final isCurrent = index == currentStep - 1;
            return Container(
              margin: const EdgeInsets.only(left: 4),
              width: isCurrent ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF25C485)
                    : Colors.white.withAlpha(77),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// 导航按钮组件
class _NavigationButtons extends StatelessWidget {
  final bool isLastStep;
  final bool canSkip;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onComplete;

  const _NavigationButtons({
    required this.isLastStep,
    required this.canSkip,
    required this.onNext,
    required this.onSkip,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 跳过按钮
        if (canSkip && !isLastStep)
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withAlpha(153),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('跳过'),
          ),
        const Spacer(),
        // 下一步/完成按钮
        ElevatedButton(
          onPressed: isLastStep ? onComplete : onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25C485),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          child: Text(
            isLastStep ? '完成' : '下一步',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// 显示引导覆盖层的便捷方法
/// 
/// 使用示例:
/// ```dart
/// showGuideOverlay(
///   context: context,
///   steps: [
///     GuideStep(
///       targetKey: myButtonKey,
///       title: '点击这里',
///       description: '这是一个按钮',
///     ),
///   ],
///   onComplete: () {
///     // 引导完成
///   },
/// );
/// ```
OverlayEntry? showGuideOverlay({
  required BuildContext context,
  required List<GuideStep> steps,
  required VoidCallback onComplete,
  VoidCallback? onSkip,
  bool canSkip = true,
}) {
  if (steps.isEmpty) {
    onComplete();
    return null;
  }

  OverlayEntry? overlayEntry;

  void removeOverlay() {
    overlayEntry?.remove();
    overlayEntry = null;
  }

  overlayEntry = OverlayEntry(
    builder: (context) => GuideOverlay(
      steps: steps,
      canSkip: canSkip,
      onComplete: () {
        removeOverlay();
        onComplete();
      },
      onSkip: onSkip != null
          ? () {
              removeOverlay();
              onSkip();
            }
          : () {
              removeOverlay();
              onComplete();
            },
    ),
  );

  Overlay.of(context).insert(overlayEntry!);
  return overlayEntry;
}
