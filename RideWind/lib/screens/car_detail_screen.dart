import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/car_model.dart';

/// 🚗 车辆详情页 — 全屏展示 + Hero 动画
///
/// 点击车库卡片进入，展示大图 + 车辆信息 + 选择按钮
class CarDetailScreen extends StatelessWidget {
  final CarModel car;

  const CarDetailScreen({super.key, required this.car});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 主内容
          Column(
            children: [
              // 顶部大图区域
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFF0A0A0A),
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Hero(
                        tag: 'car_${car.filename}',
                        child: Image.asset(
                          car.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.directions_car,
                            color: Colors.white.withOpacity(0.1),
                            size: 80,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 下方信息区域
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 品牌
                      Text(
                        car.brand.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 车型名
                      Text(
                        car.model,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      // 分隔线
                      Container(
                        width: 40,
                        height: 2,
                        color: Colors.white.withOpacity(0.1),
                      ),
                      const Spacer(),
                      // 选择按钮
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            // TODO: 绑定音效包 + 返回
                            Navigator.of(context).pop(car);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.08),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'SELECT THIS CAR',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
