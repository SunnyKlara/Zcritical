import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 处理后的图片结果
class ProcessedImageResult {
  /// RGB565格式的图片数据
  final Uint8List rgb565Data;

  /// 图片宽度
  final int width;

  /// 图片高度
  final int height;

  /// CRC32校验和
  final int crc32;

  /// 是否为圆形裁剪
  final bool isCircular;

  /// 处理时间戳
  final DateTime timestamp;

  /// 原始图片（用于预览）
  final img.Image? previewImage;

  ProcessedImageResult({
    required this.rgb565Data,
    required this.width,
    required this.height,
    required this.crc32,
    required this.isCircular,
    required this.timestamp,
    this.previewImage,
  });

  /// 数据大小（字节）
  int get dataSize => rgb565Data.length;

  /// 验证数据大小是否正确
  bool get isValidSize => dataSize == width * height * 2;
}

/// 增强的图片预处理器
/// 负责高质量图片处理，包括中心裁剪、高质量缩放、圆形裁剪和RGB565转换
class EnhancedImagePreprocessor {
  /// 目标尺寸常量
  static const int targetSize = 240;

  /// 预期的RGB565数据大小
  static const int expectedDataSize = targetSize * targetSize * 2; // 115200 bytes

  /// 预处理图片
  ///
  /// 处理流程:
  /// 1. 加载图片
  /// 2. 中心裁剪为正方形
  /// 3. 高质量缩放到240x240
  /// 4. 可选锐化增强
  /// 5. 圆形裁剪
  /// 6. 转换为RGB565
  Future<ProcessedImageResult> processImage(
    Uint8List imageBytes, {
    bool enableSharpening = true,
    bool enableCircularCrop = true,
  }) async {
    // 1. 解码图片
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('无法解码图片');
    }

    // 2. 中心裁剪为正方形
    var processed = cropToSquare(image);

    // 3. 高质量缩放到目标尺寸
    processed = highQualityResize(processed, targetSize);

    // 4. 可选锐化增强
    if (enableSharpening) {
      processed = applySharpen(processed);
    }

    // 保存预览图片（圆形裁剪前）
    final previewBeforeCircle = img.Image.from(processed);

    // 5. 圆形裁剪
    if (enableCircularCrop) {
      processed = cropToCircle(processed);
    }

    // 6. 转换为RGB565
    final rgb565Data = convertToRGB565(processed);

    // 7. 计算CRC32
    final crc32 = calculateCRC32(rgb565Data);

