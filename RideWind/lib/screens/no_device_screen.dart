import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'device_scan_screen.dart';
import 'device_connect_screen.dart';
import 'device_list_screen.dart';
import '../models/device_model.dart';
import '../utils/responsive_utils.dart';
import '../services/feedback_service.dart'; // ✅ 操作反馈服务

/// 未连接设备页面（空状态）
class NoDeviceScreen extends StatelessWidget {
  const NoDeviceScreen({super.key});

  Future<void> _handleBackNavigation(BuildContext context) async {
    debugPrint('🔙 未连接页面-返回按钮被点击');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // 已经是导航栈底部，直接退出应用
      debugPrint('🚪 导航栈为空，退出应用');
      SystemNavigator.pop();
    }
  }



  /// 显示排查建议对话框
  void _showTroubleshootingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.white70, size: 24),
            SizedBox(width: 8),
            Text(
              '连接排查建议',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TroubleshootingItem(
              icon: Icons.power_settings_new,
              text: '确认设备已开机并处于配对模式',
            ),
            SizedBox(height: 12),
            _TroubleshootingItem(
              icon: Icons.bluetooth,
              text: '检查手机蓝牙是否已开启',
            ),
            SizedBox(height: 12),
            _TroubleshootingItem(
              icon: Icons.location_on,
              text: '确认已授予位置权限（蓝牙扫描需要）',
            ),
            SizedBox(height: 12),
            _TroubleshootingItem(
              icon: Icons.signal_cellular_alt,
              text: '将手机靠近设备（建议1米内）',
            ),
            SizedBox(height: 12),
            _TroubleshootingItem(
              icon: Icons.refresh,
              text: '尝试重启设备后再次扫描',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了', style: TextStyle(color: Colors.blue)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  // ========== 🏀 调试模式开关 ==========
  static const bool _debugClickAreas = false; // 已关闭调试模式

  // ========== 📍 响应式位置参数方法 ==========
  static double _getBackButtonTop(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return safeTop + (ResponsiveUtils.isSmallScreen(context) ? 8.0 : 12.0);
  }

  static double _getBackButtonLeft(BuildContext context) {
    return ResponsiveUtils.isSmallScreen(context) ? 6.0 : 8.0;
  }

  static double _getButtonSize(BuildContext context) {
    return ResponsiveUtils.isSmallScreen(context) ? 44.0 : 56.0;
  }

  static double _getUserButtonRight(BuildContext context) {
    return ResponsiveUtils.isSmallScreen(context) ? 12.0 : 16.0;
  }

  static double _getAddButtonSize(BuildContext context) {
    if (ResponsiveUtils.isSmallScreen(context)) return 150.0;
    if (ResponsiveUtils.isLargeScreen(context)) return 220.0;
    return 200.0;
  }

  static double _getTopGradientHeight(BuildContext context) {
    return ResponsiveUtils.isSmallScreen(context) ? 55.0 : 70.0;
  }

  // ========== 📍 添加按钮位置参数（黄框）==========
  static const double _addButtonCenterY = 0.55; // 屏幕中心偏下的位置（0-1）

  // ========== 🔧 开发者模式按钮位置参数 ==========
  static double _getDevButtonBottom(BuildContext context) {
    return ResponsiveUtils.safeAreaBottom(context) + 20.0;
  }

  @override
  Widget build(BuildContext context) {
    final backButtonTop = _getBackButtonTop(context);
    final backButtonLeft = _getBackButtonLeft(context);
    final buttonSize = _getButtonSize(context);
    final userButtonRight = _getUserButtonRight(context);
    final addButtonSize = _getAddButtonSize(context);
    final topGradientHeight = _getTopGradientHeight(context);
    final devButtonBottom = _getDevButtonBottom(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackNavigation(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 背景图片（未连接设计图）
            Positioned.fill(
              child: Image.asset(
                'assets/images/no_device.png',
                fit: BoxFit.cover,
              ),
            ),

            // 遮盖顶部状态栏（只遮盖状态栏部分）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topGradientHeight,
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
              top: backButtonTop,
              left: backButtonLeft,
              child: GestureDetector(
                onTap: () => _handleBackNavigation(context),
                child: Container(
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    color: _debugClickAreas
                        ? Colors.red.withAlpha(77)
                        : Colors.transparent,
                    border: _debugClickAreas
                        ? Border.all(color: Colors.red, width: 3)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _debugClickAreas
                      ? const Center(
                          child: Column(
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
                          ),
                        )
                      : null, // 默认不显示箭头，背景图自带图标
                ),
              ),
            ),

            // 用户按钮（透明点击区域 - 保留背景图位置占位）
            Positioned(
              top: backButtonTop,
              right: userButtonRight,
              child: Container(
                width: buttonSize,
                height: buttonSize,
              ),
            ),

            // 中央添加设备按钮（透明点击区域）
            Positioned(
              top:
                  MediaQuery.of(context).size.height * _addButtonCenterY -
                  addButtonSize / 2,
              left: (MediaQuery.of(context).size.width - addButtonSize) / 2,
              child: GestureDetector(
                onTap: () {
                  debugPrint('➕ 添加设备按钮被点击 → 跳转到扫描页面');
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
                  );
                },
                child: Container(
                  width: addButtonSize,
                  height: addButtonSize,
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
                              Icon(Icons.add, color: Colors.white, size: 48),
                              SizedBox(height: 4),
                              Text(
                                '添加设备',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
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

            // 🔧 开发者模式按钮（左下角）
            Positioned(
              bottom: devButtonBottom,
              left: 20,
              child: GestureDetector(
                onTap: () {
                  debugPrint('🔧 开发者模式按钮被点击 → 进入设备列表 → 控制页面');
                  // 创建一个虚拟设备用于UI调试
                  final mockDevice = DeviceModel(
                    id: 'dev-mock-001',
                    name: 'DEV Mock Device',
                    rssi: -50,
                    isConnected: true,
                  );
                  // 先 push DeviceListScreen，再 push DeviceConnectScreen
                  // 栈: [NoDevice, DeviceList, Connect]
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeviceListScreen(),
                    ),
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DeviceConnectScreen(device: mockDevice),
                    ),
                  );
                },
                child: Container(
                  width: ResponsiveUtils.isSmallScreen(context) ? 100.0 : 120.0,
                  height: ResponsiveUtils.isSmallScreen(context) ? 40.0 : 48.0,
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(200),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.orangeAccent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withAlpha(100),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.developer_mode, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'DEV',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ❓ 帮助按钮（右下角）
            Positioned(
              bottom: devButtonBottom,
              right: 20,
              child: GestureDetector(
                onTap: () => _showTroubleshootingDialog(context),
                child: Container(
                  width: ResponsiveUtils.isSmallScreen(context) ? 48.0 : 56.0,
                  height: ResponsiveUtils.isSmallScreen(context) ? 48.0 : 56.0,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: Colors.white70,
                    size: 24,
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

/// 排查建议项组件
class _TroubleshootingItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TroubleshootingItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
