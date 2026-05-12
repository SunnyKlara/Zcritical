import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户偏好存储服务
/// 管理用户设置的持久化存储和恢复
/// 
/// 该服务使用 SharedPreferences 持久化存储用户的各项偏好设置，
/// 包括颜色预设、速度值、雾化器状态以及设备特定设置。
/// 
/// 使用示例:
/// ```dart
/// final service = PreferenceService();
/// 
/// // 保存颜色预设
/// await service.saveColorPreset(3);
/// 
/// // 读取颜色预设
/// final colorIndex = await service.getColorPreset();
/// 
/// // 保存设备特定设置
/// await service.saveDeviceSettings('device_123', {
///   'colorPreset': 3,
///   'speed': 100,
///   'atomizer': true,
/// });
/// ```
class PreferenceService {
  /// SharedPreferences 键：颜色预设索引
  static const String _keyColorPreset = 'last_color_preset';
  
  /// SharedPreferences 键：速度值
  static const String _keySpeedValue = 'last_speed_value';
  
  /// SharedPreferences 键：雾化器状态
  static const String _keyAtomizerState = 'last_atomizer_state';
  
  /// SharedPreferences 键前缀：设备特定设置
  static const String _keyDeviceSettings = 'device_settings_';

  /// SharedPreferences 键：自定义 RGB 颜色数据（JSON）
  static const String _keyCustomRGBColors = 'custom_rgb_colors';

  /// SharedPreferences 键：是否有自定义颜色标志位
  static const String _keyHasCustomColors = 'has_custom_colors';

