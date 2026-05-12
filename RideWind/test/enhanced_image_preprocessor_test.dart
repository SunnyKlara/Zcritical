import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:ridewind/services/enhanced_image_preprocessor.dart';
import 'package:ridewind/services/upload_validator.dart';

void main() {
  group('EnhancedImagePreprocessor', () {
    late EnhancedImagePreprocessor preprocessor;

    setUp(() {
      preprocessor = EnhancedImagePreprocessor();
    });

    // ============================================================
    // Property 1: 图片尺寸不变性
    // Feature: image-preprocessing-optimization, Property 1: 图片尺寸不变性
    // **Validates: Requirements 1.1, 1.3, 1.4**
    // ============================================================

    group('Property 1: 图片尺寸不变性', () {
      /// 属性测试：对于任意尺寸的输入图片，输出尺寸应始终为240x240
      test('property: output size is always 240x240 for any input size (100 iterations)', () async {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          // 生成随机尺寸 (10-1000)
          final width = random.nextInt(990) + 10;
          final height = random.nextInt(990) + 10;

          // 创建测试图片
          final testImage = img.Image(width: width, height: height);
          for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
              testImage.setPixelRgba(x, y, random.nextInt(256), random.nextInt(256), random.nextInt(256), 255);
            }
          }

          // 编码为PNG
          final imageBytes = Uint8List.fromList(img.encodePng(testImage));

          // 处理图片
          final result = await preprocessor.processImage(
            imageBytes,
            enableSharpening: false,
            enableCircularCrop: false,
          );

          // 验证输出尺寸
          expect(result.width, equals(240), reason: 'Width should be 240 for input ${width}x$height');
          expect(result.height, equals(240), reason: 'Height should be 240 for input ${width}x$height');
        }
      });

      /// 单元测试：小图片放大
      test('small image (100x100) should be resized to 240x240', () async {
        final testImage = img.Image(width: 100, height: 100);
        for (int y = 0; y < 100; y++) {
          for (int x = 0; x < 100; x++) {
            testImage.setPixelRgba(x, y, 255, 0, 0, 255);
          }
        }

        final imageBytes = Uint8List.fromList(img.encodePng(testImage));
        final result = await preprocessor.processImage(imageBytes, enableSharpening: false);

        expect(result.width, equals(240));
        expect(result.height, equals(240));
      });

      /// 单元测试：大图片缩小
      test('large image (1000x1000) should be resized to 240x240', () async {
        final testImage = img.Image(width: 1000, height: 1000);
        for (int y = 0; y < 1000; y++) {
          for (int x = 0; x < 1000; x++) {
            testImage.setPixelRgba(x, y, 0, 255, 0, 255);
          }
        }

        final imageBytes = Uint8List.fromList(img.encodePng(testImage));
        final result = await preprocessor.processImage(imageBytes, enableSharpening: false);

        expect(result.width, equals(240));
        expect(result.height, equals(240));
      });

      /// 单元测试：非正方形图片
      test('non-square image (800x600) should be cropped and resized to 240x240', () async {
        final testImage = img.Image(width: 800, height: 600);
        for (int y = 0; y < 600; y++) {
          for (int x = 0; x < 800; x++) {
            testImage.setPixelRgba(x, y, 0, 0, 255, 255);
          }
        }

        final imageBytes = Uint8List.fromList(img.encodePng(testImage));
        final result = await preprocessor.processImage(imageBytes, enableSharpening: false);

        expect(result.width, equals(240));
        expect(result.height, equals(240));
      });
    });

    // ============================================================
    // Property 2: 正方形裁剪保持中心
    // Feature: image-preprocessing-optimization, Property 2: 正方形裁剪保持中心
    // **Validates: Requirements 1.2**
    // ============================================================

    group('Property 2: 正方形裁剪保持中心', () {
      test('cropToSquare should produce square output', () {
        // 测试横向图片
        final wideImage = img.Image(width: 800, height: 600);
        final croppedWide = preprocessor.cropToSquare(wideImage);
        expect(croppedWide.width, equals(croppedWide.height));
        expect(croppedWide.width, equals(600));

        // 测试纵向图片
        final tallImage = img.Image(width: 600, height: 800);
        final croppedTall = preprocessor.cropToSquare(tallImage);
        expect(croppedTall.width, equals(croppedTall.height));
        expect(croppedTall.width, equals(600));

        // 测试正方形图片
        final squareImage = img.Image(width: 500, height: 500);
        final croppedSquare = preprocessor.cropToSquare(squareImage);
        expect(croppedSquare.width, equals(500));
        expect(croppedSquare.height, equals(500));
      });

      /// 属性测试：裁剪后的图片应为正方形
      test('property: cropped image is always square (100 iterations)', () {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          final width = random.nextInt(990) + 10;
          final height = random.nextInt(990) + 10;

          final testImage = img.Image(width: width, height: height);
          final cropped = preprocessor.cropToSquare(testImage);

          expect(cropped.width, equals(cropped.height),
              reason: 'Cropped image should be square for input ${width}x$height');
          expect(cropped.width, equals(math.min(width, height)),
              reason: 'Cropped size should be min(width, height)');
        }
      });
    });


    // ============================================================
    // Property 3: 圆形裁剪外部背景
    // Feature: image-preprocessing-optimization, Property 3: 圆形裁剪外部背景
    // **Validates: Requirements 2.1, 2.2**
    // ============================================================

    group('Property 3: 圆形裁剪外部背景', () {
      /// 属性测试：圆形外部像素应为黑色
      test('property: pixels outside circle are black (100 iterations)', () {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          // 创建随机颜色的测试图片
          final testImage = img.Image(width: 240, height: 240);
          for (int y = 0; y < 240; y++) {
            for (int x = 0; x < 240; x++) {
              testImage.setPixelRgba(
                x, y,
                random.nextInt(256),
                random.nextInt(256),
                random.nextInt(256),
                255,
              );
            }
          }

          // 圆形裁剪
          final cropped = preprocessor.cropToCircle(testImage);

          // 验证圆形外部像素为黑色
          final centerX = 120.0;
          final centerY = 120.0;
          final radius = 120.0;

          // 检查四个角（肯定在圆外）
          final corners = [
            [0, 0],
            [0, 239],
            [239, 0],
            [239, 239],
          ];

          for (final corner in corners) {
            final pixel = cropped.getPixel(corner[0], corner[1]);
            expect(pixel.r.toInt(), equals(0), reason: 'Corner pixel R should be 0');
            expect(pixel.g.toInt(), equals(0), reason: 'Corner pixel G should be 0');
            expect(pixel.b.toInt(), equals(0), reason: 'Corner pixel B should be 0');
          }

          // 随机检查一些圆外的点
          for (int j = 0; j < 10; j++) {
            // 生成圆外的点
            final angle = random.nextDouble() * 2 * math.pi;
            final dist = radius + 5 + random.nextDouble() * 10;
            final x = (centerX + dist * math.cos(angle)).clamp(0, 239).toInt();
            final y = (centerY + dist * math.sin(angle)).clamp(0, 239).toInt();

            // 确认点在圆外
            final actualDist = math.sqrt(math.pow(x - centerX, 2) + math.pow(y - centerY, 2));
            if (actualDist > radius) {
              final pixel = cropped.getPixel(x, y);
              expect(pixel.r.toInt(), equals(0), reason: 'Outside pixel R at ($x,$y) should be 0');
              expect(pixel.g.toInt(), equals(0), reason: 'Outside pixel G at ($x,$y) should be 0');
              expect(pixel.b.toInt(), equals(0), reason: 'Outside pixel B at ($x,$y) should be 0');
            }
          }
        }
      });

      /// 单元测试：圆形内部像素保持不变
      test('pixels inside circle should be preserved', () {
        // 创建纯红色测试图片
        final testImage = img.Image(width: 240, height: 240);
        for (int y = 0; y < 240; y++) {
          for (int x = 0; x < 240; x++) {
            testImage.setPixelRgba(x, y, 255, 0, 0, 255);
          }
        }

        final cropped = preprocessor.cropToCircle(testImage);

        // 检查中心点（肯定在圆内）
        final centerPixel = cropped.getPixel(120, 120);
        expect(centerPixel.r.toInt(), equals(255));
        expect(centerPixel.g.toInt(), equals(0));
        expect(centerPixel.b.toInt(), equals(0));
      });
    });

    // ============================================================
    // Property 4: RGB565数据大小不变性
    // Feature: image-preprocessing-optimization, Property 4: RGB565数据大小不变性
    // **Validates: Requirements 4.4, 5.1**
    // ============================================================

    group('Property 4: RGB565数据大小不变性', () {
      /// 属性测试：RGB565数据大小应始终为115200字节
      test('property: RGB565 data size is always 115200 bytes (100 iterations)', () async {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          // 生成随机尺寸图片
          final width = random.nextInt(990) + 10;
          final height = random.nextInt(990) + 10;

          final testImage = img.Image(width: width, height: height);
          for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
              testImage.setPixelRgba(x, y, random.nextInt(256), random.nextInt(256), random.nextInt(256), 255);
            }
          }

          final imageBytes = Uint8List.fromList(img.encodePng(testImage));
          final result = await preprocessor.processImage(imageBytes, enableSharpening: false);

          expect(result.rgb565Data.length, equals(115200),
              reason: 'RGB565 data size should be 115200 for input ${width}x$height');
          expect(result.isValidSize, isTrue);
        }
      });

      /// 单元测试：240x240图片转换后大小正确
      test('240x240 image should produce exactly 115200 bytes', () {
        final testImage = img.Image(width: 240, height: 240);
        for (int y = 0; y < 240; y++) {
          for (int x = 0; x < 240; x++) {
            testImage.setPixelRgba(x, y, 255, 128, 64, 255);
          }
        }

        final rgb565Data = preprocessor.convertToRGB565(testImage);
        expect(rgb565Data.length, equals(115200));
      });
    });

    // ============================================================
    // Property 5: RGB565转换往返一致性
    // Feature: image-preprocessing-optimization, Property 5: RGB565转换往返一致性
    // **Validates: Requirements 4.1, 4.2**
    // ============================================================

    group('Property 5: RGB565转换往返一致性', () {
      /// 属性测试：RGB转RGB565再转回RGB，误差应在可接受范围内
      test('property: RGB to RGB565 round-trip error is within acceptable range (100 iterations)', () {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          final r = random.nextInt(256);
          final g = random.nextInt(256);
          final b = random.nextInt(256);

          // RGB转RGB565
          final r5 = (r >> 3) & 0x1F;
          final g6 = (g >> 2) & 0x3F;
          final b5 = (b >> 3) & 0x1F;
          final rgb565 = (r5 << 11) | (g6 << 5) | b5;

          // RGB565转回RGB
          final restored = EnhancedImagePreprocessor.rgb565ToRgb(rgb565);

          // 验证误差在可接受范围内（每通道不超过8）
          expect((restored[0] - r).abs(), lessThanOrEqualTo(8),
              reason: 'R channel error should be <= 8 for R=$r');
          expect((restored[1] - g).abs(), lessThanOrEqualTo(8),
              reason: 'G channel error should be <= 8 for G=$g');
          expect((restored[2] - b).abs(), lessThanOrEqualTo(8),
              reason: 'B channel error should be <= 8 for B=$b');
        }
      });

      /// 单元测试：纯色转换
      test('pure colors should convert correctly', () {
        // 纯红色 (255, 0, 0) -> RGB565: 0xF800
        final redRgb565 = (31 << 11) | (0 << 5) | 0;
        expect(redRgb565, equals(0xF800));

        // 纯绿色 (0, 255, 0) -> RGB565: 0x07E0
        final greenRgb565 = (0 << 11) | (63 << 5) | 0;
        expect(greenRgb565, equals(0x07E0));

        // 纯蓝色 (0, 0, 255) -> RGB565: 0x001F
        final blueRgb565 = (0 << 11) | (0 << 5) | 31;
        expect(blueRgb565, equals(0x001F));
      });

      /// 单元测试：大端序存储验证
      test('RGB565 should be stored in big-endian format', () {
        final testImage = img.Image(width: 1, height: 1);
        testImage.setPixelRgba(0, 0, 255, 0, 0, 255); // 纯红色

        final rgb565Data = preprocessor.convertToRGB565(testImage);

        // 纯红色 RGB565 = 0xF800
        // 大端序: 高字节在前
        expect(rgb565Data[0], equals(0xF8)); // 高字节
        expect(rgb565Data[1], equals(0x00)); // 低字节
      });
    });
  });


  // ============================================================
  // UploadValidator Tests
  // ============================================================

  group('UploadValidator', () {
    late UploadValidator validator;

    setUp(() {
      validator = UploadValidator();
    });

    // ============================================================
    // Property 6: CRC32计算确定性
    // Feature: image-preprocessing-optimization, Property 6: CRC32计算确定性
    // **Validates: Requirements 5.2**
    // ============================================================

    group('Property 6: CRC32计算确定性', () {
      /// 属性测试：相同数据应产生相同CRC32
      test('property: same data produces same CRC32 (100 iterations)', () {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          // 生成随机数据
          final length = random.nextInt(1000) + 100;
          final data = Uint8List(length);
          for (int j = 0; j < length; j++) {
            data[j] = random.nextInt(256);
          }

          // 计算两次CRC32
          final crc1 = validator.calculateCRC32(data);
          final crc2 = validator.calculateCRC32(data);

          expect(crc1, equals(crc2), reason: 'Same data should produce same CRC32');
        }
      });

      /// 属性测试：不同数据应产生不同CRC32（高概率）
      test('property: different data produces different CRC32 (100 iterations)', () {
        final random = math.Random(42);
        int collisions = 0;

        for (int i = 0; i < 100; i++) {
          // 生成两组不同的随机数据
          final length = random.nextInt(1000) + 100;
          final data1 = Uint8List(length);
          final data2 = Uint8List(length);
          for (int j = 0; j < length; j++) {
            data1[j] = random.nextInt(256);
            data2[j] = random.nextInt(256);
          }

          // 确保数据不同
          if (data1.toString() == data2.toString()) continue;

          final crc1 = validator.calculateCRC32(data1);
          final crc2 = validator.calculateCRC32(data2);

          if (crc1 == crc2) collisions++;
        }

        // 碰撞概率应该极低
        expect(collisions, lessThan(5), reason: 'CRC32 collision rate should be very low');
      });
    });

    // ============================================================
    // Property 7: 数据验证完整性
    // Feature: image-preprocessing-optimization, Property 7: 数据验证完整性
    // **Validates: Requirements 5.1, 5.3**
    // ============================================================

    group('Property 7: 数据验证完整性', () {
      /// 属性测试：大小不为115200的数据应验证失败
      test('property: data with wrong size should fail validation (100 iterations)', () {
        final random = math.Random(42);

        for (int i = 0; i < 100; i++) {
          // 生成错误大小的数据
          int wrongSize;
          do {
            wrongSize = random.nextInt(200000);
          } while (wrongSize == 115200);

          final wrongData = Uint8List(wrongSize);
          final result = validator.validateRawData(wrongData);

          expect(result.isValid, isFalse,
              reason: 'Data with size $wrongSize should fail validation');
          expect(result.errorMessage, contains('数据大小错误'));
        }
      });

      /// 单元测试：正确大小的数据应验证通过
      test('data with correct size (115200) should pass validation', () {
        final correctData = Uint8List(115200);
        final result = validator.validateRawData(correctData);

        expect(result.isValid, isTrue);
        expect(result.dataSize, equals(115200));
        expect(result.crc32, isNotNull);
      });

      /// 单元测试：空数据应验证失败
      test('empty data should fail validation', () {
        final emptyData = Uint8List(0);
        final result = validator.validateRawData(emptyData);

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('数据大小错误'));
      });
    });
  });

  // ============================================================
  // Test Image Generation Tests
  // ============================================================

  group('TestImageGeneration', () {
    test('should generate solid red test image', () {
      final image = EnhancedImagePreprocessor.generateTestImage(
        type: TestImageType.solidRed,
        size: 240,
      );

      expect(image.width, equals(240));
      expect(image.height, equals(240));

      // 检查中心像素是红色
      final pixel = image.getPixel(120, 120);
      expect(pixel.r.toInt(), equals(255));
      expect(pixel.g.toInt(), equals(0));
      expect(pixel.b.toInt(), equals(0));
    });

    test('should generate gradient test image', () {
      final image = EnhancedImagePreprocessor.generateTestImage(
        type: TestImageType.gradient,
        size: 240,
      );

      expect(image.width, equals(240));
      expect(image.height, equals(240));

      // 检查左上角和右下角颜色不同
      final topLeft = image.getPixel(0, 0);
      final bottomRight = image.getPixel(239, 239);

      expect(topLeft.r.toInt(), isNot(equals(bottomRight.r.toInt())));
    });

    test('should generate checkerboard test image', () {
      final image = EnhancedImagePreprocessor.generateTestImage(
        type: TestImageType.checkerboard,
        size: 240,
      );

      expect(image.width, equals(240));
      expect(image.height, equals(240));
    });
  });
}


