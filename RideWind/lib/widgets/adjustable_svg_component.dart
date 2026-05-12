import 'package:flutter/material.dart';

/// 可调整位置的SVG组件模板
/// 
/// 使用方法：
/// 1. 继承此类或参考此模式创建组件
/// 2. 在组件类中定义位置参数（static const double）
/// 3. 在主页面中调整参数直到对齐设计图
class AdjustableSvgComponent extends StatelessWidget {
  final bool debugMode;
  final double top;
  final double? bottom;
  final double? left;
  final double? right;
  final double width;
  final double height;
  final Widget child;
  final Color debugColor;
  final String debugLabel;

  const AdjustableSvgComponent({
    super.key,
    this.debugMode = true,
    required this.top,
    this.bottom,
    this.left,
    this.right,
    required this.width,
    required this.height,
    required this.child,
    this.debugColor = Colors.green,
    this.debugLabel = '组件',
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: width,
        height: height,
        // 调试模式：显示边框和标签
        decoration: debugMode
            ? BoxDecoration(
                border: Border.all(color: debugColor, width: 2),
                color: debugColor.withAlpha(26),
              )
            : null,
        child: Stack(
          children: [
            // 实际组件内容
            child,
            
            // 调试标签（左上角）
            if (debugMode)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: debugColor.withAlpha(204),
                  child: Text(
                    debugLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            
            // 调试信息（右下角）
            if (debugMode)
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  color: Colors.black54,
                  child: Text(
                    'W:${width.toInt()} H:${height.toInt()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 使用示例：
/// 
/// class MyCustomButton extends StatelessWidget {
///   // ========== 📍 位置参数 ==========
///   static const double buttonTop = 500.0;    // 往上移 = 减小数值
///   static const double buttonLeft = 40.0;    // 往右移 = 增大数值
///   static const double buttonWidth = 280.0;  // 按钮宽度
///   static const double buttonHeight = 68.0;  // 按钮高度
///   
///   final bool debugMode;
///   
///   const MyCustomButton({super.key, this.debugMode = true});
///   
///   @override
///   Widget build(BuildContext context) {
///     return AdjustableSvgComponent(
///       debugMode: debugMode,
///       top: buttonTop,
///       left: buttonLeft,
///       width: buttonWidth,
///       height: buttonHeight,
///       debugColor: Colors.green,
///       debugLabel: '启动按钮',
///       child: GestureDetector(
///         onTap: () {
///           print('按钮被点击');
///         },
///         child: Container(
///           decoration: BoxDecoration(
///             gradient: LinearGradient(
///               colors: [Color(0xFF25C485), Color(0xFF28FAA6)],
///             ),
///             borderRadius: BorderRadius.circular(34),
///           ),
///           child: Center(
///             child: Text('启动气流', style: TextStyle(color: Colors.white)),
///           ),
///         ),
///       ),
///     );
///   }
/// }

