import 'dart:convert';
import 'package:flutter/services.dart';

/// 引擎声音映射服务 — 根据车辆名称查找对应的声音 Profile
class EngineSoundService {
  static EngineSoundService? _instance;
  static EngineSoundService get instance => _instance ??= EngineSoundService._();

  EngineSoundService._();

  Map<String, String> _carToProfile = {};
  Map<String, EngineSoundProfile> _profiles = {};
  bool _loaded = false;

  /// 加载 engine_sound_map.json
  Future<void> load() async {
    if (_loaded) return;
    try {
      final jsonStr = await rootBundle.loadString(
        'assets/car_thumbnails/engine_sound_map.json',
      );
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      // 解析 profiles
      final profilesList = data['profiles'] as List<dynamic>;
      for (final p in profilesList) {
        final profile = EngineSoundProfile.fromJson(p as Map<String, dynamic>);
        _profiles[profile.profileId] = profile;
      }

      // 解析 car_assignments
      final assignments = data['car_assignments'] as List<dynamic>;
      for (final a in assignments) {
        final map = a as Map<String, dynamic>;
        _carToProfile[map['full_name'] as String] = map['sound_profile'] as String;
      }

      _loaded = true;
    } catch (_) {
      // 静默失败，不影响 UI
    }
  }

  /// 获取车辆对应的声音 Profile
  EngineSoundProfile? getProfileForCar(String fullName) {
    final profileId = _carToProfile[fullName];
    if (profileId == null) return null;
    return _profiles[profileId];
  }

  /// 获取车辆对应的 profile ID
  String? getProfileIdForCar(String fullName) => _carToProfile[fullName];
}

/// 引擎声音 Profile 数据
class EngineSoundProfile {
  final String profileId;
  final String displayName;
  final String engineType;
  final String character;

  const EngineSoundProfile({
    required this.profileId,
    required this.displayName,
    required this.engineType,
    required this.character,
  });

  factory EngineSoundProfile.fromJson(Map<String, dynamic> json) {
    return EngineSoundProfile(
      profileId: json['profile_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      engineType: json['engine_type'] as String? ?? '',
      character: json['character'] as String? ?? '',
    );
  }
}
