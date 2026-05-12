# Implementation Plan: 色彩圆环重新设计

## Overview

将现有 COPIC 风格色彩圆盘替换为圆环布局。新建 3 个文件（ColorRingScreen、ColorRingPainter、ColorDetailPanel），修改 2 个现有文件（DeviceConnectScreen、RGBColorScreen）的入口引用。数据层不变。

## Tasks

- [x] 1. Implement ColorRingPainter (CustomPainter)
  - [x] 1.1 Create `lib/widgets/color_ring_painter.dart` with `ColorRingPainter` class
    - Accept `List<ColorFamily> families`, `double rotationAngle`, `ChineseColor? selectedColor`, `double innerRadius`, `double outerRadius`
    - Calculate `sectorAngle = 2π / familyCount`, `layerThickness`, `maxLayers`
    - Paint each Color_Band: iterate families, for each color draw an arc segment from `innerRadius + i * layerThickness` to `innerRadius + (i+1) * layerThickness`, offset by `rotationAngle`
    - Draw 1.5px separator lines between adjacent Color_Bands
    - Draw inner band (3-4px narrow arc) using each family's darkest color
    - Draw color name text on each swatch, auto-select black/white via `ChineseColor.textColor`
    - Draw selected color highlight (white stroke) when `selectedColor` matches
    - Implement `shouldRepaint` comparing all fields
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

  - [x] 1.2 Implement `hitTest` method on `ColorRingPainter`
    - Convert tap position to polar coordinates relative to ring center
    - Subtract `rotationAngle` to get unrotated angle
    - Calculate `familyIndex = floor(normalizedAngle / sectorAngle)` and `layerIndex = floor((distance - innerRadius) / layerThickness)`
    - Return `families[familyIndex].colors[layerIndex]` with bounds checking, or null if outside ring
    - _Requirements: 4.1, 4.5_

  - [x] 1.3 Implement color family name labels along inner arc
    - Draw family name text rotated along arc tangent direction at each Color_Band's inner edge
    - Use white/semi-transparent white color, font size scaled with ring size
    - _Requirements: 6.1, 6.2, 6.3_

  - [ ]* 1.4 Write unit tests for ColorRingPainter
    - Test `shouldRepaint` returns true/false correctly
    - Test `hitTest` returns correct color for known coordinates
    - Test `hitTest` returns null for center and outside ring
    - Test `hitTest` accounts for `rotationAngle` offset
    - _Requirements: 1.1, 1.2, 4.1, 4.5_

- [x] 2. Implement ColorDetailPanel widget
  - [x] 2.1 Create `lib/widgets/color_detail_panel.dart` with `ColorDetailPanel` StatelessWidget
    - Accept `ChineseColor? color` and `VoidCallback? onConfirm`
    - Display color name (Chinese), circular color preview swatch with white border, RGB values (R:xxx G:xxx B:xxx)
    - Show confirm button that calls `onConfirm`
    - Use `AnimatedSwitcher` for transition animation (200ms) when color changes
    - Show empty/placeholder state when `color` is null
    - _Requirements: 4.3, 7.4_

  - [ ]* 2.2 Write widget tests for ColorDetailPanel
    - Test renders color name and RGB values when color is provided
    - Test renders empty state when color is null
    - Test confirm button triggers onConfirm callback
    - _Requirements: 4.3_

