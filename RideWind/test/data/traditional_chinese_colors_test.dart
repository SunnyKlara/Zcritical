import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/data/traditional_chinese_colors.dart';

void main() {
  group('ChineseColor', () {
    test('toColor returns correct ARGB color', () {
      const color = ChineseColor(
        name: '朱砂',
        r: 255,
        g: 46,
        b: 0,
        family: 'red',
      );
      expect(color.toColor(), equals(const Color.fromARGB(255, 255, 46, 0)));
    });

    test('textColor returns darker variant for bright colors', () {
      // White: very high lightness → should return a darker variant
      const bright = ChineseColor(
        name: '白',
        r: 255,
        g: 255,
        b: 255,
        family: 'neutral',
      );
      final tc = bright.textColor;
      // Should be a dark color (low luminance) for readability on bright bg
      final lum = 0.299 * tc.red + 0.587 * tc.green + 0.114 * tc.blue;
      expect(lum, lessThan(128));
    });

    test('textColor returns lighter variant for dark colors', () {
      // Black: very low lightness → should return a lighter variant
      const dark = ChineseColor(
        name: '黑',
        r: 0,
        g: 0,
        b: 0,
        family: 'neutral',
      );
      final tc = dark.textColor;
      // Should be a light color (high luminance) for readability on dark bg
      final lum = 0.299 * tc.red + 0.587 * tc.green + 0.114 * tc.blue;
      expect(lum, greaterThan(128));
    });

    test('textColor for mid-gray returns darker variant', () {
      const boundary = ChineseColor(
        name: '中灰',
        r: 128,
        g: 128,
        b: 128,
        family: 'neutral',
      );
      // HSL lightness of (128,128,128) ≈ 0.502, which is < 0.55
      // so it should return a lighter variant
      final tc = boundary.textColor;
      final lum = 0.299 * tc.red + 0.587 * tc.green + 0.114 * tc.blue;
      expect(lum, greaterThan(128));
    });

    test('textColor for colored block preserves hue', () {
      // A saturated red
      const red = ChineseColor(
        name: '朱砂',
        r: 200,
        g: 30,
        b: 30,
        family: 'red',
      );
      final tc = red.textColor;
      final hsl = HSLColor.fromColor(tc);
      final origHsl = HSLColor.fromColor(red.toColor());
      // Hue should be preserved (same color family)
      expect((hsl.hue - origHsl.hue).abs(), lessThan(1.0));
    });

    test('stores all fields correctly', () {
      const color = ChineseColor(
        name: '胭脂',
        r: 157,
        g: 41,
        b: 51,
        family: 'red',
      );
      expect(color.name, '胭脂');
      expect(color.r, 157);
      expect(color.g, 41);
      expect(color.b, 51);
      expect(color.family, 'red');
    });
  });

  group('ColorFamily', () {
    test('stores all fields correctly', () {
      const family = ColorFamily(
        id: 'red',
        name: '红色系',
        colors: [
          ChineseColor(name: '朱砂', r: 255, g: 46, b: 0, family: 'red'),
          ChineseColor(name: '胭脂', r: 157, g: 41, b: 51, family: 'red'),
        ],
      );
      expect(family.id, 'red');
      expect(family.name, '红色系');
      expect(family.colors.length, 2);
      expect(family.colors[0].name, '朱砂');
      expect(family.colors[1].name, '胭脂');
    });

    test('can be constructed with empty colors list', () {
      const family = ColorFamily(
        id: 'empty',
        name: '空色系',
        colors: [],
      );
      expect(family.colors, isEmpty);
    });
  });
}
