import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../protocol/error_messages.dart';
import '../services/audio_stream_service.dart';

/// 音频投射页面
///
/// 扫描 WiFi → 选择 → 输入密码 → ESP32 连接 → 开始投射
/// 需求: 5.3, 5.5, 5.6, 5.7, 12.1, 12.2, 12.3
class AudioStreamScreen extends StatefulWidget {
  const AudioStreamScreen({super.key});

  @override
  State<AudioStreamScreen> createState() => _AudioStreamScreenState();
}

class _WifiAp {
  final String ssid;
  final int rssi;
  final bool needsPassword;
  _WifiAp(this.ssid, this.rssi, this.needsPassword);
}

class _AudioStreamScreenState extends State<AudioStreamScreen> {
  bool _isStreaming = false;
  String _status = '点击扫描开始';
  bool _loading = false;
  String? _esp32Ip;
  final _passController = TextEditingController();
  List<StreamSubscription> _subscriptions = [];
  List<_WifiAp> _wifiList = [];
  bool _scanning = false;
  _WifiAp? _selectedAp;

  // Android 10+ (API 29) 支持检查
  bool _platformSupported = true;
  bool _platformChecked = false;

  // 已保存的 WiFi 凭据
  Map<String, String>? _savedCredentials;

  @override
  void initState() {
    super.initState();
    _checkPlatformSupport();
    _loadSavedCredentials();
    _listenBle();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _passController.dispose();
    super.dispose();
  }

  /// 检查平台支持 — 仅 Android 10+ (API 29) 支持音频投射 (需求 5.7)
  Future<void> _checkPlatformSupport() async {
    if (!Platform.isAndroid) {
      setState(() {
        _platformSupported = false;
        _platformChecked = true;
        _status = '仅支持 Android 平台';
      });
      return;
    }

    // 检查是否已在投射
    final active = await AudioStreamService.isCapturing();
    if (active) {
      setState(() {
        _isStreaming = true;
        _status = '正在投射音频';
      });
    }

    setState(() => _platformChecked = true);
  }

  /// 加载已保存的 WiFi 凭据 (需求 11.2)
  Future<void> _loadSavedCredentials() async {
    final creds = await AudioStreamService.loadWifiCredentials();
    if (mounted) {
      setState(() => _savedCredentials = creds);
    }
  }

  /// 监听 BLE 数据流 — WiFi IP / WiFi 错误 / 音频就绪 / WIFI_SCAN:USE_PHONE
  void _listenBle() {
    final bt = Provider.of<BluetoothProvider>(context, listen: false);

    // 监听 WiFi IP (需求 5.2)
    _subscriptions.add(bt.wifiIpStream.listen((ip) {
      if (!mounted) return;
      setState(() {
        _esp32Ip = ip;
        _status = 'ESP32 已连接 WiFi，IP: $ip';
        _loading = false;
      });
    }));

    // 监听 WiFi 错误 (需求 5.4)
    _subscriptions.add(bt.wifiErrorStream.listen((reason) {
      if (!mounted) return;
      final msg = DeviceErrorMessages.getWifiErrorMessage('WIFI_ERR:$reason');
      setState(() {
        _status = msg;
        _loading = false;
      });
    }));

    // 监听音频就绪
    _subscriptions.add(bt.audioReadyStream.listen((data) {
      if (!mounted) return;
      setState(() => _status = '音频服务就绪');
    }));

    // 监听原始数据流处理 WIFI_SCAN:USE_PHONE (需求 12.3)
    _subscriptions.add(bt.rawDataStream.listen((data) {
      if (!mounted) return;
      for (final line in data.split('\n')) {
        final msg = line.trim();
        if (msg == 'WIFI_SCAN:USE_PHONE') {
          // ESP32 不执行扫描，由手机端完成
          _scanWifi();
        }
      }
    }));
  }

  /// 扫描 WiFi 网络 (需求 5.5, 12.1, 12.2)
  Future<void> _scanWifi() async {
    setState(() {
      _scanning = true;
      _wifiList.clear();
      _status = '正在扫描 WiFi...';
    });

    try {
      final results = await AudioStreamService.scanWifi();
      setState(() {
        _wifiList = results.map((r) => _WifiAp(
          r['ssid'] as String,
          r['rssi'] as int,
          r['secure'] as bool,
        )).toList();
        _scanning = false;
        _status = '找到 ${_wifiList.length} 个 WiFi';
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _status = '扫描失败: $e';
      });
    }
  }

  /// 连接 WiFi — 如果需要密码则弹出对话框，否则直接连接
  Future<void> _connectWifi(_WifiAp ap) async {
    if (ap.needsPassword) {
      _selectedAp = ap;
      _passController.clear();

      // 已保存的 WiFi 自动填充密码 (需求 11.2)
      if (_savedCredentials != null && _savedCredentials!['ssid'] == ap.ssid) {
        _passController.text = _savedCredentials!['password'] ?? '';
      }

      _showPasswordDialog(ap);
    } else {
      _doConnect(ap.ssid, '');
    }
  }

  bool _showPassword = false;

