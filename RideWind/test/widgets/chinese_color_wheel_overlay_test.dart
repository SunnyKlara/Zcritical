import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridewind/widgets/chinese_color_wheel_overlay.dart';

/// ChineseColorWheelOverlay widget 测试（COPIC 风格）
void main() {
  Widget buildTestWidget({
    Function(int, int, int)? onColorSelected,
  }) {
    return MaterialApp(
      home: ChineseColorWheelOverlay(
        onColorSelected: onColorSelected ?? (r, g, b) {},
      ),
    );
  }

  group('ChineseColorWheelOverlay', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(ChineseColorWheelOverlay), findsOneWidget);
    });

    testWidgets('contains a CustomPaint for the color wheel', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byKey(const ValueKey('color_wheel_paint')), findsOneWidget);
    });

    testWidgets('shows default hint text when no color is selected', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('中华传统色'), findsOneWidget);
      expect(find.text('双指缩放查看 · 点击色块选色'), findsOneWidget);
    });

    testWidgets('has a close button with X icon', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('close button pops the route', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChineseColorWheelOverlay(
                        onColorSelected: (r, g, b) {},
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChineseColorWheelOverlay), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(ChineseColorWheelOverlay), findsNothing);
    });

    testWidgets('shows confirm button with disabled state initially', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('请选择颜色'), findsOneWidget);
    });

    testWidgets('contains InteractiveViewer for zoom/pan', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('renders on small screen without errors', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(ChineseColorWheelOverlay), findsOneWidget);
    });

    testWidgets('renders on large screen without errors', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(ChineseColorWheelOverlay), findsOneWidget);
    });

    testWidgets('shows zoom hint when no color selected', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('双指捏合缩放 · 拖动平移'), findsOneWidget);
    });
  });
}
