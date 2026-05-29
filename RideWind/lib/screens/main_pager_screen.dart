import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../services/firmware_compatibility.dart';
import 'garage_screen.dart';
import 'treadmill_dashboard_screen.dart';
import 'device_connect_screen.dart';
import 'model_3d_screen.dart';

/// 🏠 全屏 PageView 容器
///
/// 结构：[GarageScreen 0] ← [TreadmillDashboardScreen 1] ← [DeviceConnectScreen 2 默认] → [Model3DScreen 3]
///
/// 用户从 DeviceConnectScreen 往左滑进入仪表盘页面，再滑进入车库。
/// 从 DeviceConnectScreen 往右滑进入 3D 模型预览（Step 1 占位符版）。
class MainPagerScreen extends StatefulWidget {
  final DeviceModel device;

  const MainPagerScreen({super.key, required this.device});

  @override
  State<MainPagerScreen> createState() => _MainPagerScreenState();
}

class _MainPagerScreenState extends State<MainPagerScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // 默认显示 DeviceConnectScreen（index=2）
    _pageController = PageController(initialPage: 2);
    // 延迟检查固件兼容性（等连接初始化完成）
    Future.delayed(const Duration(seconds: 2), _checkFirmwareCompatibility);
  }

  void _checkFirmwareCompatibility() {
    if (!mounted) return;
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    final result = btProvider.compatibilityResult;
    if (result != null) {
      FirmwareCompatibility.showWarningIfNeeded(context, result);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView(
        controller: _pageController,
        physics: const ClampingScrollPhysics(),
        children: [
          // index=0: 车库页面
          const GarageScreen(),
          // index=1: 跑步机仪表盘页面
          const TreadmillDashboardScreen(),
          // index=2: 设备控制页面（默认）
          DeviceConnectScreen(device: widget.device),
          // index=3: 3D 模型预览（Step 1 占位符）
          const Model3DScreen(),
        ],
      ),
    );
  }
}
