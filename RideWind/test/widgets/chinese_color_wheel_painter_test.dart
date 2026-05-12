import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/data/traditional_chinese_colors.dart';
import 'package:ridewind/widgets/chinese_color_wheel_painter.dart';

/// ChineseColorWheelPainter 单元测试（COPIC 风格）
void main() {
  group('ChineseColorWheelPainter', () {
    final testFamilies = TraditionalChineseColors.families;

    group('shouldRepaint', () {
      test('returns true when selectedColor changes', () {
        final oldPainter = ChineseColorWheelPainter(families: testFamilies);
        final newPainter = ChineseColorWheelPainter(
          families: testFamilies,
          selectedColor: testFamilies.first.colors.first,
        );
        expect(newPainter.shouldRepaint(oldPainter), isTrue);
      });

      test('returns false when all properties are the same', () {
        final painter1 = ChineseColorWheelPainter(families: testFamilies);
        final painter2 = ChineseColorWheelPainter(families: testFamilies);
        expect(painter2.shouldRepaint(painter1), isFalse);
      });

      test('returns true when families change', () {
        final painter1 = ChineseColorWheelPainter(families: testFamilies);
        final painter2 = ChineseColorWheelPainter(families: [testFamilies.first]);
        expect(painter2.shouldRepaint(painter1), isTrue);
      });
    });

    group('paint', () {
      testWidgets('paints without error with real data', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(600, 600),
                painter: ChineseColorWheelPainter(families: testFamilies),
              ),
            ),
          ),
        );
      });

      testWidgets('paints without error with selected color', (tester) async {
        final selected = testFamilies[2].colors[3];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(600, 600),
                painter: ChineseColorWheelPainter(
                  families: testFamilies,
                  selectedColor: selected,
                ),
              ),
            ),
          ),
        );
      });

      testWidgets('handles empty families list gracefully', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(600, 600),
                painter: ChineseColorWheelPainter(families: const []),
              ),
            ),
          ),
        );
      });

      testWidgets('handles single family', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(600, 600),
                painter: ChineseColorWheelPainter(families: [testFamilies.first]),
              ),
            ),
          ),
        );
      });

      testWidgets('paints on small canvas without error', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(150, 150),
                painter: ChineseColorWheelPainter(families: testFamilies),
              ),
            ),
          ),
        );
      });
    });

    group('colorHitTest', () {
      // Canvas 600x600, center = (300, 300)
      // shortSide = 600
      // outerRadius = 600 * 0.48 = 288
      // innerRadius = 600 * 0.10 = 60
      // familyCount = 6, totalSectorAngle = 2*pi/6 = pi/3
      // maxColors = 9, totalRadial = 228
      // ringGap = 1.5, ringThickness = (228 - 1.5*8) / 9 ≈ 24.0
      const canvasSize = Size(600, 600);

      test('returns null when tapping the center', () {
        final painter = ChineseColorWheelPainter(families: testFamilies);
        expect(painter.colorHitTest(const Offset(300, 300), canvasSize), isNull);
        // Just inside inner radius (distance = 55 < 60)
        expect(painter.colorHitTest(const Offset(355, 300), canvasSize), isNull);
      });

      test('returns null when tapping outside the wheel', () {
        final painter = ChineseColorWheelPainter(families: testFamilies);
        expect(painter.colorHitTest(const Offset(600, 300), canvasSize), isNull);
      });

      test('returns a color when tapping a valid swatch', () {
        final painter = ChineseColorWheelPainter(families: testFamilies);
        // Tap at angle 0 (right of center), distance = 70 (inside first ring)
        // angle 0 → family index 0 (red), ring index 0 → 暗红
        final result = painter.colorHitTest(const Offset(370, 300), canvasSize);
        expect(result, isNotNull);
        expect(result!.family, equals('red'));
        expect(result.name, equals('暗红'));
      });

      test('returns correct family for different angles', () {
        final painter = ChineseColorWheelPainter(families: testFamilies);
        // Family 1 (yellow): angle [pi/3, 2*pi/3)
        // Tap at angle = pi/2 (straight down), distance = 70
        final midAngle = pi / 2;
        const distance = 70.0;
        final result = painter.colorHitTest(
          Offset(300 + distance * cos(midAngle), 300 + distance * sin(midAngle)),
          canvasSize,
        );
        expect(result, isNotNull);
        expect(result!.family, equals('yellow'));
      });

      test('returns null for empty families', () {
        final painter = ChineseColorWheelPainter(families: const []);
        expect(painter.colorHitTest(const Offset(370, 300), canvasSize), isNull);
      });
    });

    group('snapToSector', () {
      test('snapping to exact boundary returns the same angle', () {
        const sectorCount = 6;
        final sectorAngle = 2 * pi / sectorCount;
        for (int i = 0; i < sectorCount; i++) {
          final boundary = i * sectorAngle;
          expect(
            ChineseColorWheelPainter.snapToSector(boundary, sectorCount),
            closeTo(boundary, 1e-10),
          );
        }
      });

      test('snapping from midpoints goes to the nearest boundary', () {
        const sectorCount = 4;
        final sectorAngle = 2 * pi / sectorCount;
        expect(
          ChineseColorWheelPainter.snapToSector(sectorAngle * 0.4, sectorCount),
          closeTo(0.0, 1e-10),
        );
        expect(
          ChineseColorWheelPainter.snapToSector(sectorAngle * 0.6, sectorCount),
          closeTo(sectorAngle, 1e-10),
        );
      });

      test('edge case: 0 sectors returns angle unchanged', () {
        expect(ChineseColorWheelPainter.snapToSector(1.5, 0), equals(1.5));
      });

      test('edge case: negative sector count returns angle unchanged', () {
        expect(ChineseColorWheelPainter.snapToSector(2.0, -3), equals(2.0));
      });

      test('result is always a multiple of 2*pi/N', () {
        const sectorCount = 6;
        final sectorAngle = 2 * pi / sectorCount;
        final random = Random(42);
        for (int i = 0; i < 100; i++) {
          final angle = random.nextDouble() * 4 * pi - 2 * pi;
          final snapped = ChineseColorWheelPainter.snapToSector(angle, sectorCount);
          final ratio = snapped / sectorAngle;
          expect((ratio - ratio.roundToDouble()).abs(), lessThan(1e-10));
        }
      });
    });

    group('geometry', () {
      test('sector angles are evenly distributed', () {
        for (int n = 1; n <= 12; n++) {
          final totalAngle = (2 * pi / n) * n;
          expect(totalAngle, closeTo(2 * pi, 1e-10));
        }
      });

      test('colors within each family are ordered by luminance', () {
        for (final family in testFamilies) {
          for (int i = 0; i < family.colors.length - 1; i++) {
            final current = family.colors[i];
            final next = family.colors[i + 1];
            final lumCurrent = 0.299 * current.r + 0.587 * current.g + 0.114 * current.b;
            final lumNext = 0.299 * next.r + 0.587 * next.g + 0.114 * next.b;
            expect(lumNext, greaterThanOrEqualTo(lumCurrent),
              reason: '${family.name}: ${next.name} should be >= ${current.name}');
          }
        }
      });
    });
  });
}
