# Critical

智能风洞模拟器 — 硬件 + APP 全栈项目。

风洞通过旋转扇叶模拟不同风速环境，配合 LED 灯效、雾化器、引擎音效，用于骑行训练、产品展示等场景。手机端通过蓝牙连接硬件，实时控制所有参数。

## 硬件

- **主控：** ESP32-S3（双核 240MHz，16MB Flash，板载 BLE 5.0）
- **显示：** 1.14" ST7789 LCD（135×240），SPI 驱动
- **灯带：** WS2812B × 4 条（左/中/右/底），RMT 驱动，14 种预设 + 自定义 RGB
- **风扇：** PWM 调速，0-100 档
- **音频：** I2S DAC 输出，MP3 解码 + 多轨混音（引擎音效 + 背景音乐）
- **交互：** 旋转编码器（旋转 + 单击/长按/三击），LCD 菜单轮盘 UI
- **雾化器：** GPIO 开关控制
- **通信：** BLE GATT（控制通道）+ WiFi TCP（音频投射通道）

## APP

Flutter 跨平台应用，支持 Android / iOS。

主要功能：
- 蓝牙扫描、连接、自动重连
- Running 模式 — 速度滚轮控制，油门模式，km/h 与 mph 切换
- Colorize 模式 — 14 种预设灯效一键切换，四区独立 RGB 调色，亮度调节，流水灯
- Logo 上传 — 拍照或从相册选取，压缩后通过 BLE 分包传输到 LCD 显示
- OTA 固件升级 — 从 GitHub 拉取固件，BLE 分包写入
- WiFi 音频投射 — 手机系统音频通过 WiFi TCP 实时推流到硬件扬声器
- 雾化器、音量控制
- APP 内自动更新

## 项目结构

```
├── .kiro/
│   ├── steering/              AI 协作文档体系
│   │   ├── START-HERE.md      唯一入口（新对话从这里开始）
│   │   ├── specs/             不可变约束（协议真值源）
│   │   ├── guides/            操作指南（AI行为、构建命令）
│   │   └── knowledge/         知识传承（教训、决策、架构设计）
│   └── specs/                 已完成的 Kiro Specs（历史参考）
│
├── ridewind-esp/              ESP32-S3 固件（C, ESP-IDF v5.3.5）
│   └── main/
│       ├── drivers/           硬件驱动（LCD、LED、编码器、PWM、I2S、GPIO）
│       ├── services/          BLE、协议解析、WiFi音频、音频引擎、NVS存储
│       ├── app/               应用逻辑（状态管理、灯效、编码器事件）
│       ├── ui/                LCD菜单状态机（速度/预设/RGB/亮度/音量/Logo）
│       └── config/            引脚定义、板级配置、预设颜色
│
├── RideWind/                  Flutter APP（Dart）
│   └── lib/
│       ├── protocol/          BLE协议层（解析、命令发送、响应路由、错误映射）
│       ├── services/          BLE底层、音频投射、Logo传输、OTA、固件更新
│       ├── providers/         状态管理（BluetoothProvider）
│       ├── controllers/       业务逻辑控制器
│       ├── screens/           页面（启动页、扫描、连接控制、Logo管理、OTA...）
│       ├── widgets/           可复用组件
│       └── models/            数据模型
│
├── f4_26_1.1/                 旧版 STM32F405 固件（仅参考）
├── CONTINUATION_GUIDE.md      Session Handoff（当前状态 + 下一步）
└── DEBUG_PLAN.md              真机调试计划
```

## 通信协议

硬件和 APP 之间通过 BLE 文本协议通信。

- BLE Service: `0xFFE0`，Characteristic: `0xFFE1`
- 命令格式: `COMMAND:param\n`（APP → 硬件）
- 响应格式: `OK:COMMAND:param\r\n`（硬件 → APP）
- 主动上报: `EVENT:data\n`（硬件 → APP，如速度变化、旋钮操作）

支持的控制：风扇速度、LED 预设/RGB/亮度、流水灯、雾化器、音量、速度单位、油门模式、LCD 开关、WiFi 配置、Logo 上传、OTA 升级。

详细协议表见 [protocol-contract.md](.kiro/steering/specs/protocol-contract.md)。

## 构建

### 固件

需要 ESP-IDF v5.3.5 环境。

```bash
cd ridewind-esp
idf.py build
idf.py -p COMx flash
```

### APP

需要 Flutter SDK。

```bash
cd RideWind
flutter pub get
flutter run
```

打包：

```bash
flutter build apk --release    # Android
flutter build ios --release     # iOS
```

## 技术栈

| 层 | 技术 |
|----|------|
| 固件 | C, ESP-IDF v5.3.5, FreeRTOS |
| APP | Flutter / Dart |
| BLE | flutter_blue_plus |
| 状态管理 | Provider + get_it |
| 音频 | Android AudioPlaybackCapture + TCP |
| 存储 | NVS (固件端), SharedPreferences (APP端) |
