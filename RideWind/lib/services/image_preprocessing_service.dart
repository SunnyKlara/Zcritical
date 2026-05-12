import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 预处理后的图片数据
class PreprocessedImage {
  final Uint8List rgb565Data;
  final ImageFeatures features;
  final int width;
  final int height;
  final DateTime timestamp;

  PreprocessedImage({
    required this.rgb565Data,
    required this.features,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  int get dataSize => rgb565Data.length;
}

/// 图片特征分析结果
class ImageFeatures {
  final int uniqueColors;
  final double complexity;
  final bool hasLargeUniformAreas;
  final double estimatedCompressionRatio;

  ImageFeatures({
    required this.uniqueColors,
    required this.complexity,
    required this.hasLargeUniformAreas,
    required this.estimatedCompressionRatio,
  });
}

/// 图片预处理服务
/// 负责图片加载、缩放、格式转换和特征分析
class ImagePreprocessingService {
  /// 目标尺寸常量
  static const int targetSize = 240;

  /// 加载并预处理图片
  ///
  /// 处理流程:
  /// 1. 加载图片文件
  /// 2. 中心裁剪为正方形
  /// 3. 调整尺寸到240x240
  /// 4. 转换为RGB565格式
  /// 5. 分析图片特征
  Future<PreprocessedImage> preprocessImage(File imageFile) async {
    // 1. 加载图片
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('无法加载图片');
    }

    // 2. 中心裁剪为正方形
    final squared = cropToSquare(image);

    // 3. 调整尺寸到240x240
    final resized = resizeImage(squared, targetSize);

    // 4. 转换为RGB565
    final rgb565Data = convertToRGB565(resized);

    // 5. 分析图片特征
    final features = analyzeImage(rgb565Data);

    return PreprocessedImage(
      rgb565Data: rgb565Data,
      features: features,
      width: targetSize,
      height: targetSize,
      timestamp: DateTime.now(),
    );
  }

  /// 中心裁剪为正方形
  /// 对于非正方形图片，以中心为基准裁剪为正方形
  img.Image cropToSquare(img.Image image) {
    final width = image.width;
    final height = image.height;

    // 如果已经是正方形，直接返回
    if (width == height) {
      return image;
    }

    // 计算裁剪区域
    final size = math.min(width, height);
    final x = (width - size) ~/ 2;
    final y = (height - size) ~/ 2;

    // 执行裁剪
    return img.copyCrop(image, x: x, y: y, width: size, height: size);
  }

  /// 调整图片尺寸到指定大小
  /// 使用Lanczos算法进行高质量缩放
  img.Image resizeImage(img.Image image, int targetSize) {
    return img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.cubic,
    );
  }

  /// 转换为RGB565格式
  /// RGB565格式: R(5位) G(6位) B(5位)
  /// 高位在前(MSB First)
  Uint8List convertToRGB565(img.Image image) {
    final buffer = Uint8List(image.width * image.height * 2);
    int offset = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);

        // 提取RGB分量
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 转换为RGB565
        final r5 = (r >> 3) & 0x1F;
        final g6 = (g >> 2) & 0x3F;
        final b5 = (b >> 3) & 0x1F;
        final rgb565 = (r5 << 11) | (g6 << 5) | b5;

        // 写入buffer (高位在前)
        buffer[offset++] = (rgb565 >> 8) & 0xFF;
        buffer[offset++] = rgb565 & 0xFF;
      }
    }

    return buffer;
  }

  /// 分析图片特征
  /// 用于预估压缩效果
  ImageFeatures analyzeImage(Uint8List rgb565Data) {
    // 统计唯一颜色
    final colorSet = <int>{};
    int consecutiveCount = 0;
    int totalPixels = rgb565Data.length ~/ 2;

    for (int i = 0; i < rgb565Data.length; i += 2) {
      final pixel = (rgb565Data[i] << 8) | rgb565Data[i + 1];
      colorSet.add(pixel);

      // 检测连续相同像素
      if (i >= 2) {
        final prevPixel = (rgb565Data[i - 2] << 8) | rgb565Data[i - 1];
        if (pixel == prevPixel) {
          consecutiveCount++;
        }
      }
    }

    final uniqueColors = colorSet.length;
    final complexity = uniqueColors / totalPixels;
    final hasLargeUniformAreas = consecutiveCount > totalPixels * 0.3;

    // 预估压缩率
    double estimatedRatio;
    if (hasLargeUniformAreas) {
      estimatedRatio = 0.8; // 80%压缩率
    } else if (uniqueColors < 256) {
      estimatedRatio = 0.6; // 60%压缩率
    } else {
      estimatedRatio = 0.4; // 40%压缩率
    }

    return ImageFeatures(
      uniqueColors: uniqueColors,
      complexity: complexity,
      hasLargeUniformAreas: hasLargeUniformAreas,
      estimatedCompressionRatio: estimatedRatio,
    );
  }
}
