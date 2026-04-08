import 'dart:async';

import 'package:flutter/material.dart';

/// Toast 通知类型枚举
///
/// 定义了三种不同类型的 Toast 通知：
/// - [success]: 成功通知，绿色背景，勾选图标
/// - [error]: 错误通知，红色背景，错误图标，可选重试按钮
/// - [warning]: 警告通知，橙色背景，警告图标
enum ToastType {
  /// 成功通知
  success,
  /// 错误通知
  error,
  /// 警告通知
  warning,
}

/// 统一的 Toast 通知组件
///
/// 一个可复用的 Toast 通知 Widget，支持成功、错误、警告三种类型，
/// 支持自动消失和手动关闭，错误类型支持重试按钮。
///
/// 使用示例:
/// ```dart
/// // 使用静态方法显示 Toast
/// ToastNotification.success(context, '操作成功');
/// ToastNotification.error(context, '操作失败', onRetry: () => retry());
/// ToastNotification.warning(context, '请注意');
///
/// // 使用通用方法
/// ToastNotification.show(context, '消息', ToastType.success);
/// ```
///
/// **Validates: Requirements 4.2, 4.3**
class ToastNotification extends StatefulWidget {
  /// 要显示的消息文本
  final String message;

  /// Toast 类型
  final ToastType type;

  /// 显示持续时间，默认 2 秒
  final Duration duration;

  /// 关闭回调
  final VoidCallback? onDismiss;

  /// 重试回调（仅错误类型有效）
  final VoidCallback? onRetry;

  /// 是否显示关闭按钮
  final bool showCloseButton;

  /// 动画持续时间
  static const Duration _animationDuration = Duration(milliseconds: 200);

  /// 默认显示持续时间
  static const Duration _defaultDuration = Duration(seconds: 2);

  /// 有重试按钮时的延长显示时间
  static const Duration _extendedDuration = Duration(seconds: 4);

  const ToastNotification({
    super.key,
    required this.message,
    required this.type,
    this.duration = const Duration(seconds: 2),
    this.onDismiss,
    this.onRetry,
    this.showCloseButton = false,
  });

  /// 显示 Toast 通知
  ///
  /// 通用方法，可以显示任意类型的 Toast。
  ///
  /// 参数:
  /// - [context]: BuildContext，用于获取 Overlay
  /// - [message]: 要显示的消息
  /// - [type]: Toast 类型
  /// - [duration]: 可选的显示持续时间
  /// - [onDismiss]: 可选的关闭回调
  /// - [onRetry]: 可选的重试回调（仅错误类型有效）
  /// - [showCloseButton]: 是否显示关闭按钮
  ///
  /// 返回:
  /// - [OverlayEntry]: 覆盖层入口，可用于手动移除
  static OverlayEntry show(
    BuildContext context,
    String message,
    ToastType type, {
    Duration? duration,
    VoidCallback? onDismiss,
    VoidCallback? onRetry,
    bool showCloseButton = false,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    // 确定显示时间
    final effectiveDuration = duration ??
        (onRetry != null ? _extendedDuration : _defaultDuration);

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastOverlay(
        message: message,
        type: type,
        duration: effectiveDuration,
        onDismiss: () {
          overlayEntry.remove();
          onDismiss?.call();
        },
        onRetry: onRetry,
        showCloseButton: showCloseButton,
        animationDuration: _animationDuration,
      ),
    );

    overlayState.insert(overlayEntry);
    return overlayEntry;
  }

