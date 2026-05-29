import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

/// 🚗 3D 模型预览页（Step 2：接入 flutter_3d_controller）
///
/// 路由位置：`MainPagerScreen` PageView index=3。
/// 滑动方式：从 DeviceConnectScreen 主面板向**右**滑进入。
///
/// 当前数据源：远程 URL（Khronos 官方 GLB Sample，CC0 授权，公开测试用）。
/// 后续切到本地：把 GLB 文件放 `assets/models/`，pubspec 注册，src 改 'assets/models/xxx.glb'。
///
/// 性能注意：
/// - 底层是 WebView + Google `<model-viewer>`，不是 Impeller 原生
/// - 中低端 Android（< 4GB RAM）拖动可能掉帧
/// - 不要在此屏外面盖 BackdropFilter/烟雾，iOS 上盖不上
class Model3DScreen extends StatefulWidget {
  const Model3DScreen({super.key});

  @override
  State<Model3DScreen> createState() => _Model3DScreenState();
}

class _Model3DScreenState extends State<Model3DScreen> {
  final Flutter3DController _controller = Flutter3DController();

  // 测试模型：Khronos 官方 GLB Sample（DamagedHelmet，CC0），公开免费
  // 替换为本地：'assets/models/your_model.glb'
  static const String _modelSrc =
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/DamagedHelmet/glTF-Binary/DamagedHelmet.glb';

  bool _isLoading = true;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 主体：3D Viewer
            Positioned.fill(
              child: Flutter3DViewer(
                src: _modelSrc,
                controller: _controller,
                progressBarColor: Colors.white24,
                enableTouch: true,
                onProgress: (progress) {
                  // progress 0.0 ~ 1.0，1.0 表示加载完成
                  if (progress >= 1.0 && _isLoading && mounted) {
                    setState(() => _isLoading = false);
                  }
                },
                onLoad: (modelAddress) {
                  if (mounted) setState(() => _isLoading = false);
                },
                onError: (error) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _hasError = true;
                    });
                  }
                },
              ),
            ),

            // 加载中遮罩
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '加载 3D 模型...',
                          style: TextStyle(
                            color: Colors.white.withAlpha(160),
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 加载失败提示
            if (_hasError)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white54,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '模型加载失败',
                          style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '检查网络后左滑返回再进入重试',
                          style: TextStyle(
                            color: Colors.white.withAlpha(120),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 左上角返回提示
            Positioned(
              top: 16,
              left: 16,
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white.withAlpha(120),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '左滑返回',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // 右下角自动旋转开关
            Positioned(
              bottom: 24,
              right: 24,
              child: _AutoRotateButton(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自动旋转开关：演示 Flutter3DController 的相机控制能力
class _AutoRotateButton extends StatefulWidget {
  final Flutter3DController controller;
  const _AutoRotateButton({required this.controller});

  @override
  State<_AutoRotateButton> createState() => _AutoRotateButtonState();
}

class _AutoRotateButtonState extends State<_AutoRotateButton> {
  bool _autoRotate = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _autoRotate = !_autoRotate);
        if (_autoRotate) {
          widget.controller.playAnimation();
        } else {
          widget.controller.pauseAnimation();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(_autoRotate ? 60 : 30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withAlpha(_autoRotate ? 200 : 80),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.autorenew,
              color: Colors.white.withAlpha(_autoRotate ? 255 : 160),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _autoRotate ? '自动旋转中' : '自动旋转',
              style: TextStyle(
                color: Colors.white.withAlpha(_autoRotate ? 255 : 160),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
