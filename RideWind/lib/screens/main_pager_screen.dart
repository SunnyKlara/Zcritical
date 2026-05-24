import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../services/firmware_compatibility.dart';
import 'garage_screen.dart';
import 'device_connect_screen.dart';

/// 🏠 全屏 PageView 容器
///
/// 结构：[GarageScreen (index=0)] ← [DeviceConnectScreen (index=1, 默认)]
///
/// 用户从 DeviceConnectScreen 往左滑（即向 index=0 方向），
/// 整个屏幕切换到车库页面。
///
/// 不修改 DeviceConnectScreen 内部任何代码。
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
    // 默认显示 DeviceConnectScreen（index=1）
    _pageController = PageController(initialPage: 1);
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
          // index=1: 设备控制页面（默认）
          DeviceConnectScreen(device: widget.device),
        ],
      ),
    );
  }
}
