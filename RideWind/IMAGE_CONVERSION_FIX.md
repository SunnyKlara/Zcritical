# 图片转换修复方案

## 问题分析

取模软件配置：
- **扫描模式**：水平扫描（从左到右，从上到下）
- **输出灰度**：16位真彩色（RGB565）
- **字节序**：高位在前（MSB First，大端序）
- **输出格式**：C数组，每个像素2字节

当前APP的问题：
1. 使用Flutter的图片缩放，可能与取模软件的算法不同
2. RGB565转换可能有细微差异
3. 字节序可能不对

## 解决方案

### 方案1：使用image包（推荐）

添加依赖到 `pubspec.yaml`：
```yaml
dependencies:
  image: ^4.0.0
```

修改 `_convertImageToRGB565` 函数：

```dart
import 'package:image/image.dart' as img;

Future<Uint8List?> _convertImageToRGB565(File imageFile) async {
  try {
    _addLog('   📖 读取图片文件...');
    final bytes = await imageFile.readAsBytes();
    _addLog('   📖 原始文件大小: ${bytes.length} 字节');

    _addLog('   🔄 解码图片...');
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      _addLog('   ❌ 图片解码失败');
      return null;
    }
    _addLog('   📐 原始尺寸: ${image.width}x${image.height}');

    const targetSize = 154;
    _addLog('   🔄 缩放到 ${targetSize}x$targetSize...');
    
    // 使用最近邻插值（nearest），更接近取模软件的行为
    img.Image resized = img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.nearest,  // 关键：使用最近邻插值
    );

    _addLog('   🔄 转换为RGB565格式（大端序）...');
    final rgb565 = Uint8List(targetSize * targetSize * 2);
    int outIndex = 0;

    // 水平扫描：从上到下，从左到右
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final pixel = resized.getPixel(x, y);
        
        // 获取RGB值（0-255）
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // 转换为RGB565（5-6-5位）
        final r5 = (r >> 3) & 0x1F;  // 取高5位
        final g6 = (g >> 2) & 0x3F;  // 取高6位
        final b5 = (b >> 3) & 0x1F;  // 取高5位
        
        // 组合成16位RGB565值
        final rgb565Value = (r5 << 11) | (g6 << 5) | b5;
        
        // 大端序输出（高位在前，MSB First）
        rgb565[outIndex++] = (rgb565Value >> 8) & 0xFF;  // 高字节
        rgb565[outIndex++] = rgb565Value & 0xFF;         // 低字节
      }
    }

    _addLog('   ✅ RGB565转换完成: ${rgb565.length} 字节');
    return rgb565;
  } catch (e, stackTrace) {
    _addLog('   ❌ 图片处理异常: $e');
    print('[LOGO] 图片处理异常: $e\n$stackTrace');
    return null;
  }
}
```

### 方案2：不添加依赖，改进当前实现

如果不想添加image包，可以改进当前的Flutter实现：

```dart
Future<Uint8List?> _convertImageToRGB565(File imageFile) async {
  try {
    _addLog('   📖 读取图片文件...');
    final bytes = await imageFile.readAsBytes();
    _addLog('   📖 原始文件大小: ${bytes.length} 字节');

    _addLog('   🔄 解码图片...');
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    _addLog('   📐 原始尺寸: ${image.width}x${image.height}');

    const targetSize = 154;
    _addLog('   🔄 缩放到 ${targetSize}x$targetSize...');
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // 使用FilterQuality.none（最近邻插值）
    final paint = Paint()
      ..filterQuality = FilterQuality.none  // 关键：不使用插值
      ..isAntiAlias = false;  // 关键：不使用抗锯齿
    
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, targetSize.toDouble(), targetSize.toDouble()),
      paint,
    );
    
    final picture = recorder.endRecording();
    final resizedImage = await picture.toImage(targetSize, targetSize);

    _addLog('   🔄 获取RGBA像素数据...');
    final byteData = await resizedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      _addLog('   ❌ toByteData返回null');
      return null;
    }
    final rgba = byteData.buffer.asUint8List();
    _addLog('   📊 RGBA数据: ${rgba.length} 字节');

    _addLog('   🔄 转换为RGB565格式（大端序）...');
    final rgb565 = Uint8List(targetSize * targetSize * 2);
    int outIndex = 0;
    
    // 水平扫描：从上到下，从左到右
    for (int i = 0; i < rgba.length; i += 4) {
      // 获取RGB值
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      
      // 转换为RGB565（5-6-5位）
      final r5 = (r >> 3) & 0x1F;
      final g6 = (g >> 2) & 0x3F;
      final b5 = (b >> 3) & 0x1F;
      
      // 组合成16位RGB565值
      final rgb565Value = (r5 << 11) | (g6 << 5) | b5;
      
      // 大端序输出（高位在前，MSB First）
      rgb565[outIndex++] = (rgb565Value >> 8) & 0xFF;  // 高字节
      rgb565[outIndex++] = rgb565Value & 0xFF;         // 低字节
    }
    
    _addLog('   ✅ RGB565转换完成: ${rgb565.length} 字节');
    return rgb565;
  } catch (e, stackTrace) {
    _addLog('   ❌ 图片处理异常: $e');
    print('[LOGO] 图片处理异常: $e\n$stackTrace');
    return null;
  }
}
```

## 传输速度优化

### 问题：2965包，20分钟太慢

优化方案：

1. **减少等待时间**
```dart
// 当前：每10包等待50ms
await Future.delayed(const Duration(milliseconds: 50));

// 优化：减少到10ms或不等待
await Future.delayed(const Duration(milliseconds: 10));
// 或者完全不等待，让硬件缓冲区处理
```

2. **增加窗口大小**
```dart
// 当前：每10包等待ACK
if ((seq + 1) % 10 == 0) {
  // 等待ACK
}

// 优化：每20包或30包等待ACK
if ((seq + 1) % 20 == 0) {
  // 等待ACK
}
```

3. **使用优化版传输**
- 确保使用"上传(优化)"按钮
- `LogoTransmissionManager` 已经做了很多优化

## 关键点总结

1. **插值算法**：使用 `Interpolation.nearest`（最近邻）或 `FilterQuality.none`
2. **字节序**：大端序（高字节在前）
3. **扫描顺序**：水平扫描（从左到右，从上到下）
4. **RGB565格式**：R(5位) G(6位) B(5位)

## 测试步骤

1. 先用"测试取模数组"按钮测试硬件是否正常
2. 如果硬件正常，修改APP的转换函数
3. 选择一张图片测试
4. 对比LCD显示效果