  void _showPasswordDialog(_WifiAp ap) {
    _showPassword = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(ap.ssid, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: _passController,
            obscureText: !_showPassword,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '输入 WiFi 密码',
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue)),
              suffixIcon: IconButton(
                icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white54,
                    size: 20),
                onPressed: () =>
                    setDialogState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消',
                    style: TextStyle(color: Colors.white54))),
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _doConnect(ap.ssid, _passController.text);
                },
                child:
                    const Text('连接', style: TextStyle(color: Colors.blue))),
          ],
        ),
      ),
    );
  }

  /// 发送 WiFi 凭据给 ESP32 (需求 5.1)
  Future<void> _doConnect(String ssid, String password) async {
    final bt = Provider.of<BluetoothProvider>(context, listen: false);
    setState(() {
      _loading = true;
      _status = '正在连接 "$ssid"...';
    });

    // 使用 BluetoothProvider 的 sendWifiCredentials 方法
    await bt.sendWifiCredentials(ssid, password);

    // 保存 WiFi 凭据 (需求 11.1)
    await AudioStreamService.saveWifiCredentials(ssid, password);
    _savedCredentials = {'ssid': ssid, 'password': password};
  }

  /// 开始音频投射 (需求 5.3)
  Future<void> _startStream() async {
    if (_esp32Ip == null) {
      _showSnack('请先连接 WiFi');
      return;
    }
    setState(() => _loading = true);
    try {
      final ok = await AudioStreamService.startCapture(ip: _esp32Ip!);
      setState(() {
        _isStreaming = ok;
        _status = ok ? '正在投射音频 ♪' : '权限被拒绝';
      });
    } on UnsupportedError {
      // Android < 10 (需求 5.7)
      setState(() {
        _platformSupported = false;
        _status = '音频投射需要 Android 10 或更高版本';
      });
    } catch (e) {
      _showSnack('$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 停止音频投射 (需求 5.6)
  Future<void> _stopStream() async {
    await AudioStreamService.stopCapture();
    setState(() {
      _isStreaming = false;
      _status = '已停止';
    });
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _rssiIcon(int rssi) {
    IconData icon;
    Color color;
    if (rssi > -50) {
      icon = Icons.wifi;
      color = Colors.green;
    } else if (rssi > -70) {
      icon = Icons.wifi;
      color = Colors.orange;
    } else {
      icon = Icons.wifi_1_bar;
      color = Colors.red;
    }
    return Icon(icon, color: color, size: 20);
  }

  /// 构建不支持平台的提示 (需求 5.7)
  Widget _buildUnsupportedMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              '音频投射需要 Android 10 或更高版本',
              style: TextStyle(color: Colors.white54, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '当前设备不支持此功能',
              style: TextStyle(color: Colors.white.withAlpha(60), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建 WiFi 列表 (需求 5.5, 12.2)
  Widget _buildWifiList() {
    if (_wifiList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_find, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('点击右上角刷新按钮扫描 WiFi',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _wifiList.length,
      itemBuilder: (ctx, i) {
        final ap = _wifiList[i];
        final isSaved =
            _savedCredentials != null && _savedCredentials!['ssid'] == ap.ssid;
        return ListTile(
          leading: _rssiIcon(ap.rssi),
          title: Row(
            children: [
              Expanded(
                child: Text(ap.ssid,
                    style: const TextStyle(color: Colors.white)),
              ),
              if (isSaved)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('已保存',
                      style: TextStyle(color: Colors.blue, fontSize: 10)),
                ),
            ],
          ),
          subtitle: Text(
              '${ap.rssi} dBm${ap.needsPassword ? " 🔒" : ""}',
              style:
                  const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.blue))
              : null,
          onTap: _loading ? null : () => _connectWifi(ap),
        );
      },
    );
  }

  /// 构建投射状态指示器和控制按钮 (需求 5.6)
  Widget _buildStreamingControls() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 投射状态指示器 (需求 5.6)
            Icon(
              _isStreaming ? Icons.speaker : Icons.speaker_outlined,
              size: 80,
              color: _isStreaming ? Colors.green : Colors.blue,
            ),
            const SizedBox(height: 24),

            // 开始/停止投射按钮 (需求 5.6)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_isStreaming ? _stopStream : _startStream),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isStreaming ? Colors.red : Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                child: Text(
                    _isStreaming ? '停止投射' : '开始投射',
                    style: const TextStyle(
                        fontSize: 17,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Text('设备 IP: $_esp32Ip',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 13)),

            // 断开 WiFi 连接按钮
            const SizedBox(height: 12),
            if (!_isStreaming)
              TextButton(
                onPressed: () {
                  setState(() {
                    _esp32Ip = null;
                    _status = '已断开 WiFi';
                  });
                },
                child: const Text('返回 WiFi 列表',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title:
            const Text('音频投射', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 扫描按钮 — 仅在 WiFi 列表阶段显示
          if (_platformSupported && !_isStreaming && _esp32Ip == null)
            IconButton(
              icon: _scanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _scanning ? null : _scanWifi,
            ),
        ],
      ),
      body: !_platformChecked
          ? const Center(
              child:
                  CircularProgressIndicator(color: Colors.white))
          : !_platformSupported
              ? _buildUnsupportedMessage()
              : Column(
                  children: [
                    // 状态栏
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      color: _isStreaming
                          ? Colors.green.withAlpha(40)
                          : Colors.white.withAlpha(10),
                      child: Text(_status,
                          style: TextStyle(
                              color: _isStreaming
                                  ? Colors.green
                                  : Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center),
                    ),

                    // WiFi 列表 (Step 1) — 需求 5.5, 12.2
                    if (!_isStreaming && _esp32Ip == null)
                      Expanded(child: _buildWifiList()),

                    // 已连接 — 投射控制 (Step 2) — 需求 5.6
                    if (_esp32Ip != null)
                      Expanded(child: _buildStreamingControls()),
                  ],
                ),
    );
  }
}
