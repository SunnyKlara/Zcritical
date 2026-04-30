# Critical 项目开发续接文档

> **用途：** 换会话/换设备/改文件夹名后，把这份文档发给 AI 助手即可继续开发。
> **最后更新：** 2026-04-30

---

## 一、项目概况

Critical 是一款智能风洞模拟器产品。硬件端基于 ESP32-S3，通过 BLE 与 Flutter 手机 APP 通信，控制风扇、LED 灯带、雾化器、LCD 屏幕和音频系统。

> 品牌名已从 RideWind 更名为 Critical（2026-04-29）。代码中用户可见的品牌名已全部替换，内部包名（com.example.ridewind）和 Dart 包名（package:ridewind）暂未改动，避免构建问题。

### 工作区目录

```
zcritical/                     （原 4.8/，根目录文件夹）
├── ridewind-esp/              ESP32-S3 固件（C, ESP-IDF v5.3.5）     ✅ 已完成
├── RideWind/                  Flutter 手机 APP（Dart）                🔧 正在重构
├── f4_26_1.1/                 旧 STM32F405 固件                      📦 仅参考
├── audio参考项目/              PlatformIO 音频参考                     📦 仅参考
├── ESPtest/                   ESP32 测试项目                          📦 仅参考
├── Tixing-main/               旧版 Python 显示代码                    📦 仅参考
├── .kiro/specs/               Kiro spec 文档（3个spec，全部完成）
└── CONTINUATION_GUIDE.md      本文档
```

### 开发阶段

| 阶段 | 内容 | 状态 |
|------|------|------|
| 1 | STM32→ESP32 硬件迁移（固件完全重写） | ✅ 完成 |
| 2 | ESP32 LCD 菜单轮盘 UI 重构 | ✅ 完成 |
| 3 | APP 适配 ESP32 协议（14项需求，17个任务） | ✅ 完成 |
| 4 | APP 架构重构（协议层✅ Provider✅ Screen部分✅ DI✅） | 🔧 进行中 |
| 4.5 | 引擎音效系统重写（4层可变采样率合成引擎） | ✅ 完成 |
| 5 | 用户自定义引擎音频上传功能 | ✅ 完成 |
| 6 | 真机联调验证 | ⬜ 待做 |
| 7 | 上架准备（CI/CD、国际化） | ⬜ 待做 |

---

## 二、ESP32 固件（ridewind-esp/）

### 分层架构

```
ridewind-esp/main/
├── drivers/     硬件驱动：drv_lcd(ST7789), drv_led(WS2812B), drv_encoder, drv_pwm, drv_audio(I2S), drv_gpio
├── services/    服务层：ble_service(GATT), protocol(文本协议), wifi_audio_service(TCP), audio_engine(WiFi音频混音), audio_player(4层引擎声合成), storage(NVS)
├── app/         应用层：app_state(全局状态), led_effects(14种预设), encoder_handler(编码器事件)
├── ui/          UI状态机：ui_manager, ui_speed, ui_preset, ui_rgb, ui_bright, ui_volume, ui_logo, ui_menu
├── config/      配置：pin_config.h, board_config.h, preset_colors.h
└── resources/   资源：字体、图片数组
```

### BLE 协议

**Service UUID: `0xFFE0` / Characteristic UUID: `0xFFE1`**
**设备广播名: `T1`**

#### APP→ESP32 命令

