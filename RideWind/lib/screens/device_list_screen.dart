import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../services/ble_connection_manager.dart';
import '../services/firmware_update_checker.dart';
import '../core/service_locator.dart';
import '../widgets/app_update_dialog.dart';
import 'main_pager_screen.dart';
import 'device_scan_screen.dart';
import 'device_management_screen.dart';
import 'ota_upgrade_screen.dart';
import 'settings_screen.dart';

/// 设备列表首页 — APP 栈底页面
///
/// 视觉设计：
/// - 已连接设备：顶部 Hero 大卡片（产品图 + 状态 + 进入控制）
/// - 未连接设备：下方小卡片列表
/// - 产品图替代蓝牙图标
/// - 固件升级徽章（有新版本时显示）
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

  // ========== 固件更新检测 ==========

  FirmwareUpdateStatus _firmwareUpdateStatus = FirmwareUpdateStatus.unknown;
  FirmwareUpdateDetail? _firmwareUpdateDetail;

  Future<void> _checkFirmwareUpdate() async {
    final btProvider = sl<BluetoothProvider>();
    final fwVersion = btProvider.firmwareInfo?.version;
    if (fwVersion == null) return;

    final checker = FirmwareUpdateChecker.instance;
    final status = await checker.checkForUpdate(fwVersion);
    final detail = await checker.getUpdateDetail(fwVersion);

    if (mounted) {
      setState(() {
        _firmwareUpdateStatus = status;
        _firmwareUpdateDetail = detail;
      });
    }
  }

  // ========== BLE 连接 ==========

  void _onBleStateChanged() {
    if (!mounted) return;
    if (_bleMgr.state == BleState.connected && _bleMgr.device != null) {
      DeviceManagementScreen.recordDevice(
          _bleMgr.device!.id, _bleMgr.device!.name);
      setState(() {
        _connectingDeviceId = null;
      });
      _loadSavedDevices();
      _checkFirmwareUpdate();
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

    if (success) return; // _onBleStateChanged handles navigation

    setState(() => _connectingDeviceId = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('连接失败，请确认设备已开机且在范围内'),
          backgroundColor: Colors.orange.withAlpha(200),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
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
        backgroundColor: const Color(0xFF1C1C1E),
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
            child:
                const Text('取消', style: TextStyle(color: Colors.white54)),
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

    if (newName != null &&
        newName.isNotEmpty &&
        newName != device.customName) {
      setState(() => device.customName = newName);
      await _saveToPersistence();
    }
  }

  Future<void> _removeDevice(SavedDeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('移除设备', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要移除"${device.customName}"吗？\n移除后需重新扫描添加。',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('取消', style: TextStyle(color: Colors.white54)),
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
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white70),
              title: const Text('重命名',
                  style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _renameDevice(device); },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('移除设备',
                  style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(ctx); _removeDevice(device); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ========== 固件更新弹窗 ==========

  void _showFirmwareUpdateDialog() {
    if (_firmwareUpdateDetail == null) return;
    final detail = _firmwareUpdateDetail!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF94).withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.system_update,
                  color: Color(0xFF00FF94), size: 22),
            ),
            const SizedBox(width: 12),
            const Text('固件更新可用',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersionRow('当前版本', detail.currentVersion),
            const SizedBox(height: 8),
            _buildVersionRow('最新版本', detail.latestVersion),
            const SizedBox(height: 16),
            const Text('更新内容：',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                detail.changelog,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('稍后', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToOta();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF94),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow(String label, String version) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text('v$version',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ],
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

  void _navigateToOta() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OtaUpgradeScreen()),
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
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00FF94)))
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final connectedId = _bleMgr.device?.id;
    final connectedDevice = _bleMgr.state == BleState.connected
        ? _savedDevices
            .where((d) => d.id == connectedId)
            .firstOrNull
        : null;
    final otherDevices = _savedDevices
        .where((d) => d.id != connectedId || connectedDevice == null)
        .toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(child: _buildHeader()),
          // 已连接设备 Hero 卡片
          if (connectedDevice != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _buildConnectedHeroCard(connectedDevice),
              ),
            ),
          // 其他设备标题
          if (otherDevices.isNotEmpty && connectedDevice != null)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('其他设备',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          // 其他设备列表
          if (otherDevices.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final device = otherDevices[index];
                    final isConnecting =
                        _connectingDeviceId == device.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildDeviceCard(device, isConnecting),
                    );
                  },
                  childCount: otherDevices.length,
                ),
              ),
            ),
          // 空状态
          if (_savedDevices.isEmpty)
            SliverFillRemaining(child: _buildEmptyState()),
          // 底部留白
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      child: Row(
        children: [
          const Text(
            '我的设备',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _navigateToSettings,
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white54, size: 22),
          ),
          GestureDetector(
            onTap: _navigateToScan,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF00FF94).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add,
                  color: Color(0xFF00FF94), size: 20),
            ),
          ),
        ],
      ),
    );
  }

  /// 已连接设备 — Hero 大卡片
  Widget _buildConnectedHeroCard(SavedDeviceInfo device) {
    final hasUpdate =
        _firmwareUpdateStatus == FirmwareUpdateStatus.updateAvailable;

    return GestureDetector(
      onTap: () {
        if (_bleMgr.device != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MainPagerScreen(device: _bleMgr.device!),
            ),
          );
        }
      },
      onLongPress: () => _showDeviceOptions(device),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A2A1F),
              const Color(0xFF0F1A12),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF00FF94).withAlpha(60),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00FF94).withAlpha(15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // 产品图区域
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  // 产品图
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/device_product.png',
                      width: 80, height: 50,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.devices,
                            color: Colors.white38, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 设备信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.customName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00FF94),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('已连接',
                                style: TextStyle(
                                    color: Color(0xFF00FF94),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 进入控制箭头
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF94).withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_forward_ios,
                        color: Color(0xFF00FF94), size: 16),
                  ),
                ],
              ),
            ),

            // 固件更新提示条
            if (hasUpdate) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _showFirmwareUpdateDialog,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.orange.withAlpha(60), width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.system_update,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '新固件 v${_firmwareUpdateDetail?.latestVersion ?? ""} 可用',
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Text('查看',
                          style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right,
                          color: Colors.orange, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 未连接设备 — 小卡片
  Widget _buildDeviceCard(SavedDeviceInfo device, bool isConnecting) {
    return GestureDetector(
      onTap: isConnecting ? null : () => _connectToDevice(device),
      onLongPress: () => _showDeviceOptions(device),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withAlpha(10), width: 0.5),
        ),
        child: Row(
          children: [
            // 产品缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48, height: 48,
                color: Colors.white.withAlpha(6),
                child: Image.asset(
                  'assets/images/device_product.png',
                  width: 48, height: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.devices, color: Colors.white24, size: 22),
                ),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatLastConnected(device.lastConnectedAt),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            // 连接状态/操作
            if (isConnecting)
              const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00FF94),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('连接',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ),
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 产品图作为空状态插画
          Opacity(
            opacity: 0.4,
            child: Image.asset(
              'assets/images/device_product.png',
              width: 120,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.devices, color: Colors.white24, size: 64),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '还没有设备',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '添加你的第一台 RideWind',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _navigateToScan,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00FF94), Color(0xFF00CC76)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF94).withAlpha(40),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, color: Colors.black, size: 18),
                  SizedBox(width: 8),
                  Text('扫描添加设备',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
