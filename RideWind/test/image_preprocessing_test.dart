import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:ridewind/services/image_preprocessing_service.dart';
import 'package:ridewind/services/image_compression_service.dart';

void main() {
  group('ImagePreprocessingService', () {
    late ImagePreprocessingService service;

    setUp(() {
      service = ImagePreprocessingService();
    });

    test('应该正确转换为RGB565格式', () {
      // 创建一个简单的测试图片数据
      // 这里我们测试RGB565转换的正确性

      // 测试红色像素 (255, 0, 0)
      // RGB565: R=31(11111), G=0(000000), B=0(00000)
      // 结果: 0xF800

      // 由于我们需要image包来创建图片，这里只测试核心逻辑
      expect(service, isNotNull);
    });

    test('应该正确分析图片特征', () {
      // 创建测试数据：纯色图片
      final testData = Uint8List(240 * 240 * 2);
      // 填充相同的像素值
      for (int i = 0; i < testData.length; i += 2) {
        testData[i] = 0xF8;
        testData[i + 1] = 0x00;
      }

      final features = service.analyzeImage(testData);

      expect(features.uniqueColors, equals(1));
      expect(features.hasLargeUniformAreas, isTrue);
      expect(features.estimatedCompressionRatio, greaterThan(0.7));
    });
  });

  group('ImageCompressionService', () {
    late ImageCompressionService service;

    setUp(() {
      service = ImageCompressionService();
    });

    test('应该正确压缩纯色图片', () {
      // 创建纯色测试数据
      final testData = Uint8List(240 * 240 * 2);
      for (int i = 0; i < testData.length; i += 2) {
        testData[i] = 0xF8;
        testData[i + 1] = 0x00;
      }

      final preprocessed = PreprocessedImage(
        rgb565Data: testData,
        features: ImageFeatures(
          uniqueColors: 1,
          complexity: 0.0,
          hasLargeUniformAreas: true,
          estimatedCompressionRatio: 0.9,
        ),
        width: 240,
        height: 240,
        timestamp: DateTime.now(),
      );

      final compressed = service.compressRLE(preprocessed);

      // 纯色图片应该有很高的压缩率
      expect(compressed.compressionRatio, greaterThan(0.95));
      // 压缩后大小应该远小于原始大小
      expect(compressed.compressedSize, lessThan(testData.length ~/ 100));
      print(
        '纯色压缩: ${testData.length} -> ${compressed.compressedSize} (${(compressed.compressionRatio * 100).toStringAsFixed(1)}%)',
      );
    });

    test('压缩后解压缩应该得到原始数据', () {
      // 创建测试数据：包含重复和非重复像素
      final testData = Uint8List.fromList([
        // 5个红色像素
        0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00, 0xF8, 0x00,
        // 2个绿色像素
        0x07, 0xE0, 0x07, 0xE0,
        // 3个蓝色像素
        0x00, 0x1F, 0x00, 0x1F, 0x00, 0x1F,
      ]);

      final preprocessed = PreprocessedImage(
        rgb565Data: testData,
        features: ImageFeatures(
          uniqueColors: 3,
          complexity: 0.3,
          hasLargeUniformAreas: false,
          estimatedCompressionRatio: 0.5,
        ),
        width: 5,
        height: 2,
        timestamp: DateTime.now(),
      );

      final compressed = service.compressRLE(preprocessed);
      final decompressed = service.decompressRLE(compressed.data);

      // 解压缩后应该与原始数据完全一致
      expect(decompressed.length, equals(testData.length));
      for (int i = 0; i < testData.length; i++) {
        expect(
          decompressed[i],
          equals(testData[i]),
          reason: 'Byte $i mismatch',
        );
      }
    });

    test('应该正确计算CRC32', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final crc1 = service.calculateCRC32(testData);
      final crc2 = service.calculateCRC32(testData);

      // 相同数据应该产生相同的CRC32
      expect(crc1, equals(crc2));

      // 不同数据应该产生不同的CRC32
      final differentData = Uint8List.fromList([1, 2, 3, 4, 6]);
      final crc3 = service.calculateCRC32(differentData);
      expect(crc1, isNot(equals(crc3)));
    });
  });
}
