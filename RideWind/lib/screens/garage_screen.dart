import 'package:flutter/material.dart';

/// 🚗 车库页面 — 占位版本
///
/// 纯黑背景 + 暗灰 "GARAGE" 文字，用于验证全屏滑动效果。
/// 后续将实现：车辆卡片网格 + 分类筛选（参考 Horizon 5 Cars APP 风格）
/// 功能定位：选一辆车 = 选一套引擎音效（对应硬件端多音效包切换）
class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'GARAGE',
          style: TextStyle(
            color: Color(0xFF3A3A3A),
            fontSize: 48,
            fontWeight: FontWeight.w900,
            letterSpacing: 12,
          ),
        ),
      ),
    );
  }
}
