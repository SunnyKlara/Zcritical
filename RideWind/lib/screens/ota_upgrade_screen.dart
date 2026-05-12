import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../services/ota_upload_service.dart';
import '../services/firmware_update_service.dart';

/// OTA 固件升级页面
class OtaUpgradeScreen extends StatefulWidget {
  const OtaUpgradeScreen({super.key});

  @override
  State<OtaUpgradeScreen> createState() => _OtaUpgradeScreenState();
}

class _OtaUpgradeScreenState extends State<OtaUpgradeScreen> {
  late BluetoothProvider _btProvider;
  late OtaUploadService _otaService;

  String _firmwareVersion = '查询中...';
  OtaState _otaState = OtaState.idle;
  double _progress = 0.0;
  String _errorMessage = '';
  String _logText = '';

  // 远程升级相关状态
  FirmwareInfo? _latestFirmware;
  bool _isCheckingUpdate = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  StreamSubscription? _versionSub;

  @override
  void initState() {
    super.initState();
    _btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    _otaService = OtaUploadService(_btProvider);
    _setupOtaCallbacks();
    _queryFirmwareVersion();
  }

  @override
  void dispose() {
    _versionSub?.cancel();
    super.dispose();
  }

  void _setupOtaCallbacks() {
    _otaService.onStateChanged = (state) {
      if (mounted) setState(() => _otaState = state);
    };
    _otaService.onProgress = (p) {
      if (mounted) setState(() => _progress = p);
    };
    _otaService.onError = (msg) {
      if (mounted) setState(() => _errorMessage = msg);
    };
    _otaService.onSuccess = () {
      // state already set via onStateChanged
    };
    _otaService.onLog = (msg) {
      if (mounted) {
        setState(() {
          _logText += '$msg\n';
        });
      }
    };
  }

