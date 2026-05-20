import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/car_model.dart';
import 'logo_management_screen.dart';

/// 🚗 车辆详情页 — 可缩放大图 + 丰富信息 + Hero 动画 + 设为 Logo
class CarDetailScreen extends StatefulWidget {
  final CarModel car;

  const CarDetailScreen({super.key, required this.car});

  @override
  State<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends State<CarDetailScreen> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _uploadStatus;

  CarModel get car => widget.car;

  /// 跳转到 Logo 管理页面，传入当前车辆图片
  Future<void> _setAsLogo() async {
    setState(() => _uploadStatus = '加载图片...');

    try {
      final byteData = await rootBundle.load(car.assetPath);
      final imageBytes = byteData.buffer.asUint8List();

      if (!mounted) return;

      // 跳转到 Logo 管理页面，传入预选图片
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LogoManagementScreen(initialImageBytes: imageBytes),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载图片失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadStatus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final specs = car.specs;
    final country = _getCountryFlag(car.brand);

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
                      // 品牌 + 国旗 + 年份
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
                          if (specs?.year != null) ...[
                            const SizedBox(width: 12),
                            Text(
                              specs!.year!,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 13,
                              ),
                            ),
                          ],
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

                      // 性能数据网格（有数据时显示）
                      if (specs != null && specs.horsepower != null) ...[
                        _buildSpecsGrid(specs),
                        const SizedBox(height: 20),
                      ],

                      // 标签行
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (specs?.engine != null)
                            _buildChip('${specs!.displacement ?? ''} ${specs.engine!}'.trim(), Icons.settings),
                          if (specs?.aspiration != null)
                            _buildChip(specs!.aspiration!, Icons.air),
                          if (specs?.drivetrain != null)
                            _buildChip(specs!.drivetrain!, Icons.swap_horiz),
                          if (specs?.gears != null)
                            _buildChip(specs!.gears!, Icons.speed),
                          if (specs?.layout != null)
                            _buildChip(specs!.layout!, Icons.architecture),
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

                      // 设为 Logo 按钮（WiFi 上传）
                      if (_isUploading) ...[
                        // 上传进度
                        Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _uploadProgress,
                                minHeight: 6,
                                backgroundColor: Colors.grey[800],
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C8FF)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _uploadStatus ?? '上传中...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _setAsLogo,
                            icon: const Icon(Icons.upload_rounded, size: 20),
                            label: const Text(
                              'SET AS LOGO',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C8FF).withOpacity(0.15),
                              foregroundColor: const Color(0xFF00C8FF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                  color: Color(0xFF00C8FF),
                                  width: 0.5,
                                ),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

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

  /// 性能数据网格 — 2x2 布局展示核心参数
  Widget _buildSpecsGrid(CarSpecs specs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildSpecItem(
                '${specs.horsepower ?? "—"}',
                'HP',
                Icons.bolt,
              )),
              Container(width: 1, height: 44, color: Colors.white.withOpacity(0.05)),
              Expanded(child: _buildSpecItem(
                '${specs.torqueLbft ?? "—"}',
                'LB·FT',
                Icons.rotate_right,
              )),
            ],
          ),
          Container(height: 1, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSpecItem(
                specs.weightKg != null ? '${specs.weightKg}' : '—',
                'KG',
                Icons.fitness_center,
              )),
              Container(width: 1, height: 44, color: Colors.white.withOpacity(0.05)),
              Expanded(child: _buildSpecItem(
                specs.drivetrain ?? '—',
                'DRIVE',
                Icons.swap_horiz,
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecItem(String value, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: Colors.white.withOpacity(0.3)),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
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
}
