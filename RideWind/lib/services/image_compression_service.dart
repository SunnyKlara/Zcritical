import 'dart:typed_data';
import 'image_preprocessing_service.dart';

/// 压缩后的图片数据
class CompressedImage {
  final Uint8List data;
  final int originalSize;
  final int compressedSize;
  final double compressionRatio;
  final int crc32;
  final DateTime timestamp;

  CompressedImage({
    required this.data,
    required this.originalSize,
    required this.compressedSize,
    required this.compressionRatio,
    required this.crc32,
    required this.timestamp,
  });

  /// 节省的字节数
  int get savedBytes => originalSize - compressedSize;

  /// 压缩率百分比
  double get compressionPercentage => compressionRatio * 100;
}

/// 图片压缩服务
/// 使用RLE(Run-Length Encoding)算法压缩图片数据
class ImageCompressionService {
  /// RLE压缩
  ///
  /// 压缩格式（与硬件端一致）:
  /// - 原始块: 0xxxxxxx dd dd ... (高位=0, 低7位=像素数-1, 后跟原始数据)
  /// - 压缩块: 1xxxxxxx vv vv (高位=1, 低7位=重复次数-1, 后跟2字节RGB565)
  CompressedImage compressRLE(PreprocessedImage image) {
    final rgb565Data = image.rgb565Data;
    final compressed = <int>[];
    int i = 0;

    while (i < rgb565Data.length) {
      // 读取当前像素
      final pixel = (rgb565Data[i] << 8) | rgb565Data[i + 1];

      // 计算重复次数
      int count = 1;
      while (i + count * 2 < rgb565Data.length && count < 128) {
        final nextPixel =
            (rgb565Data[i + count * 2] << 8) | rgb565Data[i + count * 2 + 1];
        if (nextPixel != pixel) break;
        count++;
      }

      // 判断是否使用RLE压缩
      if (count >= 3) {
        // 重复3次以上,使用RLE压缩
        // 格式: 1xxxxxxx vv vv
        compressed.add(0x80 | (count - 1)); // 高位=1, 低7位=count-1
        compressed.add((pixel >> 8) & 0xFF);
        compressed.add(pixel & 0xFF);
        i += count * 2;
      } else {
        // 重复次数少,使用原始数据
        // 格式: 0xxxxxxx dd dd ...
        compressed.add(count - 1); // 高位=0, 低7位=count-1
        for (int j = 0; j < count; j++) {
          compressed.add(rgb565Data[i + j * 2]);
          compressed.add(rgb565Data[i + j * 2 + 1]);
        }
        i += count * 2;
      }
    }

    final compressedData = Uint8List.fromList(compressed);
    // CRC32应该是原始数据的CRC，不是压缩数据的
    final crc32 = calculateCRC32(rgb565Data);

    return CompressedImage(
      data: compressedData,
      originalSize: rgb565Data.length,
      compressedSize: compressedData.length,
      compressionRatio: 1.0 - (compressedData.length / rgb565Data.length),
      crc32: crc32,
      timestamp: DateTime.now(),
    );
  }

  /// RLE解压缩(用于验证)
  Uint8List decompressRLE(Uint8List compressedData) {
    final decompressed = <int>[];
    int i = 0;

    while (i < compressedData.length) {
      final header = compressedData[i++];

      if ((header & 0x80) != 0) {
        // RLE压缩块: 1xxxxxxx vv vv
        final count = (header & 0x7F) + 1;
        final pixelHigh = compressedData[i++];
        final pixelLow = compressedData[i++];

        for (int j = 0; j < count; j++) {
          decompressed.add(pixelHigh);
          decompressed.add(pixelLow);
        }
      } else {
        // 原始数据块: 0xxxxxxx dd dd ...
        final count = (header & 0x7F) + 1;
        for (int j = 0; j < count; j++) {
          decompressed.add(compressedData[i++]);
          decompressed.add(compressedData[i++]);
        }
      }
    }

    return Uint8List.fromList(decompressed);
  }

  /// 计算CRC32校验
  int calculateCRC32(Uint8List data) {
    const polynomial = 0xEDB88320;
    int crc = 0xFFFFFFFF;

    for (final byte in data) {
      crc ^= byte;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ polynomial;
        } else {
          crc = crc >> 1;
        }
      }
    }

    return ~crc & 0xFFFFFFFF;
  }
}
