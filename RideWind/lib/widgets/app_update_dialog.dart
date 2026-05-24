import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_update_service.dart';

/// APP更新提示弹窗
class AppUpdateDialog extends StatefulWidget {
  final AppVersionInfo versionInfo;

  const AppUpdateDialog({super.key, required this.versionInfo});

  /// 在任意页面检查并弹出更新提示
  static Future<void> checkAndShow(BuildContext context) async {
    final info = await AppUpdateService().checkForUpdate();
    if (info != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: !info.forceUpdate,
        builder: (_) => AppUpdateDialog(versionInfo: info),
      );
    }
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  void _startDownload() {
    // iOS: 跳转 App Store 或 TestFlight 更新
    if (Platform.isIOS) {
      _openIOSUpdate();
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
    });

    AppUpdateService().downloadAndInstall(
      widget.versionInfo,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onComplete: () {
        if (mounted) Navigator.of(context).pop();
      },
      onError: (e) {
        if (mounted) setState(() { _error = e; _downloading = false; });
      },
    );
  }

  /// iOS 更新：跳转 App Store 或 TestFlight
  Future<void> _openIOSUpdate() async {
    // 优先使用 app_version.json 中配置的 App Store URL
    // TestFlight 阶段使用 TestFlight 深链接
    const testFlightUrl = 'https://testflight.apple.com/join/YOUR_CODE';
    final appStoreUrl = AppUpdateService.iosAppStoreUrl;

    final url = appStoreUrl.isNotEmpty ? appStoreUrl : testFlightUrl;

    try {
      // 使用系统 URL scheme 打开（不需要 url_launcher 依赖）
      final uri = Uri.parse(url);
      await SystemChannels.platform.invokeMethod('SystemNavigator.routeInformationUpdated');
      // 通过 platform channel 打开 URL
      const channel = MethodChannel('plugins.flutter.io/url_launcher_ios');
      await channel.invokeMethod('launch', <String, Object>{
        'url': uri.toString(),
        'useSafariVC': false,
        'useWebView': false,
        'enableJavaScript': false,
        'enableDomStorage': false,
        'universalLinksOnly': false,
        'headers': <String, String>{},
      });
    } catch (_) {
      // fallback: 复制链接到剪贴板
      if (mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('更新链接已复制，请在浏览器中打开')),
          );
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.versionInfo.forceUpdate,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Color(0xFF00FF94), size: 24),
            SizedBox(width: 8),
            Text('发现新版本', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${widget.versionInfo.version}',
              style: const TextStyle(color: Color(0xFF00FF94), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (widget.versionInfo.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新内容:', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                widget.versionInfo.releaseNotes,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00FF94)),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
        actions: [
          if (!widget.versionInfo.forceUpdate && !_downloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('稍后再说', style: TextStyle(color: Colors.white54)),
            ),
          if (!_downloading)
            ElevatedButton(
              onPressed: _startDownload,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF94),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('立即更新', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          if (_downloading)
            TextButton(
              onPressed: () {
                AppUpdateService().cancelDownload();
                setState(() => _downloading = false);
              },
              child: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
        ],
      ),
    );
  }
}
