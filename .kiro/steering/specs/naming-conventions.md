---
inclusion: auto
---

<!-- last-verified: 2026-05-12 -->

# 模式 15：命名统一表

> 跨 ESP32 固件和 Flutter APP 的命名约定。消除"同一概念两个名字"的混乱。

---

## 核心概念命名

| 概念 | ESP32 (C) | Flutter (Dart) | BLE 协议 | 说明 |
|------|-----------|----------------|----------|------|
| 风扇速度 | `fan_speed` | `fanSpeed` | `SPD:xx` | 0-100 整数 |
| LED 预设 | `led_preset` | `ledPreset` | `LED:xx` | 0-13 索引 |
| LED 亮度 | `led_brightness` | `ledBrightness` | `BRT:xx` | 0-100 整数 |
| RGB 颜色 | `rgb_color` / `r,g,b` | `rgbColor` / `Color` | `RGB:zone:r:g:b` | zone=0-3 |
| 雾化器 | `atomizer` | `atomizer` | `ATM:0/1` | 开关量 |
| 音量 | `volume` | `volume` | `VOL:xx` | 0-100 整数 |
| 速度单位 | `speed_unit` | `speedUnit` | `UNIT:KMH/MPH` | 枚举 |
| 油门模式 | `throttle_mode` | `throttleMode` | `THR:0/1` | 0=手动 1=油门 |
| 流水灯 | `marquee` | `marquee` | `MRQ:0/1` | 开关量 |
| LCD 开关 | `lcd_enable` | `lcdEnabled` | `LCD:0/1` | 开关量 |
| 引擎音效 | `engine_sound` | `engineSound` | — | 本地状态 |
| WiFi 音频 | `wifi_audio` | `audioStream` | `WIFI_CFG:ssid:pwd` | 配置命令 |

---

## 文件命名规范

### ESP32 固件 (C)

| 层 | 前缀 | 示例 |
|----|------|------|
| drivers/ | `drv_` | `drv_lcd.c`, `drv_led.c`, `drv_encoder.c` |
| services/ | 无前缀，功能名 | `ble_service.c`, `protocol.c`, `audio_engine.c` |
| app/ | `app_` 或功能名 | `app_state.c`, `led_effects.c`, `encoder_handler.c` |
| ui/ | `ui_` | `ui_menu.c`, `ui_speed.c`, `ui_rgb.c` |
| config/ | 功能名 + `_config` | `board_config.h`, `pin_config.h` |
| resources/ | 描述性名称 | `menu_icons.c`, `boot_logo_240.c` |

### Flutter APP (Dart)

| 层 | 后缀 | 示例 |
|----|------|------|
| protocol/ | `_parser`, `_commands`, `_router` | `protocol_parser.dart`, `protocol_commands.dart` |
| services/ | `_service` | `ble_service.dart`, `audio_stream_service.dart` |
| providers/ | `_provider` | `bluetooth_provider.dart` |
| controllers/ | `_controller` | `speed_controller.dart` |
| screens/ | `_screen` | `device_connect_screen.dart`, `logo_management_screen.dart` |
| widgets/ | `_widget` 或描述性 | `running_mode_widget.dart`, `colorize_rgb_detail_view.dart` |
| models/ | `_model` | `device_model.dart` |

---

## 函数/方法命名

### ESP32 (C) — snake_case

| 类型 | 格式 | 示例 |
|------|------|------|
| 初始化 | `模块_init()` | `ble_service_init()`, `drv_lcd_init()` |
| 设置值 | `模块_set_xxx()` | `app_state_set_fan_speed()` |
| 获取值 | `模块_get_xxx()` | `app_state_get_volume()` |
| 事件处理 | `模块_handle_xxx()` | `protocol_handle_command()` |
| UI 入口 | `ui_xxx_enter()` | `ui_menu_enter()` |
| UI 更新 | `ui_xxx_update()` | `ui_speed_update()` |
| UI 退出 | `ui_xxx_exit()` | `ui_menu_exit()` |

### Flutter (Dart) — camelCase

| 类型 | 格式 | 示例 |
|------|------|------|
| 公开方法 | `动词Noun()` | `sendCommand()`, `parseResponse()` |
| 私有方法 | `_动词Noun()` | `_handleDisconnect()` |
| Stream | `xxxStream` | `speedStream`, `ledUpdateStream` |
| 状态变量 | `_noun` / `noun` | `_isConnected`, `fanSpeed` |
| 回调 | `onXxx` | `onSpeedChanged`, `onDisconnected` |
| Builder | `buildXxx()` | `buildSpeedGauge()` |

---

## BLE 协议命名

### 命令方向

| 方向 | 格式 | 示例 |
|------|------|------|
| APP → ESP32 | `COMMAND:param\n` | `SPD:50\n`, `LED:3\n` |
| ESP32 → APP (响应) | `OK:COMMAND:param\r\n` | `OK:SPD:50\r\n` |
| ESP32 → APP (事件) | `EVENT:data\n` | `SPEED:45\n`, `ENCODER:CW\n` |
| ESP32 → APP (状态同步) | `STATUS:key:value\r\n` | `STATUS:FAN:50\r\n` |

### 命令缩写表

| 全称 | 缩写 | 用途 |
|------|------|------|
| Speed | SPD | 风扇速度 |
| LED | LED | 灯效预设 |
| Brightness | BRT | LED 亮度 |
| RGB | RGB | 自定义颜色 |
| Volume | VOL | 音量 |
| Atomizer | ATM | 雾化器 |
| Unit | UNIT | 速度单位 |
| Throttle | THR | 油门模式 |
| Marquee | MRQ | 流水灯 |
| LCD | LCD | 屏幕开关 |
| WiFi Config | WIFI_CFG | WiFi 配置 |
| Logo | LOGO_START/DATA/END | Logo 上传 |
| OTA | OTA_START/DATA/END | 固件升级 |
| Query All | QUERY_ALL | 全状态查询 |

---

## 禁止的命名

| 不要用 | 应该用 | 原因 |
|--------|--------|------|
| `speed` (单独) | `fan_speed` / `fanSpeed` | 与 BLE 速度上报 `SPEED:xx` 混淆 |
| `light` | `led` | 项目统一用 LED |
| `fog` / `mist` | `atomizer` | 硬件文档用 atomizer |
| `bluetooth` (变量名) | `ble` | 太长，且项目统一用 BLE 缩写 |
| `ws2812` (业务层) | `led_strip` / `ledStrip` | 驱动细节不暴露到业务层 |
| `pwm` (业务层) | `fan` | 驱动细节不暴露到业务层 |
| `ridewind` (用户可见) | `Critical` | 品牌已改名，但代码内部保持 ridewind |

---

## 新增命名检查清单

添加新功能时，确认：
- [ ] ESP32 变量名用 snake_case
- [ ] Flutter 变量名用 camelCase
- [ ] BLE 命令缩写不超过 8 字符
- [ ] 同一概念在三端（ESP32/Flutter/协议）名称可互相映射
- [ ] 没有使用"禁止的命名"列表中的词
