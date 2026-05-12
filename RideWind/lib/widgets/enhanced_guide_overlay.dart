import 'package:flutter/material.dart';
import '../models/guide_models.dart';
import 'ripple_effect_painter.dart';
import 'finger_pointer_widget.dart';
import 'gesture_validator_widget.dart';
import 'guide_overlay.dart' show HighlightMaskPainter;
import 'guide_tooltip_styles.dart';

/// 引导步骤的阶段
enum _GuidePhase {
  /// 演示阶段：系统自动操作底层 UI，手指动画同步播放，用户观看
  demonstrating,
  /// 用户上手阶段：遮罩消失，用户自由操作，底部显示"继续下一步"
  userTrying,
}

/// 增强引导覆盖层组件
///
/// 三阶段引导流程：
/// 1. 演示阶段：系统通过 demoAction 回调编程式操作底层 UI，
///    同时播放手指动画 + 提示文字，用户观看真实交互效果
/// 2. 用户上手阶段：遮罩完全消失，界面恢复正常状态，
///    用户自由探索操作，底部浮现"继续下一步"按钮
/// 3. 用户点击"继续下一步" → 推进到下一步引导
///
/// 关键设计：使用 Listener 而非 GestureDetector，不抢夺手势竞技场
class EnhancedGuideOverlay extends StatefulWidget {
  final List<GuideStep> steps;
  final VoidCallback onComplete;
  final VoidCallback? onSkip;
  final bool canSkip;
  final GuideTooltipStyle tooltipStyle;

  const EnhancedGuideOverlay({
    super.key,
    required this.steps,
    required this.onComplete,
    this.onSkip,
    this.canSkip = true,
    this.tooltipStyle = GuideTooltipStyle.glassmorphism,
  });

  @override
  State<EnhancedGuideOverlay> createState() => EnhancedGuideOverlayState();
}

