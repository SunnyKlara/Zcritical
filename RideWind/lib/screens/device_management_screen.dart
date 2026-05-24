import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import 'main_pager_screen.dart';
import 'device_scan_screen.dart';

/// 已保存设备的持久化信息
class SavedDeviceInfo {
  final String id;
  String customName;
  final String originalName;
  final DateTime lastConnectedAt;

  SavedDeviceInfo({
    required this.id,
    required this.customName,
    required this.originalName,
    required this.lastConnectedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'customName': customName,
        'originalName': originalName,
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
      };

  factory SavedDeviceInfo.fromJson(Map<String, dynamic> json) {
    return SavedDeviceInfo(
      id: json['id'] as String,
      customName: json['customName'] as String? ?? json['originalName'] as String,
      originalName: json['originalName'] as String,
      lastConnectedAt: DateTime.tryParse(json['lastConnectedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 设备管理页面
///
/// 功能：
/// - 已保存设备列表（显示自定义名称、连接状态、上次连接时间）
/// - 点击设备可重连
/// - 长按设备可重命名或删除
/// - 添加新设备入口
class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  static const String _storageKey = 'saved_devices_list';

  /// 添加或更新设备记录（供外部调用）
  static Future<void> recordDevice(String id, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      List<SavedDeviceInfo> devices = [];
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List;
        devices = list
            .map((e) => SavedDeviceInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      final existingIndex = devices.indexWhere((d) => d.id == id);
      if (existingIndex >= 0) {
        devices[existingIndex] = SavedDeviceInfo(
          id: id,
          customName: devices[existingIndex].customName,
          originalName: name,
          lastConnectedAt: DateTime.now(),
        );
      } else {
        devices.add(SavedDeviceInfo(
          id: id,
          customName: name,
          originalName: name,
          lastConnectedAt: DateTime.now(),
        ));
      }

      final newJsonStr = jsonEncode(devices.map((d) => d.toJson()).toList());
      await prefs.setString(_storageKey, newJsonStr);
    } catch (e) {
      debugPrint('记录设备失败: $e');
    }
  }

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  static const String _storageKey = 'saved_devices_list';

  List<SavedDeviceInfo> _savedDevices = [];
  String? _connectingDeviceId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedDevices();
  }

  Future<void> _loadSavedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List;
        _savedDevices = list
            .map((e) => SavedDeviceInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        // 按最近连接时间排序
        _savedDevices.sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      }
    } catch (e) {
      debugPrint('加载设备列表失败: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveToPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_savedDevices.map((d) => d.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('保存设备列表失败: $e');
    }
  }

  Future<void> _connectToDevice(SavedDeviceInfo deviceInfo) async {
    if (_connectingDeviceId != null) return;

    setState(() => _connectingDeviceId = deviceInfo.id);

    try {
      final btDevice = fbp.BluetoothDevice.fromId(deviceInfo.id);
      final deviceModel = DeviceModel(
        id: deviceInfo.id,
        name: deviceInfo.customName,
        rssi: -60,
        bluetoothDevice: btDevice,
      );

      final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
      final success = await btProvider.connectToDevice(deviceModel);

      if (!mounted) return;

      if (success) {
        // 更新连接时间
        deviceInfo = SavedDeviceInfo(
          id: deviceInfo.id,
          customName: deviceInfo.customName,
          originalName: deviceInfo.originalName,
          lastConnectedAt: DateTime.now(),
        );
        final idx = _savedDevices.indexWhere((d) => d.id == deviceInfo.id);
        if (idx >= 0) _savedDevices[idx] = deviceInfo;
        await _saveToPersistence();

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainPagerScreen(device: deviceModel),
          ),
        );
        return;
      } else {
        _showSnackBar('连接失败，请确认设备已开机且在范围内');
      }
    } catch (e) {
      if (mounted) _showSnackBar('连接异常: $e');
    }

    if (mounted) setState(() => _connectingDeviceId = null);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _renameDevice(SavedDeviceInfo device) async {
    final controller = TextEditingController(text: device.customName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重命名设备', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '输入设备名称',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white24),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Color(0xFF00FF94)),
              borderRadius: BorderRadius.circular(8),
            ),
            counterStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != device.customName) {
      setState(() => device.customName = newName);
      await _saveToPersistence();
    }
  }

  Future<void> _removeDevice(SavedDeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除设备', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要移除"${device.customName}"吗？\n移除后需重新扫描添加。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _savedDevices.removeWhere((d) => d.id == device.id));
      await _saveToPersistence();
    }
  }

  void _showDeviceOptions(SavedDeviceInfo device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text('重命名', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _renameDevice(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('移除设备', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _removeDevice(device);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatLastConnected(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}月${dt.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final btProvider = Provider.of<BluetoothProvider>(context);
    final connectedId = btProvider.connectedDevice?.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('设备管理'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: '添加新设备',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _savedDevices.isEmpty
              ? _buildEmptyState()
              : _buildDeviceList(connectedId),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          const Text(
            '暂无已保存的设备',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
              );
            },
            icon: const Icon(Icons.search, size: 20),
            label: const Text('扫描添加设备'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(String? connectedId) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _savedDevices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final device = _savedDevices[index];
        final isConnected = connectedId == device.id;
        final isConnecting = _connectingDeviceId == device.id;

        return _buildDeviceCard(device, isConnected, isConnecting);
      },
    );
  }

  Widget _buildDeviceCard(
    SavedDeviceInfo device,
    bool isConnected,
    bool isConnecting,
  ) {
    return GestureDetector(
      onTap: isConnecting ? null : () => _connectToDevice(device),
      onLongPress: () => _showDeviceOptions(device),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isConnected
              ? const Color(0xFF00FF94).withAlpha(20)
              : Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isConnected
                ? const Color(0xFF00FF94).withAlpha(100)
                : Colors.white10,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 设备图标 + 状态指示
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF00FF94).withAlpha(40)
                    : Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.bluetooth,
                    color: isConnected ? const Color(0xFF00FF94) : Colors.white54,
                    size: 24,
                  ),
                  // 连接状态小圆点
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected ? const Color(0xFF00FF94) : Colors.white24,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // 设备信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.customName,
                    style: TextStyle(
                      color: isConnected ? const Color(0xFF00FF94) : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnected
                        ? '已连接'
                        : '上次连接: ${_formatLastConnected(device.lastConnectedAt)}',
                    style: TextStyle(
                      color: isConnected
                          ? const Color(0xFF00FF94).withAlpha(180)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                  if (device.customName != device.originalName)
                    Text(
                      device.originalName,
                      style: const TextStyle(color: Colors.white24, fontSize: 11),
                    ),
                ],
              ),
            ),
            // 操作区域
            if (isConnecting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              )
            else if (isConnected)
              const Icon(Icons.check_circle, color: Color(0xFF00FF94), size: 24)
            else
              const Icon(Icons.chevron_right, color: Colors.white24, size: 24),
          ],
        ),
      ),
    );
  }
}