| 命令 | 参数 | 说明 | 响应 |
|------|------|------|------|
| `FAN:speed` | 0-100 | 风扇速度 | `OK:FAN:speed\r\n` |
| `SPEED:value` | 0-340 | 运行模式速度 | 无（高频命令） |
| `PRESET:index` | 1-14 | LED预设方案 | `OK:PRESET:index\r\n` |
| `LED:strip:r:g:b` | strip=1-4, rgb=0-255 | RGB调色 | `OK:LED\r\n` |
| `BRIGHT:value` | 0-100 | 全局亮度 | `OK:BRIGHT:value\r\n` |
| `STREAMLIGHT:x` | 0/1 | 流水灯开关 | `OK:STREAMLIGHT:x\r\n` |
| `VOL:value` | 0-100 | 音量 | `OK:VOL:value\r\n` |
| `WUHUA:x` | 0/1 | 雾化器开关 | `OK:WUHUA:x\r\n` |
| `UI:index` | 0-6 | 硬件UI切换 | `OK:UI:index\r\n` |
| `THROTTLE:x` | 0/1 | 油门模式 | `OK:THROTTLE:x\r\n` |
| `UNIT:x` | 0=km/h, 1=mph | 速度单位 | `OK:UNIT:x\r\n` |
| `LCD:x` | 0/1 | LCD开关 | `OK:LCD:x\r\n` |
| `WIFI:ssid:password` | 字符串 | WiFi凭据 | `WIFI_IP:x.x.x.x\r\n` 或 `WIFI_ERR:reason\r\n` |
| `GET:ALL` | 无 | 查询全部状态 | `STATUS:FAN:x:WUHUA:x:BRIGHT:x\r\n` |
| `GET:FAN` | 无 | 查询风扇速度 | `FAN:x\r\n` |
| `GET:WUHUA` | 无 | 查询雾化器 | `WUHUA:x\r\n` |
| `GET:PRESET` | 无 | 查询当前预设 | `PRESET_REPORT:x\r\n` |
| `GET:VOL` | 无 | 查询音量 | `VOL:x\r\n` |
| `GET:STREAMLIGHT` | 无 | 查询流水灯 | `STREAMLIGHT:x\r\n` |
| `GET:LOGO_SLOTS` | 无 | 查询Logo槽位 | `LOGO_SLOTS:v0:v1:v2:active\r\n` |
| `LOGO_START:size:crc32` | 字节数:CRC32 | Logo上传开始 | `LOGO_READY:slot\r\n` |
| `LOGO_DATA:seq:hex` | 序号:十六进制 | Logo数据包 | `LOGO_ACK:seq\r\n` |
| `LOGO_END` | 无 | Logo上传结束 | `LOGO_OK:slot\r\n` 或 `LOGO_FAIL:reason\r\n` |
| `OTA_START:size:crc32` | 字节数:CRC32 | OTA升级开始 | `OTA_READY\r\n` |
| `OTA_DATA:seq:hex` | 序号:十六进制 | OTA数据包 | `OTA_ACK:seq\r\n` |
| `OTA_END` | 无 | OTA升级结束 | `OTA_OK\r\n` 或 `OTA_FAIL:reason\r\n` |
| `AUDIO_START_BIN:layer:size:crc32` | layer=0-3, 字节数, CRC32 | 音频上传开始(二进制) | `AUDIO_READY:layer\r\n` |
| `AUDIO_END` | 无 | 音频上传结束 | `AUDIO_OK:layer\r\n` 或 `AUDIO_FAIL:reason\r\n` |
| `AUDIO_DELETE` | 无 | 删除全部自定义音频 | `OK:AUDIO_DELETE_ALL\r\n` |
| `AUDIO_DELETE:layer` | 0-3 | 删除指定层音频 | `OK:AUDIO_DELETE:layer\r\n` |
| `GET:AUDIO` | 无 | 查询自定义音频状态 | `AUDIO_STATUS:v0:v1:v2:v3:custom\r\n` |

#### ESP32→APP 主动上报