  /// 查询固件版本号
  void _queryFirmwareVersion() {
    _versionSub?.cancel();
    _versionSub = _btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      if (trimmed.startsWith('OTA_VERSION:')) {
        final version = trimmed.substring('OTA_VERSION:'.length);
        if (mounted) {
          setState(() => _firmwareVersion = version);
        }
        _versionSub?.cancel();
      }
    });

    _btProvider.sendCommand('OTA_VERSION');

    // 超时处理
    Future.delayed(const Duration(seconds: 3), () {
      if (_firmwareVersion == '查询中...' && mounted) {
        setState(() => _firmwareVersion = '未知');
        _versionSub?.cancel();
      }
    });
  }

  /// 本地升级
  Future<void> _startLocalUpgrade() async {
    try {
      final firmwareData = await OtaUploadService.pickLocalFirmware();
      if (firmwareData == null) return; // 用户取消
      await _otaService.upload(firmwareData);
    } catch (e) {
      if (mounted) {
        setState(() {
          _otaState = OtaState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 远程升级：检查更新 → 下载固件 → 蓝牙传输
  Future<void> _startRemoteUpgrade() async {
    // 1. 检查更新
    setState(() {
      _isCheckingUpdate = true;
      _errorMessage = '';
    });

    try {
      final currentVer = _firmwareVersion;
      if (currentVer == '查询中...' || currentVer == '未知') {
        setState(() {
          _isCheckingUpdate = false;
          _errorMessage = '请先等待设备版本查询完成';
        });
        return;
      }

      final info = await FirmwareUpdateService.checkForUpdate(currentVer);
      setState(() => _isCheckingUpdate = false);

      if (info == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('当前已是最新版本'),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF00FF94),
            ),
          );
        }
        return;
      }

      // 2. 弹窗确认
      setState(() => _latestFirmware = info);
      final confirmed = await _showUpdateDialog(info);
      if (confirmed != true) return;

      // 3. 下载固件
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });

      final firmwareData = await OtaUploadService.downloadRemoteFirmware(
        info,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );

      setState(() => _isDownloading = false);

      if (firmwareData == null) {
        setState(() => _errorMessage = '固件下载失败');
        return;
      }

      // 4. 蓝牙传输（复用现有 upload 流程）
      await _otaService.upload(firmwareData);
    } catch (e) {
      setState(() {
        _isCheckingUpdate = false;
        _isDownloading = false;
        _otaState = OtaState.error;
        _errorMessage = e.toString();
      });
    }
  }

  /// 显示更新确认弹窗
  Future<bool?> _showUpdateDialog(FirmwareInfo info) {
    final sizeKB = (info.size / 1024).toStringAsFixed(1);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('发现新固件', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '新版本: v${info.version}',
              style: const TextStyle(color: Color(0xFF00C8FF), fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '文件大小: $sizeKB KB',
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            if (info.changelog != null && info.changelog!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新内容:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 4),
              Text(
                info.changelog!,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C8FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('立即升级'),
          ),
        ],
      ),
    );
  }

  /// 取消升级
  void _cancelUpgrade() {
    _otaService.cancel();
  }

  /// 重试
  void _retry() {
    setState(() {
      _otaState = OtaState.idle;
      _progress = 0.0;
      _errorMessage = '';
      _logText = '';
    });
  }

  /// 获取状态文本
  String _getStateText() {
    if (_isCheckingUpdate) return '检查更新中...';
    if (_isDownloading) return '下载固件中...';
    switch (_otaState) {
      case OtaState.idle:
        return '就绪';
      case OtaState.preparing:
        return '准备中...';
      case OtaState.erasing:
        return '擦除中...';
      case OtaState.uploading:
        return '传输中...';
      case OtaState.verifying:
        return '校验中...';
      case OtaState.rebooting:
        return '重启中...';
      case OtaState.complete:
        return '升级完成';
      case OtaState.error:
        return '升级失败';
    }
  }

  /// 获取状态图标
  IconData _getStateIcon() {
    switch (_otaState) {
      case OtaState.idle:
        return Icons.system_update;
      case OtaState.preparing:
      case OtaState.erasing:
        return Icons.hourglass_top;
      case OtaState.uploading:
        return Icons.upload;
      case OtaState.verifying:
        return Icons.verified_user;
      case OtaState.rebooting:
        return Icons.restart_alt;
      case OtaState.complete:
        return Icons.check_circle;
      case OtaState.error:
        return Icons.error;
    }
  }

  /// 获取状态颜色
  Color _getStateColor() {
    switch (_otaState) {
      case OtaState.idle:
        return Colors.white70;
      case OtaState.preparing:
      case OtaState.erasing:
        return Colors.amber;
      case OtaState.uploading:
        return const Color(0xFF00C8FF);
      case OtaState.verifying:
        return Colors.orange;
      case OtaState.rebooting:
        return Colors.purple;
      case OtaState.complete:
        return const Color(0xFF00FF94);
      case OtaState.error:
        return Colors.red;
    }
  }

  bool get _isInProgress =>
      _isCheckingUpdate ||
      _isDownloading ||
      _otaState == OtaState.preparing ||
      _otaState == OtaState.erasing ||
      _otaState == OtaState.uploading ||
      _otaState == OtaState.verifying ||
      _otaState == OtaState.rebooting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('固件升级'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // 固件版本信息
              _buildVersionCard(),
              const SizedBox(height: 24),
              // 状态区域
              _buildStatusSection(),
              const SizedBox(height: 24),
              // 下载进度（downloading 时显示）
              if (_isDownloading) _buildDownloadProgressSection(),
              // 进度条（uploading 时显示）
              if (_otaState == OtaState.uploading) _buildProgressSection(),
              // 成功提示
              if (_otaState == OtaState.complete) _buildSuccessSection(),
              // 错误提示
              if (_otaState == OtaState.error) _buildErrorSection(),
              const Spacer(),
              // 操作按钮
              _buildActionButtons(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.memory, color: Colors.white70, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前固件版本',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'v$_firmwareVersion',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () {
              setState(() => _firmwareVersion = '查询中...');
              _queryFirmwareVersion();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    final color = _getStateColor();
    return Row(
      children: [
        Icon(_getStateIcon(), color: color, size: 24),
        const SizedBox(width: 10),
        Text(
          _getStateText(),
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildProgressSection() {
    final percent = (_progress * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 10,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C8FF)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '蓝牙传输 $percent%',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadProgressSection() {
    final percent = (_downloadProgress * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _downloadProgress,
            minHeight: 10,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '下载固件 $percent%',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00FF94).withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00FF94).withAlpha(77)),
      ),
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF00FF94), size: 48),
          SizedBox(height: 12),
          Text(
            '固件升级成功！',
            style: TextStyle(
              color: Color(0xFF00FF94),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '设备正在重启，请等待约 10 秒后重新连接蓝牙。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withAlpha(77)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          const Text(
            '升级失败',
            style: TextStyle(
              color: Colors.red,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    // 升级进行中：显示取消按钮
    if (_isInProgress) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: _cancelUpgrade,
          icon: const Icon(Icons.cancel, size: 20),
          label: const Text('取消升级', style: TextStyle(fontSize: 16)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
      );
    }

    // 错误状态：显示重试按钮
    if (_otaState == OtaState.error) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('重试', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
      );
    }

    // 完成状态：显示返回按钮
    if (_otaState == OtaState.complete) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, size: 20),
          label: const Text('返回', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FF94),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
      );
    }

    // 空闲状态：显示本地升级和远程升级按钮
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _startLocalUpgrade,
              icon: const Icon(Icons.folder_open, size: 20),
              label: const Text('本地升级', style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C8FF),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _startRemoteUpgrade,
              icon: const Icon(Icons.cloud_download, size: 20),
              label: const Text('远程升级', style: TextStyle(fontSize: 15)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
