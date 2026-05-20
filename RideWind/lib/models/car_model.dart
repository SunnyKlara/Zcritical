/// 🚗 车辆数据模型
///
/// 对应 assets/car_thumbnails/car_index.json 中的条目。
class CarModel {
  final String brand;
  final String model;
  final String fullName;
  final String filename;
  final String url;

  const CarModel({
    required this.brand,
    required this.model,
    required this.fullName,
    required this.filename,
    required this.url,
  });

  factory CarModel.fromJson(Map<String, dynamic> json) {
    return CarModel(
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  /// 本地 asset 路径
  String get assetPath => 'assets/car_thumbnails/$filename';
}
