/// 设备菜单和对话框 — 从 DeviceConnectScreen 提取
///
/// 包含：设备菜单（Logo/OTA/WiFi/Audio/Engine）、
/// 断开连接对话框、重连失败对话框、移除设备对话框。

import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/device_model.dart';
import '../../providers/bluetooth_provider.dart';
import '../logo_management_screen.dart';
import '../ota_upgrade_screen.dart';
import '../audio_stream_screen.dart';
import '../audio_management_screen.dart';
import 'wifi_provisioning_dialog.dart';

/// 显示设备菜单（Logo/OTA/WiFi/Audio/Engine/移除）
///
/// [context] — 触发菜单的 BuildContext
/// [onLogoUpload] — Logo 上传回调
/// [onOtaUpgrade] — OTA 升级回调
/// [onWifiProvisioning] — WiFi 配网回调
/// [onRemoveDevice] — 移除设备回调
void showDeviceMenu(
  BuildContext context, {
  required VoidCallback onLogoUpload,
  required VoidCallback onOtaUpgrade,
  required VoidCallback onWifiProvisioning,
  required VoidCallback onRemoveDevice,
}) {
  final parentContext = context;
  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(
      MediaQuery.of(context).size.width - 200,
      100,
      20,
      0,
    ),
    items: [
      // Logo 设置选项
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.image_outlined, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text(
              'Logo 设置',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onLogoUpload();
          });
        },
      ),
      // OTA 固件升级选项
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.system_update_outlined, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text(
              'OTA 升级',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onOtaUpgrade();
          });
        },
      ),
      // WiFi 配网选项
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.wifi_outlined, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text(
              'WiFi 配网',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        onTap: () {
          // 延迟 300ms 让 popup menu 完全关闭后再打开 dialog
          // 避免 Overlay GlobalKey 冲突
          Future.delayed(const Duration(milliseconds: 300), () {
            onWifiProvisioning();
          });
        },
      ),
      // 音频投射选项 — 仅 Android（iOS 不支持系统音频捕获）
      if (Platform.isAndroid)
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.speaker_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                '音频投射',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.push(
                parentContext,
                MaterialPageRoute(builder: (_) => const AudioStreamScreen()),
              );
            });
          },
        ),
      // 引擎音频管理选项
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.music_note_outlined, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Text(
              '引擎音效',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.push(
              parentContext,
              MaterialPageRoute(builder: (_) => const AudioManagementScreen()),
            );
          });
        },
      ),
      // 车模识别选项 — 仅 Android（TFLite + ONNX Runtime）
      if (Platform.isAndroid)
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text(
                '车模识别',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(parentContext).showSnackBar(
                const SnackBar(content: Text('车模识别功能开发中')),
              );
            });
          },
        ),
      // 移除设备选项
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red, size: 20),
            SizedBox(width: 12),
            Text('移除设备', style: TextStyle(color: Colors.red, fontSize: 16)),
          ],
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onRemoveDevice();
          });
        },
      ),
    ],
    color: Colors.grey[850],
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}

/// 显示 Logo 上传界面
///
/// [context] — BuildContext
/// [btProvider] — BluetoothProvider 实例
/// [lastSentHardwareUI] — 当前硬件 UI 值
/// [currentModeIndex] — 当前模式索引
/// [onHardwareUIChanged] — 硬件 UI 变更回调（传入新值）
void navigateToLogoUpload(
  BuildContext context, {
  required BluetoothProvider btProvider,
  required int lastSentHardwareUI,
  required int currentModeIndex,
  required ValueChanged<int> onHardwareUIChanged,
}) {
  // 同步硬件UI到Logo模式
  if (btProvider.isConnected) {
    btProvider.setHardwareUI(6);
    onHardwareUIChanged(6);
  }

  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const LogoManagementScreen()),
  ).then((_) {
    // 返回后恢复硬件UI
    if (btProvider.isConnected && lastSentHardwareUI == 6) {
      // 0=running(UI=1), 1=colorize(UI=2), 2=rgb(UI=3)
      final targetUI = currentModeIndex == 0
          ? 1
          : (currentModeIndex == 1 ? 2 : 3);
      if (targetUI != 6) {
        btProvider.setHardwareUI(targetUI);
        onHardwareUIChanged(targetUI);
      }
    }
  });
}

/// 导航到 OTA 固件升级页面（仅蓝牙已连接时允许）
void navigateToOtaUpgrade(
  BuildContext context, {
  required BluetoothProvider btProvider,
}) {
  if (!btProvider.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先连接蓝牙设备'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const OtaUpgradeScreen()),
  );
}

/// WiFi 配网对话框 — 扫描 WiFi 列表，用户选择后输入密码
void showWifiProvisioningDialog(
  BuildContext context, {
  required BluetoothProvider btProvider,
}) {
  if (!btProvider.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先连接蓝牙设备'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => WifiProvisioningDialog(btProvider: btProvider),
  );
}

/// 移除设备确认对话框
void showRemoveDeviceDialog(
  BuildContext context, {
  required DeviceModel device,
  required VoidCallback onDeviceRemoved,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: Colors.grey[850],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text(
          '移除设备',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '确定要移除设备"${device.name}"吗？',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: Colors.blue, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onDeviceRemoved();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '移除',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}

/// 蓝牙断开连接提示对话框
///
/// [onReturnToList] — 返回设备列表回调
/// [onReconnect] — 重新连接回调
void showDisconnectDialog(
  BuildContext context, {
  required VoidCallback onReturnToList,
  required VoidCallback onReconnect,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.bluetooth_disabled, color: Colors.orange, size: 24),
          SizedBox(width: 8),
          Text('设备已断开', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
      content: const Text(
        '蓝牙连接已断开，请选择操作：',
        style: TextStyle(color: Colors.white70, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onReturnToList();
          },
          child: const Text('返回设备列表', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onReconnect();
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25C485)),
          child: const Text('重新连接'),
        ),
      ],
    ),
  );
}

/// 重连失败提示对话框
///
/// [btProvider] — BluetoothProvider（用于获取 lastConnectionError）
/// [onReturnToList] — 返回设备列表回调
void showReconnectFailedDialog(
  BuildContext context, {
  required BluetoothProvider btProvider,
  required VoidCallback onReturnToList,
}) {
  final errorReason = btProvider.lastConnectionError;

  String title;
  String content;
  if (errorReason == 'device_busy') {
    title = '设备已被占用';
    content = '该设备可能已被其他手机连接，请先断开另一台手机的连接后重试。';
  } else {
    title = '连接失败';
    content = '无法重新连接到设备，请检查设备状态后重试。';
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            errorReason == 'device_busy' ? Icons.phone_android : Icons.error_outline,
            color: errorReason == 'device_busy' ? Colors.orange : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
      content: Text(
        content,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onReturnToList();
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text('返回设备列表'),
        ),
      ],
    ),
  );
}
