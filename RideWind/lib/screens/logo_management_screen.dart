import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../services/enhanced_image_preprocessor.dart';
import '../services/logo_transmission_manager.dart';

/// 正式 Logo 管理界面
///
/// 提供图片选择、裁剪预览、240×240 RGB565 转换和上传进度显示。
/// 使用统一的 LogoTransmissionManager 执行上传。
/// _需求: 14.2, 14.3_
class LogoManagementScreen extends StatefulWidget {
  const LogoManagementScreen({Key? key}) : super(key: key);

  @override
  State<LogoManagementScreen> createState() => _LogoManagementScreenState();
}

class _LogoManagementScreenState extends State<LogoManagementScreen> {
  final ImagePicker _picker = ImagePicker();
  final EnhancedImagePreprocessor _preprocessor = EnhancedImagePreprocessor();

  // 图片状态
  Uint8List? _selectedImageBytes;
  img.Image? _processedImage;
  img.Image? _circularPreview;

  // 上传状态
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = '';
  LogoTransmissionManager? _transmissionManager;

  // 槽位状态
  int _selectedSlot = 0;
  final List<bool> _slotStatus = [false, false, false];
  int _activeSlot = -1;

  // 响应监听
  StreamSubscription<String>? _responseSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _querySlotStatus();
    });
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _transmissionManager?.cancel();
    super.dispose();
  }

  /// 查询 Logo 槽位状态
  Future<void> _querySlotStatus() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    // 设置临时监听器来接收 LOGO_SLOTS 响应
    final completer = Completer<String>();
    _responseSub?.cancel();
    _responseSub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      if (trimmed.startsWith('LOGO_SLOTS:') && !completer.isCompleted) {
        completer.complete(trimmed);
      }
    });

    await btProvider.sendCommand('GET:LOGO_SLOTS');

    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 3),
      );
      _parseSlotStatus(response);
    } on TimeoutException {
      // 超时忽略
    } finally {
      _responseSub?.cancel();
    }
  }

  void _parseSlotStatus(String response) {
    // 格式: LOGO_SLOTS:v0:v1:v2:active
    final parts = response.split(':');
    if (parts.length >= 5) {
      setState(() {
        _slotStatus[0] = parts[1] == '1';
        _slotStatus[1] = parts[2] == '1';
        _slotStatus[2] = parts[3] == '1';
        _activeSlot = int.tryParse(parts[4]) ?? -1;
      });
    }
  }

  /// 选择图片
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          // 中心裁剪为正方形 → 缩放到 240×240 → 圆形裁剪预览
          final squared = _preprocessor.cropToSquare(decoded);
          final resized = _preprocessor.highQualityResize(squared, 240);
          final circular = _preprocessor.cropToCircle(resized);

          setState(() {
            _selectedImageBytes = bytes;
            _processedImage = resized;
            _circularPreview = circular;
            _statusMessage = '图片已准备: ${decoded.width}×${decoded.height} → 240×240';
          });
        } else {
          _showError('图片解码失败');
        }
      }
    } catch (e) {
      _showError('选择图片失败: $e');
    }
  }

  /// 开始上传
  Future<void> _startUpload() async {
    if (_processedImage == null) {
      _showError('请先选择图片');
      return;
    }

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) {
      _showError('蓝牙未连接');
      return;
    }

    // 转换为 240×240 RGB565 格式 (115200 字节)
    final circularImage = _preprocessor.cropToCircle(_processedImage!);
    final rgb565Data = _preprocessor.convertToRGB565(circularImage);

    if (rgb565Data.length != 115200) {
      _showError('图片转换异常: ${rgb565Data.length} 字节 (应为 115200)');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _statusMessage = '准备上传...';
    });

    // 创建 LogoTransmissionManager 实例
    _transmissionManager = LogoTransmissionManager(
      btProvider: btProvider,
      imageData: rgb565Data,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
      },
      onStateChange: (state) {
        if (mounted) {
          setState(() {
            switch (state) {
              case TransmissionState.starting:
                _statusMessage = '正在连接设备...';
                break;
              case TransmissionState.transmitting:
                _statusMessage = '正在上传...';
                break;
              case TransmissionState.verifying:
                _statusMessage = '校验中...';
                break;
              case TransmissionState.completed:
                _statusMessage = '上传成功！';
                break;
              case TransmissionState.error:
                _statusMessage = '上传失败';
                break;
              default:
                break;
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          _showError(error);
        }
      },
    );

    try {
      final success = await _transmissionManager!.transmit(slot: _selectedSlot);
      if (success && mounted) {
        setState(() {
          _uploadProgress = 1.0;
          _statusMessage = '上传成功！Logo 已写入槽位 $_selectedSlot';
        });
        // 刷新槽位状态
        await _querySlotStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logo 上传成功 (槽位 $_selectedSlot)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '上传失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
      _transmissionManager = null;
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _statusMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logo 管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isUploading ? null : _querySlotStatus,
            tooltip: '刷新槽位状态',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图片预览区域
            _buildImagePreview(),
            const SizedBox(height: 16),

            // 图片选择按钮
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('选择图片'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // 槽位选择
            _buildSlotSelector(),
            const SizedBox(height: 16),

            // 上传进度
            if (_isUploading) ...[
              _buildProgressSection(),
              const SizedBox(height: 16),
            ],

            // 状态消息
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.contains('失败') || _statusMessage.contains('错误')
                        ? Colors.redAccent
                        : _statusMessage.contains('成功')
                            ? Colors.greenAccent
                            : Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // 上传按钮
            ElevatedButton(
              onPressed: _isUploading || _processedImage == null ? null : _startUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _isUploading ? '上传中...' : '开始上传',
                style: const TextStyle(fontSize: 16),
              ),
            ),

            // 取消按钮
            if (_isUploading) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  _transmissionManager?.cancel();
                  setState(() {
                    _isUploading = false;
                    _statusMessage = '已取消上传';
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('取消上传', style: TextStyle(fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 图片预览区域
  Widget _buildImagePreview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 原图预览
            Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[800],
                  ),
                  child: _selectedImageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                        )
                      : const Center(
                          child: Icon(Icons.image, size: 40, color: Colors.grey),
                        ),
                ),
                const SizedBox(height: 4),
                const Text('原图', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward, color: Colors.grey),
            const SizedBox(width: 16),
            // 圆形预览 (240×240 RGB565)
            Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    shape: BoxShape.circle,
                    color: Colors.grey[800],
                  ),
                  child: _circularPreview != null
                      ? ClipOval(
                          child: Image.memory(
                            Uint8List.fromList(img.encodePng(_circularPreview!)),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.circle_outlined, size: 40, color: Colors.grey),
                        ),
                ),
                const SizedBox(height: 4),
                const Text('240×240 预览', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 槽位选择器
  Widget _buildSlotSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Logo 槽位', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: List.generate(3, (index) {
                final isActive = index == _activeSlot;
                final hasLogo = _slotStatus[index];
                final isSelected = index == _selectedSlot;

                return Expanded(
                  child: GestureDetector(
                    onTap: _isUploading
                        ? null
                        : () => setState(() => _selectedSlot = index),
                    child: Container(
                      margin: EdgeInsets.only(
                        left: index > 0 ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.grey,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected ? Colors.blue.withOpacity(0.1) : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            hasLogo ? Icons.image : Icons.image_outlined,
                            color: hasLogo ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '槽位 $index',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (isActive)
                            const Text(
                              '当前激活',
                              style: TextStyle(fontSize: 10, color: Colors.blue),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// 上传进度区域
  Widget _buildProgressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('上传进度', style: TextStyle(fontSize: 14)),
                Text(
                  '${(_uploadProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 8,
                backgroundColor: Colors.grey[800],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
