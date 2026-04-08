# 🌊 RideWind - 智能LED风扇控制应用

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.9.2-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)
![Bluetooth](https://img.shields.io/badge/Bluetooth-BLE-0082FC?logo=bluetooth)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green)

一款基于Flutter开发的智能LED风扇蓝牙控制应用

</div>

---

## 📖 项目简介

RideWind 是一款物联网应用，通过蓝牙 BLE 与智能 LED 风扇设备进行通信，提供以下核心功能:

- 🔍 **蓝牙设备扫描**: 自动发现并连接 RideWind 设备
- 🎨 **RGB 灯光控制**: 4个独立区域的颜色和亮度调节
- 💨 **风扇转速控制**: 0-100% 无级调速
- 🎭 **预设方案**: 8种预设灯光效果
- 🎯 **三种操作模式**: Cleaning / Running / Colorize
- 💾 **配置保存**: 设置永久保存到设备

---

## 🎯 项目状态

| 模块 | 状态 | 说明 |
|------|------|------|
| UI设计 | ✅ 完成 | 所有界面已实现 |
| 蓝牙架构 | ✅ 完成 | 两套协议方案已准备 |
| 状态管理 | ✅ 完成 | Provider架构已搭建 |
| 硬件集成 | ⚠️ 进行中 | 等待真实设备对接 |
| 测试 | ⏳ 待进行 | 硬件对接后开始 |

**当前阶段**: 从"花瓶应用"过渡到真实硬件连接

---

## 🏗️ 项目架构

```
lib/
├── main.dart                    # 应用入口
├── models/                      # 数据模型
│   ├── device_model.dart        # 设备数据模型
│   └── sound_wave_scanner.dart  # 扫描动画模型
├── providers/                   # 状态管理
│   ├── bluetooth_provider.dart  # 蓝牙状态管理
│   └── device_provider.dart     # 设备状态管理
├── services/                    # 业务逻辑层
│   ├── bluetooth_service.dart         # 基础BLE服务
│   ├── jdy08_bluetooth_service.dart   # JDY-08专用服务 ⭐推荐
│   ├── protocol_service.dart          # JSON协议服务
│   ├── device_control_service.dart    # 高层控制接口
│   └── engine_audio_controller.dart   # 音效控制
├── screens/                     # UI界面
│   ├── splash_screen.dart           # 启动页
│   ├── onboarding_flow_screen.dart  # 引导页
│   ├── device_scan_screen.dart      # 设备扫描
│   ├── device_list_screen.dart      # 设备列表
│   ├── device_connect_screen.dart   # 设备连接/控制
│   ├── rgb_color_screen.dart        # RGB颜色设置
│   ├── cleaning_mode_screen.dart    # 清洁模式
│   └── no_device_screen.dart        # 未连接提示
├── widgets/                     # 自定义组件
│   ├── airflow_button.dart          # 气流按钮
│   ├── running_mode_widget.dart     # 运行模式组件
│   └── user_info_drawer.dart        # 用户信息抽屉
└── utils/                       # 工具类
    └── responsive_utils.dart        # 响应式布局工具
```

---

## 🚀 快速开始

### 环境要求

- Flutter SDK: `≥ 3.9.2`
- Dart SDK: `≥ 3.0.0`
- Android: API 21+ (Android 5.0+)
- iOS: iOS 12.0+

### 安装步骤

1. **克隆项目**
```bash
git clone https://github.com/your-repo/ridewind.git
cd ridewind
```

2. **安装依赖**
```bash
flutter pub get
```

3. **运行应用**
```bash
# Android
flutter run

# iOS
flutter run -d ios

# Windows (调试)
flutter run -d windows
```

### 快速命令

项目根目录提供了便捷脚本:

- **Windows**: 双击 `run.bat` 启动应用
- **命令行**: `flutter run`

---

## 📚 开发文档

| 文档 | 说明 |
|------|------|
| [蓝牙架构文档](BLUETOOTH_ARCHITECTURE.md) | 详细的蓝牙通信架构说明 |
| [硬件集成指南](HARDWARE_INTEGRATION_GUIDE.md) | 硬件对接快速上手指南 |
| [协议规范](PROTOCOL_SPECIFICATION.md) | 完整的通信协议定义 |

---

## 🔌 蓝牙协议

### 支持的协议方案

#### 方案1: 统一二进制协议 (推荐) ⭐
- **文件**: `lib/services/jdy08_bluetooth_service.dart`
- **优势**: 高效、低延迟、数据包小
- **格式**: `[AA] [LEN] [CMD] [DATA...] [CS] [55]`

#### 方案2: JSON文本协议
- **文件**: `lib/services/protocol_service.dart`
- **优势**: 易读、灵活、便于调试
- **格式**: `{"command": "xxx", "value": yyy}`

### 主要命令

| 命令码 | 功能 | 参数 |
|--------|------|------|
| 0x01 | 查询设备状态 | - |
| 0x02 | 设置LED颜色 | zone, R, G, B, brightness |
| 0x03 | 设置整体亮度 | brightness (0-100) |
| 0x04 | 设置风扇转速 | percent (0-100) |
| 0x05 | 选择预设方案 | preset (1-8) |
| 0x06 | 设置工作模式 | mode (0=独立, 1=组合) |
| 0x08 | 紧急停止 | - |
| 0x10 | 保存配置 | - |
| 0x11 | 恢复出厂 | - |

详细协议说明请参考 [协议规范文档](PROTOCOL_SPECIFICATION.md)

---

## 🎨 界面截图

### 主要页面

1. **Splash Screen**: 启动动画页面
2. **Onboarding**: 功能引导页
3. **Device Scan**: 设备扫描页 (声波动画)
4. **Device Connect**: 设备控制主界面
   - Cleaning Mode: 清洁模式
   - Running Mode: 运行模式 (速度控制)
   - Colorize Mode: RGB调色模式
5. **RGB Color**: 高级颜色设置页

---

## 🛠️ 技术栈

### 核心框架
- **Flutter**: 跨平台UI框架
- **Dart**: 编程语言

### 主要依赖
| 库 | 版本 | 用途 |
|----|------|------|
| flutter_blue_plus | ^1.32.12 | BLE蓝牙通信 |
| provider | ^6.1.2 | 状态管理 |
| permission_handler | ^11.3.1 | 权限管理 |
| shared_preferences | ^2.2.3 | 本地存储 |
| google_fonts | ^6.2.1 | 字体库 |
| flutter_svg | ^2.0.10 | SVG图标 |
| audioplayers | ^5.2.1 | 音效播放 |

完整依赖列表见 [pubspec.yaml](pubspec.yaml)

---

## 📱 权限配置

### Android
在 `android/app/src/main/AndroidManifest.xml` 中已配置:
- ✅ BLUETOOTH & BLUETOOTH_ADMIN
- ✅ BLUETOOTH_SCAN & BLUETOOTH_CONNECT (Android 12+)
- ✅ ACCESS_FINE_LOCATION (蓝牙扫描需要)
- ✅ POST_NOTIFICATIONS (Android 13+)

### iOS
需要在 `ios/Runner/Info.plist` 中添加:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙权限以连接 RideWind 设备</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙权限以连接 RideWind 设备</string>
```

---

## 🧪 测试指南

### 单元测试
```bash
flutter test
```

### 集成测试
```bash
flutter drive --target=test_driver/app.dart
```

### 硬件测试流程
1. 扫描设备测试
2. 连接功能测试
3. 命令收发测试
4. 状态监听测试

详细测试步骤见 [硬件集成指南](HARDWARE_INTEGRATION_GUIDE.md)

---

## 🔧 开发调试

### 启用蓝牙日志
```dart
// 在 main.dart 中添加
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose);
  runApp(RideWindApp());
}
```

### 调试工具
- **nRF Connect** (Android/iOS): BLE设备调试
- **LightBlue** (iOS): BLE连接测试
- **Android Studio / Xcode**: IDE调试

---

## 📝 开发计划

### 近期任务 (P0)
- [ ] 获取真实硬件UUID
- [ ] 更新蓝牙服务配置
- [ ] 真机测试连接功能
- [ ] 验证数据包格式
- [ ] 实现错误处理

### 中期任务 (P1)
- [ ] 设备状态实时同步
- [ ] 断线重连机制
- [ ] 本地配置保存
- [ ] 用户引导优化
- [ ] 多语言支持

### 长期任务 (P2)
- [ ] 多设备管理
- [ ] OTA固件升级
- [ ] 使用统计
- [ ] 云端同步
- [ ] 智能场景

---

## 🐛 已知问题

1. **蓝牙UUID待确认**: 当前使用占位符UUID，需替换为真实UUID
2. **协议选择**: 需确认硬件支持哪种协议 (统一协议 or JSON)
3. **iOS蓝牙权限**: 需要配置Info.plist
4. **连接稳定性**: 需真机测试验证

---

## 🤝 贡献指南

欢迎贡献代码！请遵循以下步骤:

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 代码规范
- 遵循 Dart 官方代码风格
- 使用 `flutter analyze` 检查代码
- 添加必要的注释和文档
- 提交前运行测试

---

## 📄 开源协议

本项目采用 MIT 协议开源，详见 [LICENSE](LICENSE) 文件。

---

## 👥 团队

- **App开发**: Flutter团队
- **硬件开发**: STM32团队
- **UI/UX设计**: 设计团队

---

## 📞 联系方式

- 项目Issues: [GitHub Issues](https://github.com/your-repo/ridewind/issues)
- 技术支持: support@ridewind.com
- 官方网站: https://www.ridewind.com

---

## 🙏 致谢

感谢以下开源项目:
- [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus) - BLE蓝牙库
- [provider](https://pub.dev/packages/provider) - 状态管理
- [Flutter](https://flutter.dev) - 跨平台框架

---

<div align="center">

**Built with ❤️ using Flutter**

[文档](docs/) • [问题反馈](issues/) • [更新日志](CHANGELOG.md)

</div>
