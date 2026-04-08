import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 触觉反馈类型枚举
/// 
/// 定义了四种不同强度的触觉反馈类型，用于不同的交互场景：
/// - [light]: 轻微反馈，适用于轻量级交互如滑动选择
/// - [medium]: 中等反馈，适用于确认操作如切换模式
/// - [heavy]: 强烈反馈，适用于重要操作如删除确认
/// - [selection]: 选择反馈，适用于列表选择、开关切换等
enum HapticType {
  /// 轻微触觉反馈
  light,
  /// 中等触觉反馈
  medium,
  /// 强烈触觉反馈
  heavy,
  /// 选择触觉反馈
  selection,
}

/// 统一反馈服务
/// 
/// 提供触觉反馈、Toast 通知、加载状态管理等统一的用户反馈机制。
/// 所有方法都是静态的，可以直接调用而无需实例化。
/// 
/// 使用示例:
/// ```dart
/// // 触觉反馈
/// await FeedbackService.haptic(HapticType.light);
/// 
/// // 显示成功提示
/// FeedbackService.showSuccess(context, '操作成功');
/// 
/// // 显示错误提示（带重试按钮）
/// FeedbackService.showError(context, '操作失败', onRetry: () {
///   // 重试逻辑
/// });
/// 
/// // 显示加载指示器
/// final overlay = FeedbackService.showLoading(context, message: '加载中...');
/// // 操作完成后移除
/// overlay.remove();
/// ```
class FeedbackService {
  /// Toast 显示持续时间
  static const Duration _toastDuration = Duration(seconds: 2);
  
  /// Toast 动画持续时间
  static const Duration _animationDuration = Duration(milliseconds: 200);

  /// 提供触觉反馈
  /// 
  /// 根据指定的 [type] 类型提供相应强度的触觉反馈。
  /// 如果设备不支持触觉反馈或发生错误，会静默失败不影响用户操作。
  /// 
  /// 参数:
  /// - [type]: 触觉反馈类型，参见 [HapticType]
  /// 
  /// **Validates: Requirements 4.1**
  static Future<void> haptic(HapticType type) async {
    try {
      switch (type) {
        case HapticType.light:
          await HapticFeedback.lightImpact();
          break;
        case HapticType.medium:
          await HapticFeedback.mediumImpact();
          break;
        case HapticType.heavy:
          await HapticFeedback.heavyImpact();
          break;
        case HapticType.selection:
          await HapticFeedback.selectionClick();
          break;
      }
    } catch (e) {
      // 触觉反馈失败不影响用户操作，静默处理
      debugPrint('Haptic feedback failed: $e');
    }
  }

  /// 显示成功提示
  /// 
  /// 在屏幕底部显示一个绿色的成功提示 Toast，包含勾选图标和消息文本。
  /// Toast 会在 [_toastDuration] 后自动消失。
  /// 
  /// 参数:
  /// - [context]: BuildContext，用于获取 Overlay
  /// - [message]: 要显示的成功消息
  /// 
  /// **Validates: Requirements 4.2**
  static void showSuccess(BuildContext context, String message) {
    _showToast(
      context,
      message,
      Colors.green,
      Icons.check_circle,
    );
  }

  /// 显示错误提示
  /// 
  /// 在屏幕底部显示一个红色的错误提示 Toast，包含错误图标和消息文本。
  /// 如果提供了 [onRetry] 回调，会显示一个"重试"按钮。
  /// Toast 会在 [_toastDuration] 后自动消失（如果有重试按钮则延长显示时间）。
  /// 
  /// 参数:
  /// - [context]: BuildContext，用于获取 Overlay
  /// - [message]: 要显示的错误消息
  /// - [onRetry]: 可选的重试回调函数，如果提供则显示重试按钮
  /// 
  /// **Validates: Requirements 4.3**
  static void showError(BuildContext context, String message, {VoidCallback? onRetry}) {
    _showToast(
      context,
      message,
      Colors.red,
      Icons.error,
      onRetry: onRetry,
    );
  }

  /// 显示加载指示器
  /// 
  /// 在屏幕中央显示一个半透明的加载覆盖层，包含圆形进度指示器和可选的消息文本。
  /// 返回 [OverlayEntry] 对象，调用者需要在操作完成后调用 `remove()` 方法移除覆盖层。
  /// 
  /// 参数:
  /// - [context]: BuildContext，用于获取 Overlay
  /// - [message]: 可选的加载消息，显示在进度指示器下方
  /// 
  /// 返回:
  /// - [OverlayEntry]: 覆盖层入口，用于后续移除
  /// 
  /// 使用示例:
  /// ```dart
  /// final overlay = FeedbackService.showLoading(context, message: '正在连接...');
  /// try {
  ///   await someAsyncOperation();
  /// } finally {
  ///   overlay.remove();
  /// }
  /// ```
  /// 
  /// **Validates: Requirements 4.4**
  static OverlayEntry showLoading(BuildContext context, {String? message}) {
    final overlay = OverlayEntry(
      builder: (context) => _LoadingOverlay(message: message),
    );
    
    Overlay.of(context).insert(overlay);
    return overlay;
  }

  /// 内部方法：显示 Toast 通知
  /// 
  /// 创建并显示一个自定义样式的 Toast 通知。
  /// 
  /// 参数:
  /// - [context]: BuildContext
  /// - [message]: 消息文本
  /// - [backgroundColor]: 背景颜色
  /// - [icon]: 图标
  /// - [onRetry]: 可选的重试回调
  static void _showToast(
    BuildContext context,
    String message,
    Color backgroundColor,
    IconData icon, {
    VoidCallback? onRetry,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        backgroundColor: backgroundColor,
        icon: icon,
        onRetry: onRetry,
        onDismiss: () {
          overlayEntry.remove();
        },
        duration: onRetry != null 
            ? const Duration(seconds: 4) // 有重试按钮时延长显示时间
            : _toastDuration,
        animationDuration: _animationDuration,
      ),
    );
    
    overlayState.insert(overlayEntry);
  }
}

/// Toast 通知 Widget
/// 
/// 内部使用的 Toast 组件，支持自动消失和手动关闭。
class _ToastWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;
  final Duration duration;
  final Duration animationDuration;

  const _ToastWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.onDismiss,
    required this.duration,
    required this.animationDuration,
    this.onRetry,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    
    _controller.forward();
    
    // 自动消失
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.backgroundColor.withAlpha(230),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        _dismiss();
                        widget.onRetry?.call();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: const Size(44, 44), // 确保触摸区域至少 44x44
                      ),
                      child: const Text(
                        '重试',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 加载覆盖层 Widget
/// 
/// 内部使用的加载指示器组件，显示在屏幕中央。
class _LoadingOverlay extends StatelessWidget {
  final String? message;

  const _LoadingOverlay({this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withAlpha(128),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(26),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
