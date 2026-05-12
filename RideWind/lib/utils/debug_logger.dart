import 'package:flutter/material.dart';

/// 调试日志功能已移除，保留空壳以兼容旧调用。
class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  void log(String message) {
    // no-op
  }

  List<String> get logs => const [];

  void clear() {
    // no-op
  }

  static void show(BuildContext context) {
    // no-op
  }
}

/// 占位按钮，避免现有布局报错
class DebugFloatingButton extends StatelessWidget {
  const DebugFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

