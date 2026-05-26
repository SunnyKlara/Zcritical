import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/car_model.dart';
import '../services/engine_sound_service.dart';
import 'logo_management_screen.dart';

/// 🚗 车辆详情页 — 可缩放大图 + 竖列参数进度条 + Hero 动画 + 设为 Logo
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

  /// 控制进度条入场动画：页面进入后延迟触发
  bool _animateIn = false;

  /// 引擎声音 Profile
  EngineSoundProfile? _soundProfile;

  /// 引擎声音试听播放器
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  /// 车辆故事
  Map<String, dynamic>? _carStory;

  CarModel get car => widget.car;

  @override
  void initState() {
    super.initState();
    // 延迟触发动画，让进度条从 0 增长到目标值
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
    // 加载引擎声音映射
    _loadSoundProfile();
    // 加载车辆故事
    _loadCarStory();
  }

  Future<void> _loadSoundProfile() async {
    final service = EngineSoundService.instance;
    await service.load();
    if (mounted) {
      setState(() {
        _soundProfile = service.getProfileForCar(car.fullName);
      });
    }
  }

  Future<void> _loadCarStory() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_stories.json',
      );
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final stories = data['stories'] as Map<String, dynamic>?;
      if (stories == null || !mounted) return;

      // 精确匹配
      var story = stories[car.fullName];

      // 模糊匹配：full_name 包含 story key，或 story key 包含 full_name
      if (story == null) {
        final carName = car.fullName.toLowerCase();
        for (final entry in stories.entries) {
          final key = entry.key.toLowerCase();
          if (carName.contains(key) || key.contains(carName)) {
            story = entry.value;
            break;
          }
        }
      }

      // 品牌+型号匹配
      if (story == null) {
        final brandModel = '${car.brand} ${car.model}'.toLowerCase();
        for (final entry in stories.entries) {
          final key = entry.key.toLowerCase();
          if (brandModel.contains(key) || key.contains(brandModel)) {
            story = entry.value;
            break;
          }
        }
      }

      if (story != null && mounted) {
        setState(() => _carStory = story as Map<String, dynamic>);
      }
    } catch (_) {
      // 静默失败
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 试听引擎声音
  Future<void> _toggleEngineSound() async {
    if (_soundProfile == null) return;

    if (_isPlaying) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      try {
        // 优先播放独立引擎声文件
        final safeName = car.fullName.replaceAll(RegExp(r'[<>:"/\\|?*\x27]'), '');
        final individualPath = 'sound/engine_individual/$safeName.wav';

        // 尝试独立文件，失败则 fallback 到通用 profile
        // 注：自 v1.3.1 起引擎声音资源已从 APK 移除（LFS 配额阻塞），此处的播放逻辑保留以备
        // 后续接入 OSS 在线下载方案（点击 → 下载 → 缓存 → 播放）。
        try {
          await _audioPlayer.play(AssetSource(individualPath));
        } catch (_) {
          final profilePath = 'sound/engine/${_soundProfile!.profileId}.wav';
          await _audioPlayer.play(AssetSource(profilePath));
        }

        if (mounted) setState(() => _isPlaying = true);
        _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _isPlaying = false);
        });
      } catch (e) {
        if (mounted) setState(() => _isPlaying = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('引擎声音暂时不可用'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

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
                      const SizedBox(height: 24),

                      // 竖列参数进度条区域
                      if (specs != null && specs.horsepower != null) ...[
                        _buildStatsColumn(specs),
                        const SizedBox(height: 20),
                      ],

                      // 引擎信息行
                      if (specs != null) ...[
                        _buildEngineInfoRow(specs),
                        const SizedBox(height: 24),
                      ],

                      // 分隔线
                      Container(
                        width: double.infinity,
                        height: 1,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      const SizedBox(height: 24),

                      // 音效状态
                      _buildEngineSoundCard(),
                      const SizedBox(height: 24),

                      // 车辆故事
                      if (_carStory != null) ...[
                        _buildStoryCard(),
                        const SizedBox(height: 24),
                      ],

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

  // ═══════════════════════════════════════════════════════════════
  //  竖列参数进度条 — 每行：标签(左) + 进度条(中) + 数值(右)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatsColumn(CarSpecs specs) {
    // 解析档位数为整数
    int gearsValue = 0;
    if (specs.gears != null) {
      final match = RegExp(r'(\d+)').firstMatch(specs.gears!);
      if (match != null) gearsValue = int.tryParse(match.group(1)!) ?? 0;
    }

    // 0-100 加速：越小越好，反转进度条（14s为最慢基准）
    final accelValue = specs.acceleration0100 != null
        ? (14.0 - specs.acceleration0100!).clamp(0.0, 14.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          _buildStatBar(
            label: 'HORSEPOWER',
            value: (specs.horsepower ?? 0).toDouble(),
            maxValue: 2000,
            displayText: '${specs.horsepower ?? "—"} hp',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: 'TORQUE',
            value: (specs.torqueLbft ?? 0).toDouble(),
            maxValue: 1500,
            displayText: '${specs.torqueLbft ?? "—"} lb·ft',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: 'TOP SPEED',
            value: (specs.topSpeedKmh ?? 0).toDouble(),
            maxValue: 450,
            displayText: '${specs.topSpeedKmh ?? "—"} km/h',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: '0-100 KM/H',
            value: accelValue,
            maxValue: 14,
            displayText: specs.acceleration0100 != null
                ? '${specs.acceleration0100!.toStringAsFixed(1)} s'
                : '— s',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: 'DISPLACEMENT',
            value: _parseDisplacement(specs.displacement),
            maxValue: 8.0,
            displayText: specs.displacement ?? '—',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: 'WEIGHT',
            value: (specs.weightKg ?? 0).toDouble(),
            maxValue: 3000,
            displayText: specs.weightKg != null ? '${specs.weightKg} kg' : '—',
          ),
          const SizedBox(height: 14),
          _buildStatBar(
            label: 'GEARS',
            value: gearsValue.toDouble(),
            maxValue: 10,
            displayText: specs.gears ?? '—',
          ),
        ],
      ),
    );
  }

  /// 单行参数进度条：标签(左) + 进度条(中) + 数值(右)
  /// 设计风格与 GarageControlSheet._buildStatBar 一致
  Widget _buildStatBar({
    required String label,
    required double value,
    required double maxValue,
    required String displayText,
  }) {
    final double progress = _animateIn ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 9,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              displayText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final double barWidth = constraints.maxWidth * progress;
            return Container(
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(2.5),
              ),
              alignment: Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                width: barWidth,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  引擎声音卡片 — 显示匹配的声音 Profile
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEngineSoundCard() {
    final hasSound = _soundProfile != null;
    final profileName = _soundProfile?.displayName ?? 'Loading...';
    final engineType = _soundProfile?.engineType ?? '';

    return GestureDetector(
      onTap: hasSound ? _toggleEngineSound : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isPlaying
              ? Colors.white.withOpacity(0.04)
              : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isPlaying
                ? Colors.white.withOpacity(0.15)
                : hasSound
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _isPlaying
                    ? Colors.white.withOpacity(0.12)
                    : hasSound
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _isPlaying
                    ? Icons.stop_rounded
                    : hasSound
                        ? Icons.play_arrow_rounded
                        : Icons.music_note,
                color: _isPlaying
                    ? Colors.white.withOpacity(0.9)
                    : hasSound
                        ? Colors.white.withOpacity(0.6)
                        : Colors.white.withOpacity(0.3),
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isPlaying ? 'Playing...' : 'Engine Sound',
                    style: TextStyle(
                      color: _isPlaying
                          ? Colors.white.withOpacity(0.9)
                          : Colors.white.withOpacity(0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasSound ? profileName : 'Tap to preview',
                    style: TextStyle(
                      color: hasSound
                          ? Colors.white.withOpacity(0.5)
                          : Colors.white.withOpacity(0.3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (engineType.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  engineType,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  车辆故事卡片 — 展示该车的专属传奇
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStoryCard() {
    final title = _carStory!['title'] as String? ?? '';
    final story = _carStory!['story'] as String? ?? '';
    final funFact = _carStory!['fun_fact'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 16,
                color: Colors.white.withOpacity(0.4),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 故事正文
          Text(
            story,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
              height: 1.6,
            ),
          ),

          // 趣味冷知识
          if (funFact.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      funFact,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  引擎信息行 — 排量 + 引擎类型 + 进气方式
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEngineInfoRow(CarSpecs specs) {
    final parts = <String>[
      if (specs.displacement != null && specs.displacement!.isNotEmpty) specs.displacement!,
      if (specs.engine != null && specs.engine!.isNotEmpty) specs.engine!,
      if (specs.aspiration != null && specs.aspiration!.isNotEmpty) specs.aspiration!,
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.settings,
            size: 14,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 解析排量字符串为数值（升）
  double _parseDisplacement(String? displacement) {
    if (displacement == null) return 0;
    final match = RegExp(r'([\d.]+)').firstMatch(displacement);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
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
