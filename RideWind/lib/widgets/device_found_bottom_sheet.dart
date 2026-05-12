import 'package:flutter/material.dart';
import '../models/device_model.dart';

/// 设备发现弹窗（从底部滑出的丝滑设计）
/// 
/// 使用方式：
/// ```dart
/// showDeviceFoundBottomSheet(
///   context: context,
///   device: device,
///   onConnect: () { ... },
/// );
/// ```
class DeviceFoundBottomSheet extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback onConnect;
  final String? deviceImagePath; // 可选：自定义设备图片路径

  const DeviceFoundBottomSheet({
    super.key,
    required this.device,
    required this.onConnect,
    this.deviceImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomSheetHeight = screenHeight * 0.75; // 占屏幕高度的75%

    return Container(
      height: bottomSheetHeight,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          // 顶部拖动指示器
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(77),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              '发现以下可用设备',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),

          const Spacer(flex: 1),

          // 设备卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: _buildDeviceCard(context),
          ),

          const Spacer(flex: 1),

          // 连接按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 关闭弹窗
                  onConnect(); // 执行连接回调
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9A3),
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: const Color(0xFF00D9A3).withAlpha(100),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: const Text(
                  '连接设备',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  /// 构建设备卡片
  Widget _buildDeviceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00D9A3).withAlpha(100),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9A3).withAlpha(50),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 设备图片
          if (deviceImagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                deviceImagePath!,
                height: 180,
                fit: BoxFit.cover,
              ),
            )
          else
            // 默认设备图标
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(
                  Icons.bluetooth_audio,
                  size: 80,
                  color: Color(0xFF00D9A3),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // 设备名称
          Text(
            device.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 8),

          // 设备信息（信号强度）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF00D9A3).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.signal_cellular_alt,
                  size: 16,
                  color: Color(0xFF00D9A3),
                ),
                const SizedBox(width: 6),
                Text(
                  '信号强度: ${device.rssi}dBm',
                  style: const TextStyle(
                    color: Color(0xFF00D9A3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 显示设备发现弹窗的便捷方法
Future<void> showDeviceFoundBottomSheet({
  required BuildContext context,
  required DeviceModel device,
  required VoidCallback onConnect,
  String? deviceImagePath,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true, // 允许自定义高度
    isDismissible: true, // 点击外部可关闭
    enableDrag: true, // 允许拖动关闭
    builder: (context) => DeviceFoundBottomSheet(
      device: device,
      onConnect: onConnect,
      deviceImagePath: deviceImagePath,
    ),
  );
}
