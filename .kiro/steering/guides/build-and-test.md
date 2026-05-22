---
inclusion: auto
---

# 构建与测试速查

## ESP32 固件（ridewind-esp/）

```bash
cd ridewind-esp
idf.py build                    # 编译
idf.py -p COMx flash            # 烧录（用户操作）
idf.py -p COMx monitor          # 串口监视（用户操作）
idf.py fullclean                # 清理构建
```

目标芯片：ESP32-S3，Flash 8MB，PSRAM 2MB
框架：ESP-IDF v5.3.5，FreeRTOS

## Flutter APP（RideWind/）

```bash
cd RideWind
flutter pub get                  # 拉依赖
flutter analyze                  # 静态分析
flutter test                     # 全部测试
flutter test test/protocol/      # 协议解析测试（51个）
flutter build apk --debug        # Debug APK
flutter build apk --release      # Release APK
flutter run                      # 运行（需连接设备）
```

框架：Flutter/Dart，状态管理 Provider + get_it

## 已知构建注意事项

- `pubspec.yaml` 中 `image: any` 重复出现在 dependencies 和 dev_dependencies（已知，不影响构建）
- 7 个旧测试失败（重构前就有，非回归）
- Android 包名 com.example.ridewind 不要改（改了会导致 MethodChannel 断裂）

## 项目健康指标

| 指标 | 当前值 | 警戒线 |
|------|--------|--------|
| 固件体积 | 3.04MB / 3.14MB (3% free) | <10% free 需优化 |
| Flutter 最大单文件 | ~3500行 | >1000行需拆分 |
| 协议测试覆盖 | 51/51 | 新命令必须有测试 |
| ESP32 编译警告 | 0 | >0 需处理 |

### 维护规则

- 新增 BLE 命令时，必须同步在 `test/protocol/protocol_parser_test.dart` 添加测试
- 单文件超过 500 行时考虑拆分（ESP32 C 文件例外：main.c 因 dispatch 集中允许更长）
- 每次 release 前检查 `idf.py size` 输出，确认 flash 余量 >10%