| 事件 | 格式 | 说明 |
|------|------|------|
| 速度报告 | `SPEED_REPORT:value:unit\n` | value=0-340, unit=0(km/h)/1(mph) |
| 油门报告 | `THROTTLE_REPORT:0/1\n` | 硬件三击进入/退出油门模式 |
| 单位报告 | `UNIT_REPORT:0/1\n` | 硬件单击切换单位 |
| 预设报告 | `PRESET_REPORT:1-14\n` | 硬件旋钮切换预设 |
| 流水灯报告 | `STREAMLIGHT_REPORT:0/1\n` | 流水灯状态变化 |
| 引擎通知 | `ENGINE_START\n` / `ENGINE_READY\n` | 开机时上报 |
| 按钮事件 | `BTN:type:action\n` | type=KNOB, action=CLICK/LONG/TRIPLE |
| 旋钮增量 | `KNOB:delta\n` | 正=顺时针，负=逆时针 |
| WiFi IP | `WIFI_IP:x.x.x.x\r\n` | ESP32连接WiFi后上报 |
| WiFi错误 | `WIFI_ERR:reason\r\n` | WiFi连接失败 |
| 音频就绪 | `AUDIO_READY:ip:port\r\n` | TCP音频服务器就绪 |
| 音频上传ACK | `AUDIO_ACK_BIN:bytes\r\n` | 音频上传字节确认 |
| 音频重载 | `AUDIO_RELOAD:OK\r\n` | 4层全部上传后自动重载 |

---

## 三、Flutter APP（RideWind/）

### 架构

```
lib/
├── core/          service_locator.dart (get_it DI), result.dart
├── protocol/      protocol_parser.dart, command_sender.dart, response_router.dart, error_messages.dart
├── services/      ble_service.dart, audio_stream_service.dart, logo_transmission_manager.dart, ...
├── providers/     bluetooth_provider.dart（核心状态管理，~540行）
├── controllers/   colorize_controller.dart（Colorize模式业务逻辑）
├── configs/       device_connect_config.dart（响应式布局参数）
├── data/          led_presets.dart（14种预设）, traditional_chinese_colors.dart
├── models/        device_model.dart, speed_report.dart, logo_slot_status.dart
├── screens/       splash_screen, device_connect_screen（核心，~3500行）, device_scan_screen, ...
├── widgets/       running_mode_widget, colorize_preset_view, device_connect_helpers, ...
└── utils/         crc32, responsive_utils, ...
```

### 数据流

```
ESP32 BLE Notify → BLEService.rxDataStream → ResponseRouter.handleReceivedData()
    → 缓冲分包(按\n) → 解析 → 分发到 StreamController
    → BluetoothProvider 监听更新状态 → notifyListeners() → Consumer<> UI 重建
```

### 已完成的重构

1. **协议层拆分：** 旧 `protocol_service.dart`（1586行）→ 4个文件（parser/sender/router/errors），51个单元测试通过
2. **BluetoothProvider 重写：** 1274行→~540行，公开 API 完全不变，所有 Screen 零改动
3. **DI 引入：** get_it 单例注入 BLEService → CommandSender → ResponseRouter → BluetoothProvider
4. **DeviceConnectScreen 部分瘦身：** 提取了 Config、LED预设数据、RunningModeWidget、ColorizePresetView、ColorizeController
5. **死代码清理：** 删除 device_provider.dart、rgb_color_screen.dart

### 页面导航

```
首次启动:  SplashScreen → OnboardingFlowScreen → DeviceScanScreen
非首次:    NoDeviceScreen → DeviceScanScreen → DeviceFoundBottomSheet → DeviceConnectScreen
                                                                            ├── Running Mode（默认）
                                                                            ├── Colorize Mode（右滑）
                                                                            └── DevTest Mode（左滑）
           从 DeviceConnectScreen 菜单进入: LogoManagement / OTA / AudioStream / ColorRing
```

### 重构约束

- BluetoothProvider 公开 API 不能变（所有 Screen 依赖它）
- BLEService 不动（队列发送、MTU、重连已稳定）
- UI 交互不动，只重构代码组织
- 协议格式不变
- 每步改完都要能编译
- 保持 Provider 框架，不换 Riverpod/Bloc

### 已知问题

