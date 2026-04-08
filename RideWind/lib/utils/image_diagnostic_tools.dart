import 'dart:math';
import 'dart:typed_data';

/// 图片转换诊断工具
///
/// 用于诊断和对比APP生成的RGB565数组与专业取模软件的输出
class ImageDiagnosticTools {
  /// 对比两个字节数组的差异
  ///
  /// [appOutput] APP生成的字节数组
  /// [professionalOutput] 专业取模软件生成的字节数组
  /// [maxBytes] 最多对比的字节数（默认64）
  /// [onLog] 日志回调函数
  static void compareByteArrays(
    Uint8List appOutput,
    Uint8List professionalOutput, {
    int maxBytes = 64,
    Function(String)? onLog,
  }) {
    void log(String message) {
      if (onLog != null) {
        onLog(message);
      } else {
        print(message);
      }
    }

    log('📊 字节数组对比 (前$maxBytes字节)');
    log('─' * 60);

    int differences = 0;
    final compareLength = min(
      maxBytes,
      min(appOutput.length, professionalOutput.length),
    );

    for (int i = 0; i < compareLength; i++) {
      final app = appOutput[i];
      final pro = professionalOutput[i];

      if (app != pro) {
        differences++;
        log(
          '❌ 差异 @$i: '
          'APP=0x${app.toRadixString(16).padLeft(2, '0').toUpperCase()} '
          'vs '
          '专业=0x${pro.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );
      } else if (i < 16) {
        // 前16字节总是显示
        log(
          '✅ 匹配 @$i: 0x${app.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );
      }
    }

    log('─' * 60);
    log('总差异数: $differences / $compareLength');

    if (differences == 0) {
      log('🎉 完美匹配！APP输出与专业取模软件一致！');
    } else {
      log('⚠️ 发现 $differences 处差异，需要修复转换算法');
    }
  }

  /// 生成纯色测试数组（RGB565格式，BMP倒序）
  ///
  /// [r] 红色分量 (0-255)
  /// [g] 绿色分量 (0-255)
  /// [b] 蓝色分量 (0-255)
  /// [useBMPOrder] 是否使用BMP倒序（默认true，匹配专业取模软件）
  ///
  /// 返回154x154像素的RGB565字节数组（47432字节）
  static Uint8List generateSolidColorRGB565(
    int r,
    int g,
    int b, {
    bool useBMPOrder = true,
  }) {
    const pixelCount = 154 * 154;
    final data = Uint8List(pixelCount * 2);

    // 转换为RGB565
    final r5 = (r >> 3) & 0x1F; // 5位红色
    final g6 = (g >> 2) & 0x3F; // 6位绿色
    final b5 = (b >> 3) & 0x1F; // 5位蓝色

    // 组合成16位值
    final rgb565 = (r5 << 11) | (g6 << 5) | b5;

    // 大端序填充整个数组
    for (int i = 0; i < data.length; i += 2) {
      data[i] = (rgb565 >> 8) & 0xFF; // 高字节
      data[i + 1] = rgb565 & 0xFF; // 低字节
    }

    // 注：纯色图片无论是否倒序，结果都一样
    // 但保留此参数以便将来测试渐变图案

    return data;
  }

  /// 验证RGB565编码是否正确
  ///
  /// [onLog] 日志回调函数
  static void verifyRGB565Encoding({Function(String)? onLog}) {
    void log(String message) {
      if (onLog != null) {
        onLog(message);
      } else {
        print(message);
      }
    }

    log('🧪 RGB565编码验证');
    log('─' * 60);

    // 测试用例：纯色
    final testCases = [
      {'name': '纯红', 'r': 255, 'g': 0, 'b': 0, 'expected': 0xF800},
      {'name': '纯绿', 'r': 0, 'g': 255, 'b': 0, 'expected': 0x07E0},
      {'name': '纯蓝', 'r': 0, 'g': 0, 'b': 255, 'expected': 0x001F},
      {'name': '白色', 'r': 255, 'g': 255, 'b': 255, 'expected': 0xFFFF},
      {'name': '黑色', 'r': 0, 'g': 0, 'b': 0, 'expected': 0x0000},
      {'name': '灰色', 'r': 128, 'g': 128, 'b': 128, 'expected': 0x7BEF},
    ];

    int passedTests = 0;
    for (final test in testCases) {
      final r = test['r'] as int;
      final g = test['g'] as int;
      final b = test['b'] as int;
      final expected = test['expected'] as int;

      // 计算RGB565值
      final r5 = (r >> 3) & 0x1F;
      final g6 = (g >> 2) & 0x3F;
      final b5 = (b >> 3) & 0x1F;
      final actual = (r5 << 11) | (g6 << 5) | b5;

      final actualHex =
          '0x${actual.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      final expectedHex =
          '0x${expected.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      final match = actual == expected;

      if (match) {
        passedTests++;
        log('✅ ${test['name']}: RGB($r,$g,$b) → $actualHex');
      } else {
        log('❌ ${test['name']}: RGB($r,$g,$b) → $actualHex (期望: $expectedHex)');
      }
    }

    log('─' * 60);
    log('测试结果: $passedTests/${testCases.length} 通过');

    if (passedTests == testCases.length) {
      log('🎉 所有RGB565编码测试通过！');
    } else {
      log('⚠️ 部分测试失败，RGB565编码可能有问题');
    }
  }

  /// 分析字节数组的模式
  ///
  /// 用于发现字节序、重复模式等问题
  static void analyzeBytePattern(
    Uint8List data, {
    int sampleSize = 32,
    Function(String)? onLog,
  }) {
    void log(String message) {
      if (onLog != null) {
        onLog(message);
      } else {
        print(message);
      }
    }

    log('🔍 字节模式分析');
    log('─' * 60);
    log('数据大小: ${data.length} 字节');

    // 分析前几个字节
    log('\n前$sampleSize字节:');
    for (int i = 0; i < min(sampleSize, data.length); i += 2) {
      if (i + 1 < data.length) {
        final byte1 = data[i];
        final byte2 = data[i + 1];
        final word = (byte1 << 8) | byte2;
        log(
          '  [$i-${i + 1}]: 0x${byte1.toRadixString(16).padLeft(2, '0')} '
          '0x${byte2.toRadixString(16).padLeft(2, '0')} '
          '→ 0x${word.toRadixString(16).padLeft(4, '0')}',
        );
      }
    }

    // 检测字节序
    log('\n字节序检测:');
    if (data.length >= 4) {
      final word1 = (data[0] << 8) | data[1];
      final word2 = (data[1] << 8) | data[0];
      log('  大端序解释: 0x${word1.toRadixString(16).padLeft(4, '0')}');
      log('  小端序解释: 0x${word2.toRadixString(16).padLeft(4, '0')}');
    }

    log('─' * 60);
  }

  /// 获取专业取模软件的参考数据（前64字节）
  ///
  /// 这是从 f4_26_1.1/Core/Inc/pic.h 的 gImage_tou_xiang_154_154 复制的已知正确数据
  static Uint8List getProfessionalReferenceData() {
    return Uint8List.fromList([
      0x00,
      0x20,
      0x08,
      0x61,
      0x10,
      0xA2,
      0x18,
      0xE3,
      0x21,
      0x04,
      0x21,
      0x24,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
      0x29,
      0x45,
    ]);
  }
}
