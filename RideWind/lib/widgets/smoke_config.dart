/// 烟雾系统配置
/// 所有可调参数集中管理，支持实时响应（ValueNotifier）
///
/// 使用方式：
///   final config = SmokeConfig();
///   SmokeFlowWidget(config: config, ...);
///   config.gravityStrength = 1.5; // widget 自动 rebuild

library;

import 'package:flutter/material.dart';

class SmokeConfig extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════
  // 基础参数（最常调）
  // ═══════════════════════════════════════════════════════════════════════

  Color _smokeColor;
  Color get smokeColor => _smokeColor;
  set smokeColor(Color v) {
    if (v == _smokeColor) return;
    _smokeColor = v;
    notifyListeners();
  }

  /// 烟雾密度强度倍率（注入量倍率，0~2）
  double _densityScale;
  double get densityScale => _densityScale;
  set densityScale(double v) {
    if (v == _densityScale) return;
    _densityScale = v.clamp(0.0, 2.0);
    notifyListeners();
  }

  /// 流线数量（4~12，重建仿真）
  int _streamCount;
  int get streamCount => _streamCount;
  set streamCount(int v) {
    final newV = v.clamp(4, 12);
    if (newV == _streamCount) return;
    _streamCount = newV;
    _needsRebuild = true;
    notifyListeners();
  }

  /// 流线间距（4.0~10.0 格，重建仿真）
  double _streamSpacing;
  double get streamSpacing => _streamSpacing;
  set streamSpacing(double v) {
    final newV = v.clamp(4.0, 10.0);
    if (newV == _streamSpacing) return;
    _streamSpacing = newV;
    _needsRebuild = true;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 物理参数
  // ═══════════════════════════════════════════════════════════════════════

  /// 重力强度（0~2.0），speed=0 时下坠的程度
  double _gravityStrength;
  double get gravityStrength => _gravityStrength;
  set gravityStrength(double v) {
    if (v == _gravityStrength) return;
    _gravityStrength = v.clamp(0.0, 2.0);
    notifyListeners();
  }

  /// 缭绕强度（0~1，控制 sin 波动幅度）
  double _swayStrength;
  double get swayStrength => _swayStrength;
  set swayStrength(double v) {
    if (v == _swayStrength) return;
    _swayStrength = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 衰减速率系数（高速时密度衰减加快的程度，0~0.1）
  double _decayRate;
  double get decayRate => _decayRate;
  set decayRate(double v) {
    if (v == _decayRate) return;
    _decayRate = v.clamp(0.0, 0.1);
    notifyListeners();
  }

  /// 笔直压制强度（高速时 v 衰减比例，0~0.5）
  double _straightnessStrength;
  double get straightnessStrength => _straightnessStrength;
  set straightnessStrength(double v) {
    if (v == _straightnessStrength) return;
    _straightnessStrength = v.clamp(0.0, 0.5);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 障碍参数
  // ═══════════════════════════════════════════════════════════════════════

  /// 是否启用障碍
  bool _obstacleEnabled;
  bool get obstacleEnabled => _obstacleEnabled;
  set obstacleEnabled(bool v) {
    if (v == _obstacleEnabled) return;
    _obstacleEnabled = v;
    notifyListeners();
  }

  /// 障碍中心 X（归一化，0~1）
  double _obstacleX;
  double get obstacleX => _obstacleX;
  set obstacleX(double v) {
    if (v == _obstacleX) return;
    _obstacleX = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 障碍中心 Y（归一化，0~1）
  double _obstacleY;
  double get obstacleY => _obstacleY;
  set obstacleY(double v) {
    if (v == _obstacleY) return;
    _obstacleY = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 障碍椭圆半轴 X（归一化，0.05~0.30）
  double _obstacleRx;
  double get obstacleRx => _obstacleRx;
  set obstacleRx(double v) {
    if (v == _obstacleRx) return;
    _obstacleRx = v.clamp(0.05, 0.30);
    notifyListeners();
  }

  /// 障碍椭圆半轴 Y（归一化，0.05~0.30）
  double _obstacleRy;
  double get obstacleRy => _obstacleRy;
  set obstacleRy(double v) {
    if (v == _obstacleRy) return;
    _obstacleRy = v.clamp(0.05, 0.30);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 渲染参数
  // ═══════════════════════════════════════════════════════════════════════

  /// Layer 1（外层光晕）blur sigma（0~10）
  double _blur1Sigma;
  double get blur1Sigma => _blur1Sigma;
  set blur1Sigma(double v) {
    if (v == _blur1Sigma) return;
    _blur1Sigma = v.clamp(0.0, 10.0);
    notifyListeners();
  }

  /// Layer 2（核心）blur sigma（0~10）
  double _blur2Sigma;
  double get blur2Sigma => _blur2Sigma;
  set blur2Sigma(double v) {
    if (v == _blur2Sigma) return;
    _blur2Sigma = v.clamp(0.0, 10.0);
    notifyListeners();
  }

  /// 透明度倍率（0~2）
  double _opacityScale;
  double get opacityScale => _opacityScale;
  set opacityScale(double v) {
    if (v == _opacityScale) return;
    _opacityScale = v.clamp(0.0, 2.0);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 内部状态
  // ═══════════════════════════════════════════════════════════════════════

  bool _needsRebuild = false;
  bool consumeRebuildFlag() {
    final v = _needsRebuild;
    _needsRebuild = false;
    return v;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 构造函数 + 默认值（V14.1 当前最佳参数）
  // ═══════════════════════════════════════════════════════════════════════

  SmokeConfig({
    Color smokeColor = const Color(0xFFCCCCCC),
    double densityScale = 1.0,
    int streamCount = 8,
    double streamSpacing = 6.2,
    double gravityStrength = 0.5,
    double swayStrength = 0.3,
    double decayRate = 0.02,
    double straightnessStrength = 0.15,
    bool obstacleEnabled = true,
    double obstacleX = 0.40,
    double obstacleY = 0.50,
    double obstacleRx = 0.15,
    double obstacleRy = 0.12,
    double blur1Sigma = 4.0,
    double blur2Sigma = 2.0,
    double opacityScale = 1.0,
  })  : _smokeColor = smokeColor,
        _densityScale = densityScale,
        _streamCount = streamCount,
        _streamSpacing = streamSpacing,
        _gravityStrength = gravityStrength,
        _swayStrength = swayStrength,
        _decayRate = decayRate,
        _straightnessStrength = straightnessStrength,
        _obstacleEnabled = obstacleEnabled,
        _obstacleX = obstacleX,
        _obstacleY = obstacleY,
        _obstacleRx = obstacleRx,
        _obstacleRy = obstacleRy,
        _blur1Sigma = blur1Sigma,
        _blur2Sigma = blur2Sigma,
        _opacityScale = opacityScale;

  /// 重置到默认值
  void resetToDefaults() {
    _smokeColor = const Color(0xFFCCCCCC);
    _densityScale = 1.0;
    _streamCount = 8;
    _streamSpacing = 6.2;
    _gravityStrength = 0.5;
    _swayStrength = 0.3;
    _decayRate = 0.02;
    _straightnessStrength = 0.15;
    _obstacleEnabled = true;
    _obstacleX = 0.40;
    _obstacleY = 0.50;
    _obstacleRx = 0.15;
    _obstacleRy = 0.12;
    _blur1Sigma = 4.0;
    _blur2Sigma = 2.0;
    _opacityScale = 1.0;
    _needsRebuild = true;
    notifyListeners();
  }
}