1. `device_connect_helpers.dart` 已创建但 Screen 底部仍有旧私有副本，待替换
2. `pubspec.yaml` 中 `image: any` 重复出现在 dependencies 和 dev_dependencies
3. 7个旧测试失败（重构前就有）
4. 品牌名内部包名（com.example.ridewind、package:ridewind）未改，改了会导致大量构建问题

---

## 四、待完成任务

### P0：真机联调

协议层完全重写了，需要确认 BLE 通信正常。验证清单：
- BLE 扫描发现 "T1" → 连接 → 自动状态同步
- 风扇/LED预设/RGB调色/亮度/流水灯/雾化器/音量 控制
- 断线重连 + 状态重新同步
- Logo 上传、OTA 升级、WiFi 音频投射

### P1：继续拆 DeviceConnectScreen

- 创建 `ColorizeRGBDetailView` Widget（~700行待提取）
- 删除 Screen 中已迁移的旧 Colorize 变量和方法
- 提取设备菜单（~250行）

### P2：go_router 声明式路由

当前全部 `Navigator.push(MaterialPageRoute(...))`。

### P3：国际化 + CI/CD

---

## 五、编译

```bash
cd RideWind
flutter pub get
flutter analyze
flutter test test/protocol/protocol_parser_test.dart   # 51个测试
flutter build apk --debug
```

---

## 六、品牌更名记录

**2026-04-29：RideWind → Critical**

已改（用户可见）：
- splash_screen.dart — Logo品牌名、欢迎语、用户协议、隐私政策
- main.dart — App类名（CriticalApp）、MaterialApp title
- cleaning_mode_screen.dart — 默认设备名 "Critical T1"
- bluetooth_provider.dart — 未知设备默认名 "Critical Device"
- app_update_service.dart / firmware_update_service.dart — APK文件名、GitHub URL
- AndroidManifest.xml — android:label
- AudioCaptureService.kt — 通知标题和描述
- Info.plist — CFBundleDisplayName、CFBundleName
- AppInfo.xcconfig — PRODUCT_NAME
- windows/runner/main.cpp — 窗口标题
- windows/runner/Runner.rc — 产品名、文件描述
- linux/runner/my_application.cc — 窗口标题
- web/index.html — title、apple-mobile-web-app-title
- web/manifest.json — name、short_name
- test/widget_test.dart — 类名和断言文本

未改（内部构建配置，用户不可见）：
- Android 包名 com.example.ridewind
- Dart 包名 package:ridewind（pubspec.yaml name 字段）
- iOS/macOS bundle identifier com.example.ridewind
- MethodChannel 名 com.example.ridewind/audio_capture
- 文件夹名 RideWind/、ridewind-esp/
- Kotlin 文件路径 com/example/ridewind/


---

## 七、引擎音效系统（2026-04-30 完成）

### 架构

完全重写了 `audio_player.c`，从 MP3 循环播放改为 **4 层可变采样率实时合成引擎**：

```
speed_percent (0-100) → target_rpm → 非线性惯性平滑 → current_rpm
                                                          │
                                    ┌─────────────────────┼─────────────────────┐
                                    ▼                     ▼                     ▼
                              find_blend()          calc_step()           vol_gain
                              (选2层+混合比)        (音调/步进)          (fade×master)
                                    │                     │                     │
                    ┌───────────────┴───────────────┐     │                     │
                    ▼                               ▼     ▼                     ▼
            Layer[lo] × lo_gain          Layer[hi] × hi_gain                    │
                    └───────────┬───────────┘                                   │
                                ▼                                               │
                          crossfade mix (-128..127)                              │
                                │                                               │
                                ▼                                               │
                          << 8 (→ 16-bit)  ×  vol_gain  >> 8                    │
                                │                                               │
                                ▼                                               │
                    stereo I2S DMA → MAX98357 → 扬声器
```

### 4 层采样

