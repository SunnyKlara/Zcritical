import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sound_wave_scanner.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../utils/debug_logger.dart'; // 🆕 调试日志
import 'device_connect_screen.dart';
import 'device_list_screen.dart';
import 'no_device_screen.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen>
    with TickerProviderStateMixin {
  bool _showDialog = false;
  bool _isConnecting = false;
  DeviceModel? _foundDevice;
  String _statusText = '扫描中...';

  late AnimationController _slideController;
  late AnimationController _blurController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();

    // 初始化滑动动画控制器（弹窗从下方滑入）
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, 1), // 从下方开始
          end: Offset.zero, // 滑到正常位置
        ).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    // 初始化模糊动画控制器（背景先模糊，再淡入淡出至纯黑）
    _blurController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // 延长动画时间，更自然
    );

    _blurAnimation =
        Tween<double>(
          begin: 0.0, // 清晰
          end: 1.0, // 完全消失
        ).animate(
          CurvedAnimation(parent: _blurController, curve: Curves.easeInOut),
        );

    // 延迟启动蓝牙扫描，避免在 build 期间调用 notifyListeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanning();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _blurController.dispose();
    super.dispose();
  }

  /// 真实的蓝牙扫描流程
  Future<void> _startScanning() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    final logger = DebugLogger();

    try {
      // 扫描期间只显示声波动画，状态文字保持"扫描中..."
      setState(() {
        _statusText = '扫描中...';
      });

      logger.log('🔍 开始蓝牙扫描...');
      
      // 记录开始时间
      final startTime = DateTime.now();

      // 开始扫描（4秒）
      await btProvider.startScan();
      logger.log('📡 扫描完成，找到 ${btProvider.devices.length} 个设备');

      // 确保至少显示4秒的扫描动画
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed.inSeconds < 4) {
        await Future.delayed(Duration(seconds: 4 - elapsed.inSeconds));
      }

      // 检查是否找到设备
      if (btProvider.devices.isEmpty) {
        logger.log('❌ 未找到兼容的蓝牙设备');
        // 未找到设备，返回到 NoDeviceScreen（pop 回到已有的 NoDeviceScreen）
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }

      // 找到设备，自动连接第一个设备
      _foundDevice = btProvider.devices.first;
      logger.log('✅ 发现设备: ${_foundDevice!.name}');
      logger.log('🔗 开始连接设备...');
      
      setState(() {
        _isConnecting = true;
      });

      // 尝试连接
      bool connected = await btProvider.connectToDevice(_foundDevice!);

      if (!connected) {
        logger.log('❌ 连接失败！');
        // 连接失败，返回到 NoDeviceScreen
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      
      logger.log('🎉 连接成功！');

      // 连接成功，显示设备弹窗
      if (mounted) {
        setState(() {
          _showDialog = true;
          _isConnecting = false;
        });

        // 触发弹窗动画
        _slideController.forward();
        _blurController.forward();
      }
    } catch (e) {
      logger.log('❌ 异常: $e');
      debugPrint('扫描或连接失败: $e');
      // 出错返回到 NoDeviceScreen
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔧 添加try-catch防止渲染错误导致黑屏
    try {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 🔧 后备背景层（防止所有内容都透明时显示黑屏）
            Container(
              color: const Color(0xFF0D0D0D),
              child: const Center(
                child: Text(
                  '正在加载...',
                  style: TextStyle(color: Colors.white30, fontSize: 14),
                ),
              ),
            ),
            
            // 扫描界面（始终显示，作为背景）
            AnimatedBuilder(
              animation: _blurAnimation,
              builder: (context, child) {
                // 🔧 修复：只有在显示弹窗时才淡出扫描界面
                if (!_showDialog) {
                  // 未显示弹窗时，扫描界面保持完全可见
                  return child ?? const SizedBox.shrink();
                }
                
                // 分阶段处理：0-0.4模糊，0.4-1.0淡出
                final blurPhase = (_blurAnimation.value * 2.5).clamp(0.0, 1.0);
                final fadePhase = ((_blurAnimation.value - 0.4) * 1.67).clamp(
                  0.0,
                  1.0,
                );

                return ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurPhase * 15,
                    sigmaY: blurPhase * 15,
                  ),
                  child: Opacity(
                    opacity: 1.0 - fadePhase,
                    child: child,
                  ),
                );
              },
              child: _buildScanningUI(),
            ),

            // 发现设备弹窗（从下方滑入，叠加在扫描界面上）
            if (_showDialog)
              SlideTransition(
                position: _slideAnimation,
                child: _buildDeviceFoundDialog(),
              ),
            
            // 🆕 调试按钮（右下角）
            const DebugFloatingButton(),
          ],
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ DeviceScanScreen build 错误: $e');
      debugPrint('📍 堆栈: $stackTrace');
      // 🔧 错误时显示错误信息而不是黑屏
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  '扫描界面加载失败',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  '$e',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// 扫描中的UI（声波动画）
  Widget _buildScanningUI() {
    return Container(
      color: Colors.black, // 🔧 添加黑色背景，防止底层"正在加载"文字透出
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题 - 显示实时状态
              Text(
                _statusText,
                style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 8),

            // 提示文本
            Text(
              _isConnecting ? '正在建立连接，请稍候...' : '请确保您的设备处于配对模式',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),

            const Spacer(),

            // 声波扫描动画
            const Center(
              child: SoundWaveScanner(
                isScanning: true,
                width: 280,
                height: 200,
              ),
            ),

            const Spacer(),

            // 底部按钮
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {},
                    child: const Text(
                      '没有扫描到设备?',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      debugPrint('✅ 跳过扫描按钮被点击 → 返回添加设备页面');
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '跳过扫描',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
      ), // 🔧 闭合 Container
    );
  }

  /// 发现设备弹窗（从下方滑入，使用产品图+代码实现）
  Widget _buildDeviceFoundDialog() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题
                const Text(
                  '设备已连接',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                // 显示设备名称和信号强度
                if (_foundDevice != null) ...[
                  Text(
                    _foundDevice!.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '信号强度: ${_foundDevice!.rssi} dBm',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],

                const SizedBox(height: 32),

                // 设备卡片
                Image.asset(
                  'assets/images/device_product.png',
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('❌ 图片加载失败: $error');
                    return Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(51),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.bluetooth_connected,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // 进入控制界面按钮
                Center(
                  child: SizedBox(
                    width: 320,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () {
                        // 先替换 ScanScreen 为 DeviceListScreen，再 push DeviceConnectScreen
                        // 栈变为: [NoDevice, DeviceList, Connect]
                        // 回退: Connect → DeviceList → NoDevice → 退出
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const DeviceListScreen(),
                          ),
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DeviceConnectScreen(device: _foundDevice!),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D68F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(29),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '进入控制界面',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