    return ProcessedImageResult(
      rgb565Data: rgb565Data,
      width: targetSize,
      height: targetSize,
      crc32: crc32,
      isCircular: enableCircularCrop,
      timestamp: DateTime.now(),
      previewImage: enableCircularCrop ? processed : previewBeforeCircle,
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

  /// 高质量缩放
  /// 使用Cubic插值算法进行高质量缩放
  img.Image highQualityResize(img.Image image, int targetSize) {
    // 如果已经是目标尺寸，直接返回
    if (image.width == targetSize && image.height == targetSize) {
      return image;
    }

    // 计算缩放比例
    final scale = targetSize / image.width;

    // 对于大幅缩小（超过4倍），分步缩放以保持质量
    if (scale < 0.25) {
      // 分步缩放
      var result = image;
      while (result.width > targetSize * 2) {
        final newSize = result.width ~/ 2;
        result = img.copyResize(
          result,
          width: newSize,
          height: newSize,
          interpolation: img.Interpolation.cubic,
        );
      }
      // 最后一步缩放到目标尺寸
      return img.copyResize(
        result,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.cubic,
      );
    }

    // 正常缩放
    return img.copyResize(
      image,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.cubic,
    );
  }

  /// 锐化增强
  /// 应用轻度锐化以增强图片清晰度
  img.Image applySharpen(img.Image image, {double strength = 0.3}) {
    // 使用image包的卷积滤镜实现锐化
    // 锐化核心矩阵
    final kernel = [
      0.0, -strength, 0.0,
      -strength, 1.0 + 4 * strength, -strength,
      0.0, -strength, 0.0,
    ];

    return img.convolution(image, filter: kernel);
  }

  /// 圆形裁剪
  /// 将圆形外部区域设置为黑色
  img.Image cropToCircle(img.Image image) {
    final width = image.width;
    final height = image.height;
    final centerX = width / 2;
    final centerY = height / 2;
    final radius = math.min(width, height) / 2;

    // 创建新图片
    final result = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // 计算到中心的距离
        final dx = x - centerX;
        final dy = y - centerY;
        final distance = math.sqrt(dx * dx + dy * dy);

        if (distance <= radius) {
          // 在圆形内部，保持原像素
          result.setPixel(x, y, image.getPixel(x, y));
        } else {
          // 在圆形外部，设置为黑色
          result.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }

    return result;
  }

  /// 转换为RGB565格式
  /// RGB565格式: R(5位) G(6位) B(5位)
  /// 使用大端序（MSB First）存储
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

        // 写入buffer (大端序：高位在前)
        buffer[offset++] = (rgb565 >> 8) & 0xFF;
        buffer[offset++] = rgb565 & 0xFF;
      }
    }

    return buffer;
  }

  /// RGB565转回RGB（用于测试往返一致性）
  /// 返回 [r, g, b] 数组
  static List<int> rgb565ToRgb(int rgb565) {
    final r5 = (rgb565 >> 11) & 0x1F;
    final g6 = (rgb565 >> 5) & 0x3F;
    final b5 = rgb565 & 0x1F;

    // 扩展回8位
    final r = (r5 << 3) | (r5 >> 2);
    final g = (g6 << 2) | (g6 >> 4);
    final b = (b5 << 3) | (b5 >> 2);

    return [r, g, b];
  }

  /// 计算CRC32校验和
  int calculateCRC32(Uint8List data) {
    const List<int> crc32Table = [
      0x00000000, 0x77073096, 0xEE0E612C, 0x990951BA,
      0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
      0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988,
      0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
      0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE,
      0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
      0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC,
      0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
      0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172,
      0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
      0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940,
      0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
      0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116,
      0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
      0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924,
      0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
      0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A,
      0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
      0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818,
      0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
      0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E,
      0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
      0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C,
      0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
      0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2,
      0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
      0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0,
      0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
      0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086,
      0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
      0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4,
      0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
      0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A,
      0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
      0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8,
      0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
      0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE,
      0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
      0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC,
      0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
      0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252,
      0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
      0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60,
      0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
      0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236,
      0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
      0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04,
      0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
      0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A,
      0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
      0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38,
      0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
      0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E,
      0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
      0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C,
      0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
      0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2,
      0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
      0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0,
      0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
      0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6,
      0xBAD03605, 0xCDD706B3, 0x54DE5729, 0x23D967BF,
      0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94,
      0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
    ];

    int crc = 0xFFFFFFFF;
    for (int i = 0; i < data.length; i++) {
      crc = (crc >> 8) ^ crc32Table[(crc ^ data[i]) & 0xFF];
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// 生成测试图片
  /// 用于E2E测试
  static img.Image generateTestImage({
    required TestImageType type,
    int size = 240,
  }) {
    final image = img.Image(width: size, height: size);

    switch (type) {
      case TestImageType.solidRed:
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            image.setPixelRgba(x, y, 255, 0, 0, 255);
          }
        }
        break;

      case TestImageType.solidGreen:
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            image.setPixelRgba(x, y, 0, 255, 0, 255);
          }
        }
        break;

      case TestImageType.solidBlue:
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            image.setPixelRgba(x, y, 0, 0, 255, 255);
          }
        }
        break;

      case TestImageType.gradient:
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final r = (x * 255 ~/ size);
            final g = (y * 255 ~/ size);
            final b = ((x + y) * 255 ~/ (size * 2));
            image.setPixelRgba(x, y, r, g, b, 255);
          }
        }
        break;

      case TestImageType.checkerboard:
        const blockSize = 30;
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final isWhite = ((x ~/ blockSize) + (y ~/ blockSize)) % 2 == 0;
            if (isWhite) {
              image.setPixelRgba(x, y, 255, 255, 255, 255);
            } else {
              image.setPixelRgba(x, y, 0, 0, 0, 255);
            }
          }
        }
        break;
    }

    return image;
  }
}

/// 测试图片类型
enum TestImageType {
  solidRed,      // 纯红色
  solidGreen,    // 纯绿色
  solidBlue,     // 纯蓝色
  gradient,      // 渐变色
  checkerboard,  // 棋盘格
}