  /// 显示成功 Toast
  ///
  /// 快捷方法，显示绿色成功提示。
  ///
  /// 参数:
  /// - [context]: BuildContext
  /// - [message]: 成功消息
  /// - [duration]: 可选的显示持续时间
  /// - [onDismiss]: 可选的关闭回调
  ///
  /// 返回:
  /// - [OverlayEntry]: 覆盖层入口
  static OverlayEntry success(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) {
    return show(
      context,
      message,
      ToastType.success,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  /// 显示错误 Toast
  ///
  /// 快捷方法，显示红色错误提示，可选重试按钮。
  ///
  /// 参数:
  /// - [context]: BuildContext
  /// - [message]: 错误消息
  /// - [onRetry]: 可选的重试回调，如果提供则显示重试按钮
  /// - [duration]: 可选的显示持续时间
  /// - [onDismiss]: 可选的关闭回调
  ///
  /// 返回:
  /// - [OverlayEntry]: 覆盖层入口
  ///
  /// **Validates: Requirements 4.3**
  static OverlayEntry error(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
    Duration? duration,
    VoidCallback? onDismiss,
  }) {
    return show(
      context,
      message,
      ToastType.error,
      duration: duration,
      onDismiss: onDismiss,
      onRetry: onRetry,
    );
  }

  /// 显示警告 Toast
  ///
  /// 快捷方法，显示橙色警告提示。
  ///
  /// 参数:
  /// - [context]: BuildContext
  /// - [message]: 警告消息
  /// - [duration]: 可选的显示持续时间
  /// - [onDismiss]: 可选的关闭回调
  ///
  /// 返回:
  /// - [OverlayEntry]: 覆盖层入口
  static OverlayEntry warning(
    BuildContext context,
    String message, {
    Duration? duration,
    VoidCallback? onDismiss,
  }) {
    return show(
      context,
      message,
      ToastType.warning,
      duration: duration,
      onDismiss: onDismiss,
    );
  }

  @override
  State<ToastNotification> createState() => _ToastNotificationState();
}

class _ToastNotificationState extends State<ToastNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: ToastNotification._animationDuration,
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

    // 自动消失 - 使用 Timer 以便可以取消
    _autoDismissTimer = Timer(widget.duration, () {
      if (mounted && !_isDismissing) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    if (_isDismissing) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
    await _controller.reverse();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _ToastContent(
          message: widget.message,
          type: widget.type,
          onRetry: widget.onRetry,
          showCloseButton: widget.showCloseButton,
          onClose: _dismiss,
        ),
      ),
    );
  }
}

/// Toast 覆盖层 Widget
///
/// 用于在 Overlay 中显示 Toast 的内部组件。
class _ToastOverlay extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;
  final bool showCloseButton;
  final Duration animationDuration;

  const _ToastOverlay({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    required this.animationDuration,
    this.onRetry,
    this.showCloseButton = false,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;
  bool _isDismissing = false;

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

    // 自动消失 - 使用 Timer 以便可以取消
    _autoDismissTimer = Timer(widget.duration, () {
      if (mounted && !_isDismissing) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
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
            child: _ToastContent(
              message: widget.message,
              type: widget.type,
              onRetry: widget.onRetry,
              showCloseButton: widget.showCloseButton,
              onClose: _dismiss,
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast 内容 Widget
///
/// 显示 Toast 的实际内容，包括图标、消息、重试按钮和关闭按钮。
class _ToastContent extends StatelessWidget {
  final String message;
  final ToastType type;
  final VoidCallback? onRetry;
  final bool showCloseButton;
  final VoidCallback onClose;

  const _ToastContent({
    required this.message,
    required this.type,
    required this.onClose,
    this.onRetry,
    this.showCloseButton = false,
  });

  /// 获取 Toast 类型对应的背景颜色
  Color get _backgroundColor {
    switch (type) {
      case ToastType.success:
        return Colors.green;
      case ToastType.error:
        return Colors.red;
      case ToastType.warning:
        return Colors.orange;
    }
  }

  /// 获取 Toast 类型对应的图标
  IconData get _icon {
    switch (type) {
      case ToastType.success:
        return Icons.check_circle;
      case ToastType.error:
        return Icons.error;
      case ToastType.warning:
        return Icons.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _backgroundColor.withAlpha(230),
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
            _icon,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 重试按钮（仅错误类型且提供了回调时显示）
          if (type == ToastType.error && onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                onClose();
                onRetry?.call();
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
          // 关闭按钮
          if (showCloseButton) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onClose,
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ), // 确保触摸区域至少 44x44
            ),
          ],
        ],
      ),
    );
  }
}
