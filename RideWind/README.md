# Critical Flutter APP

智能风洞模拟器控制应用，通过 BLE 连接 ESP32-S3 硬件。

## 架构

```
lib/
├── core/                    # 基础设施
│   └── result.dart          # 统一 Result<T> 类型
│
├── protocol/                # 协议层（对应 ESP32 services/protocol.c）
│   ├── protocol_parser.dart # 纯函数解析器（30+ 方法，51 个单元测试）
│   ├── command_sender.dart  # 命令构造 + 发送 + 重试
│   ├── response_router.dart # 数据缓冲 + 分包重组 + 流分发
│   └── error_messages.dart  # 设备错误码 → 用户提示映射
│
├── services/                # 服务层
│   ├── ble_service.dart     # BLE 底层（扫描、连接、MTU、重连、队列发送）
│   ├── audio_stream_service.dart
│   ├── logo_transmission_manager.dart
│   ├── ota_upload_service.dart
│   └── ...
│
├── providers/               # 状态管理层
│   ├── bluetooth_provider.dart  # 设备连接 + 状态 + 命令转发
│   └── device_provider.dart     # (待清理)
│
├── configs/                 # 配置
│   └── device_connect_config.dart  # 响应式布局参数
│
├── data/                    # 静态数据
│   ├── led_presets.dart     # 14 种 LED 预设配置
│   └── traditional_chinese_colors.dart
│
├── models/                  # 数据模型
│   ├── device_model.dart
│   ├── speed_report.dart
│   └── logo_slot_status.dart
│
├── screens/                 # 页面
│   ├── device_connect_screen.dart  # 核心控制页（Running/Colorize 模式）
│   ├── device_scan_screen.dart
│   ├── logo_management_screen.dart
│   ├── ota_upgrade_screen.dart
│   ├── audio_stream_screen.dart
│   └── ...
│
├── widgets/                 # 可复用组件
│   ├── running_mode_widget.dart
│   ├── device_connect_helpers.dart
│   └── ...
│
└── utils/                   # 工具
    ├── crc32.dart
    ├── responsive_utils.dart
    └── ...
```

## BLE 协议

通过 BLE Service UUID `0xFFE0`，Characteristic `0xFFE1` 通信。

- 命令格式: `COMMAND:param\n` (APP → ESP32)
- 响应格式: `OK:COMMAND\r\n` (ESP32 → APP)
- 事件上报: `EVENT_REPORT:data\n` (ESP32 → APP)

完整协议文档: [PROTOCOL_SPECIFICATION.md](PROTOCOL_SPECIFICATION.md)

## 开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## 测试

```bash
# 协议解析单元测试（51 个）
flutter test test/protocol/

# 全部测试
flutter test
```
