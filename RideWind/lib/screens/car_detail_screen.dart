import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/car_model.dart';

/// 🚗 车辆详情页 — 可缩放大图 + 丰富信息 + Hero 动画
class CarDetailScreen extends StatelessWidget {
  final CarModel car;

  const CarDetailScreen({super.key, required this.car});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final year = _extractYear(car.model);
    final country = _getCountryFlag(car.brand);
    final category = _guessCategory(car.brand, car.model);
    final engineType = _guessEngineType(car.model, car.brand);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 可滚动主内容
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图片区域（可缩放）
                SizedBox(
                  height: screenHeight * 0.45,
                  width: double.infinity,
                  child: Container(
                    color: const Color(0xFF0A0A0A),
                    padding: EdgeInsets.only(top: topPadding + 48),
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: Hero(
                        tag: 'car_${car.filename}',
                        child: Image.asset(
                          car.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
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

                // 信息区域
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 品牌 + 国旗
                      Row(
                        children: [
                          if (country.isNotEmpty) ...[
                            Text(country, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            car.brand.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 车型名
                      Text(
                        car.model,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 标签行
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (year != null) _buildChip(year, Icons.calendar_today),
                          if (category.isNotEmpty) _buildChip(category, Icons.category),
                          if (engineType.isNotEmpty) _buildChip(engineType, Icons.speed),
                          _buildChip(car.brand, Icons.business),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // 分隔线
                      Container(
                        width: double.infinity,
                        height: 1,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      const SizedBox(height: 24),

                      // 音效状态
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.music_note,
                                color: Colors.white.withOpacity(0.3),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Engine Sound',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Not assigned',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.white.withOpacity(0.2),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 选择按钮
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
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
                      const SizedBox(height: 16),

                      // 缩放提示
                      Center(
                        child: Text(
                          'Pinch to zoom image',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 返回按钮
          Positioned(
            top: topPadding + 12,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: const Icon(
                  Icons.arrow_back,
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

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withOpacity(0.4)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 从 model 名中提取年份
  String? _extractYear(String model) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(model);
    return match?.group(0);
  }

  /// 品牌→国旗映射
  String _getCountryFlag(String brand) {
    const map = {
      // 意大利
      'Ferrari': '🇮🇹', 'Lamborghini': '🇮🇹', 'Maserati': '🇮🇹',
      'Alfa Romeo': '🇮🇹', 'Fiat': '🇮🇹', 'Abarth': '🇮🇹',
      'Pagani': '🇮🇹', 'Lancia': '🇮🇹', 'De Tomaso': '🇮🇹',
      // 德国
      'BMW': '🇩🇪', 'Mercedes-Benz': '🇩🇪', 'Mercedes-AMG': '🇩🇪',
      'Audi': '🇩🇪', 'Porsche': '🇩🇪', 'Volkswagen': '🇩🇪',
      'Opel': '🇩🇪',
      // 日本
      'Toyota': '🇯🇵', 'Nissan': '🇯🇵', 'Honda': '🇯🇵',
      'Mazda': '🇯🇵', 'Subaru': '🇯🇵', 'Mitsubishi': '🇯🇵',
      'Lexus': '🇯🇵', 'Acura': '🇯🇵', 'Infiniti': '🇯🇵',
      'Suzuki': '🇯🇵',
      // 英国
      'Aston Martin': '🇬🇧', 'McLaren': '🇬🇧', 'Jaguar': '🇬🇧',
      'Land Rover': '🇬🇧', 'Bentley': '🇬🇧', 'Rolls-Royce': '🇬🇧',
      'Lotus': '🇬🇧', 'TVR': '🇬🇧', 'Morgan': '🇬🇧',
      'Mini': '🇬🇧', 'MG': '🇬🇧',
      // 美国
      'Ford': '🇺🇸', 'Chevrolet': '🇺🇸', 'Dodge': '🇺🇸',
      'Jeep': '🇺🇸', 'GMC': '🇺🇸', 'Cadillac': '🇺🇸',
      'Buick': '🇺🇸', 'Lincoln': '🇺🇸', 'Shelby': '🇺🇸',
      'Hennessey': '🇺🇸', 'SSC': '🇺🇸', 'Saleen': '🇺🇸',
      'AMC': '🇺🇸', 'Plymouth': '🇺🇸', 'Pontiac': '🇺🇸',
      'Hummer': '🇺🇸', 'Ram': '🇺🇸',
      // 法国
      'Bugatti': '🇫🇷', 'Renault': '🇫🇷', 'Peugeot': '🇫🇷',
      'Citroen': '🇫🇷', 'Alpine': '🇫🇷',
      // 韩国
      'Hyundai': '🇰🇷', 'Kia': '🇰🇷', 'Genesis': '🇰🇷',
      // 瑞典
      'Volvo': '🇸🇪', 'Koenigsegg': '🇸🇪',
      // 捷克
      'Skoda': '🇨🇿',
      // 西班牙
      'SEAT': '🇪🇸',
      // 澳大利亚
      'Holden': '🇦🇺',
    };
    return map[brand] ?? '';
  }

  /// 从品牌+车型推断分类
  String _guessCategory(String brand, String model) {
    final m = model.toLowerCase();
    final b = brand.toLowerCase();

    if (m.contains('gt3') || m.contains('gt2') || m.contains('race') ||
        m.contains('gte') || m.contains('lm')) return 'Race';
    if (b == 'ferrari' || b == 'lamborghini' || b == 'bugatti' ||
        b == 'pagani' || b == 'koenigsegg' || b == 'mclaren' ||
        m.contains('hypercar')) return 'Hypercar';
    if (m.contains('suv') || m.contains('truck') || m.contains('raptor') ||
        b == 'jeep' || b == 'land rover') return 'Off-Road';
    if (m.contains('rally') || m.contains('wrc')) return 'Rally';
    if (RegExp(r'\b(19[4-7]\d)\b').hasMatch(model)) return 'Classic';
    if (b == 'porsche' || b == 'lotus' || m.contains('gt') ||
        m.contains('sport')) return 'Sports';
    return 'Car';
  }

  /// 从车型名推断引擎类型
  String _guessEngineType(String model, String brand) {
    final m = model.toLowerCase();
    if (m.contains('ev') || m.contains('electric') || m.contains('e-tron')) {
      return 'Electric';
    }
    if (m.contains('v12') || brand == 'Ferrari' || brand == 'Lamborghini' ||
        brand == 'Pagani') {
      return 'V12';
    }
    if (m.contains('v10')) return 'V10';
    if (m.contains('v8') || m.contains('gt500') || m.contains('hellcat')) {
      return 'V8';
    }
    if (m.contains('turbo') || m.contains('sti') || m.contains('rs')) {
      return 'Turbo';
    }
    if (m.contains('v6')) return 'V6';
    if (m.contains('i6') || m.contains('inline')) return 'I6';
    return '';
  }
}
