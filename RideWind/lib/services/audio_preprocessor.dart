import 'dart:typed_data';
import 'dart:math';

/// WAV 转 PCM 结果
class AudioConversionResult {
  final Uint8List pcmData;
  final int originalSampleRate;
  final int originalChannels;
  final int originalBitsPerSample;

  AudioConversionResult({
    required this.pcmData,
    required this.originalSampleRate,
    required this.originalChannels,
    required this.originalBitsPerSample,
  });
}

/// 音频预处理器 — WAV → 22050Hz 单声道 8-bit signed PCM
///
/// ESP32 audio_player.c 需要的格式:
/// - 采样率: 22050 Hz
/// - 声道: 单声道 (mono)
/// - 位深: 8-bit signed (-128 to 127)
/// - 无头部，纯 raw PCM 数据
class AudioPreprocessor {
  static const int targetSampleRate = 22050;

  /// 将 WAV 文件转换为目标 PCM 格式
  static AudioConversionResult convertWavToPcm(Uint8List wavData) {
    // 解析 WAV 头
    final header = _parseWavHeader(wavData);
    if (header == null) {
      throw Exception('无效的 WAV 文件');
    }

    // 提取原始 PCM 数据
    final rawSamples = _extractSamples(
      wavData,
      header.dataOffset,
      header.dataSize,
      header.bitsPerSample,
      header.channels,
    );

    // 重采样到 22050 Hz
    final resampled = _resample(
      rawSamples,
      header.sampleRate,
      targetSampleRate,
    );

    // 转换为 8-bit signed
    final pcm8bit = _convertTo8BitSigned(resampled);

    return AudioConversionResult(
      pcmData: pcm8bit,
      originalSampleRate: header.sampleRate,
      originalChannels: header.channels,
      originalBitsPerSample: header.bitsPerSample,
    );
  }

  /// 解析 WAV 文件头
  static _WavHeader? _parseWavHeader(Uint8List data) {
    if (data.length < 44) return null;

    final bd = ByteData.sublistView(data);

    // RIFF header
    final riff = String.fromCharCodes(data.sublist(0, 4));
    if (riff != 'RIFF') return null;

    final wave = String.fromCharCodes(data.sublist(8, 12));
    if (wave != 'WAVE') return null;

    // 查找 fmt 和 data chunk
    int offset = 12;
    int sampleRate = 0;
    int channels = 0;
    int bitsPerSample = 0;
    int audioFormat = 0;
    int dataOffset = 0;
    int dataSize = 0;

    while (offset < data.length - 8) {
      final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        audioFormat = bd.getUint16(offset + 8, Endian.little);
        channels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        bitsPerSample = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }

      offset += 8 + chunkSize;
      // Align to even boundary
      if (chunkSize % 2 != 0) offset++;
    }

    if (dataOffset == 0 || sampleRate == 0) return null;

    // 支持 PCM (1) 和 IEEE float (3)
    if (audioFormat != 1 && audioFormat != 3) {
      throw Exception('不支持的 WAV 格式 (audioFormat=$audioFormat)，仅支持 PCM 和 IEEE float');
    }

    return _WavHeader(
      audioFormat: audioFormat,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }

  /// 提取采样数据为 double 数组 (归一化到 -1.0 ~ 1.0)，混合为单声道
  static List<double> _extractSamples(
    Uint8List data,
    int dataOffset,
    int dataSize,
    int bitsPerSample,
    int channels,
  ) {
    final bd = ByteData.sublistView(data);
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = bytesPerSample * channels;
    final frameCount = dataSize ~/ frameSize;
    final samples = List<double>.filled(frameCount, 0.0);

    for (int i = 0; i < frameCount; i++) {
      double sum = 0.0;
      for (int ch = 0; ch < channels; ch++) {
        final pos = dataOffset + i * frameSize + ch * bytesPerSample;
        if (pos + bytesPerSample > data.length) break;

        double sample;
        switch (bitsPerSample) {
          case 8:
            // 8-bit WAV is unsigned (0-255), center at 128
            sample = (data[pos] - 128) / 128.0;
            break;
          case 16:
            sample = bd.getInt16(pos, Endian.little) / 32768.0;
            break;
          case 24:
            final b0 = data[pos];
            final b1 = data[pos + 1];
            final b2 = data[pos + 2];
            int val = b0 | (b1 << 8) | (b2 << 16);
            if (val >= 0x800000) val -= 0x1000000;
            sample = val / 8388608.0;
            break;
          case 32:
            // Could be int32 or float32
            sample = bd.getFloat32(pos, Endian.little);
            if (sample.isNaN || sample.isInfinite) {
              // Try as int32
              sample = bd.getInt32(pos, Endian.little) / 2147483648.0;
            }
            break;
          default:
            sample = 0.0;
        }
        sum += sample;
      }
      samples[i] = sum / channels; // Mix to mono
    }

    return samples;
  }

  /// 线性插值重采样
  static List<double> _resample(
    List<double> input,
    int fromRate,
    int toRate,
  ) {
    if (fromRate == toRate) return input;

    final ratio = fromRate / toRate;
    final outputLen = (input.length / ratio).floor();
    final output = List<double>.filled(outputLen, 0.0);

    for (int i = 0; i < outputLen; i++) {
      final srcPos = i * ratio;
      final srcIdx = srcPos.floor();
      final frac = srcPos - srcIdx;

      if (srcIdx + 1 < input.length) {
        output[i] =
            input[srcIdx] * (1.0 - frac) + input[srcIdx + 1] * frac;
      } else if (srcIdx < input.length) {
        output[i] = input[srcIdx];
      }
    }

    return output;
  }

  /// 转换为 8-bit signed PCM (int8_t, -128 to 127)
  static Uint8List _convertTo8BitSigned(List<double> samples) {
    final output = Uint8List(samples.length);

    // 先找峰值做归一化，避免削波
    double peak = 0.0;
    for (final s in samples) {
      final abs = s.abs();
      if (abs > peak) peak = abs;
    }

    final scale = peak > 0.0 ? min(1.0, 0.95 / peak) : 1.0;

    for (int i = 0; i < samples.length; i++) {
      final scaled = (samples[i] * scale * 127.0).round().clamp(-128, 127);
      // Store as signed byte (Dart Uint8List stores 0-255, but the bit pattern is the same)
      output[i] = scaled & 0xFF;
    }

    return output;
  }
}

class _WavHeader {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;

  _WavHeader({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