| 层 | RPM | 文件 | 大小 |
|----|-----|------|------|
| IDLE | 800 | engine_idle.h | 84893 samples (83KB) |
| LOW | 2000 | engine_low.h | 84893 samples (83KB) |
| MID | 4000 | engine_mid.h | 84893 samples (83KB) |
| HIGH | 7000 | engine_high.h | 84893 samples (83KB) |

素材由 enginesound (DasEtwas, MIT) 程序化生成，位于 `其他/enginesound-1.6/`。
生成命令：`target\release\enginesound.exe -h -c example5.esc -o output.wav -r <RPM> -v 0.5 -l 4 -w 2 -f 0.3 -q 22050`

### 关键技术点

- **可变采样率**：16.16 定点步进 + 线性插值，step = rpm / layer_rpm × 0.5
- **相邻层交叉淡入淡出**：任何 RPM 下只混合 2 个相邻层，过渡平滑
- **非线性 RPM 惯性**：低转速加速慢(100)，高转速加速快(200)；减速慢(50)，急减速快(200)
- **I2S 阻塞写入做时钟**：无 vTaskDelay，512 帧/buffer 匹配 DMA 描述符
- **淡入淡出**：启动 ~800ms 淡入，停止 ~350ms 淡出，启动前 4 个静音 buffer 清 DMA
- **与 WiFi 音频互斥**：start 时 audio_engine_pause()，stop 时 audio_engine_resume()

### 文件变更

| 文件 | 变化 |
|------|------|
| audio_player.c | 完全重写 — 4 层可变采样率合成 |
| audio_player.h | 新增 set_target_rpm()，保留 set_engine_volume() 兼容 |
| engine_idle.h / engine_low.h / engine_mid.h / engine_high.h | 新增 — 4 层 PCM 采样 |
| engine.mp3 | 不再使用（仍在目录中，可删除） |
| minimp3.h | 不再引用（lib/minimp3/ 仍在，可删除） |
| CMakeLists.txt | 移除 EMBED_FILES engine.mp3，移除 lib/minimp3 INCLUDE_DIR |
| ui_speed.c | set_engine_volume → set_target_rpm，油门模式同步 RPM |
| ui_rgb.c | 补了缺失的 ble_service.h include |
| ui_treadmill.c | 修了 drv_lcd_draw_pixel / snprintf / font_8x16 三个编译错误 |
| main.c | CMD_SPEED 处理增加 audio_player_set_target_rpm 调用 |

### 工具

- `ridewind-esp/tools/wav_to_header.py` — WAV → C 头文件转换（支持 32-bit float WAV）
- `ridewind-esp/tools/wav4_to_headers.py` — 批量转换 4 层 WAV
- `ridewind-esp/tools/samples_to_wav.py` — C 头文件 → WAV 预览

### 下一步：用户自定义引擎音频上传

计划让用户通过 APP 上传自己的引擎声音频到 ESP32：
- APP 端：选择音频文件 → 预处理（转 22050Hz 单声道 8-bit PCM）→ BLE 分包传输
- ESP32 端：接收存入 LittleFS → audio_player 启动时优先读 LittleFS 文件
- 复用 Logo 上传的 BLE 分包协议模式（AUDIO_START/DATA/END）
- LittleFS 空间充足：4 层 × 83KB = 332KB，分区有 10MB

---

## 八、用户自定义引擎音频上传（2026-04-30 完成）

### 架构

复用 Logo 上传的 BLE 二进制分包协议，新增 AUDIO_START_BIN/AUDIO_END 命令。
用户通过 APP 选择 WAV 文件 → 自动转码为 22050Hz 8-bit signed PCM → BLE 分段传输到 ESP32 → 存入 LittleFS → audio_player 自动重载。

