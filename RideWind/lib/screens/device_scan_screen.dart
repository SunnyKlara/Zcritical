import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sound_wave_scanner.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import 'device_list_screen.dart';
import 'device_management_screen.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen>
    with TickerProviderStateMixin {
  bool _showDialog = false;
  bool _isError = false; // 未找到 / 连接失败 / 扫描异常
  DeviceModel? _foundDevice;
  String _statusText = '扫描中...';
  String _hintText = '请确保您的设备处于配对模式';

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

  /// 调试日志（仅打印到控制台，不再展示在 UI）
  void _log(String msg) {
    final ts = DateTime.now().toString().substring(11, 19);
    debugPrint('🐛 [$ts] $msg');
  }

  /// 真实的蓝牙扫描流程（带详细日志）
  Future<void> _startScanning() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    try {
      setState(() {
        _statusText = '扫描中...';
        _hintText = '请确保您的设备处于配对模式';
        _isError = false;
      });

      // 1. 检查蓝牙支持
      final supported = await FlutterBluePlus.isSupported;
      _log('蓝牙支持: $supported');
      if (!supported) {
        _log('❌ 设备不支持蓝牙');
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 2. 检查蓝牙状态
      final adapterState = await FlutterBluePlus.adapterState.first;
      _log('蓝牙状态: $adapterState');
      if (adapterState != BluetoothAdapterState.on) {
        _log('❌ 蓝牙未开启');
        if (mounted) Navigator.of(context).pop();
        return;
      }

      // 3. 开始扫描
      _log('开始扫描 (过滤 FFE0)...');
      final startTime = DateTime.now();

      await btProvider.startScan();

      final elapsed = DateTime.now().difference(startTime);
      _log('扫描耗时: ${elapsed.inMilliseconds}ms');
      _log('发现设备数: ${btProvider.devices.length}');

      // 列出所有发现的设备
      for (var d in btProvider.devices) {
        _log('  📱 ${d.name} (${d.id}) RSSI:${d.rssi}');
      }

      // 确保至少显示4秒的扫描动画
      final totalElapsed = DateTime.now().difference(startTime);
      if (totalElapsed.inSeconds < 4) {
        await Future.delayed(Duration(seconds: 4 - totalElapsed.inSeconds));
      }

      // 5. 检查结果
      if (btProvider.devices.isEmpty) {
        _log('❌ 未找到 FFE0 设备');
        setState(() {
          _statusText = '未找到设备';
          _hintText = '请确保您的设备处于配对模式';
          _isError = true;
        });
        return;
      }

      // 6. 自动连接第一个设备
      _foundDevice = btProvider.devices.first;
      _log('✅ 发现设备: ${_foundDevice!.name}');
      _log('🔗 开始连接...');

      setState(() {
        _statusText = '连接中...';
        _hintText = '正在建立连接，请稍候...';
      });

      bool connected = await btProvider.connectToDevice(_foundDevice!);
      _log('连接结果: ${connected ? "成功" : "失败"}');

      if (!connected) {
        _log('❌ 连接失败');
        // 检查是否是设备被其他手机占用
        final errorReason = btProvider.lastConnectionError;
        if (errorReason == 'device_busy') {
          setState(() {
            _statusText = '设备已被占用';
            _hintText = '该设备可能已被其他手机连接，请先断开另一台手机的连接';
            _isError = true;
          });
        } else {
          setState(() {
            _statusText = '连接失败';
            _hintText = '请重试或检查设备';
            _isError = true;
          });
        }
        return;
      }

      _log('🎉 连接成功！');

      if (mounted) {
        setState(() {
          _showDialog = true;
        });
        _slideController.forward();
        _blurController.forward();
      }
    } catch (e, stack) {
      _log('❌ 异常: $e');
      _log('堆栈: ${stack.toString().split('\n').take(3).join(' | ')}');
      setState(() {
        _statusText = '扫描异常';
        _hintText = '请重试';
        _isError = true;
      });
    }
  }

  /// 显示连接排查建议对话框
  void _showTroubleshootingDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.white70, size: 24),
            SizedBox(width: 8),
            Text('连接排查建议',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TipRow(icon: Icons.power_settings_new, text: '确认设备已开机并处于配对模式'),
            SizedBox(height: 12),
            _TipRow(icon: Icons.bluetooth, text: '检查手机蓝牙是否已开启'),
            SizedBox(height: 12),
            _TipRow(icon: Icons.location_on, text: '确认已授予位置权限（蓝牙扫描需要）'),
            SizedBox(height: 12),
            _TipRow(icon: Icons.signal_cellular_alt, text: '将手机靠近设备（建议1米内）'),
            SizedBox(height: 12),
            _TipRow(icon: Icons.refresh, text: '尝试重启设备后再次扫描'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
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
            Container(color: const Color(0xFF0D0D0D)),
            
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

            // 提示文本（随状态切换文案）
            Text(
              _hintText,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),

            const Spacer(),

            // 声波扫描动画（错误态降低不透明度作为视觉淡化）
            Center(
              child: Opacity(
                opacity: _isError ? 0.35 : 1.0,
                child: SoundWaveScanner(
                  isScanning: !_isError,
                  width: 280,
                  height: 200,
                ),
              ),
            ),

            const Spacer(),

            // 排查建议链接（仅错误态显示）
            if (_isError)
              Center(
                child: GestureDetector(
                  onTap: _showTroubleshootingDialog,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '没有扫描到设备?',
                      style: TextStyle(
                        color: Color(0xFF4DA6FF),
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF4DA6FF),
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            // 底部唯一按钮（宽长条：取消 / 重试）
            GestureDetector(
              onTap: () {
                if (_isError) {
                  _startScanning();
                } else {
                  debugPrint('✅ 取消扫描 → 返回上一页');
                  Navigator.of(context).pop();
                }
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 统一设计：白底黑字主按钮风格
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withAlpha(40),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  _isError ? '重试' : '取消',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
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
                        // 记录设备到设备管理列表
                        DeviceManagementScreen.recordDevice(
                          _foundDevice!.id,
                          _foundDevice!.name,
                        );
                        // 替换 ScanScreen 为 DeviceListScreen（新栈底）
                        // DeviceListScreen 会检测到已连接设备并自动 push 控制页面
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                const DeviceListScreen(),
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

/// 排查建议条目（图标 + 文字）
class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }
}
