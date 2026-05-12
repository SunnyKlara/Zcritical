import 'package:flutter/material.dart';

/// LED 颜色预设配置
///
/// 14 种预设方案，与 ESP32 preset_colors.h 完全对齐。
/// 按色彩渐变排列：红→橙→金→粉→紫→蓝→青→绿→白→混色渐变。
///
/// 对应 ESP32 协议: PRESET:index\n (index=1-14)
/// 重要：修改此文件时必须同步修改 ridewind-esp/main/config/preset_colors.h
class LEDPreset {
  final String type;
  final Color? solidColor;
  final List<Color>? gradientColors;
  final int led2R, led2G, led2B;
  final int led3R, led3G, led3B;

  const LEDPreset._({
    required this.type,
    this.solidColor,
    this.gradientColors,
    required this.led2R, required this.led2G, required this.led2B,
    required this.led3R, required this.led3G, required this.led3B,
  });

  const LEDPreset.solid({
    required Color color,
    required int r, required int g, required int b,
  }) : this._(type: 'solid', solidColor: color,
    led2R: r, led2G: g, led2B: b, led3R: r, led3G: g, led3B: b);

  const LEDPreset.gradient({
    required List<Color> colors,
    required int led2R, required int led2G, required int led2B,
    required int led3R, required int led3G, required int led3B,
  }) : this._(type: 'gradient', gradientColors: colors,
    led2R: led2R, led2G: led2G, led2B: led2B,
    led3R: led3R, led3G: led3G, led3B: led3B);

  bool get isSolid => type == 'solid';
  Color get displayColor => solidColor ?? gradientColors?.first ?? Colors.white;

  Map<String, dynamic> toMap() {
    if (isSolid) {
      return {
        'type': 'solid',
        'color': solidColor,
        'led2': {'r': led2R, 'g': led2G, 'b': led2B},
        'led3': {'r': led3R, 'g': led3G, 'b': led3B},
      };
    } else {
      return {
        'type': 'gradient',
        'colors': gradientColors,
        'led2': {'r': led2R, 'g': led2G, 'b': led2B},
        'led3': {'r': led3R, 'g': led3G, 'b': led3B},
      };
    }
  }
}

/// 全部 14 种 LED 预设 — 按色彩渐变排列
///
/// 排列逻辑：暖色→冷色→中性色→渐变混色
///   1-3: 红系（纯红→橙→金）
///   4-5: 粉紫系（樱花粉→紫水晶）
///   6-7: 蓝紫系（极光紫→冰晶蓝）
///   8-9: 青绿系（薄荷→丛林绿）
///   10: 白色
///   11-14: 双色渐变（红蓝→橙蓝→紫绿→霓虹）
///
/// RGB 值与 ESP32 preset_colors.h 完全一致
const List<LEDPreset> ledPresets = [
  // ── 暖色系 ──
  // 1. Flame Red — 纯红
  LEDPreset.solid(
    color: Color(0xFFFF0000),
    r: 255, g: 0, b: 0,
  ),
  // 2. Blaze Orange — 烈焰橙（左橙右金）
  LEDPreset.gradient(
    colors: [Color(0xFFFF5000), Color(0xFFFFC832)],
    led2R: 255, led2G: 80, led2B: 0,
    led3R: 255, led3G: 200, led3B: 50,
  ),
  // 3. Racing Gold — 竞速金
  LEDPreset.solid(
    color: Color(0xFFFFD200),
    r: 255, g: 210, b: 0,
  ),

  // ── 粉紫系 ──
  // 4. Sakura Pink — 樱花粉（左粉右玫红）
  LEDPreset.gradient(
    colors: [Color(0xFFFF69B4), Color(0xFFFF0050)],
    led2R: 255, led2G: 105, led2B: 180,
    led3R: 255, led3G: 0, led3B: 80,
  ),
  // 5. Amethyst — 紫水晶
  LEDPreset.solid(
    color: Color(0xFF9400D3),
    r: 148, g: 0, b: 211,
  ),

  // ── 蓝紫系 ──
  // 6. Aurora Purple — 极光紫（左紫右青）
  LEDPreset.gradient(
    colors: [Color(0xFFB400FF), Color(0xFF00FFC8)],
    led2R: 180, led2G: 0, led2B: 255,
    led3R: 0, led3G: 255, led3B: 200,
  ),
  // 7. Ice Crystal — 冰晶蓝
  LEDPreset.solid(
    color: Color(0xFF00EAFF),
    r: 0, g: 234, b: 255,
  ),

  // ── 青绿系 ──
  // 8. Mint Breeze — 薄荷微风（左绿右蓝）
  LEDPreset.gradient(
    colors: [Color(0xFF00FFB4), Color(0xFF64C8FF)],
    led2R: 0, led2G: 255, led2B: 180,
    led3R: 100, led3G: 200, led3B: 255,
  ),
  // 9. Jungle Green — 丛林绿
  LEDPreset.solid(
    color: Color(0xFF00FF41),
    r: 0, g: 255, b: 65,
  ),

  // ── 中性色 ──
  // 10. Pure White — 纯白
  LEDPreset.solid(
    color: Color(0xFFE1E1E1),
    r: 225, g: 225, b: 225,
  ),

  // ── 双色渐变 ──
  // 11. Police Flash — 警灯红蓝
  LEDPreset.gradient(
    colors: [Color(0xFFFF0000), Color(0xFF0050FF)],
    led2R: 255, led2G: 0, led2B: 0,
    led3R: 0, led3G: 80, led3B: 255,
  ),
  // 12. Sunset Lava — 日落熔岩（左橙右蓝）
  LEDPreset.gradient(
    colors: [Color(0xFFFF6400), Color(0xFF00C8FF)],
    led2R: 255, led2G: 100, led2B: 0,
    led3R: 0, led3G: 200, led3B: 255,
  ),
  // 13. Cyber Neon — 赛博霓虹（左紫右绿）
  LEDPreset.gradient(
    colors: [Color(0xFF8A2BE2), Color(0xFF00FF80)],
    led2R: 138, led2G: 43, led2B: 226,
    led3R: 0, led3G: 255, led3B: 128,
  ),
  // 14. Neon Party — 霓虹派对（左青右品红）
  LEDPreset.gradient(
    colors: [Color(0xFF00FFFF), Color(0xFFFF00FF)],
    led2R: 0, led2G: 255, led2B: 255,
    led3R: 255, led3G: 0, led3B: 255,
  ),
];

/// 向后兼容：转换为旧版 Map 列表格式
List<Map<String, dynamic>> get ledPresetMaps =>
    ledPresets.map((p) => p.toMap()).toList();
