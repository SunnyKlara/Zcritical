import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';

/// 蓝牙测试界面
/// 用于验证蓝牙通信功能，发送简单命令测试硬件响应
class BluetoothTestScreen extends StatefulWidget {
  const BluetoothTestScreen({super.key});

  @override
  State<BluetoothTestScreen> createState() => _BluetoothTestScreenState();
}

class _BluetoothTestScreenState extends State<BluetoothTestScreen> {
  double _fanSpeed = 0; // 当前风扇速度 (0-100)
  String _lastResponse = '等待响应...';

  @override
  void initState() {
    super.initState();
    // 注意：响应会通过 BluetoothProvider.currentSpeed 更新
  }

  /// 发送风扇速度命令
  Future<void> _sendFanSpeed(int speed) async {
    setState(() {
      _lastResponse = '正在发送命令...';
    });

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    try {
      bool success = await btProvider.setFanSpeed(speed);

      setState(() {
        if (success) {
          _lastResponse = '✅ 命令已发送: FAN:$speed';
        } else {
          _lastResponse = '❌ 发送失败';
        }
      });
    } catch (e) {
      setState(() {
        _lastResponse = '❌ 发送异常: $e';
      });
    }
  }

  /// 查询当前风扇速度
  Future<void> _queryFanSpeed() async {
    setState(() {
      _lastResponse = '正在查询...';
    });

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    try {
      bool success = await btProvider.getFanSpeed();

      setState(() {
        if (success) {
          _lastResponse = '✅ 查询命令已发送';
        } else {
          _lastResponse = '❌ 查询失败';
        }
      });
    } catch (e) {
      setState(() {
        _lastResponse = '❌ 查询异常: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, child) {
        final isConnected = btProvider.isConnected;
        final currentSpeed = btProvider.currentSpeed;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题
                  const Text(
                    '蓝牙测试',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    '验证蓝牙通信功能',
                    style: TextStyle(color: Colors.white60, fontSize: 16),
                  ),

                  const SizedBox(height: 32),

                  // 连接状态卡片
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? Colors.green.withAlpha(26)
                          : Colors.red.withAlpha(26),
                      border: Border.all(
                        color: isConnected ? Colors.green : Colors.red,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: isConnected ? Colors.green : Colors.red,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isConnected ? '已连接' : '未连接',
                                style: TextStyle(
                                  color: isConnected
                                      ? Colors.green
                                      : Colors.red,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isConnected &&
                                  btProvider.connectedDevice != null)
                                Text(
                                  btProvider.connectedDevice!.name,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 风扇速度显示
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          '风扇速度',
                          style: TextStyle(color: Colors.white70, fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_fanSpeed.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (currentSpeed != null)
                          Text(
                            '硬件反馈: $currentSpeed%',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 速度滑块
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Slider(
                          value: _fanSpeed,
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '${_fanSpeed.toInt()}%',
                          activeColor: const Color(0xFF00D68F),
                          inactiveColor: Colors.grey[700],
                          onChanged: isConnected
                              ? (value) {
                                  setState(() {
                                    _fanSpeed = value;
                                  });
                                }
                              : null,
                          onChangeEnd: isConnected
                              ? (value) {
                                  _sendFanSpeed(value.toInt());
                                }
                              : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              '0%',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '50%',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '100%',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 快捷速度按钮
                  const Text(
                    '快捷设置',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildSpeedButton('关闭', 0, isConnected),
                      _buildSpeedButton('25%', 25, isConnected),
                      _buildSpeedButton('50%', 50, isConnected),
                      _buildSpeedButton('75%', 75, isConnected),
                      _buildSpeedButton('100%', 100, isConnected),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 查询按钮
                  ElevatedButton.icon(
                    onPressed: isConnected ? _queryFanSpeed : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('查询当前速度'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 最后响应显示
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '通信日志',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _lastResponse,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // 提示信息
                  if (!isConnected)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(26),
                        border: Border.all(color: Colors.orange),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '请先连接设备后再进行测试',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建快捷速度按钮
  Widget _buildSpeedButton(String label, int speed, bool enabled) {
    bool isSelected = _fanSpeed.toInt() == speed;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: enabled
              ? () {
                  setState(() {
                    _fanSpeed = speed.toDouble();
                  });
                  _sendFanSpeed(speed);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected
                ? const Color(0xFF00D68F)
                : Colors.grey[800],
            foregroundColor: isSelected ? Colors.black : Colors.white60,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
