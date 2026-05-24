/// WiFi 配网对话框 — 自动识别手机当前 WiFi，用户只需输入密码
///
/// 设计参考：小米/涂鸦智能家居配网模式
///
/// 流程：
///   1. 自动读取手机当前连接的 WiFi SSID + 频率
///   2. 如果是 5GHz → 显示警告（ESP32 仅支持 2.4GHz）
///   3. 显示 SSID（不可编辑），用户只输密码
///   4. 发送 WIFI:ssid:pass → ESP32 回复 OK:WIFI → BLE 断开（预期）
///   5. 等待 BLE 重连 → 收到 WIFI_IP:x.x.x.x 表示成功

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../providers/bluetooth_provider.dart';
import '../../services/audio_stream_service.dart';

class WifiProvisioningDialog extends StatefulWidget {
  final BluetoothProvider btProvider;
  const WifiProvisioningDialog({super.key, required this.btProvider});

  @override
  State<WifiProvisioningDialog> createState() => _WifiProvisioningDialogState();
}

class _WifiProvisioningDialogState extends State<WifiProvisioningDialog> {
  String? _ssid;
  int? _frequency;
  bool _loading = true;
  bool _connecting = false;
  bool _manualSsidInput = false; // iOS: 手动输入 SSID
  String? _statusMessage;
  final _passwordController = TextEditingController();
  final _ssidController = TextEditingController(); // iOS: SSID 输入框
  bool _showPassword = false;
  StreamSubscription? _ipSub;
  StreamSubscription? _errSub;

  bool get _is5GHz => (_frequency ?? 0) > 3000;

  @override
  void initState() {
    super.initState();
    _loadCurrentWifi();

    // Listen for WiFi IP (success) — may come after BLE reconnects
    _ipSub = widget.btProvider.wifiIpStream.listen((ip) {
      if (!mounted) return;
      widget.btProvider.clearWifiProvisioningFlag();
      setState(() {
        _connecting = false;
        _statusMessage = '✅ WiFi 已连接\nIP: $ip';
      });
    });

    // Listen for WiFi error
    _errSub = widget.btProvider.wifiErrorStream.listen((err) {
      if (!mounted) return;
      widget.btProvider.clearWifiProvisioningFlag();
      setState(() {
        _connecting = false;
        _statusMessage = '❌ 连接失败: $err';
      });
    });
  }

