import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../providers/bluetooth_provider.dart';
import '../services/enhanced_image_preprocessor.dart';
import '../services/upload_validator.dart';
import 'package:provider/provider.dart';

/// Logo上传界面
/// 支持选择自定义图片或使用测试图片
class LogoUploadE2ETestScreen extends StatefulWidget {
  const LogoUploadE2ETestScreen({Key? key}) : super(key: key);

  @override
  State<LogoUploadE2ETestScreen> createState() =>
      _LogoUploadE2ETestScreenState();
}

class _LogoUploadE2ETestScreenState extends State<LogoUploadE2ETestScreen> {
  final List<String> _logs = [];
  bool _isUploading = false;
  double _progress = 0.0;

  // 图片数据
  Uint8List? _selectedImageBytes;  // 用户选择的原始图片
  img.Image? _processedImage;      // 处理后的240x240图片
  img.Image? _circularPreview;     // 圆形裁剪预览
  bool _useTestImage = true;       // 是否使用测试图片
  TestImageType _testImageType = TestImageType.solidRed;  // 测试图片类型

  // 多槽位支持
  int _selectedSlot = 0;  // 当前选择的上传槽位 (0-2)
  final List<bool> _slotStatus = [false, false, false];  // 各槽位状态
  int _activeSlot = 0;  // 当前激活的槽位

  // 预处理器和验证器
  final EnhancedImagePreprocessor _preprocessor = EnhancedImagePreprocessor();
  final UploadValidator _validator = UploadValidator();

  // 发送记录
  final List<Map<String, dynamic>> _sentPackets = [];

  // 蓝牙响应监听
  StreamSubscription<String>? _responseSub;
  String _lastResponse = '';
  bool _responseReceived = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadTestImage();
    _setupResponseListener();
    _querySlotStatus();  // 查询槽位状态
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    super.dispose();
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
        setState(() {
          _selectedImageBytes = bytes;
          _useTestImage = false;
        });
        
        // 解码并处理图片
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          // 使用增强预处理器处理图片
          _addLog('✓ 已选择图片: ${decoded.width}x${decoded.height}');
          
          // 中心裁剪为正方形
          final squared = _preprocessor.cropToSquare(decoded);
          _addLog('  中心裁剪: ${squared.width}x${squared.height}');
          
          // 高质量缩放到240x240
          _processedImage = _preprocessor.highQualityResize(squared, 240);
          _addLog('  缩放完成: ${_processedImage!.width}x${_processedImage!.height}');
          
          // 生成圆形预览
          _circularPreview = _preprocessor.cropToCircle(_processedImage!);
          _addLog('  圆形裁剪预览已生成');
          
