/// 🚗 车辆数据模型
///
/// 对应 assets/car_thumbnails/car_specs.json 中的条目。
class CarModel {
  final String brand;
  final String model;
  final String fullName;
  final String filename;
  final String url;
  final CarSpecs? specs;

  const CarModel({
    required this.brand,
    required this.model,
    required this.fullName,
    required this.filename,
    required this.url,
    this.specs,
  });

  factory CarModel.fromJson(Map<String, dynamic> json) {
    return CarModel(
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      fullName: json['full_name'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      url: json['url'] as String? ?? '',
      specs: json['specs'] != null && (json['specs'] as Map).isNotEmpty
          ? CarSpecs.fromJson(json['specs'])
          : null,
    );
  }

  /// 本地 asset 路径
  String get assetPath => 'assets/car_thumbnails/$filename';
}

/// 车辆规格数据
class CarSpecs {
  final String? year;
  final String? origin;
  final String? engine;
  final String? displacement;
  final String? aspiration;
  final int? horsepower;
  final int? torqueLbft;
  final String? layout;
  final String? drivetrain;
  final int? weightLbs;
  final int? weightKg;
  final String? gears;
  final String? weightDist;
  final String? carClass;
  final int? topSpeedKmh;
  final double? acceleration0100;

  const CarSpecs({
    this.year,
    this.origin,
    this.engine,
    this.displacement,
    this.aspiration,
    this.horsepower,
    this.torqueLbft,
    this.layout,
    this.drivetrain,
    this.weightLbs,
    this.weightKg,
    this.gears,
    this.weightDist,
    this.carClass,
    this.topSpeedKmh,
    this.acceleration0100,
  });

  factory CarSpecs.fromJson(Map<String, dynamic> json) {
    return CarSpecs(
      year: json['year'] as String?,
      origin: json['origin'] as String?,
      engine: json['engine'] as String?,
      displacement: json['displacement'] as String?,
      aspiration: json['aspiration'] as String?,
      horsepower: json['horsepower'] as int?,
      torqueLbft: json['torque_lbft'] as int?,
      layout: json['layout'] as String?,
      drivetrain: json['drivetrain'] as String?,
      weightLbs: json['weight_lbs'] as int?,
      weightKg: json['weight_kg'] as int?,
      gears: json['gears'] as String?,
      weightDist: json['weight_dist'] as String?,
      carClass: json['class'] as String?,
      topSpeedKmh: json['top_speed_kmh'] as int?,
      acceleration0100: (json['acceleration_0_100'] as num?)?.toDouble(),
    );
  }
}