  @override
  void dispose() {
    _ipSub?.cancel();
    _errSub?.cancel();
    _passwordController.dispose();
    _ssidController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentWifi() async {
    try {
      // iOS 上 getConnectedWifi 使用 Android 平台通道，会抛出 MissingPluginException
      // 此时允许用户手动输入 SSID
      if (Platform.isIOS) {
        setState(() {
          _ssid = null;
          _loading = false;
          _manualSsidInput = true;
        });
        return;
      }
      final info = await AudioStreamService.getConnectedWifi();
      if (!mounted) return;
      if (info != null) {
        setState(() {
          _ssid = info['ssid'] as String?;
          _frequency = info['frequency'] as int?;
          _loading = false;
        });
      } else {
        setState(() {
          _ssid = null;
          _loading = false;
          _statusMessage = '⚠️ 手机未连接 WiFi\n请先连接 2.4GHz WiFi 网络';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // iOS 或其他平台通道不可用时，允许手动输入
        _manualSsidInput = true;
      });
    }
  }

  void _doConnect() {
    // iOS 手动输入模式：从 _ssidController 获取 SSID
    if (_manualSsidInput) {
      _ssid = _ssidController.text.trim();
    }
    if (_ssid == null || _ssid!.isEmpty) {
      setState(() => _statusMessage = '⚠️ 请输入 WiFi 名称');
      return;
    }
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _statusMessage = '⚠️ 请输入密码');
      return;
    }

    setState(() {
      _connecting = true;
      _statusMessage = '正在发送凭据...\n设备将断开蓝牙以连接 WiFi';
    });

    widget.btProvider.sendWifiCredentials(_ssid!, password);

    // Save credentials locally for future use
    AudioStreamService.saveWifiCredentials(_ssid!, password);

    // Timeout: if no response after 20s (BLE disconnect + reconnect + WiFi connect)
    Future.delayed(const Duration(seconds: 20), () {
      if (!mounted) return;
      if (_connecting) {
        setState(() {
          _connecting = false;
          _statusMessage = '⏱️ 等待超时\n\n可能原因：\n• WiFi 密码错误\n• 设备距离路由器太远\n\n请重试或检查密码';
        });
        widget.btProvider.clearWifiProvisioningFlag();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Row(
        children: [
          const Icon(Icons.wifi, color: Colors.blue, size: 24),
          const SizedBox(width: 10),
          const Text('WiFi 配网', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(color: Colors.blue)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 5GHz warning
                    if (_is5GHz) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '当前连接的是 5GHz 网络\nESP32 仅支持 2.4GHz，请切换网络',
                                style: TextStyle(color: Colors.orange[200], fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // SSID display (read-only) 或手动输入 (iOS)
                    if (_manualSsidInput) ...[
                      Text(
                        '请输入 WiFi 名称（仅支持 2.4GHz）',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ssidController,
                        enabled: !_connecting,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'WiFi 名称 (SSID)',
                          labelStyle: TextStyle(color: Colors.white54),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white12),
                          ),
                          prefixIcon: Icon(Icons.wifi, color: Colors.blue, size: 20),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Password input for manual mode
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        enabled: !_connecting,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'WiFi 密码',
                          labelStyle: const TextStyle(color: Colors.white54),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue),
                          ),
                          disabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword ? Icons.visibility : Icons.visibility_off,
                              color: Colors.white54,
                            ),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_connecting) _doConnect();
                        },
                      ),
                    ] else if (_ssid != null && _ssid!.isNotEmpty) ...[
                      Text(
                        '将设备连接到',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _is5GHz ? Icons.signal_wifi_statusbar_connected_no_internet_4 : Icons.wifi,
                              color: _is5GHz ? Colors.orange : Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _ssid!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (_frequency != null)
                              Text(
                                _is5GHz ? '5GHz' : '2.4GHz',
                                style: TextStyle(
                                  color: _is5GHz ? Colors.orange : Colors.green,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password input
                      TextField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        enabled: !_connecting,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'WiFi 密码',
                          labelStyle: const TextStyle(color: Colors.white54),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.blue),
                          ),
                          disabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white12),
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword ? Icons.visibility : Icons.visibility_off,
                              color: Colors.white54,
                            ),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_connecting && !_is5GHz) _doConnect();
                        },
                      ),
                    ],

                    // Status message
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _statusMessage!.startsWith('✅')
                              ? Colors.green.withOpacity(0.1)
                              : _statusMessage!.startsWith('❌') || _statusMessage!.startsWith('⚠️')
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_connecting)
                              const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                              )
                            else
                              Icon(
                                _statusMessage!.startsWith('✅')
                                    ? Icons.check_circle
                                    : _statusMessage!.startsWith('❌')
                                        ? Icons.error
                                        : Icons.info_outline,
                                color: _statusMessage!.startsWith('✅')
                                    ? Colors.green
                                    : _statusMessage!.startsWith('❌')
                                        ? Colors.red
                                        : Colors.blue,
                                size: 18,
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  color: _statusMessage!.startsWith('✅')
                                      ? Colors.green[200]
                                      : _statusMessage!.startsWith('❌') || _statusMessage!.startsWith('⚠️')
                                          ? Colors.red[200]
                                          : Colors.blue[200],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_connecting) {
              // Cancel provisioning — clear flag
              widget.btProvider.clearWifiProvisioningFlag();
            }
            Navigator.of(context).pop();
          },
          child: Text(
            _statusMessage != null && _statusMessage!.startsWith('✅') ? '完成' : '关闭',
            style: TextStyle(
              color: _statusMessage != null && _statusMessage!.startsWith('✅')
                  ? Colors.green
                  : Colors.white54,
            ),
          ),
        ),
        if ((_manualSsidInput || (_ssid != null && _ssid!.isNotEmpty)) && !_connecting && !(_statusMessage?.startsWith('✅') ?? false))
          ElevatedButton(
            onPressed: _is5GHz ? null : _doConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[800],
            ),
            child: const Text('连接'),
          ),
      ],
    );
  }
}
