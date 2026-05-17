import 'package:flutter/material.dart';

/// 用户自定义颜色预设
///
/// 与 [LEDPreset]（data/led_presets.dart）的数据模型对齐，但所有字段可变 + 带 UUID/创建时间，
/// 用于持久化到 SharedPreferences。
///
/// - `type='solid'` 时 `color1 == color2`，两条灯条同色
/// - `type='gradient'` 时 `color1`(主) 用于左侧灯带 L/M，`color2`(副) 用于右侧灯带 R/B
///
/// 这与 ESP32 协议 `LED:strip:r:g:b` 配合：
///   strip 1 (M) = color1, strip 2 (L) = color1, strip 3 (R) = color2, strip 4 (B) = color2
class CustomPreset {
  final String id;
  final String type; // 'solid' | 'gradient'
  final int r1;
  final int g1;
  final int b1;
  final int r2;
  final int g2;
  final int b2;
  final int createdAtMs; // 创建时间戳（毫秒），用于排序与稳定 key

  const CustomPreset({
    required this.id,
    required this.type,
    required this.r1,
    required this.g1,
    required this.b1,
    required this.r2,
    required this.g2,
    required this.b2,
    required this.createdAtMs,
  });

  bool get isSolid => type == 'solid';

  Color get color1 => Color.fromARGB(255, r1, g1, b1);
  Color get color2 => Color.fromARGB(255, r2, g2, b2);

  /// 用于胶囊 UI 渲染的展示色（与现有预设的 displayColor 等价）
  Color get displayColor => color1;

  /// 拷贝并修改部分字段
  CustomPreset copyWith({
    String? type,
    int? r1,
    int? g1,
    int? b1,
    int? r2,
    int? g2,
    int? b2,
  }) {
    return CustomPreset(
      id: id,
      type: type ?? this.type,
      r1: r1 ?? this.r1,
      g1: g1 ?? this.g1,
      b1: b1 ?? this.b1,
      r2: r2 ?? this.r2,
      g2: g2 ?? this.g2,
      b2: b2 ?? this.b2,
      createdAtMs: createdAtMs,
    );
  }

  /// 序列化为 Map，准备 JSON 编码
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'r1': r1,
        'g1': g1,
        'b1': b1,
        'r2': r2,
        'g2': g2,
        'b2': b2,
        'createdAtMs': createdAtMs,
      };

  static CustomPreset fromJson(Map<String, dynamic> json) {
    return CustomPreset(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'solid',
      r1: (json['r1'] as num?)?.toInt().clamp(0, 255) ?? 0,
      g1: (json['g1'] as num?)?.toInt().clamp(0, 255) ?? 0,
      b1: (json['b1'] as num?)?.toInt().clamp(0, 255) ?? 0,
      r2: (json['r2'] as num?)?.toInt().clamp(0, 255) ?? 0,
      g2: (json['g2'] as num?)?.toInt().clamp(0, 255) ?? 0,
      b2: (json['b2'] as num?)?.toInt().clamp(0, 255) ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 转成与 ledPresetMaps 兼容的 Map（用于胶囊 UI 复用现有渲染逻辑）
  Map<String, dynamic> toCapsuleMap() {
    if (isSolid) {
      return {
        'kind': 'custom',
        'customId': id,
        'type': 'solid',
        'color': color1,
        'led2': {'r': r1, 'g': g1, 'b': b1},
        'led3': {'r': r1, 'g': g1, 'b': b1},
      };
    }
    return {
      'kind': 'custom',
      'customId': id,
      'type': 'gradient',
      'colors': [color1, color2],
      'led2': {'r': r1, 'g': g1, 'b': b1},
      'led3': {'r': r2, 'g': g2, 'b': b2},
    };
  }
}