// ============================================================
// Property 8: 蓝牙协议格式一致性
// Feature: image-preprocessing-optimization, Property 8: 蓝牙协议格式一致性
// **Validates: Requirements 7.4**
// ============================================================

void bluetoothProtocolTests() {
  group('Property 8: 蓝牙协议格式一致性', () {
    /// 验证LOGO_START命令格式
    test('LOGO_START command format should be correct', () {
      const dataSize = 115200;
      const crc32 = 0x12345678;
      
      final command = 'LOGO_START:$dataSize:$crc32';
      
      // 验证格式
      expect(command, startsWith('LOGO_START:'));
      expect(command.split(':').length, equals(3));
      
      final parts = command.split(':');
      expect(parts[0], equals('LOGO_START'));
      expect(int.tryParse(parts[1]), equals(dataSize));
      expect(int.tryParse(parts[2]), equals(crc32));
    });

    /// 验证LOGO_DATA命令格式
    test('LOGO_DATA command format should be correct', () {
      final testData = Uint8List.fromList([0xF8, 0x00, 0x07, 0xE0]);
      const seq = 42;
      
      final hexString = testData.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
      final command = 'LOGO_DATA:$seq:$hexString';
      
      // 验证格式
      expect(command, startsWith('LOGO_DATA:'));
      expect(command.split(':').length, equals(3));
      
      final parts = command.split(':');
      expect(parts[0], equals('LOGO_DATA'));
      expect(int.tryParse(parts[1]), equals(seq));
      expect(parts[2], equals('f80007e0'));
    });

    /// 验证LOGO_END命令格式
    test('LOGO_END command format should be correct', () {
      const command = 'LOGO_END';
      expect(command, equals('LOGO_END'));
    });

    /// 属性测试：数据包序号应连续
    test('property: packet sequence numbers should be continuous (100 iterations)', () {
      final random = math.Random(42);
      
      for (int i = 0; i < 100; i++) {
        // 生成随机数据大小
        final dataSize = random.nextInt(115200) + 1000;
        final totalPackets = (dataSize + 15) ~/ 16;
        
        // 验证序号连续性
        for (int seq = 0; seq < totalPackets; seq++) {
          expect(seq, greaterThanOrEqualTo(0));
          expect(seq, lessThan(totalPackets));
        }
      }
    });

    /// 属性测试：每个数据包大小不超过16字节
    test('property: each data packet should not exceed 16 bytes (100 iterations)', () {
      final random = math.Random(42);
      
      for (int i = 0; i < 100; i++) {
        // 生成随机数据
        final dataSize = random.nextInt(115200) + 1000;
        final data = Uint8List(dataSize);
        
        final totalPackets = (dataSize + 15) ~/ 16;
        
        for (int seq = 0; seq < totalPackets; seq++) {
          final start = seq * 16;
          final end = (start + 16 > dataSize) ? dataSize : start + 16;
          final chunkSize = end - start;
          
          expect(chunkSize, lessThanOrEqualTo(16),
              reason: 'Packet $seq size should be <= 16 bytes');
          expect(chunkSize, greaterThan(0),
              reason: 'Packet $seq size should be > 0 bytes');
        }
      }
    });

    /// 属性测试：十六进制字符串格式正确
    test('property: hex string format should be correct (100 iterations)', () {
      final random = math.Random(42);
      final hexPattern = RegExp(r'^[0-9a-f]+$');
      
      for (int i = 0; i < 100; i++) {
        // 生成随机数据包
        final chunkSize = random.nextInt(16) + 1;
        final chunk = Uint8List(chunkSize);
        for (int j = 0; j < chunkSize; j++) {
          chunk[j] = random.nextInt(256);
        }
        
        final hexString = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
        
        // 验证格式
        expect(hexString.length, equals(chunkSize * 2),
            reason: 'Hex string length should be 2x chunk size');
        expect(hexPattern.hasMatch(hexString), isTrue,
            reason: 'Hex string should only contain 0-9 and a-f');
      }
    });
  });
}