          setState(() {});
        } else {
          _addLog('❌ 图片解码失败');
        }
      }
    } catch (e) {
      _addLog('❌ 选择图片失败: $e');
    }
  }

  /// 设置蓝牙响应监听
  void _setupResponseListener() {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    _responseSub = btProvider.rawDataStream.listen((data) {
      final trimmed = data.trim();
      
      if (trimmed.isEmpty) return;
      
      if (trimmed == 'LOGO_END' || trimmed == 'LOGO_TEST') {
        return;
      }
      
      if (trimmed.startsWith('LOGO_START:') && trimmed.contains(':') && !trimmed.contains('ERROR')) {
        final parts = trimmed.split(':');
        if (parts.length >= 3 && int.tryParse(parts[1]) != null) {
          return;
        }
      }
      
      if (trimmed.startsWith('LOGO_DATA:') && trimmed.length > 20) {
        return;
      }
      
      if (trimmed.contains('f800f800') || trimmed.contains('LOGO_DAT')) {
        return;
      }
      
      if (trimmed.startsWith('LOGO_') || trimmed.startsWith('DEBUG:')) {
        _addLog('📥 硬件响应: $trimmed');
        _lastResponse = trimmed;
        _responseReceived = true;
      }
    });
  }

  /// 等待硬件响应
  Future<String> _waitForResponse({
    Duration timeout = const Duration(seconds: 5),
    List<String>? expectedPrefixes,
  }) async {
    _responseReceived = false;
    _lastResponse = '';
    final deadline = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(deadline)) {
      if (_responseReceived) {
        final response = _lastResponse;
        _responseReceived = false;
        
        if (expectedPrefixes != null) {
          bool matched = expectedPrefixes.any((prefix) => response.contains(prefix));
          if (matched) {
            return response;
          }
          continue;
        }
        
        if (!response.startsWith('DEBUG:')) {
          return response;
        }
        continue;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
    return 'TIMEOUT';
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 23)}] $message');
    });
    print('LOGO_UPLOAD: $message');
  }

  /// 加载测试图片（240x240）
  Future<void> _loadTestImage() async {
    _processedImage = EnhancedImagePreprocessor.generateTestImage(
      type: _testImageType,
      size: 240,
    );
    
    // 生成圆形预览
    _circularPreview = _preprocessor.cropToCircle(_processedImage!);

    final typeNames = {
      TestImageType.solidRed: '纯红色',
      TestImageType.solidGreen: '纯绿色',
      TestImageType.solidBlue: '纯蓝色',
      TestImageType.gradient: '渐变色',
      TestImageType.checkerboard: '棋盘格',
    };
    
    _addLog('✓ 测试图片已准备: 240x240 (${typeNames[_testImageType]})');
    setState(() {});
  }

  /// 开始端到端测试
  Future<void> _startE2ETest() async {
    if (_processedImage == null) {
      _addLog('✗ 测试图片未准备好');
      return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0.0;
      _sentPackets.clear();
      _logs.clear();
    });

    try {
      _addLog('=== 开始端到端测试 (240x240) ===');
      _addLog('图片信息: ${_processedImage!.width}x${_processedImage!.height}');

      // 1. 圆形裁剪
      final circularImage = _preprocessor.cropToCircle(_processedImage!);
      _addLog('✓ 圆形裁剪完成');

      // 2. 转换图片为RGB565格式 (240x240)
      final bitmapData = _preprocessor.convertToRGB565(circularImage);
      _addLog('✓ 图片转换完成: ${bitmapData.length} bytes');
      _addLog('  预期数据量: 240x240x2 = 115200 bytes');
      _addLog('  实际数据量: ${bitmapData.length} bytes');
      _addLog('  匹配: ${bitmapData.length == 115200 ? "✓ YES" : "✗ NO"}');

      // 3. 验证数据
      final validationResult = _validator.validateRawData(bitmapData);
      if (!validationResult.isValid) {
        _addLog('❌ 数据验证失败: ${validationResult.errorMessage}');
        return;
      }
      _addLog('✓ 数据验证通过');

      // 4. 计算CRC32校验和
      final crc32 = validationResult.crc32!;
      _addLog('✓ CRC32计算完成: 0x${crc32.toRadixString(16).padLeft(8, '0')}');
      _addLog('  十进制: $crc32');

      // 5. 发送开始命令并等待硬件就绪
      final startSuccess = await _sendStartCommand(bitmapData.length, crc32);
      if (!startSuccess) {
        _addLog('❌ 硬件未就绪，测试终止');
        return;
      }

      // 6. 分包发送数据
      final dataSuccess = await _sendDataPackets(bitmapData);
      if (!dataSuccess) {
        _addLog('❌ 数据传输失败，测试终止');
        return;
      }

      // 7. 发送结束命令并等待结果
      final endSuccess = await _sendEndCommand();

      _addLog('=== 测试完成 ===');
      _addLog('总发送包数: ${_sentPackets.length}');
      if (endSuccess) {
        _addLog('🎉 测试成功！Logo已成功上传到槽位 $_selectedSlot');
        // 刷新槽位状态
        await _querySlotStatus();
      } else {
        _addLog('❌ 测试失败，请检查日志');
      }
    } catch (e) {
      _addLog('✗ 测试失败: $e');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  /// 转换为RGB565格式 (240x240)
  Uint8List _convertToRGB565(img.Image image) {
    return _preprocessor.convertToRGB565(image);
  }

  /// 计算CRC32校验和
  int _calculateCRC32(Uint8List data) {
    return _validator.calculateCRC32(data);
  }

  /// 发送开始命令 (支持槽位参数)
  Future<bool> _sendStartCommand(int dataSize, int crc32) async {
    _addLog('--- 发送开始命令 ---');

    // 使用三参数格式: LOGO_START:slot:size:crc32
    final command = 'LOGO_START:$_selectedSlot:$dataSize:$crc32';

    _addLog('📤 发送: $command');
    _addLog('  目标槽位: $_selectedSlot');
    _addLog('  数据大小: $dataSize bytes');
    _addLog('  CRC32: 0x${crc32.toRadixString(16).padLeft(8, '0')} ($crc32)');

    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );
    await bluetoothProvider.sendCommand(command);

    _sentPackets.add({
      'type': 'START',
      'time': DateTime.now(),
      'command': command,
    });

    // 🔥 等待硬件响应（只关注LOGO_开头的响应，忽略DEBUG）
    _addLog('⏳ 等待硬件响应...');
    var response = await _waitForResponse(
      timeout: const Duration(seconds: 10),
      expectedPrefixes: ['LOGO_ERASING', 'LOGO_READY', 'LOGO_ERROR'],
    );
    
    // 如果是ERASING，继续等待READY
    if (response.contains('LOGO_ERASING')) {
      _addLog('⏳ Flash擦除中，继续等待...');
      response = await _waitForResponse(
        timeout: const Duration(seconds: 15),
        expectedPrefixes: ['LOGO_READY', 'LOGO_ERROR'],
      );
    }
    
    if (response.contains('LOGO_READY')) {
      _addLog('✅ 硬件就绪！');
      return true;
    } else if (response.contains('LOGO_ERROR')) {
      _addLog('❌ 硬件返回错误: $response');
      return false;
    } else if (response == 'TIMEOUT') {
      _addLog('❌ 等待响应超时！硬件可能未收到命令或未响应');
      return false;
    } else {
      _addLog('⚠️ 未知响应: $response');
      return false;
    }
  }

  /// 分包发送数据（简化版：逐包发送，每16包等待ACK）
  Future<bool> _sendDataPackets(Uint8List data) async {
    _addLog('--- 开始发送数据包 ---');

    const int maxPayloadSize = 16;  // 每包16字节
    final int totalPackets = (data.length + maxPayloadSize - 1) ~/ maxPayloadSize;

    _addLog('总数据: ${data.length} bytes');
    _addLog('总包数: $totalPackets');
    _addLog('模式: 逐包发送，每16包等待ACK');

    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );

    for (int seq = 0; seq < totalPackets; seq++) {
      // 准备当前包的数据
      final start = seq * maxPayloadSize;
      final end = (start + maxPayloadSize > data.length) ? data.length : start + maxPayloadSize;
      final chunk = data.sublist(start, end);
      final hexData = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
      final command = 'LOGO_DATA:$seq:$hexData';
      
      // 发送当前包
      await bluetoothProvider.sendCommand(command);
      
      // 包间延迟20ms
      await Future.delayed(const Duration(milliseconds: 20));
      
      // 每16包等待一次ACK
      if ((seq + 1) % 16 == 0 || seq == totalPackets - 1) {
        // 等待ACK
        final response = await _waitForResponse(
          timeout: const Duration(seconds: 5),
          expectedPrefixes: ['LOGO_ACK:', 'LOGO_RESEND:', 'LOGO_NAK:', 'LOGO_ERROR'],
        );
        
        if (response.contains('LOGO_ACK:')) {
          // ACK收到，继续
          // 更新进度
          setState(() {
            _progress = (seq + 1) / totalPackets;
          });
          
          if ((seq + 1) % 100 < 16 || seq == totalPackets - 1) {
            _addLog('📊 进度: ${seq + 1}/$totalPackets (${((seq + 1) * 100 / totalPackets).toStringAsFixed(1)}%)');
          }
        } else if (response.contains('LOGO_RESEND:')) {
          // 硬件请求重发
          _addLog('❌ 硬件请求重发: $response');
          return false;
        } else if (response == 'TIMEOUT') {
          _addLog('❌ ACK超时 at seq=$seq');
          return false;
        } else {
          _addLog('❌ 意外响应: $response');
          return false;
        }
      }
    }

    _addLog('✓ 所有数据包发送完成');
    return true;
  }

  /// 发送结束命令
  Future<bool> _sendEndCommand() async {
    _addLog('--- 发送结束命令 ---');

    final command = 'LOGO_END';  // 🔥 移除多余的\n

    _addLog('📤 发送: $command');

    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );
    await bluetoothProvider.sendCommand(command);

    _sentPackets.add({
      'type': 'END',
      'time': DateTime.now(),
      'command': command,
    });

    // 🔥 等待硬件验证CRC并写入Flash
    _addLog('⏳ 等待硬件验证CRC并写入Flash...');
    final response = await _waitForResponse(
      timeout: const Duration(seconds: 30),
      expectedPrefixes: ['LOGO_OK', 'LOGO_FAIL', 'LOGO_ERROR'],
    );
    
    if (response.contains('LOGO_OK')) {
      _addLog('🎉 上传成功！Logo已写入Flash');
      return true;
    } else if (response.contains('LOGO_FAIL')) {
      _addLog('❌ 上传失败: $response');
      return false;
    } else if (response.contains('LOGO_ERROR')) {
      _addLog('❌ 硬件错误: $response');
      return false;
    } else if (response == 'TIMEOUT') {
      _addLog('❌ 等待结果超时！硬件可能正在处理或已断开');
      return false;
    } else {
      _addLog('⚠️ 未知响应: $response');
      return false;
    }
  }

  /// 发送LOGO_TEST命令查询Flash状态
  Future<void> _sendLogoTest() async {
    _addLog('=== 发送LOGO_TEST命令 ===');

    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );

    await bluetoothProvider.sendCommand('LOGO_TEST');  // 🔥 移除多余的\n
    _addLog('📤 LOGO_TEST命令已发送');
    _addLog('⏳ 等待硬件响应...');
    
    // 🔥 等待响应
    final response = await _waitForResponse(timeout: const Duration(seconds: 5));
    if (response != 'TIMEOUT') {
      _addLog('📥 Flash状态: $response');
    } else {
      _addLog('⚠️ 响应超时');
    }
  }

  /// 查询所有槽位状态
  Future<void> _querySlotStatus() async {
    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );

    await bluetoothProvider.sendCommand('GET:LOGO_SLOTS');
    
    final response = await _waitForResponse(
      timeout: const Duration(seconds: 3),
      expectedPrefixes: ['LOGO_SLOTS:'],
    );
    
    if (response.startsWith('LOGO_SLOTS:')) {
      // 解析响应: LOGO_SLOTS:v0:v1:v2:active
      final parts = response.split(':');
      if (parts.length >= 5) {
        setState(() {
          _slotStatus[0] = parts[1] == '1';
          _slotStatus[1] = parts[2] == '1';
          _slotStatus[2] = parts[3] == '1';
          _activeSlot = int.tryParse(parts[4]) ?? 0;
        });
        _addLog('📥 槽位状态: ${_slotStatus[0] ? "✓" : "○"} ${_slotStatus[1] ? "✓" : "○"} ${_slotStatus[2] ? "✓" : "○"}, 激活: $_activeSlot');
      }
    }
  }

  /// 构建测试图片预览
  Widget _buildTestImagePreview() {
    Color color;
    switch (_testImageType) {
      case TestImageType.solidRed:
        color = Colors.red;
        break;
      case TestImageType.solidGreen:
        color = Colors.green;
        break;
      case TestImageType.solidBlue:
        color = Colors.blue;
        break;
      case TestImageType.gradient:
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red, Colors.green, Colors.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Text('渐变', style: TextStyle(color: Colors.white, fontSize: 10)),
          ),
        );
      case TestImageType.checkerboard:
        return Container(
          color: Colors.white,
          child: CustomPaint(
            painter: _CheckerboardPainter(),
            child: const Center(
              child: Text('棋盘', style: TextStyle(color: Colors.black, fontSize: 10)),
            ),
          ),
        );
    }
    return Container(
      color: color,
      child: const Center(
        child: Text('测试', style: TextStyle(color: Colors.white, fontSize: 10)),
      ),
    );
  }

  /// 导出测试日志
  String _exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== LOGO上传端到端测试日志 ===');
    buffer.writeln('测试时间: ${DateTime.now()}');
    buffer.writeln('');

    buffer.writeln('=== 发送的数据包 ===');
    for (var packet in _sentPackets) {
      buffer.writeln('${packet['type']} - ${packet['time']}');
      buffer.writeln('  命令: ${packet['command']}');
    }
    buffer.writeln('');

    buffer.writeln('=== 日志记录 ===');
    for (var log in _logs) {
      buffer.writeln(log);
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logo上传'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _exportLogs()));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 进度条
          if (_isUploading) LinearProgressIndicator(value: _progress),

          // 图片预览和选择
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 原图预览
                Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _selectedImageBytes != null && !_useTestImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                            )
                          : _buildTestImagePreview(),
                    ),
                    const SizedBox(height: 4),
                    const Text('原图', style: TextStyle(fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 8),
                // 圆形预览
                Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        shape: BoxShape.circle,
                      ),
                      child: _circularPreview != null
                          ? ClipOval(
                              child: Image.memory(
                                Uint8List.fromList(img.encodePng(_circularPreview!)),
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Center(child: Text('预览', style: TextStyle(fontSize: 10))),
                    ),
                    const SizedBox(height: 4),
                    const Text('圆形', style: TextStyle(fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 16),
                // 选择按钮
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _useTestImage ? '测试图片 (240x240)' : '自定义图片',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : _pickImage,
                            icon: const Icon(Icons.photo_library, size: 18),
                            label: const Text('选择'),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<TestImageType>(
                            enabled: !_isUploading,
                            onSelected: (type) {
                              setState(() {
                                _testImageType = type;
                                _useTestImage = true;
                                _selectedImageBytes = null;
                              });
                              _loadTestImage();
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: TestImageType.solidRed, child: Text('纯红色')),
                              const PopupMenuItem(value: TestImageType.solidGreen, child: Text('纯绿色')),
                              const PopupMenuItem(value: TestImageType.solidBlue, child: Text('纯蓝色')),
                              const PopupMenuItem(value: TestImageType.gradient, child: Text('渐变色')),
                              const PopupMenuItem(value: TestImageType.checkerboard, child: Text('棋盘格')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('测试图'),
                                  Icon(Icons.arrow_drop_down, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 控制按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // 槽位选择
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<int>(
                    value: _selectedSlot,
                    underline: const SizedBox(),
                    items: [0, 1, 2].map((slot) {
                      final status = _slotStatus[slot] ? '✓' : '○';
                      final active = slot == _activeSlot ? '*' : '';
                      return DropdownMenuItem(
                        value: slot,
                        child: Text('槽$slot $status$active'),
                      );
                    }).toList(),
                    onChanged: _isUploading ? null : (value) {
                      if (value != null) {
                        setState(() => _selectedSlot = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isUploading || _processedImage == null ? null : _startE2ETest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('开始上传', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _querySlotStatus,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新槽位状态',
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                      _sentPackets.clear();
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 日志显示
          Expanded(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(8.0),
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Text(
                    _logs[index],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// 棋盘格绘制器
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    const blockSize = 10.0;
    
    for (double y = 0; y < size.height; y += blockSize) {
      for (double x = 0; x < size.width; x += blockSize) {
        final isBlack = ((x ~/ blockSize) + (y ~/ blockSize)) % 2 == 1;
        if (isBlack) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, blockSize, blockSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