  /// 保存颜色预设索引
  /// 
  /// [index] 颜色预设的索引值（通常为 0-11）
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> saveColorPreset(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyColorPreset, index);
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
    }
  }

  /// 获取上次的颜色预设索引
  /// 
  /// 返回上次保存的颜色预设索引，如果没有保存过或读取失败，返回默认值 0。
  Future<int> getColorPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyColorPreset) ?? 0;
    } catch (e) {
      // 读取失败时返回默认值
      return 0;
    }
  }

  /// 保存速度值
  /// 
  /// [speed] 速度值（通常为 0-340）
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> saveSpeedValue(int speed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySpeedValue, speed);
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
    }
  }

  /// 获取上次的速度值
  /// 
  /// 返回上次保存的速度值，如果没有保存过或读取失败，返回默认值 0。
  Future<int> getSpeedValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keySpeedValue) ?? 0;
    } catch (e) {
      // 读取失败时返回默认值
      return 0;
    }
  }

  /// 保存雾化器状态
  /// 
  /// [isOn] 雾化器开关状态，`true` 表示开启，`false` 表示关闭
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> saveAtomizerState(bool isOn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAtomizerState, isOn);
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
    }
  }

  /// 获取上次的雾化器状态
  /// 
  /// 返回上次保存的雾化器状态，如果没有保存过或读取失败，返回默认值 `false`（关闭）。
  Future<bool> getAtomizerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAtomizerState) ?? false;
    } catch (e) {
      // 读取失败时返回默认值（关闭状态）
      return false;
    }
  }

  /// 保存设备特定设置
  /// 
  /// [deviceId] 设备的唯一标识符
  /// [settings] 设备的设置数据，将被序列化为 JSON 字符串存储
  /// 
  /// 设置数据可以包含任意键值对，例如：
  /// ```dart
  /// {
  ///   'colorPreset': 3,
  ///   'speed': 100,
  ///   'atomizer': true,
  ///   'brightness': 80,
  /// }
  /// ```
  /// 
  /// 如果写入失败，会静默处理错误，不会影响应用正常运行。
  Future<void> saveDeviceSettings(String deviceId, Map<String, dynamic> settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyDeviceSettings$deviceId', jsonEncode(settings));
    } catch (e) {
      // 写入失败时静默处理，不影响用户操作
    }
  }

  /// 获取设备特定设置
  /// 
  /// [deviceId] 设备的唯一标识符
  /// 
  /// 返回该设备之前保存的设置数据，如果没有保存过或读取失败，返回 `null`。
  /// 
  /// 返回的 Map 包含之前保存的所有设置键值对。
  Future<Map<String, dynamic>?> getDeviceSettings(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_keyDeviceSettings$deviceId');
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // 读取或解析失败时返回 null
      return null;
    }
  }

  /// 清除设备特定设置
  /// 
  /// [deviceId] 设备的唯一标识符
  /// 
  /// 删除该设备的所有保存设置。主要用于：
  /// - 用户手动重置设备设置
  /// - 设备解绑时清理数据
  /// 
  /// 如果删除失败，会静默处理错误。
  Future<void> clearDeviceSettings(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyDeviceSettings$deviceId');
    } catch (e) {
      // 删除失败时静默处理
    }
  }

  /// 保存自定义 RGB 颜色数据
  ///
  /// [zoneColors] 区域颜色映射，键为区域标识（L/M/R/B），
  /// 值为包含 r、g、b 键的颜色值映射。
  ///
  /// 数据将被序列化为 JSON 字符串存储到 SharedPreferences。
  /// 如果写入失败，会静默处理错误。
  Future<void> saveCustomRGBColors(Map<String, Map<String, int>> zoneColors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomRGBColors, jsonEncode(zoneColors));
    } catch (e) {
      // 写入失败时静默处理
    }
  }

  /// 获取已保存的自定义 RGB 颜色数据
  ///
  /// 返回区域颜色映射，键为区域标识（L/M/R/B），值为 RGB 颜色值映射。
  /// RGB 值使用 `clamp(0, 255)` 约束在有效范围内。
  /// 如果没有保存过、数据损坏或读取失败，返回 `null`。
  Future<Map<String, Map<String, int>>?> getCustomRGBColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyCustomRGBColors);
      if (json == null) return null;

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final result = <String, Map<String, int>>{};
      for (final entry in decoded.entries) {
        final colorMap = entry.value as Map<String, dynamic>;
        result[entry.key] = {
          'r': (colorMap['r'] as num).toInt().clamp(0, 255),
          'g': (colorMap['g'] as num).toInt().clamp(0, 255),
          'b': (colorMap['b'] as num).toInt().clamp(0, 255),
        };
      }
      return result;
    } catch (e) {
      // 解析失败时清除损坏的数据并返回 null
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyCustomRGBColors);
      } catch (_) {}
      return null;
    }
  }

  /// 清除已保存的自定义 RGB 颜色数据
  ///
  /// 同时清除颜色数据和颜色来源标志位。
  /// 如果删除失败，会静默处理错误。
  Future<void> clearCustomRGBColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCustomRGBColors);
      await prefs.remove(_keyHasCustomColors);
    } catch (e) {
      // 删除失败时静默处理
    }
  }

  /// 保存颜色来源标志位
  ///
  /// [value] `true` 表示当前使用自定义颜色，`false` 表示使用预设颜色
  Future<void> saveHasCustomColors(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasCustomColors, value);
    } catch (e) {
      // 写入失败时静默处理
    }
  }

  /// 获取颜色来源标志位
  ///
  /// 返回 `true` 表示当前使用自定义颜色，`false` 表示使用预设颜色。
  /// 如果没有保存过或读取失败，返回默认值 `false`。
  Future<bool> getHasCustomColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyHasCustomColors) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 重置所有用户偏好（用于测试和调试）
  /// 
  /// 清除所有偏好相关的持久化数据，包括：
  /// - 颜色预设索引
  /// - 速度值
  /// - 雾化器状态
  /// 
  /// 注意：此方法不会清除设备特定设置，如需清除请使用 `clearDeviceSettings`。
  /// 
  /// 如果清除失败，会静默处理错误。
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyColorPreset);
      await prefs.remove(_keySpeedValue);
      await prefs.remove(_keyAtomizerState);
      await prefs.remove(_keyCustomRGBColors);
      await prefs.remove(_keyHasCustomColors);
    } catch (e) {
      // 重置失败时静默处理
    }
  }
}