@visibleForTesting
class EnhancedGuideOverlayState extends State<EnhancedGuideOverlay>
    with TickerProviderStateMixin {
  int _currentVisibleIndex = 0;
  List<GuideStep> _visibleSteps = [];
  bool _isAdvancing = false;
  _GuidePhase _phase = _GuidePhase.demonstrating;

  late AnimationController _fadeController;
  late AnimationController _fingerController;
  late AnimationController _rippleController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _fingerAnimation;

  Rect? _targetRect;
  static const double _highlightPadding = 12.0;
  static const double _tooltipWidth = 280.0;
  static const double _tooltipHeight = 80.0;
  bool _demoCancelled = false; // 用于取消正在进行的演示

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _fingerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fingerAnimation = CurvedAnimation(
      parent: _fingerController,
      curve: Curves.easeInOut,
    );

    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _filterVisibleSteps();
      if (_visibleSteps.isEmpty) {
        widget.onComplete();
        return;
      }
      await _advanceToFirstAvailableStep();
      if (!mounted) return;
      if (_visibleSteps.isEmpty || _currentVisibleIndex >= _visibleSteps.length) {
        widget.onComplete();
        return;
      }
      _updateTargetRect();
      _configureFingerAnimation();
      _fadeController.forward();
      // 开始演示
      _startDemo();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _fingerController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _filterVisibleSteps() {
    _visibleSteps = List.from(widget.steps);
  }

  /// 开始演示：调用 demoAction 回调，让底层 UI 真实操作
  /// 有 demoAction 的步骤：循环演示 3 遍，每遍之间有停顿
  /// 无 demoAction 的步骤：手指动画播放一段时间
  static const int _demoRepeatCount = 3; // 演示循环次数

  Future<void> _startDemo() async {
    final step = _currentStep;
    if (step == null) return;

    _demoCancelled = false;

    if (step.demoAction != null) {
      // 先让用户看清提示文字
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted || _demoCancelled) return;

      // 循环演示多遍
      for (int i = 0; i < _demoRepeatCount; i++) {
        await step.demoAction!();
        if (!mounted || _demoCancelled) return;
        // 每遍之间停顿，让用户消化
        if (i < _demoRepeatCount - 1) {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (!mounted || _demoCancelled) return;
        }
      }

      // 最后一遍结束后再停顿一下
      await Future.delayed(const Duration(milliseconds: 1000));
    } else {
      // 无 demoAction：手指动画播放足够长的时间
      await Future.delayed(const Duration(milliseconds: 3500));
    }
    if (!mounted || _demoCancelled) return;
    _enterUserTrying();
  }

  /// 进入用户上手阶段：遮罩消失，用户自由操作
  void _enterUserTrying() {
    if (!mounted) return;
    _fingerController.stop();
    _rippleController.forward(from: 0.0);
    setState(() => _phase = _GuidePhase.userTrying);
  }

  /// 根据手势类型配置手指动画
  void _configureFingerAnimation() {
    _fingerController.stop();
    _fingerController.reset();
    _phase = _GuidePhase.demonstrating;

    final gestureType = _currentStep?.gestureType ?? GestureType.tap;
    switch (gestureType) {
      case GestureType.tap:
        _fingerController.duration = const Duration(milliseconds: 800);
        _fingerController.repeat(reverse: true);
        break;
      case GestureType.longPress:
        _fingerController.duration = const Duration(milliseconds: 1800);
        _fingerController.repeat();
        break;
      case GestureType.swipeLeft:
      case GestureType.swipeRight:
      case GestureType.swipeUp:
      case GestureType.swipeDown:
        _fingerController.duration = const Duration(milliseconds: 1200);
        _fingerController.repeat();
        break;
      case GestureType.dragHorizontal:
      case GestureType.dragVertical:
        _fingerController.duration = const Duration(milliseconds: 1500);
        _fingerController.repeat();
        break;
    }
  }

  Future<void> _advanceToFirstAvailableStep() async {
    while (_currentVisibleIndex < _visibleSteps.length) {
      final step = _visibleSteps[_currentVisibleIndex];
      final renderBox = _getRenderBox(step);
      if (renderBox != null && renderBox.hasSize) return;
      final available = await _waitForTarget(step.targetKey);
      if (!mounted) return;
      if (available) return;
      _currentVisibleIndex++;
    }
  }

  RenderBox? _getRenderBox(GuideStep step) {
    try {
      return step.targetKey.currentContext?.findRenderObject() as RenderBox?;
    } catch (e) {
      return null;
    }
  }

  GuideStep? get _currentStep =>
      _visibleSteps.isNotEmpty && _currentVisibleIndex < _visibleSteps.length
          ? _visibleSteps[_currentVisibleIndex]
          : null;

  bool get _isLastStep => _currentVisibleIndex >= _visibleSteps.length - 1;

  void _updateTargetRect() {
    final step = _currentStep;
    if (step == null) {
      setState(() => _targetRect = null);
      return;
    }
    try {
      final renderBox = _getRenderBox(step);
      if (renderBox != null && renderBox.hasSize) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        setState(() {
          _targetRect = Rect.fromLTWH(
            position.dx, position.dy, size.width, size.height,
          );
        });
      } else {
        setState(() => _targetRect = null);
      }
    } catch (e) {
      debugPrint('Error updating target rect: $e');
      setState(() => _targetRect = null);
    }
  }

  Future<bool> _waitForTarget(GlobalKey targetKey, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(milliseconds: 2000),
  }) async {
    final maxAttempts = timeout.inMilliseconds ~/ pollInterval.inMilliseconds;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final renderBox =
          targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) return true;
      await Future.delayed(pollInterval);
      if (!mounted) return false;
    }
    return false;
  }

  /// 用户点击"继续下一步"
  void _onContinuePressed() {
    if (_isAdvancing) return;
    _nextStep();
  }

  /// 推进到下一步
  Future<void> _nextStep() async {
    if (_isAdvancing) return;
    _isAdvancing = true;
    _demoCancelled = true; // 取消当前演示

    if (_isLastStep) {
      await _complete();
      _isAdvancing = false;
      return;
    }

    await _fadeController.reverse();
    if (!mounted) return;

    int nextIndex = _currentVisibleIndex + 1;
    while (nextIndex < _visibleSteps.length) {
      final nextStep = _visibleSteps[nextIndex];
      final renderBox = _getRenderBox(nextStep);
      if (renderBox != null && renderBox.hasSize) break;
      final available = await _waitForTarget(nextStep.targetKey);
      if (!mounted) return;
      if (available) break;
      nextIndex++;
    }

    if (!mounted) return;

    if (nextIndex >= _visibleSteps.length) {
      await _complete();
      _isAdvancing = false;
      return;
    }

    setState(() {
      _currentVisibleIndex = nextIndex;
      _phase = _GuidePhase.demonstrating;
    });
    _updateTargetRect();
    _configureFingerAnimation();
    _rippleController.reset();

    if (mounted) await _fadeController.forward();
    _isAdvancing = false;

    // 开始新步骤的演示
    _startDemo();
  }

  Future<void> _complete() async {
    _demoCancelled = true;
    await _fadeController.reverse();
    if (!mounted) return;
    widget.onComplete();
  }

  Future<void> _skip() async {
    _demoCancelled = true;
    await _fadeController.reverse();
    if (!mounted) return;
    if (widget.onSkip != null) {
      widget.onSkip!();
    } else {
      widget.onComplete();
    }
  }

  /// 用户触摸屏幕时中断演示，立即进入用户上手阶段
  void _onUserTouch(PointerDownEvent event) {
    if (_phase != _GuidePhase.demonstrating) return;
    _demoCancelled = true;
    _enterUserTrying();
  }

  @override
  Widget build(BuildContext context) {
    if (_visibleSteps.isEmpty) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final currentStep = _currentStep;
    final gestureType = currentStep?.gestureType ?? GestureType.tap;
    final isDemonstrating = _phase == _GuidePhase.demonstrating;
    final isUserTrying = _phase == _GuidePhase.userTrying;

    final effectRect = _targetRect ?? Rect.fromCenter(
      center: Offset(screenSize.width / 2, screenSize.height * 0.35),
      width: 120, height: 80,
    );

    final tooltipPosition = calculateTooltipPosition(
      targetRect: effectRect,
      screenSize: screenSize,
      tooltipSize: const Size(_tooltipWidth, _tooltipHeight),
    );

    final stepIndicator =
        '${_currentVisibleIndex + 1} / ${_visibleSteps.length}';

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnimation,
        // Listener 监听用户触摸：演示阶段触摸即中断演示
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onUserTouch,
          child: Stack(
            children: [
              // ===== 演示阶段：遮罩 + 高亮 + 手指 + 提示 =====
              if (isDemonstrating) ...[
                // 半透明遮罩 + 高亮洞
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: HighlightMaskPainter(
                      targetRect: _targetRect,
                      overlayColor: Colors.black.withAlpha(100),
                      highlightPadding: _highlightPadding,
                      highlightBorderRadius: 12.0,
                    ),
                  ),
                ),
              ),

              // 手指动画
              FingerPointerWidget(
                targetRect: effectRect,
                gestureType: gestureType,
                bounceAnimation: _fingerAnimation,
                color: Colors.white,
                iconSize: 52.0,
              ),

              // 提示框
              if (currentStep != null)
                Positioned(
                  left: tooltipPosition.dx,
                  top: tooltipPosition.dy,
                  child: IgnorePointer(
                    child: _buildNormalTooltip(currentStep, stepIndicator),
                  ),
                ),

              // 跳过按钮（演示阶段，非最后一步）
              if (widget.canSkip && !_isLastStep)
                Positioned(
                  right: 24,
                  bottom: MediaQuery.of(context).padding.bottom + 20,
                  child: GestureDetector(
                    onTap: _skip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '跳过引导',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            // ===== 用户上手阶段：无遮罩，只有顶部浮动按钮栏 =====
            // 完全不遮挡底层 UI，用户体验和正常使用一模一样
            if (isUserTrying)
              Positioned(
                left: 16,
                right: 16,
                top: safeTop + 90,
                child: _buildUserTryingBar(),
              ),
          ],
          ),
        ),
      ),
    );
  }

  /// 正常提示框
  Widget _buildNormalTooltip(GuideStep step, String stepIndicator) {
    return KeyedSubtree(
      key: const ValueKey('normal'),
      child: widget.tooltipStyle == GuideTooltipStyle.glassmorphism
          ? GlassmorphismTooltip(
              text: step.description, stepIndicator: stepIndicator)
          : GlowBorderTooltip(
              text: step.description, stepIndicator: stepIndicator),
    );
  }

  /// 用户上手阶段的浮动操作栏
  /// 放在屏幕顶部安全区域下方，不和底部 UI 冲突
  Widget _buildUserTryingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // 提示文字
          Expanded(
            child: Text(
              '试试看，自由操作体验一下',
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 跳过引导
          if (widget.canSkip)
            GestureDetector(
              onTap: _skip,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6,
                ),
                child: Text(
                  '跳过',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          if (widget.canSkip) const SizedBox(width: 8),
          // 继续下一步 / 完成引导
          GestureDetector(
            onTap: _onContinuePressed,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 9,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF25C485), Color(0xFF1DA06B)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isLastStep ? '完成' : '下一步',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 计算提示框位置（纯函数）
Offset calculateTooltipPosition({
  required Rect targetRect,
  required Size screenSize,
  required Size tooltipSize,
  double padding = 16.0,
  double minSpacing = 80.0,
}) {
  final double tooltipWidth = tooltipSize.width;
  final double tooltipHeight = tooltipSize.height;

  double top;
  final bool targetInUpperHalf =
      targetRect.center.dy <= screenSize.height / 2;

  if (targetInUpperHalf) {
    top = targetRect.bottom + minSpacing;
  } else {
    top = targetRect.top - minSpacing - tooltipHeight;
  }

  double left = targetRect.center.dx - tooltipWidth / 2;

  left = left.clamp(padding, screenSize.width - tooltipWidth - padding);
  top = top.clamp(padding, screenSize.height - tooltipHeight - padding);

  return Offset(left, top);
}

/// 显示增强引导覆盖层
OverlayEntry? showEnhancedGuideOverlay({
  required BuildContext context,
  required List<GuideStep> steps,
  required VoidCallback onComplete,
  VoidCallback? onSkip,
  bool canSkip = true,
  GuideTooltipStyle tooltipStyle = GuideTooltipStyle.glassmorphism,
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
    builder: (context) => EnhancedGuideOverlay(
      steps: steps,
      canSkip: canSkip,
      tooltipStyle: tooltipStyle,
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
