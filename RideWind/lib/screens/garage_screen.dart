import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/car_model.dart';
import 'car_detail_screen.dart';

/// 🚗 车库页面 — FH5 车辆数据库浏览器
///
/// 暗色背景 + 车辆卡片网格 + 品牌筛选 + 搜索
/// 参考 Horizon 5 Cars APP 设计风格
class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  List<CarModel> _allCars = [];
  List<CarModel> _filteredCars = [];
  List<String> _brands = [];
  String _selectedBrand = 'All';
  String _searchQuery = '';
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCarData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCarData() async {
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/car_index.json',
      );
      final List<dynamic> jsonList = json.decode(jsonStr);
      final cars = jsonList.map((e) => CarModel.fromJson(e)).toList();

      // 提取品牌列表并排序
      final brandSet = <String>{};
      for (final car in cars) {
        if (car.brand.isNotEmpty) brandSet.add(car.brand);
      }
      final brands = brandSet.toList()..sort();

      setState(() {
        _allCars = cars;
        _filteredCars = cars;
        _brands = brands;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 加载车辆数据失败: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredCars = _allCars.where((car) {
        // 品牌筛选
        if (_selectedBrand != 'All' && car.brand != _selectedBrand) {
          return false;
        }
        // 搜索筛选
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          return car.fullName.toLowerCase().contains(query) ||
              car.brand.toLowerCase().contains(query) ||
              car.model.toLowerCase().contains(query);
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部标题栏
            _buildHeader(),
            // 搜索栏
            _buildSearchBar(),
            // 品牌筛选条
            _buildBrandFilter(),
            // 车辆网格
            Expanded(child: _buildCarGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          const Text(
            'GARAGE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_filteredCars.length}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          // 右滑提示箭头
          Icon(
            Icons.chevron_right,
            color: Colors.white.withOpacity(0.2),
            size: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search cars...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _searchQuery = '';
                      _applyFilters();
                    },
                    child: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.3),
                      size: 18,
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (value) {
            _searchQuery = value;
            _applyFilters();
          },
        ),
      ),
    );
  }

  Widget _buildBrandFilter() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _brands.length + 1, // +1 for "All"
        itemBuilder: (context, index) {
          final brand = index == 0 ? 'All' : _brands[index - 1];
          final isSelected = brand == _selectedBrand;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _selectedBrand = brand;
                _applyFilters();
                // 滚动回顶部
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white.withOpacity(0.3)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Text(
                  brand,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCarGrid() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    if (_filteredCars.isEmpty) {
      return Center(
        child: Text(
          'No cars found',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 16,
          ),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _filteredCars.length,
      itemBuilder: (context, index) {
        return _buildCarCard(_filteredCars[index]);
      },
    );
  }

  Widget _buildCarCard(CarModel car) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => CarDetailScreen(car: car),
            transitionDuration: const Duration(milliseconds: 350),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(0.04),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 车辆图片
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF0D0D0D),
                  child: Hero(
                    tag: 'car_${car.filename}',
                    child: Image.asset(
                      car.assetPath,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          Icons.directions_car,
                          color: Colors.white.withOpacity(0.1),
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 车辆信息
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    car.brand,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    car.model,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
