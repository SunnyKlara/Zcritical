import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../models/device_model.dart';
import '../utils/responsive_utils.dart';
import 'device_connect_screen.dart';
import 'no_device_screen.dart';

class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  Future<void> _handleBackNavigation(BuildContext context) async {
    debugPrint('🔙 设备列表-返回按钮被点击 → 返回上一页');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // 栈底兜底：直接回到 NoDeviceScreen
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NoDeviceScreen()),
      );
    }
  }

  // ========== 🏀 调试模式开关（设备列表页面）==========
  static const bool _debugClickAreas = false; // 调试模式已关闭

  // ========== 📍 响应式位置参数方法 ==========
  // 所有位置参数改为动态计算，根据屏幕尺寸自适应

  /// 获取返回/用户按钮的顶部位置
  static double _getTopButtonTop(BuildContext context) {
    return ResponsiveUtils.height(context, 7); // 屏幕高度的7%
  }

  /// 获取返回按钮的左边距
  static double _getBackButtonLeft(BuildContext context) {
    return ResponsiveUtils.width(context, 2); // 屏幕宽度的2%
  }

  /// 获取用户按钮的右边距
  static double _getUserButtonRight(BuildContext context) {
    return ResponsiveUtils.width(context, 4); // 屏幕宽度的4%
  }

  /// 获取按钮尺寸（确保最小触摸目标）
  static double _getButtonSize(BuildContext context) {
    return ResponsiveUtils.scaledSize(context, 56.0).clamp(48.0, 64.0);
  }

  /// 获取设备卡片顶部位置
  static double _getDeviceCardTop(BuildContext context) {
    return ResponsiveUtils.height(context, 20); // 屏幕高度的20%（从25%上移）
  }

  /// 获取设备卡片左右边距
  static double _getDeviceCardHorizontalMargin(BuildContext context) {
    return ResponsiveUtils.horizontalPadding(context) * 2; // 标准水平padding的2倍
  }

  /// 获取设备卡片高度
  static double _getDeviceCardHeight(BuildContext context) {
    return ResponsiveUtils.scaledHeight(context, 140.0).clamp(120.0, 160.0);
  }

  /// 获取添加按钮底部位置
  static double _getAddButtonBottom(BuildContext context) {
    return ResponsiveUtils.height(context, 15); // 屏幕高度的15%
  }

  /// 获取添加按钮右边距
  static double _getAddButtonRight(BuildContext context) {
    return ResponsiveUtils.width(context, 10); // 屏幕宽度的10%
  }

  /// 获取添加按钮尺寸
  static double _getAddButtonSize(BuildContext context) {
    return ResponsiveUtils.scaledSize(context, 64.0).clamp(56.0, 72.0);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackNavigation(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<BluetoothProvider>(
          builder: (context, bluetoothProvider, _) {
            final device = bluetoothProvider.devices.isNotEmpty
                ? bluetoothProvider.devices.first
                : null;
            final isConnected =
                bluetoothProvider.connectedDevice?.id == device?.id;

            return Stack(
              children: [
                // 背景图片（根据连接状态动态切换）
                Positioned.fill(
                  child: Image.asset(
                    isConnected
                        ? 'assets/images/device_list_connected_active.png' // 已连接：带绿色圆点
                        : 'assets/images/device_list_connected.png', // 未连接：带"连接"文字
                    fit: BoxFit.cover,
                  ),
                ),

                // 遮盖顶部状态栏（只遮盖状态栏部分）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: ResponsiveUtils.isSmallScreen(context) ? 55.0 : 70.0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black,
                          Colors.black,
                          Colors.black.withAlpha(200),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.4, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),

                // 返回按钮（透明点击区域）
                Positioned(
                  top: _getTopButtonTop(context),
                  left: _getBackButtonLeft(context),
                  child: GestureDetector(
                    onTap: () => _handleBackNavigation(context),
                    child: Container(
                      width: _getButtonSize(context),
                      height: _getButtonSize(context),
                      decoration: BoxDecoration(
                        color: _debugClickAreas
                            ? Colors.red.withAlpha(77)
                            : Colors.transparent,
                        border: _debugClickAreas
                            ? Border.all(color: Colors.red, width: 3)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: _debugClickAreas
                            ? const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '返回',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : null, // 不显示箭头，因为背景图已经有了
                      ),
                    ),
                  ),
                ),

                // 用户按钮区域（已移除用户中心功能）
                Positioned(
                  top: _getTopButtonTop(context),
                  right: _getUserButtonRight(context),
                  child: Container(
                    width: _getButtonSize(context),
                    height: _getButtonSize(context),
                  ),
                ),

                // 设备卡片点击区域（绿框）
                Positioned(
                  top: _getDeviceCardTop(context),
                  left: _getDeviceCardHorizontalMargin(context),
                  right: _getDeviceCardHorizontalMargin(context),
                  child: Consumer<BluetoothProvider>(
                    builder: (context, bluetoothProvider, _) {
                      final device = bluetoothProvider.devices.isNotEmpty
                          ? bluetoothProvider.devices.first
                          : null;
                      // 判断是否已连接：检查设备列表中的设备或直接检查 connectedDevice
                      final isConnected = bluetoothProvider.connectedDevice != null &&
                          (device == null || bluetoothProvider.connectedDevice?.id == device.id);

                      return GestureDetector(
                        // 点击：仅在已连接时跳转到主控制页面
                        onTap: () {
                          if (!isConnected) {
                            // 🔴 未连接状态，点击无效，显示提示
                            debugPrint('🔴 设备未连接，点击无效');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('设备未连接，请先扫描并连接设备'),
                                backgroundColor: Colors.red.withAlpha(200),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          // 🟢 已连接状态，跳转到主控制页面
                          final targetDevice = device 
                              ?? bluetoothProvider.connectedDevice!;
                          debugPrint('🟢 设备卡片被点击 → 跳转到主控制页面: ${targetDevice.name}');
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeviceConnectScreen(device: targetDevice),
                            ),
                          );
                        },
                        // 长按：显示断开连接对话框（仅已连接时）
                        onLongPress: () {
                          final targetDevice = device ?? bluetoothProvider.connectedDevice;
                          if (targetDevice == null || !isConnected) return;
                          debugPrint('🔒 设备卡片被长按 → 显示断开连接对话框');
                          _showDisconnectDialog(
                            context,
                            targetDevice,
                            bluetoothProvider,
                          );
                        },
                        child: Container(
                          height: _getDeviceCardHeight(context),
                          decoration: BoxDecoration(
                            color: _debugClickAreas
                                ? Colors.green.withAlpha(77)
                                : Colors.transparent,
                            border: _debugClickAreas
                                ? Border.all(color: Colors.green, width: 3)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _debugClickAreas
                              ? Center(
                                  child: Text(
                                    isConnected
                                        ? '【设备卡片】🟢 已连接\n点击进入控制页面'
                                        : '【设备卡片】未连接\n点击无效',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),

                // 添加按钮（透明点击区域）
                Positioned(
                  bottom: _getAddButtonBottom(context),
                  right: _getAddButtonRight(context),
                  child: GestureDetector(
                    onTap: () {
                      debugPrint('➕ 添加设备按钮被点击');
                      // TODO: 跳转到扫描页面
                    },
                    child: Container(
                      width: _getAddButtonSize(context),
                      height: _getAddButtonSize(context),
                      decoration: BoxDecoration(
                        color: _debugClickAreas
                            ? Colors.yellow.withAlpha(77)
                            : Colors.transparent,
                        border: _debugClickAreas
                            ? Border.all(color: Colors.yellow, width: 3)
                            : null,
                        shape: BoxShape.circle,
                      ),
                      child: _debugClickAreas
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  Text(
                                    '添加',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 显示断开连接确认对话框
  static void _showDisconnectDialog(
    BuildContext context,
    DeviceModel device,
    BluetoothProvider bluetoothProvider,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Align(
          alignment: Alignment.bottomCenter, // 对话框显示在底部
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: 40.0,
              left: 24.0,
              right: 24.0,
            ),
            child: Material(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题
                    const Text(
                      '断开连接',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 提示信息
                    Text(
                      '将断开与"${device.name}"的连接',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 断开连接按钮
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () async {
                          debugPrint('🔌 断开连接按钮被点击');
                          await bluetoothProvider.disconnect();
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          '断开连接',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 取消按钮
                    TextButton(
                      onPressed: () {
                        debugPrint('❌ 取消断开连接');
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
