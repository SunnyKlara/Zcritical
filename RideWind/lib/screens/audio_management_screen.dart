import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
import '../services/audio_transmission_manager.dart';
import '../services/audio_preprocessor.dart';

/// 自定义引擎音频管理界面
///
/// 功能:
/// - 选择音频文件 (WAV/MP3/OGG/FLAC)
/// - 预处理转码为 22050Hz 单声道 8-bit signed PCM
/// - 分层上传 4 层引擎音频 (idle/low/mid/high)
/// - 查询/删除已上传的自定义音频
class AudioManagementScreen extends StatefulWidget {
  const AudioManagementScreen({Key? key}) : super(key: key);

  @override
  State<AudioManagementScreen> createState() => _AudioManagementScreenState();
}

class _AudioManagementScreenState extends State<AudioManagementScreen> {
  // 每层的选中文件和处理后的 PCM 数据
  final Map<AudioLayer, String?> _selectedFiles = {};
  final Map<AudioLayer, Uint8List?> _processedPcm = {};
  final Map<AudioLayer, int?> _originalSampleRates = {};

  // 上传状态
  bool _isUploading = false;
  int _currentUploadLayer = -1;
  double _uploadProgress = 0.0;
  double _totalProgress = 0.0;
  String _statusMessage = '';
  AudioTransmissionManager? _transmissionManager;

  // 硬件端音频状态
  Map<String, dynamic>? _audioStatus;
  bool _isQuerying = false;

