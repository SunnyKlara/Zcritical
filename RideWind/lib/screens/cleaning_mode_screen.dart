import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../providers/device_provider.dart';
import 'device_list_screen.dart';

class CleaningModeScreen extends StatelessWidget {
  const CleaningModeScreen({super.key});

  Future<void> _handleBackNavigation(BuildContext context) async {
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DeviceListScreen()),
    );
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
      child: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // 顶部栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => _handleBackNavigation(context),
                ),
                Consumer<BluetoothProvider>(
                  builder: (context, bluetoothProvider, _) {
                    return Text(
                      bluetoothProvider.connectedDevice?.name ?? 'RideWind T1',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () {
                    _showDisconnectDialog(context);
                  },
                ),
              ],
            ),
            
            const Spacer(),
            
            // 设备展示区域
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[900]?.withAlpha(77),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Container(
                  width: 280,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.directions_car, color: Colors.white, size: 48),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 60),
            
            // 模式标题
            const Text(
              'Cleaning Mode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const Spacer(),
            
            // 启动气流按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('清洁气流已启动'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(0xFF00FF94),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF94),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Text(
                    '启动气流',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 120),
          ],
        ),
        ),
      ),
    );
  }

  void _showDisconnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '断开连接',
          style: TextStyle(color: Colors.white),
        ),
        content: Consumer<BluetoothProvider>(
          builder: (context, bluetoothProvider, _) {
            return Text(
              '将断开与"${bluetoothProvider.connectedDevice?.name ?? 'RideWind T1'}"的连接',
              style: const TextStyle(color: Colors.white70),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () async {
              final bluetoothProvider = Provider.of<BluetoothProvider>(
                context,
                listen: false,
              );
              final deviceProvider = Provider.of<DeviceProvider>(
                context,
                listen: false,
              );
              
              await bluetoothProvider.disconnect();
              deviceProvider.reset();
              
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const DeviceListScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('断开连接', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

