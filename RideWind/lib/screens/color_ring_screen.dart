import 'dart:math';
import 'package:flutter/material.dart';
import '../data/traditional_chinese_colors.dart';
import '../widgets/color_detail_panel.dart';
import '../widgets/color_ring_painter.dart';

/// 手势变换状态，用 ValueNotifier 驱动，避免 setState 重建整棵树
class _TransformState {
  final Offset center;
  final double scale;
  final double rotation;

  const _TransformState({
    required this.center,
    required this.scale,
    required this.rotation,
  });
}

class ColorRingScreen extends StatefulWidget {
  final Function(int r, int g, int b) onColorSelected;

  const ColorRingScreen({super.key, required this.onColorSelected});

  @override
  State<ColorRingScreen> createState() => _ColorRingScreenState();
}

class _ColorRingScreenState extends State<ColorRingScreen>
    with TickerProviderStateMixin {
  ChineseColor? _selectedColor;
  bool _initialized = false;

  late final ValueNotifier<_TransformState> _transform;

  // 手势状态
  double _gestureStartScale = 1.0;
  double _lastAngle = 0.0;
  Offset? _tapPosition;
  double _totalDistance = 0.0;
  int _pointerCount = 0;

  // 区域拖曳状态
  bool _isDragZone = false;
  Offset _lastFocalPoint = Offset.zero;

  // 手势期间缓存
  RenderBox? _cachedBox;
  Offset _cachedRingCenter = Offset.zero;

  late final List<SortedFamily> _sortedFamilies = _buildSortedFamilies();
  late final LabelCache _labelCache;

  late final AnimationController _popupController;
  late final Animation<double> _popupAnimation;

  static const double _baseInnerRadius = 90.0;
  // 点击判定阈值：手指移动距离小于此值视为点击
  static const double _tapThreshold = 15.0;

  List<SortedFamily> _buildSortedFamilies() {
    return TraditionalChineseColors.families.map((family) {
      final result = TraditionalChineseColors.sortFamilyIntoColumns(family);
      return SortedFamily(
        id: family.id,
        name: family.name,
        colors: result.colors,
        columnLengths: result.columnLengths,
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _transform = ValueNotifier(const _TransformState(
      center: Offset.zero,
      scale: 1.8,
      rotation: 0.0,
    ));
    _popupController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _popupAnimation = CurvedAnimation(
      parent: _popupController,
      curve: Curves.easeOutBack,
    );
    _labelCache = LabelCache()..preRender(_sortedFamilies, onBatchDone: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    _popupController.dispose();
    super.dispose();
  }

  double _calcMaxOuterRadius() {
    const innerR = _baseInnerRadius;
    const neutralOuter = innerR + ColorRingPainter.neutralRingHeight;
    const colorInner = neutralOuter + ColorRingPainter.ringGap;
    int maxRows = 0;
    for (final sf in _sortedFamilies) {
      if (sf.id == 'neutral') continue;
      if (sf.maxRows > maxRows) maxRows = sf.maxRows;
    }
    return colorInner + maxRows * ColorRingPainter.rowHeight;
  }

  // ─── 手势处理 ───

  void _cacheGestureContext() {
    _cachedBox = context.findRenderObject() as RenderBox?;
    if (_cachedBox != null) {
      final size = _cachedBox!.size;
      final sc = Offset(size.width / 2, size.height / 2);
      final t = _transform.value;
      _cachedRingCenter = Offset(sc.dx + t.center.dx, sc.dy + t.center.dy);
    }
  }

  double _angleOfPointFast(Offset globalPoint) {
    final local = _cachedBox!.globalToLocal(globalPoint);
    return atan2(local.dy - _cachedRingCenter.dy, local.dx - _cachedRingCenter.dx);
  }

  bool _isInsideInnerCircle(Offset globalPoint) {
    if (_cachedBox == null) return false;
    final local = _cachedBox!.globalToLocal(globalPoint);
    final dx = local.dx - _cachedRingCenter.dx;
    final dy = local.dy - _cachedRingCenter.dy;
    final distInRing = sqrt(dx * dx + dy * dy) / _transform.value.scale;
    return distInRing < _baseInnerRadius;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _cacheGestureContext();
    final t = _transform.value;
    _gestureStartScale = t.scale;
    _tapPosition = details.focalPoint;
    _totalDistance = 0.0;
    _pointerCount = details.pointerCount;
    _lastFocalPoint = details.focalPoint;
    _lastAngle = _cachedBox != null ? _angleOfPointFast(details.focalPoint) : 0.0;
    _isDragZone = _isInsideInnerCircle(details.focalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _pointerCount = max(_pointerCount, details.pointerCount);
    _totalDistance += details.focalPointDelta.distance;

    final t = _transform.value;

    if (_pointerCount >= 2) {
      // 双指：仅缩放
      final newScale = (_gestureStartScale * details.scale).clamp(0.3, 4.0);
      _transform.value = _TransformState(
        center: t.center,
        scale: newScale,
        rotation: t.rotation,
      );
    } else if (_isDragZone) {
      // 单指 + 内圈空白区：拖曳平移
      final delta = details.focalPoint - _lastFocalPoint;
      _transform.value = _TransformState(
        center: t.center + delta,
        scale: t.scale,
        rotation: t.rotation,
      );
      _cachedRingCenter = _cachedRingCenter + delta;
    } else if (_cachedBox != null) {
      // 单指 + 色块区/外延：旋转
      final currentAngle = _angleOfPointFast(details.focalPoint);
      final delta = currentAngle - _lastAngle;
      _lastAngle = currentAngle;
      final normalizedDelta = atan2(sin(delta), cos(delta));
      _transform.value = _TransformState(
        center: t.center,
        scale: t.scale,
        rotation: t.rotation + normalizedDelta,
      );
    }

    _lastFocalPoint = details.focalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_totalDistance < _tapThreshold && _tapPosition != null) {
      _handleTap(_tapPosition!);
    }
    _tapPosition = null;
    _isDragZone = false;
    // 不清除 _cachedBox，下次手势开始时会重新缓存
  }

  void _handleTap(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(globalPosition);
    final canvasSize = box.size;
    final t = _transform.value;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final fromCenter = localPos - t.center - center;
    final unscaled = fromCenter / t.scale;
    final cosR = cos(-t.rotation);
    final sinR = sin(-t.rotation);
    final unrotated = Offset(
      unscaled.dx * cosR - unscaled.dy * sinR,
      unscaled.dx * sinR + unscaled.dy * cosR,
    );
    final adjustedPos = unrotated + center;

    final painter = ColorRingPainter(
      sortedFamilies: _sortedFamilies,
      rotationAngle: 0,
      selectedColor: _selectedColor,
      innerRadius: _baseInnerRadius,
      outerRadius: _calcMaxOuterRadius(),
      labelCache: _labelCache,
    );

    final hit = painter.colorHitTest(adjustedPos, canvasSize);
    if (hit != null) {
      setState(() => _selectedColor = hit);
      _popupController.forward(from: 0);
    } else {
      // 点击空白区域关闭详情面板
      _dismissPanel();
    }
  }

  void _dismissPanel() {
    if (_selectedColor != null) {
      _popupController.reverse().then((_) {
        if (mounted) setState(() => _selectedColor = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      _transform.value = _TransformState(
        center: Offset(-size.width / 2, -size.height / 2),
        scale: 1.8,
        rotation: 0.0,
      );
      _initialized = true;
    }

    final outerR = _calcMaxOuterRadius();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 手势层 + 圆环
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(
              child: ValueListenableBuilder<_TransformState>(
                valueListenable: _transform,
                builder: (context, t, child) {
                  final screenSize = MediaQuery.of(context).size;
                  final sc = Offset(screenSize.width / 2, screenSize.height / 2);
                  return Transform(
                    transform: Matrix4.identity()
                      ..translate(sc.dx + t.center.dx, sc.dy + t.center.dy)
                      ..scale(t.scale)
                      ..rotateZ(t.rotation)
                      ..translate(-sc.dx, -sc.dy),
                    child: child,
                  );
                },
                child: RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    painter: ColorRingPainter(
                      sortedFamilies: _sortedFamilies,
                      rotationAngle: 0,
                      selectedColor: _selectedColor,
                      innerRadius: _baseInnerRadius,
                      outerRadius: outerR,
                      labelCache: _labelCache,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),

          // 详情卡片 — 用 IgnorePointer 让手势穿透到底层 GestureDetector
          // 只有卡片本身可点击（通过内部的 GestureDetector）
          if (_selectedColor != null)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: false,
                child: Center(
                  child: ScaleTransition(
                    scale: _popupAnimation,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      // 阻止卡片区域的点击穿透到底层
                      onTap: () {},
                      child: Material(
                        color: Colors.transparent,
                        child: ColorDetailPanel(
                          color: _selectedColor,
                          onConfirm: () {
                            final c = _selectedColor;
                            if (c != null) {
                              widget.onColorSelected(c.r, c.g, c.b);
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.black54, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 缩放百分比
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: ValueListenableBuilder<_TransformState>(
                  valueListenable: _transform,
                  builder: (context, t, _) => Text(
                    '${(t.scale * 100).round()}%',
                    style: const TextStyle(color: Colors.black26, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
