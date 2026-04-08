import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// 固件版本信息（从 GitHub 获取）
class FirmwareInfo {
  final String version;
  final int size;
  final String downloadUrl;
  final String? changelog;

  FirmwareInfo({
    required this.version,
    required this.size,
    required this.downloadUrl,
    this.changelog,
  });

  factory FirmwareInfo.fromJson(Map<String, dynamic> json) {
    return FirmwareInfo(
      version: json['version'] as String,
      size: json['size'] as int,
      downloadUrl: json['download_url'] as String,
      changelog: json['changelog'] as String?,
    );
  }

  /// 解析版本号为可比较的整数列表 [major, minor, patch]
  List<int> get versionParts {
    final parts = version.replaceFirst('v', '').split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    ];
  }

  /// 比较版本号，返回 true 表示 this 比 other 更新
  bool isNewerThan(String otherVersion) {
    final other = otherVersion.replaceFirst('v', '').split('.');
    final otherParts = [
      int.tryParse(other.isNotEmpty ? other[0] : '0') ?? 0,
      int.tryParse(other.length > 1 ? other[1] : '0') ?? 0,
      int.tryParse(other.length > 2 ? other[2] : '0') ?? 0,
    ];
    final mine = versionParts;
    for (int i = 0; i < 3; i++) {
      if (mine[i] > otherParts[i]) return true;
      if (mine[i] < otherParts[i]) return false;
    }
    return false;
  }
}

/// 固件更新服务
///
/// 从 GitHub 仓库获取最新固件版本信息并下载固件文件。
///
/// 使用方式：
/// 1. 在 GitHub 仓库根目录放一个 firmware.json 文件
/// 2. 每次发布新固件时更新 firmware.json 的版本号和下载地址
/// 3. 把编译好的 .bin 文件作为 Release 附件上传
///
/// firmware.json 格式：
/// ```json
/// {
///   "version": "1.1.0",
///   "size": 123456,
///   "download_url": "https://github.com/你的用户名/你的仓库/releases/download/v1.1.0/firmware.bin",
///   "changelog": "修复了xxx问题，新增了xxx功能"
/// }
/// ```
class FirmwareUpdateService {
  /// GitHub 上 firmware.json 的原始文件地址
  static const String _firmwareInfoUrl =
      'https://raw.githubusercontent.com/SunnyKlara/RideWind/main/firmware.json';

  /// 检查是否有新固件版本
  ///
  /// [currentVersion] 设备当前固件版本号，格式 "1.0.0"
  /// 返回 FirmwareInfo 如果有新版本，null 如果已是最新
  static Future<FirmwareInfo?> checkForUpdate(String currentVersion) async {
    try {
      final info = await _fetchFirmwareInfo();
      if (info == null) return null;

      if (info.isNewerThan(currentVersion)) {
        return info;
      }
      return null;
    } catch (e) {
      print('[FirmwareUpdate] 检查更新失败: $e');
      return null;
    }
  }

  /// 获取最新固件信息（不比较版本）
  static Future<FirmwareInfo?> getLatestFirmwareInfo() async {
    return _fetchFirmwareInfo();
  }

  /// 从 GitHub 下载固件文件
  ///
  /// [info] 固件信息（包含下载地址）
  /// [onProgress] 下载进度回调 (0.0 - 1.0)
  /// 返回固件二进制数据
  static Future<Uint8List> downloadFirmware(
    FirmwareInfo info, {
    Function(double)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? info.size;
    final bytes = <int>[];
    int received = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(received / contentLength);
      }
    }

    final data = Uint8List.fromList(bytes);

    if (data.isEmpty) {
      throw Exception('下载的固件文件为空');
    }
    if (data.length > 960 * 1024) {
      throw Exception('固件文件过大 (${data.length} bytes)，最大支持 960KB');
    }

    return data;
  }

  /// 从 GitHub 获取 firmware.json
  static Future<FirmwareInfo?> _fetchFirmwareInfo() async {
    final response = await http.get(Uri.parse(_firmwareInfoUrl)).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('请求超时'),
    );

    if (response.statusCode != 200) {
      throw Exception('获取固件信息失败: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return FirmwareInfo.fromJson(json);
  }
}
