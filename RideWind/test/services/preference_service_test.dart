import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ridewind/services/preference_service.dart';

/// PreferenceService 属性测试
/// 
/// **Feature: ux-experience-optimization, Property 3: Preference Storage Round-Trip**
/// **Feature: ux-experience-optimization, Property 4: Device Settings Round-Trip**
/// 
/// **Validates: Requirements 9.1, 9.2, 9.3, 9.5**
/// 
/// Property 3 Description:
/// *For any* valid preference value (color preset index 0-11, speed value 0-340, 
/// atomizer state true/false), saving the value and then retrieving it should 
/// return the same value.
/// 
/// Property 4 Description:
/// *For any* device ID and valid settings map, calling `saveDeviceSettings(deviceId, settings)` 
/// followed by `getDeviceSettings(deviceId)` should return an equivalent settings map.
void main() {
  group('PreferenceService', () {
    late Random random;

    setUp(() {
      // 每个测试前重置 SharedPreferences 模拟值
      SharedPreferences.setMockInitialValues({});
      // 使用固定种子以便测试可重现
      random = Random(42);
    });

    // ============================================================
    // Property 3: Preference Storage Round-Trip
    // Feature: ux-experience-optimization, Property 3: Preference Storage Round-Trip
    // ============================================================

    group('Property 3: Preference Storage Round-Trip', () {
      /// **Validates: Requirements 9.1**
      /// 测试颜色预设索引的 round-trip
      test('round-trip: color preset index - save then get returns same value', () async {
        final service = PreferenceService();
        
        // 测试边界值
        await service.saveColorPreset(0);
        expect(await service.getColorPreset(), 0);
        
        await service.saveColorPreset(11);
        expect(await service.getColorPreset(), 11);
        
        // 测试中间值
        await service.saveColorPreset(5);
        expect(await service.getColorPreset(), 5);
      });

      /// **Validates: Requirements 9.2**
      /// 测试速度值的 round-trip
      test('round-trip: speed value - save then get returns same value', () async {
        final service = PreferenceService();
        
        // 测试边界值
        await service.saveSpeedValue(0);
        expect(await service.getSpeedValue(), 0);
        
        await service.saveSpeedValue(340);
        expect(await service.getSpeedValue(), 340);
        
        // 测试中间值
        await service.saveSpeedValue(170);
        expect(await service.getSpeedValue(), 170);
      });

      /// **Validates: Requirements 9.3**
      /// 测试雾化器状态的 round-trip
      test('round-trip: atomizer state - save then get returns same value', () async {
        final service = PreferenceService();
        
        // 测试 true
        await service.saveAtomizerState(true);
        expect(await service.getAtomizerState(), true);
        
        // 测试 false
        await service.saveAtomizerState(false);
        expect(await service.getAtomizerState(), false);
      });

      /// **Validates: Requirements 9.1**
      /// 属性测试：颜色预设索引 round-trip (100 次迭代)
      /// 对于任意有效的颜色预设索引 (0-11)，保存后读取应返回相同值
      test('property: color preset round-trip holds for all valid indices (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成随机的颜色预设索引 (0-11)
          final colorIndex = random.nextInt(12); // 0 to 11
          
          // 保存
          await service.saveColorPreset(colorIndex);
          
          // 读取并验证
          final retrieved = await service.getColorPreset();
          expect(retrieved, colorIndex,
              reason: 'Iteration $iteration: Color preset $colorIndex should round-trip correctly');
        }
      });

      /// **Validates: Requirements 9.2**
      /// 属性测试：速度值 round-trip (100 次迭代)
      /// 对于任意有效的速度值 (0-340)，保存后读取应返回相同值
      test('property: speed value round-trip holds for all valid values (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成随机的速度值 (0-340)
          final speed = random.nextInt(341); // 0 to 340
          
          // 保存
          await service.saveSpeedValue(speed);
          
          // 读取并验证
          final retrieved = await service.getSpeedValue();
          expect(retrieved, speed,
              reason: 'Iteration $iteration: Speed value $speed should round-trip correctly');
        }
      });

      /// **Validates: Requirements 9.3**
      /// 属性测试：雾化器状态 round-trip (100 次迭代)
      /// 对于任意布尔值，保存后读取应返回相同值
      test('property: atomizer state round-trip holds for all boolean values (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成随机的布尔值
          final atomizerState = random.nextBool();
          
          // 保存
          await service.saveAtomizerState(atomizerState);
          
          // 读取并验证
          final retrieved = await service.getAtomizerState();
          expect(retrieved, atomizerState,
              reason: 'Iteration $iteration: Atomizer state $atomizerState should round-trip correctly');
        }
      });

      /// **Validates: Requirements 9.1, 9.2, 9.3**
      /// 属性测试：所有偏好值组合的 round-trip (100 次迭代)
      /// 对于任意有效的偏好值组合，保存后读取应返回相同值
      test('property: all preferences round-trip together (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成随机的偏好值
          final colorIndex = random.nextInt(12); // 0 to 11
          final speed = random.nextInt(341); // 0 to 340
          final atomizerState = random.nextBool();
          
          // 保存所有偏好
          await service.saveColorPreset(colorIndex);
          await service.saveSpeedValue(speed);
          await service.saveAtomizerState(atomizerState);
          
          // 读取并验证所有偏好
          expect(await service.getColorPreset(), colorIndex,
              reason: 'Iteration $iteration: Color preset $colorIndex should round-trip correctly');
          expect(await service.getSpeedValue(), speed,
              reason: 'Iteration $iteration: Speed value $speed should round-trip correctly');
          expect(await service.getAtomizerState(), atomizerState,
              reason: 'Iteration $iteration: Atomizer state $atomizerState should round-trip correctly');
        }
      });

      /// **Validates: Requirements 9.1, 9.2, 9.3**
      /// 属性测试：保存操作是幂等的
      test('property: save operations are idempotent (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final colorIndex = random.nextInt(12);
          final speed = random.nextInt(341);
          final atomizerState = random.nextBool();
          
          // 多次保存相同的值
          for (int i = 0; i < 3; i++) {
            await service.saveColorPreset(colorIndex);
            await service.saveSpeedValue(speed);
            await service.saveAtomizerState(atomizerState);
          }
          
          // 验证值保持不变
          expect(await service.getColorPreset(), colorIndex,
              reason: 'Iteration $iteration: Color preset should remain $colorIndex after multiple saves');
          expect(await service.getSpeedValue(), speed,
              reason: 'Iteration $iteration: Speed should remain $speed after multiple saves');
          expect(await service.getAtomizerState(), atomizerState,
              reason: 'Iteration $iteration: Atomizer state should remain $atomizerState after multiple saves');
        }
      });

      /// **Validates: Requirements 9.1, 9.2, 9.3**
      /// 属性测试：不同 PreferenceService 实例共享状态
      test('property: different instances share state via SharedPreferences', () async {
        final service1 = PreferenceService();
        final service2 = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final colorIndex = random.nextInt(12);
          final speed = random.nextInt(341);
          final atomizerState = random.nextBool();
          
          // 通过 service1 保存
          await service1.saveColorPreset(colorIndex);
          await service1.saveSpeedValue(speed);
          await service1.saveAtomizerState(atomizerState);
          
          // 通过 service2 读取
          expect(await service2.getColorPreset(), colorIndex,
              reason: 'Iteration $iteration: Color preset should be shared between instances');
          expect(await service2.getSpeedValue(), speed,
              reason: 'Iteration $iteration: Speed should be shared between instances');
          expect(await service2.getAtomizerState(), atomizerState,
              reason: 'Iteration $iteration: Atomizer state should be shared between instances');
        }
      });

      /// **Validates: Requirements 9.1, 9.2, 9.3**
      /// 属性测试：覆盖写入正确更新值
      test('property: overwriting values correctly updates stored data (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 保存初始值
          final initialColor = random.nextInt(12);
          final initialSpeed = random.nextInt(341);
          final initialAtomizer = random.nextBool();
          
          await service.saveColorPreset(initialColor);
          await service.saveSpeedValue(initialSpeed);
          await service.saveAtomizerState(initialAtomizer);
          
          // 保存新值
          final newColor = random.nextInt(12);
          final newSpeed = random.nextInt(341);
          final newAtomizer = random.nextBool();
          
          await service.saveColorPreset(newColor);
          await service.saveSpeedValue(newSpeed);
          await service.saveAtomizerState(newAtomizer);
          
          // 验证新值
          expect(await service.getColorPreset(), newColor,
              reason: 'Iteration $iteration: Color preset should be updated to $newColor');
          expect(await service.getSpeedValue(), newSpeed,
              reason: 'Iteration $iteration: Speed should be updated to $newSpeed');
          expect(await service.getAtomizerState(), newAtomizer,
              reason: 'Iteration $iteration: Atomizer state should be updated to $newAtomizer');
        }
      });

      /// **Validates: Requirements 9.1, 9.2, 9.3**
      /// 属性测试：边界值测试
      test('property: boundary values round-trip correctly', () async {
        final service = PreferenceService();
        
        // 颜色预设边界值
        final colorBoundaries = [0, 11];
        for (final color in colorBoundaries) {
          await service.saveColorPreset(color);
          expect(await service.getColorPreset(), color,
              reason: 'Color preset boundary $color should round-trip correctly');
        }
        
        // 速度边界值
        final speedBoundaries = [0, 340];
        for (final speed in speedBoundaries) {
          await service.saveSpeedValue(speed);
          expect(await service.getSpeedValue(), speed,
              reason: 'Speed boundary $speed should round-trip correctly');
        }
        
        // 雾化器状态边界值
        final atomizerBoundaries = [true, false];
        for (final atomizer in atomizerBoundaries) {
          await service.saveAtomizerState(atomizer);
          expect(await service.getAtomizerState(), atomizer,
              reason: 'Atomizer state boundary $atomizer should round-trip correctly');
        }
      });
    });


    // ============================================================
    // Property 4: Device Settings Round-Trip
    // Feature: ux-experience-optimization, Property 4: Device Settings Round-Trip
    // ============================================================

    group('Property 4: Device Settings Round-Trip', () {
      /// 生成随机设备 ID
      String generateRandomDeviceId(Random random) {
        const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
        final length = random.nextInt(20) + 5; // 5 to 24 characters
        return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
      }

      /// 生成随机设置 Map
      Map<String, dynamic> generateRandomSettings(Random random) {
        final settings = <String, dynamic>{};
        
        // 随机添加颜色预设
        if (random.nextBool()) {
          settings['colorPreset'] = random.nextInt(12);
        }
        
        // 随机添加速度值
        if (random.nextBool()) {
          settings['speed'] = random.nextInt(341);
        }
        
        // 随机添加雾化器状态
        if (random.nextBool()) {
          settings['atomizer'] = random.nextBool();
        }
        
        // 随机添加亮度值
        if (random.nextBool()) {
          settings['brightness'] = random.nextInt(101); // 0 to 100
        }
        
        // 随机添加字符串值
        if (random.nextBool()) {
          settings['customName'] = 'device_${random.nextInt(1000)}';
        }
        
        // 随机添加浮点数值
        if (random.nextBool()) {
          settings['temperature'] = random.nextDouble() * 100;
        }
        
        // 确保至少有一个键值对
        if (settings.isEmpty) {
          settings['defaultKey'] = 'defaultValue';
        }
        
        return settings;
      }

      /// **Validates: Requirements 9.5**
      /// 测试设备设置的基本 round-trip
      test('round-trip: device settings - save then get returns equivalent map', () async {
        final service = PreferenceService();
        
        const deviceId = 'test_device_001';
        final settings = {
          'colorPreset': 3,
          'speed': 100,
          'atomizer': true,
          'brightness': 80,
        };
        
        // 保存设置
        await service.saveDeviceSettings(deviceId, settings);
        
        // 读取并验证
        final retrieved = await service.getDeviceSettings(deviceId);
        expect(retrieved, isNotNull);
        expect(retrieved, equals(settings));
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：设备设置 round-trip (100 次迭代)
      /// 对于任意设备 ID 和有效设置 Map，保存后读取应返回等价的 Map
      test('property: device settings round-trip holds for random device IDs and settings (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成随机设备 ID 和设置
          final deviceId = generateRandomDeviceId(random);
          final settings = generateRandomSettings(random);
          
          // 保存设置
          await service.saveDeviceSettings(deviceId, settings);
          
          // 读取并验证
          final retrieved = await service.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Iteration $iteration: Device settings for $deviceId should not be null');
          
          // 验证所有键值对
          for (final key in settings.keys) {
            expect(retrieved!.containsKey(key), true,
                reason: 'Iteration $iteration: Retrieved settings should contain key $key');
            
            // 对于浮点数，使用近似比较
            if (settings[key] is double) {
              expect((retrieved[key] as double), closeTo(settings[key] as double, 0.0001),
                  reason: 'Iteration $iteration: Value for key $key should match');
            } else {
              expect(retrieved[key], settings[key],
                  reason: 'Iteration $iteration: Value for key $key should match');
            }
          }
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：不同设备的设置相互独立
      test('property: different devices have independent settings (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          // 生成两个不同的设备 ID 和设置
          final deviceId1 = 'device_a_${random.nextInt(1000)}';
          final deviceId2 = 'device_b_${random.nextInt(1000)}';
          final settings1 = generateRandomSettings(random);
          final settings2 = generateRandomSettings(random);
          
          // 保存两个设备的设置
          await service.saveDeviceSettings(deviceId1, settings1);
          await service.saveDeviceSettings(deviceId2, settings2);
          
          // 验证设备 1 的设置
          final retrieved1 = await service.getDeviceSettings(deviceId1);
          expect(retrieved1, isNotNull,
              reason: 'Iteration $iteration: Device 1 settings should not be null');
          for (final key in settings1.keys) {
            if (settings1[key] is double) {
              expect((retrieved1![key] as double), closeTo(settings1[key] as double, 0.0001),
                  reason: 'Iteration $iteration: Device 1 value for key $key should match');
            } else {
              expect(retrieved1![key], settings1[key],
                  reason: 'Iteration $iteration: Device 1 value for key $key should match');
            }
          }
          
          // 验证设备 2 的设置
          final retrieved2 = await service.getDeviceSettings(deviceId2);
          expect(retrieved2, isNotNull,
              reason: 'Iteration $iteration: Device 2 settings should not be null');
          for (final key in settings2.keys) {
            if (settings2[key] is double) {
              expect((retrieved2![key] as double), closeTo(settings2[key] as double, 0.0001),
                  reason: 'Iteration $iteration: Device 2 value for key $key should match');
            } else {
              expect(retrieved2![key], settings2[key],
                  reason: 'Iteration $iteration: Device 2 value for key $key should match');
            }
          }
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：覆盖设备设置正确更新
      test('property: overwriting device settings correctly updates stored data (100 iterations)', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final deviceId = generateRandomDeviceId(random);
          
          // 保存初始设置
          final initialSettings = generateRandomSettings(random);
          await service.saveDeviceSettings(deviceId, initialSettings);
          
          // 保存新设置
          final newSettings = generateRandomSettings(random);
          await service.saveDeviceSettings(deviceId, newSettings);
          
          // 验证新设置
          final retrieved = await service.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Iteration $iteration: Device settings should not be null after update');
          
          for (final key in newSettings.keys) {
            if (newSettings[key] is double) {
              expect((retrieved![key] as double), closeTo(newSettings[key] as double, 0.0001),
                  reason: 'Iteration $iteration: Updated value for key $key should match');
            } else {
              expect(retrieved![key], newSettings[key],
                  reason: 'Iteration $iteration: Updated value for key $key should match');
            }
          }
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：不同 PreferenceService 实例共享设备设置
      test('property: different instances share device settings via SharedPreferences', () async {
        final service1 = PreferenceService();
        final service2 = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final deviceId = generateRandomDeviceId(random);
          final settings = generateRandomSettings(random);
          
          // 通过 service1 保存
          await service1.saveDeviceSettings(deviceId, settings);
          
          // 通过 service2 读取
          final retrieved = await service2.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Iteration $iteration: Device settings should be shared between instances');
          
          for (final key in settings.keys) {
            if (settings[key] is double) {
              expect((retrieved![key] as double), closeTo(settings[key] as double, 0.0001),
                  reason: 'Iteration $iteration: Shared value for key $key should match');
            } else {
              expect(retrieved![key], settings[key],
                  reason: 'Iteration $iteration: Shared value for key $key should match');
            }
          }
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：空设置 Map 的 round-trip
      test('property: empty settings map round-trip correctly', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final deviceId = generateRandomDeviceId(random);
          final emptySettings = <String, dynamic>{};
          
          // 保存空设置
          await service.saveDeviceSettings(deviceId, emptySettings);
          
          // 读取并验证
          final retrieved = await service.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Iteration $iteration: Empty settings should not return null');
          expect(retrieved, isEmpty,
              reason: 'Iteration $iteration: Empty settings should round-trip as empty map');
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：特殊字符设备 ID 的 round-trip
      test('property: device IDs with special characters round-trip correctly', () async {
        final service = PreferenceService();
        
        final specialDeviceIds = [
          'device-with-dashes',
          'device_with_underscores',
          'device123',
          'UPPERCASE_DEVICE',
          'MixedCase_Device-123',
          'a', // 单字符
          'very_long_device_id_that_is_quite_lengthy_indeed',
        ];
        
        for (final deviceId in specialDeviceIds) {
          final settings = generateRandomSettings(random);
          
          // 保存设置
          await service.saveDeviceSettings(deviceId, settings);
          
          // 读取并验证
          final retrieved = await service.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Device ID "$deviceId" settings should not be null');
          
          for (final key in settings.keys) {
            if (settings[key] is double) {
              expect((retrieved![key] as double), closeTo(settings[key] as double, 0.0001),
                  reason: 'Device ID "$deviceId": value for key $key should match');
            } else {
              expect(retrieved![key], settings[key],
                  reason: 'Device ID "$deviceId": value for key $key should match');
            }
          }
        }
      });

      /// **Validates: Requirements 9.5**
      /// 属性测试：各种数据类型的设置值 round-trip
      test('property: various data types in settings round-trip correctly', () async {
        final service = PreferenceService();
        
        for (int iteration = 0; iteration < 100; iteration++) {
          final deviceId = generateRandomDeviceId(random);
          
          // 创建包含各种数据类型的设置
          final settings = <String, dynamic>{
            'intValue': random.nextInt(1000),
            'doubleValue': random.nextDouble() * 100,
            'boolValue': random.nextBool(),
            'stringValue': 'test_string_${random.nextInt(100)}',
            'nullableInt': random.nextBool() ? random.nextInt(100) : null,
          };
          
          // 保存设置
          await service.saveDeviceSettings(deviceId, settings);
          
          // 读取并验证
          final retrieved = await service.getDeviceSettings(deviceId);
          expect(retrieved, isNotNull,
              reason: 'Iteration $iteration: Settings with various types should not be null');
          
          expect(retrieved!['intValue'], settings['intValue'],
              reason: 'Iteration $iteration: Int value should match');
          expect((retrieved['doubleValue'] as double), closeTo(settings['doubleValue'] as double, 0.0001),
              reason: 'Iteration $iteration: Double value should match');
          expect(retrieved['boolValue'], settings['boolValue'],
              reason: 'Iteration $iteration: Bool value should match');
          expect(retrieved['stringValue'], settings['stringValue'],
              reason: 'Iteration $iteration: String value should match');
          expect(retrieved['nullableInt'], settings['nullableInt'],
              reason: 'Iteration $iteration: Nullable int value should match');
        }
      });

      /// **Validates: Requirements 9.5**
      /// 测试清除设备设置
      test('clearDeviceSettings removes device settings', () async {
        final service = PreferenceService();
        
        const deviceId = 'test_device_clear';
        final settings = {'key': 'value'};
        
        // 保存设置
        await service.saveDeviceSettings(deviceId, settings);
        expect(await service.getDeviceSettings(deviceId), isNotNull);
        
        // 清除设置
        await service.clearDeviceSettings(deviceId);
        
        // 验证设置已被清除
        expect(await service.getDeviceSettings(deviceId), isNull);
      });

      /// **Validates: Requirements 9.5**
      /// 测试获取不存在的设备设置返回 null
      test('getDeviceSettings returns null for non-existent device', () async {
        final service = PreferenceService();
        
        final result = await service.getDeviceSettings('non_existent_device');
        expect(result, isNull);
      });
    });

    // ============================================================
    // 边界情况测试
    // ============================================================

    group('Edge Cases', () {
      /// 测试默认值
      test('returns default values when no preferences saved', () async {
        final service = PreferenceService();
        
        expect(await service.getColorPreset(), 0);
        expect(await service.getSpeedValue(), 0);
        expect(await service.getAtomizerState(), false);
      });

      /// 测试带有预设值的 SharedPreferences
      test('handles pre-existing preference values', () async {
        SharedPreferences.setMockInitialValues({
          'last_color_preset': 5,
          'last_speed_value': 200,
          'last_atomizer_state': true,
        });
        
        final service = PreferenceService();
        
        expect(await service.getColorPreset(), 5);
        expect(await service.getSpeedValue(), 200);
        expect(await service.getAtomizerState(), true);
      });

      /// 测试 reset 方法
      test('reset clears all preference values', () async {
        final service = PreferenceService();
        
        // 保存一些值
        await service.saveColorPreset(7);
        await service.saveSpeedValue(150);
        await service.saveAtomizerState(true);
        
        // 验证值已保存
        expect(await service.getColorPreset(), 7);
        expect(await service.getSpeedValue(), 150);
        expect(await service.getAtomizerState(), true);
        
        // 重置
        await service.reset();
        
        // 验证值已重置为默认值
        expect(await service.getColorPreset(), 0);
        expect(await service.getSpeedValue(), 0);
        expect(await service.getAtomizerState(), false);
      });

      /// 测试 reset 不影响设备设置
      test('reset does not affect device settings', () async {
        final service = PreferenceService();
        
        // 保存偏好和设备设置
        await service.saveColorPreset(7);
        await service.saveDeviceSettings('device_1', {'key': 'value'});
        
        // 重置偏好
        await service.reset();
        
        // 验证偏好已重置
        expect(await service.getColorPreset(), 0);
        
        // 验证设备设置未受影响
        final deviceSettings = await service.getDeviceSettings('device_1');
        expect(deviceSettings, isNotNull);
        expect(deviceSettings!['key'], 'value');
      });

      /// 测试带有预设设备设置的 SharedPreferences
      test('handles pre-existing device settings', () async {
        SharedPreferences.setMockInitialValues({
          'device_settings_device_123': '{"colorPreset":3,"speed":100}',
        });
        
        final service = PreferenceService();
        
        final settings = await service.getDeviceSettings('device_123');
        expect(settings, isNotNull);
        expect(settings!['colorPreset'], 3);
        expect(settings['speed'], 100);
      });

      /// 测试嵌套 Map 的设备设置
      test('handles nested map in device settings', () async {
        final service = PreferenceService();
        
        final settings = {
          'simple': 'value',
          'nested': {
            'level1': {
              'level2': 'deep_value',
            },
          },
          'list': [1, 2, 3],
        };
        
        await service.saveDeviceSettings('nested_device', settings);
        
        final retrieved = await service.getDeviceSettings('nested_device');
        expect(retrieved, isNotNull);
        expect(retrieved!['simple'], 'value');
        expect(retrieved['nested'], isA<Map>());
        expect((retrieved['nested'] as Map)['level1'], isA<Map>());
        expect(((retrieved['nested'] as Map)['level1'] as Map)['level2'], 'deep_value');
        expect(retrieved['list'], [1, 2, 3]);
      });
    });

    // ============================================================
    // Custom RGB Colors Persistence
    // Feature: app-ux-and-color-bug-fix, Task 1.1
    // ============================================================

    group('Custom RGB Colors Persistence', () {
      /// **Validates: Requirements 4.1, 4.4**
      /// 测试自定义 RGB 颜色的基本 round-trip
      test('round-trip: saveCustomRGBColors then getCustomRGBColors returns same data', () async {
        final service = PreferenceService();

        final zoneColors = <String, Map<String, int>>{
          'L': {'r': 255, 'g': 128, 'b': 0},
          'M': {'r': 100, 'g': 200, 'b': 50},
          'R': {'r': 0, 'g': 0, 'b': 255},
          'B': {'r': 10, 'g': 20, 'b': 30},
        };

        await service.saveCustomRGBColors(zoneColors);
        final retrieved = await service.getCustomRGBColors();

        expect(retrieved, isNotNull);
        expect(retrieved, equals(zoneColors));
      });

      /// **Validates: Requirements 4.1, 4.4**
      /// 测试边界 RGB 值 (0 和 255)
      test('round-trip: boundary RGB values 0 and 255', () async {
        final service = PreferenceService();

        final zoneColors = <String, Map<String, int>>{
          'L': {'r': 0, 'g': 0, 'b': 0},
          'M': {'r': 255, 'g': 255, 'b': 255},
          'R': {'r': 0, 'g': 255, 'b': 0},
          'B': {'r': 255, 'g': 0, 'b': 255},
        };

        await service.saveCustomRGBColors(zoneColors);
        final retrieved = await service.getCustomRGBColors();

        expect(retrieved, isNotNull);
        expect(retrieved, equals(zoneColors));
      });

      /// **Validates: Requirements 4.3**
      /// 测试 clearCustomRGBColors 清除颜色数据和标志位
      test('clearCustomRGBColors removes color data and flag', () async {
        final service = PreferenceService();

        final zoneColors = <String, Map<String, int>>{
          'L': {'r': 100, 'g': 100, 'b': 100},
        };

        await service.saveCustomRGBColors(zoneColors);
        await service.saveHasCustomColors(true);

        // Verify saved
        expect(await service.getCustomRGBColors(), isNotNull);
        expect(await service.getHasCustomColors(), true);

        // Clear
        await service.clearCustomRGBColors();

        // Verify cleared
        expect(await service.getCustomRGBColors(), isNull);
        expect(await service.getHasCustomColors(), false);
      });

      /// **Validates: Requirements 4.1**
      /// 测试 getCustomRGBColors 在无数据时返回 null
      test('getCustomRGBColors returns null when no data saved', () async {
        final service = PreferenceService();
        final result = await service.getCustomRGBColors();
        expect(result, isNull);
      });

      /// 测试 clamp(0, 255) 约束 RGB 值
      test('getCustomRGBColors clamps RGB values to 0-255 range', () async {
        // Manually set corrupted data with out-of-range values
        SharedPreferences.setMockInitialValues({
          'custom_rgb_colors': '{"L":{"r":300,"g":-10,"b":128},"M":{"r":256,"g":0,"b":999}}',
        });

        final service = PreferenceService();
        final retrieved = await service.getCustomRGBColors();

        expect(retrieved, isNotNull);
        expect(retrieved!['L']!['r'], 255); // 300 clamped to 255
        expect(retrieved['L']!['g'], 0);    // -10 clamped to 0
        expect(retrieved['L']!['b'], 128);  // 128 unchanged
        expect(retrieved['M']!['r'], 255);  // 256 clamped to 255
        expect(retrieved['M']!['g'], 0);    // 0 unchanged
        expect(retrieved['M']!['b'], 255);  // 999 clamped to 255
      });

      /// 测试损坏的 JSON 数据返回 null
      test('getCustomRGBColors returns null for corrupted JSON data', () async {
        SharedPreferences.setMockInitialValues({
          'custom_rgb_colors': 'not_valid_json',
        });

        final service = PreferenceService();
        final result = await service.getCustomRGBColors();
        expect(result, isNull);
      });

      /// 测试覆盖写入正确更新
      test('overwriting custom RGB colors updates stored data', () async {
        final service = PreferenceService();

        final initial = <String, Map<String, int>>{
          'L': {'r': 10, 'g': 20, 'b': 30},
        };
        await service.saveCustomRGBColors(initial);

        final updated = <String, Map<String, int>>{
          'L': {'r': 200, 'g': 100, 'b': 50},
          'R': {'r': 0, 'g': 255, 'b': 128},
        };
        await service.saveCustomRGBColors(updated);

        final retrieved = await service.getCustomRGBColors();
        expect(retrieved, equals(updated));
      });

      /// 测试 reset 也清除自定义颜色数据
      test('reset clears custom RGB colors and flag', () async {
        final service = PreferenceService();

        await service.saveCustomRGBColors({
          'L': {'r': 1, 'g': 2, 'b': 3},
        });
        await service.saveHasCustomColors(true);

        await service.reset();

        expect(await service.getCustomRGBColors(), isNull);
        expect(await service.getHasCustomColors(), false);
      });
    });

    // ============================================================
    // Has Custom Colors Flag
    // Feature: app-ux-and-color-bug-fix, Task 1.1
    // ============================================================

    group('Has Custom Colors Flag', () {
      /// **Validates: Requirements 3.4**
      /// 测试颜色来源标志位 round-trip
      test('round-trip: saveHasCustomColors then getHasCustomColors', () async {
        final service = PreferenceService();

        await service.saveHasCustomColors(true);
        expect(await service.getHasCustomColors(), true);

        await service.saveHasCustomColors(false);
        expect(await service.getHasCustomColors(), false);
      });

      /// 测试默认值为 false
      test('getHasCustomColors returns false by default', () async {
        final service = PreferenceService();
        expect(await service.getHasCustomColors(), false);
      });

      /// 测试不同实例共享标志位状态
      test('different instances share hasCustomColors flag', () async {
        final service1 = PreferenceService();
        final service2 = PreferenceService();

        await service1.saveHasCustomColors(true);
        expect(await service2.getHasCustomColors(), true);
      });
    });
  });
}
