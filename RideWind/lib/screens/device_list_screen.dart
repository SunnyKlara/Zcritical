import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/ble_connection_manager.dart';
import '../core/service_locator.dart';
import '../widgets/app_update_dialog.dart';
import 'main_pager_screen.dart';
import 'device_scan_screen.dart';
import 'device_management_screen.dart';
import 'settings_screen.dart';

/// 设备列表首页 — APP 栈底页面
///
/// 功能：
/// - 显示已保存设备列表（卡片式）
/// - 自动连接最近使用的设备
/// - 点击设备卡片连接并进入控制页面
/// - 长按设备卡片弹出操作菜单（重命名/删除）
/// - "+" 按钮进入扫描页面添加新设备
/// - 返回键退出 APP
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen>
    with WidgetsBindingObserver {
  static const String _storageKey = 'saved_devices_list';

  late final BleConnectionManager _bleMgr;
  List<SavedDeviceInfo> _savedDevices = [];
  String? _connectingDeviceId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleMgr = sl<BleConnectionManager>();
    _bleMgr.addListener(_onBleStateChanged);
    _loadSavedDevices();
    Future.delayed(const Duration(seconds: 2), _checkAppUpdate);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleMgr.removeListener(_onBleStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时刷新设备列表（可能在扫描页添加了新设备）
      _loadSavedDevices();
    }
  }

  Future<void> _checkAppUpdate() async {
    if (!mounted) return;
    AppUpdateDialog.checkAndShow(context);
  }

  // ========== 数据加载 ==========

  Future<void> _loadSavedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List;
        _savedDevices = list
            .map((e) => SavedDeviceInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        _savedDevices
            .sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));
      }
    } catch (e) {
      debugPrint('加载设备列表失败: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  // ========== BLE 连接 ==========

  void _onBleStateChanged() {
    if (!mounted) return;
    if (_bleMgr.state == BleState.connected && _bleMgr.device != null) {
      // 连接成功 → 记录设备并进入控制页面
      DeviceManagementScreen.recordDevice(
          _bleMgr.device!.id, _bleMgr.device!.name);
      setState(() {
        _connectingDeviceId = null;
      });
      // 刷新列表后 push 控制页面
      _loadSavedDevices();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MainPagerScreen(device: _bleMgr.device!),
        ),
      );
      return;
    }
    if (_bleMgr.state == BleState.idle || _bleMgr.state == BleState.failed) {
      setState(() {
        _connectingDeviceId = null;
      });
    }
  }

  Future<void> _connectToDevice(SavedDeviceInfo deviceInfo) async {
    if (_connectingDeviceId != null) return;

    setState(() => _connectingDeviceId = deviceInfo.id);

    final btDevice = fbp.BluetoothDevice.fromId(deviceInfo.id);
    final deviceModel = DeviceModel(
      id: deviceInfo.id,
      name: deviceInfo.customName,
      rssi: -60,
      bluetoothDevice: btDevice,
    );

    final success = await _bleMgr.connectToDevice(deviceModel);
    if (!mounted) return;

    if (success) {
      // _onBleStateChanged 会处理导航
      return;
    }

    // 连接失败
    setState(() => _connectingDeviceId = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('连接失败，请确认设备已开机且在范围内'),
          backgroundColor: Colors.orange.withAlpha(200),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ========== 设备管理操作 ==========

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
              title:
                  const Text('重命名', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _renameDevice(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('移除设备', style: TextStyle(color: Colors.red)),
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

  // ========== 导航 ==========

  void _navigateToScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  // ========== 工具方法 ==========

  String _formatLastConnected(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}月${dt.day}日';
  }

  // ========== Build ==========

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          // 栈底，退出 APP
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: _savedDevices.isEmpty
                ? _buildEmptyState()
                : _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          const Text(
            '我的设备',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 设置按钮
          IconButton(
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white70, size: 24),
            tooltip: '设置',
          ),
          // 添加设备按钮
          IconButton(
            onPressed: _navigateToScan,
            icon: const Icon(Icons.add_circle_outline,
                color: Color(0xFF00FF94), size: 28),
            tooltip: '添加设备',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.devices, color: Colors.white24, size: 64),
          const SizedBox(height: 16),
          const Text(
            '暂无已保存的设备',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _navigateToScan,
            icon: const Icon(Icons.search, size: 20),
            label: const Text('扫描添加设备'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    final connectedId = _bleMgr.device?.id;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _savedDevices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final device = _savedDevices[index];
        final isConnected =
            _bleMgr.state == BleState.connected && connectedId == device.id;
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
      onTap: isConnecting
          ? null
          : () {
              if (isConnected && _bleMgr.device != null) {
                // 已连接，直接进入控制页面
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MainPagerScreen(device: _bleMgr.device!),
                  ),
                );
              } else {
                // 未连接，发起连接
                _connectToDevice(device);
              }
            },
      onLongPress: () => _showDeviceOptions(device),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isConnected
              ? const Color(0xFF00FF94).withAlpha(20)
              : const Color(0xFF1A1A1A),
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
                    color: isConnected
                        ? const Color(0xFF00FF94)
                        : Colors.white54,
                    size: 24,
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? const Color(0xFF00FF94)
                            : Colors.white24,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
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
                      color: isConnected
                          ? const Color(0xFF00FF94)
                          : Colors.white,
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
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 11),
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
              const Icon(Icons.check_circle,
                  color: Color(0xFF00FF94), size: 24)
            else
              const Icon(Icons.chevron_right,
                  color: Colors.white24, size: 24),
          ],
        ),
      ),
    );
  }

}