  // 预处理状态
  bool _isProcessing = false;
  String _processingMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queryAudioStatus();
    });
  }

  @override
  void dispose() {
    _transmissionManager?.cancel();
    super.dispose();
  }

  /// 查询硬件端自定义音频状态
  Future<void> _queryAudioStatus() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) return;

    setState(() => _isQuerying = true);
    final status =
        await AudioTransmissionManager.queryAudioStatus(btProvider);
    if (mounted) {
      setState(() {
        _audioStatus = status;
        _isQuerying = false;
      });
    }
  }

  /// 为指定层选择音频文件
  Future<void> _pickAudioFile(AudioLayer layer) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg', 'flac', 'pcm', 'raw'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        _showError('文件读取失败');
        return;
      }

      setState(() {
        _isProcessing = true;
        _processingMessage = '正在处理 ${file.name}...';
      });

      // 预处理音频文件
      final ext = file.extension?.toLowerCase() ?? '';
      Uint8List pcmData;
      int? originalRate;

      if (ext == 'pcm' || ext == 'raw') {
        // 已经是 raw PCM — 假设是 22050Hz 8-bit signed
        pcmData = file.bytes!;
        originalRate = 22050;
      } else if (ext == 'wav') {
        // WAV 文件 — 解析并转换
        final result = AudioPreprocessor.convertWavToPcm(file.bytes!);
        pcmData = result.pcmData;
        originalRate = result.originalSampleRate;
      } else {
        // 不支持的格式提示
        _showError('暂不支持 $ext 格式，请使用 WAV 或 PCM 文件');
        setState(() {
          _isProcessing = false;
          _processingMessage = '';
        });
        return;
      }

      if (pcmData.isEmpty) {
        _showError('音频转换失败');
        setState(() {
          _isProcessing = false;
          _processingMessage = '';
        });
        return;
      }

      setState(() {
        _selectedFiles[layer] = file.name;
        _processedPcm[layer] = pcmData;
        _originalSampleRates[layer] = originalRate;
        _isProcessing = false;
        _processingMessage = '';
        _statusMessage =
            '${layer.name}: ${file.name} → ${pcmData.length} 字节 PCM '
            '(${(pcmData.length / 22050).toStringAsFixed(1)}s)';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingMessage = '';
      });
      _showError('选择文件失败: $e');
    }
  }

  /// 上传所有已选择的层
  Future<void> _startUpload() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isConnected) {
      _showError('蓝牙未连接');
      return;
    }

    // 收集要上传的层
    final layersToUpload = <AudioLayer>[];
    for (final layer in AudioLayer.values) {
      if (_processedPcm[layer] != null) {
        layersToUpload.add(layer);
      }
    }

    if (layersToUpload.isEmpty) {
      _showError('请先选择音频文件');
      return;
    }

    // 检查是否选了全部 4 层
    if (layersToUpload.length < 4) {
      final missing = AudioLayer.values
          .where((l) => !layersToUpload.contains(l))
          .map((l) => l.name)
          .join(', ');
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('未选择全部层'),
          content: Text(
            '缺少: $missing\n\n'
            'ESP32 需要全部 4 层音频才能使用自定义音效。\n'
            '是否继续上传已选择的层？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续上传'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _totalProgress = 0.0;
      _statusMessage = '准备上传...';
    });

    int completed = 0;
    bool allSuccess = true;

    for (final layer in layersToUpload) {
      if (!mounted || !btProvider.isConnected) break;

      setState(() {
        _currentUploadLayer = layer.layerIndex;
        _uploadProgress = 0.0;
        _statusMessage = '上传 ${layer.description}...';
      });

      _transmissionManager = AudioTransmissionManager(
        btProvider: btProvider,
        pcmData: _processedPcm[layer]!,
        layer: layer,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _uploadProgress = p;
              _totalProgress =
                  (completed + p) / layersToUpload.length;
            });
          }
        },
        onStateChange: (state) {
          if (mounted) {
            setState(() {
              switch (state) {
                case AudioTransmissionState.starting:
                  _statusMessage = '连接 ${layer.name}...';
                  break;
                case AudioTransmissionState.transmitting:
                  _statusMessage = '上传 ${layer.description}...';
                  break;
                case AudioTransmissionState.verifying:
                  _statusMessage = '校验 ${layer.name}...';
                  break;
                case AudioTransmissionState.completed:
                  _statusMessage = '${layer.name} 完成';
                  break;
                case AudioTransmissionState.error:
                  _statusMessage = '${layer.name} 失败';
                  break;
                default:
                  break;
              }
            });
          }
        },
        onError: (error) {
          if (mounted) {
            _showError('${layer.name}: $error');
          }
        },
      );

      final success = await _transmissionManager!.transmit();
      if (success) {
        completed++;
      } else {
        allSuccess = false;
        break;
      }

      // 层间间隔，让 ESP32 写入 LittleFS
      if (completed < layersToUpload.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _currentUploadLayer = -1;
        _totalProgress = allSuccess ? 1.0 : _totalProgress;
        _statusMessage = allSuccess
            ? '全部 $completed 层上传成功！'
            : '$completed/${layersToUpload.length} 层上传完成';
      });

      if (allSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$completed 层引擎音频上传成功'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 刷新状态
      await _queryAudioStatus();
    }
    _transmissionManager = null;
  }

  /// 删除所有自定义音频
  Future<void> _deleteAllAudio() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除自定义音频'),
        content: const Text('确定要删除所有自定义引擎音频吗？\n设备将恢复使用内置音效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    final success =
        await AudioTransmissionManager.deleteAllAudio(btProvider);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('自定义音频已删除，已恢复内置音效'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showError('删除失败');
      }
      await _queryAudioStatus();
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _statusMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('引擎音频管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isUploading ? null : _queryAudioStatus,
            tooltip: '刷新状态',
          ),
          if (_audioStatus != null && _audioStatus!['custom'] == true)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _isUploading ? null : _deleteAllAudio,
              tooltip: '删除自定义音频',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 硬件状态卡片
            _buildStatusCard(),
            const SizedBox(height: 16),

            // 说明
            _buildInfoCard(),
            const SizedBox(height: 16),

            // 4 层音频选择
            ...AudioLayer.values.map((layer) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildLayerCard(layer),
                )),

            // 处理中提示
            if (_isProcessing) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(_processingMessage),
                    ],
                  ),
                ),
              ),
            ],

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
                    color: _statusMessage.contains('失败') ||
                            _statusMessage.contains('错误')
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
            ElevatedButton.icon(
              onPressed: _isUploading || _isProcessing
                  ? null
                  : _startUpload,
              icon: const Icon(Icons.upload),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              label: Text(
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
                child:
                    const Text('取消上传', style: TextStyle(fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 硬件状态卡片
  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _audioStatus?['custom'] == true
                      ? Icons.music_note
                      : Icons.music_off,
                  color: _audioStatus?['custom'] == true
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _audioStatus?['custom'] == true
                      ? '当前使用: 自定义音频'
                      : '当前使用: 内置音效',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isQuerying)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_audioStatus != null) ...[
              const SizedBox(height: 12),
              Row(
                children: AudioLayer.values.map((layer) {
                  final exists =
                      _audioStatus?[layer.layerIndex.toString()] == true;
                  return Expanded(
                    child: Column(
                      children: [
                        Icon(
                          exists
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: exists ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          layer.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: exists ? Colors.white : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 说明卡片
  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.withOpacity(0.1),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '使用说明',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '• 需要上传全部 4 层音频才能启用自定义音效\n'
              '• 支持 WAV 格式，自动转换为 22050Hz 8-bit PCM\n'
              '• 也可直接上传 .pcm/.raw 文件 (22050Hz 8-bit signed)\n'
              '• 每层建议 2-4 秒循环片段 (约 44-88 KB)\n'
              '• 4 层对应不同转速: 怠速→低→中→高',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  /// 单层音频选择卡片
  Widget _buildLayerCard(AudioLayer layer) {
    final hasFile = _processedPcm[layer] != null;
    final fileName = _selectedFiles[layer];
    final pcmSize = _processedPcm[layer]?.length;
    final isCurrentUpload = _currentUploadLayer == layer.layerIndex;
    final existsOnDevice =
        _audioStatus?[layer.layerIndex.toString()] == true;

    return Card(
      color: isCurrentUpload ? Colors.blue.withOpacity(0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 层信息
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    layer.description,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
                  if (existsOnDevice)
                    const Text(
                      '✓ 已上传',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 文件信息
            Expanded(
              child: hasFile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName ?? '未知文件',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${(pcmSize! / 1024).toStringAsFixed(1)} KB · '
                          '${(pcmSize / 22050).toStringAsFixed(1)}s',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      '未选择文件',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
            ),

            // 选择按钮
            IconButton(
              onPressed: _isUploading || _isProcessing
                  ? null
                  : () => _pickAudioFile(layer),
              icon: Icon(
                hasFile ? Icons.swap_horiz : Icons.add,
                color: hasFile ? Colors.blue : Colors.grey,
              ),
              tooltip: hasFile ? '更换文件' : '选择文件',
            ),

            // 清除按钮
            if (hasFile)
              IconButton(
                onPressed: _isUploading
                    ? null
                    : () {
                        setState(() {
                          _selectedFiles.remove(layer);
                          _processedPcm.remove(layer);
                          _originalSampleRates.remove(layer);
                        });
                      },
                icon: const Icon(Icons.close, size: 18),
                tooltip: '清除',
              ),
          ],
        ),
      ),
    );
  }

  /// 上传进度区域
  Widget _buildProgressSection() {
    final currentLayer = _currentUploadLayer >= 0 &&
            _currentUploadLayer < AudioLayer.values.length
        ? AudioLayer.values[_currentUploadLayer]
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 总进度
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('总进度', style: TextStyle(fontSize: 14)),
                Text(
                  '${(_totalProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _totalProgress,
                minHeight: 8,
                backgroundColor: Colors.grey[800],
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
            ),

            // 当前层进度
            if (currentLayer != null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${currentLayer.name} 层',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${(_uploadProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _uploadProgress,
                  minHeight: 4,
                  backgroundColor: Colors.grey[800],
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