```
APP: 选择 WAV → AudioPreprocessor.convertWavToPcm()
     → 22050Hz mono 8-bit signed PCM (Uint8List)
     → AudioTransmissionManager.transmit()
        → AUDIO_START_BIN:layer:size:crc32
        → [raw binary BLE packets, 244 bytes each]
        → AUDIO_ACK_BIN:received (every ~4KB)
        → AUDIO_END
        → AUDIO_OK:layer

ESP32: ble_service.c → audio_upload_feed_binary() → PSRAM buffer
       → AUDIO_END → storage_audio_write() → LittleFS
       → 4层全部到齐 → audio_player_reload_layers()
       → synth task 使用 PSRAM 中的自定义采样
```

### 协议

| 命令 | 方向 | 说明 |
|------|------|------|
| `AUDIO_START_BIN:layer:size:crc32` | APP→ESP | 开始上传，layer=0-3 |
| `AUDIO_READY:layer` | ESP→APP | 就绪，PSRAM 已分配 |
| [raw binary data] | APP→ESP | BLE 包直传 PCM 数据 |
| `AUDIO_ACK_BIN:bytes` | ESP→APP | 每 ~4KB 确认已收字节数 |
| `AUDIO_END` | APP→ESP | 传输结束，触发 CRC 校验 + 写入 |
| `AUDIO_OK:layer` | ESP→APP | 写入成功 |
| `AUDIO_FAIL:reason` | ESP→APP | 失败原因 |
| `AUDIO_RELOAD:OK` | ESP→APP | 4层全部到齐，引擎已重载 |
| `GET:AUDIO` | APP→ESP | 查询状态 |
| `AUDIO_STATUS:v0:v1:v2:v3:custom` | ESP→APP | 各层存在+是否使用自定义 |
| `AUDIO_DELETE` | APP→ESP | 删除全部自定义音频 |

### LittleFS 文件

| 层 | 文件路径 | 说明 |
|----|----------|------|
| 0 (idle) | /storage/engine_idle.pcm | 怠速 800 RPM |
| 1 (low) | /storage/engine_low.pcm | 低转速 2000 RPM |
| 2 (mid) | /storage/engine_mid.pcm | 中转速 4000 RPM |
| 3 (high) | /storage/engine_high.pcm | 高转速 7000 RPM |

格式：raw signed 8-bit PCM, 22050 Hz, mono, 无头部。
最大 256KB/层。建议 2-4 秒循环片段（44-88 KB）。

### audio_player.c 改动

- `LAYERS[]` 改为 `s_layers[]`（可变），`BUILTIN_LAYERS[]`（只读）
- `audio_player_init()` 调用 `load_audio_layers()`：检查 LittleFS 4 层是否齐全，齐全则从 PSRAM 加载，否则用内置
- 新增 `audio_player_reload_layers()`：上传完成后热重载（停止→加载→重启）
- 新增 `audio_player_has_custom_audio()`：查询是否使用自定义
- 自定义音频存在 PSRAM 中（`heap_caps_malloc(MALLOC_CAP_SPIRAM)`），不占内部 SRAM

### Flutter 新增文件

| 文件 | 说明 |
|------|------|
| `lib/services/audio_transmission_manager.dart` | 音频 BLE 传输管理器 |
| `lib/services/audio_preprocessor.dart` | WAV → PCM 转码器 |
| `lib/screens/audio_management_screen.dart` | 音频管理 UI 界面 |

### ESP32 改动文件

| 文件 | 变化 |
|------|------|
| protocol.h | 新增 CMD_AUDIO_START/DATA/END/DELETE/GET_AUDIO |
| protocol.c | 新增 AUDIO_* 命令解析 |
| storage.h | 新增 storage_audio_* API |
| storage.c | 新增 LittleFS 音频文件读写删除 |
| audio_player.h | 新增 reload_layers(), has_custom_audio() |
| audio_player.c | LAYERS→s_layers, load_audio_layers(), PSRAM 加载 |
| ble_service.c | 新增 audio binary mode 处理 |
| main.c | 新增 audio upload state machine + dispatch |