- [x] 3. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Implement ColorRingScreen (full-screen page)
  - [x] 4.1 Create `lib/screens/color_ring_screen.dart` with `ColorRingScreen` StatefulWidget
    - Accept `Function(int r, int g, int b) onColorSelected` callback
    - Manage state: `_rotationAngle` (double), `_ringOffset` (Offset, initial ~Offset(80, 120)), `_selectedColor` (ChineseColor?), `_popupController` (AnimationController), `_inertiaController` (AnimationController), `_lastAngularVelocity` (double)
    - Build dark background scaffold with `CustomPaint` using `ColorRingPainter`, positioned via `Transform.translate` with `_ringOffset`
    - Place `ColorDetailPanel` in ring center area
    - Use `ResponsiveUtils` to calculate `innerRadius` (screenShortSide * 0.15) and `outerRadius` dynamically
    - On small screens (height < 700), reduce ring size appropriately
    - Clamp `_ringOffset` to keep ring partially visible on screen
    - _Requirements: 2.1, 2.3, 4.2, 4.3, 8.1, 8.2, 8.3, 8.4_

  - [x] 4.2 Implement popup/dismiss animation
    - `_popupController`: 400ms duration, `Curves.easeOutBack`, scale from 0.0→1.0 + fade from 0.0→1.0
    - Set `alignment: Alignment.topLeft` so scale expands from top-left origin
    - Auto-forward on `initState`
    - Dismiss: reverse with 250ms, `Curves.easeInCubic`, then `Navigator.pop`
    - Add close button (top-right) that triggers dismiss animation
    - _Requirements: 2.2, 2.5, 2.6, 7.1, 7.2_

  - [x] 4.3 Implement gesture handling: rotation vs. drag-move
    - In `_onPanStart`: calculate distance from touch to ring center; if `innerRadius < d < outerRadius` → rotation mode, else → move mode
    - In `_onPanUpdate` (rotation mode): compute angle delta from previous touch position relative to ring center, update `_rotationAngle`
    - In `_onPanUpdate` (move mode): update `_ringOffset` by drag delta
    - _Requirements: 3.1, 3.4, 7.5_

  - [x] 4.4 Implement inertia rotation animation
    - On `_onPanEnd` in rotation mode: capture angular velocity, start `_inertiaController` (800-1500ms based on velocity, `Curves.decelerate`)
    - Animate `_rotationAngle` += velocity * remaining curve value
    - On new touch during inertia: stop `_inertiaController` immediately
    - _Requirements: 3.2, 3.3, 7.3_

  - [x] 4.5 Implement color selection: tap and double-tap
    - `_onTapUp`: call `ColorRingPainter.hitTest` with local position, update `_selectedColor` if hit
    - `_onDoubleTap`: if `_selectedColor != null`, call `onColorSelected(r, g, b)` and `Navigator.pop`
    - Confirm button in `ColorDetailPanel` also triggers `_confirmSelection`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 4.6 Write widget tests for ColorRingScreen
    - Test screen renders with dark background and CustomPaint
    - Test popup animation plays on open
    - Test close button triggers dismiss animation and pops
    - Test tap on ring area updates selected color
    - Test double-tap calls onColorSelected and pops
    - _Requirements: 2.1, 2.2, 2.5, 4.1, 4.4_

- [x] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Integrate entry points and remove old references
  - [x] 6.1 Update `DeviceConnectScreen` to use `ColorRingScreen`
    - Replace `ChineseColorWheelOverlay` navigation with `Navigator.push` to `ColorRingScreen`
    - Update all entry buttons: `_buildHighQualityRGBPanel`, colorize preset, colorize rgbDetail
    - Wire `onColorSelected` callback to set RGB slider values and sync to hardware
    - Remove `ChineseColorWheelOverlay` import
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 6.2 Update `RGBColorScreen` to use `ColorRingScreen`
    - Replace `ChineseColorWheelOverlay` navigation with `Navigator.push` to `ColorRingScreen`
    - Wire `onColorSelected` callback to existing `_onColorSelected` handler
    - Remove `ChineseColorWheelOverlay` import
    - _Requirements: 5.4_

  - [ ]* 6.3 Update existing tests referencing `ChineseColorWheelOverlay`
    - Update `test/widgets/chinese_color_wheel_overlay_test.dart` if needed, or mark as legacy
    - Ensure no broken imports in test suite
    - _Requirements: 5.4_

- [x] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Data layer (`TraditionalChineseColors`) is unchanged — no data migration needed
- Old files (`chinese_color_wheel_painter.dart`, `chinese_color_wheel_overlay.dart`) are preserved but no longer referenced
- All code uses Dart/Flutter, consistent with the existing codebase
