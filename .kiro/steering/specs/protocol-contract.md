---
inclusion: fileMatch
fileMatchPattern: "**/protocol.c,**/protocol.h,**/protocol_parser.dart,**/command_sender.dart,**/ble_service.c,**/ble_service.dart"
---

<!-- last-verified: 2026-05-12 | source: CONTINUATION_GUIDE.md §二 + RideWind/PROTOCOL_SPECIFICATION.md -->

# BLE 通信协议 — 唯一真值源

> ⚠️ 这是协议的权威定义。代码中的实现必须与此文件一致。
> 如果发现代码与本文件不一致，以本文件为准并修复代码。

## 连接参数

| 项目 | 值 |
|------|-----|
| BLE Service UUID | 0xFFE0 |
| Characteristic UUID | 0xFFE1（write-without-response + notify） |
| 设备广播名 | "T1" |
| MTU | 247 字节（有效载荷 244） |
| 连接参数 | High Priority（11.25ms interval） |
| 命令格式 | 纯文本，`\n` 结尾 |
| 命令确认格式 | `\r\n` 结尾 |
| 事件报告格式 | `\n` 结尾 |

## 设备发现

| 匹配方式 | 条件 | 设备类型 |
|---------|------|---------|
| 设备名 | "T1" | ESP32 |
| Service UUID | 0xFFE0 | ESP32 |
| 设备名 | 包含 "JDY"/"BT05"/"HC" | F4 旧设备（兼容） |

---

## APP → ESP32 命令

### 基础控制

| 命令 | 格式 | 参数 | 响应 |
|------|------|------|------|
| 风扇速度 | `FAN:xx\n` | 0-100 | `OK:FAN:xx\r\n` |
| 速度显示 | `SPEED:xxx\n` | 0-999 | 无（高频） |
| 预设 | `PRESET:xx\n` | 1-14 | `OK:PRESET:xx\r\n` |
| LED 颜色 | `LED:s:r:g:b\n` | s=1-4, rgb=0-255 | `OK:LED\r\n` |
| LED 渐变 | `LED_GRADIENT:s:r:g:b:speed\n` | speed=渐变速度 | `OK:LED_GRADIENT\r\n` |
| 亮度 | `BRIGHT:xx\n` | 0-100 | `OK:BRIGHT:xx\r\n` |
| 流水灯 | `STREAMLIGHT:x\n` | 0/1 | `OK:STREAMLIGHT:x\r\n` |
| 音量 | `VOL:xx\n` | 0-100 | `OK:VOL:xx\r\n` |
| 雾化器 | `WUHUA:x\n` | 0/1 | `OK:WUHUA:x\r\n` |
| UI 切换 | `UI:x\n` | 0-6 | `OK:UI:x\r\n` |
| 油门模式 | `THROTTLE:x\n` | 0/1 | `OK:THROTTLE:x\r\n` |
| 油门灯效 | `THROTTLE_FX:x\n` | 0-8 | `OK:THROTTLE_FX:x\r\n` |
| 速度单位 | `UNIT:x\n` | 0=km/h, 1=mph | `OK:UNIT:x\r\n` |
| LCD 开关 | `LCD:x\n` | 0/1 | `OK:LCD:x\r\n` |
| 极速上限 | `SPEED_MAX:xxx\n` | 50-500 | `OK:SPEED_MAX:xxx\r\n` |
| 风力范围 | `FAN_RANGE:min,max\n` | min=0-100, max=0-100 | `OK:FAN_RANGE:min,max\r\n` |

### 握手

| 命令 | 格式 | 响应 |
|------|------|------|
| 握手 | `HELLO:app_ver:proto_ver:platform\n` | `HELLO_OK:fw_ver:proto_ver:hw_model\r\n` |

APP 连接后发送握手命令，告知自身版本信息。固件回复自身版本，双方据此判断兼容性。
- `app_ver`：APP 版本号（如 `1.2.1`）
- `proto_ver`：APP 支持的协议版本（整数，如 `1`）
- `platform`：平台标识（`android` / `ios` / `windows` / `macos`）

### 状态查询

| 命令 | 响应 |
|------|------|
| `GET:ALL\n` | `STATUS:FAN:x:WUHUA:x:BRIGHT:x\r\n` |
| `GET:PRESET\n` | `PRESET_REPORT:x\r\n` |
| `GET:VOL\n` | `VOL:xx\r\n` |
| `GET:STREAMLIGHT\n` | `STREAMLIGHT:x\r\n` |
| `GET:LOGO_SLOTS\n` | `LOGO_SLOTS:v0:v1:v2:active\r\n` |
| `GET:AUDIO\n` | `AUDIO_STATUS:v0:v1:v2:v3:custom\r\n` |
| `GET:VERSION\n` | `VERSION:fw=x.y.z:proto=N\r\n` |
| `OTA_VERSION\n` | `OTA_VERSION:<fw_version>\r\n` |

### WiFi 音频投射

| 命令 | 格式 | 响应 |
|------|------|------|
| WiFi 凭据 | `WIFI:ssid:password\n` | `WIFI_IP:x.x.x.x\r\n` 或 `WIFI_ERR:reason\r\n` |
| WiFi 扫描 | `WIFI_SCAN\n` | `WIFI_SCAN:USE_PHONE\r\n` |

音频投射通道：WiFi TCP:8080，44100Hz 16-bit 立体声 PCM。

### Logo 上传

| 命令 | 格式 | 响应 |
|------|------|------|
| 开始（自动槽位） | `LOGO_START:size:crc32\n` | `LOGO_ERASING\r\n` → `LOGO_READY:slot\r\n` |
| 开始（指定槽位） | `LOGO_START:slot:size:crc32\n` | 同上 |
| 数据包 | `LOGO_DATA:seq:hex\n` | `LOGO_ACK:seq\r\n` 或 `LOGO_SACK:base:bitmap\r\n` |
| 结束 | `LOGO_END\n` | `LOGO_OK:slot\r\n` 或 `LOGO_FAIL:reason\r\n` |
| 删除 | `LOGO_DELETE:slot\n` | — |

Logo 格式：240×240 RGB565，115200 字节，CRC32 校验（ISO 3309，多项式 0xEDB88320）。

### OTA 固件升级

| 命令 | 格式 | 响应 |
|------|------|------|
| 开始（推荐） | `OTA_BEGIN:size[:sha256_hex]\n` | `OTA_READY\r\n` |
| 开始（旧格式） | `OTA_START:size\n` | `OTA_READY\r\n` |
| 数据包 | `OTA_DATA:seq:hex\n` | `OTA_ACK:seq\r\n` |
| 结束 | `OTA_END\n` | `OTA_OK\r\n` 或 `OTA_FAIL:reason\r\n` |
| 中止 | `OTA_ABORT\n` | — |

- `OTA_BEGIN` 为推荐格式，支持可选 SHA256 校验（64 字符十六进制）。`OTA_START` 保留向后兼容。
- `OTA_ABORT` 中止正在进行的 OTA 传输，设备回滚到当前固件。
- 最大固件 2.5MB。失败自动回滚。

### 自定义引擎音频上传（二进制模式）

| 命令 | 格式 | 响应 |
|------|------|------|
| 开始 | `AUDIO_START_BIN:layer:size:crc32\n` | `AUDIO_READY:layer\r\n` |
| 数据 | [raw binary BLE packets, 244 bytes] | `AUDIO_ACK_BIN:bytes\r\n`（每~4KB） |
| 结束 | `AUDIO_END\n` | `AUDIO_OK:layer\r\n` 或 `AUDIO_FAIL:reason\r\n` |
| 删除全部 | `AUDIO_DELETE\n` | `OK:AUDIO_DELETE_ALL\r\n` |
| 删除指定层 | `AUDIO_DELETE:layer\n` | `OK:AUDIO_DELETE:layer\r\n` |

layer=0(idle)/1(low)/2(mid)/3(high)。格式：22050Hz 8-bit signed PCM mono，最大 256KB/层。
4 层全部上传后自动重载：`AUDIO_RELOAD:OK\r\n`。

---

## ESP32 → APP 主动上报

| 事件 | 格式 | 说明 |
|------|------|------|
| 速度报告 | `SPEED_REPORT:value:unit\n` | value=0-340, unit=0/1 |
| 油门报告 | `THROTTLE_REPORT:0/1\n` | 三击进入/退出 |
| 单位报告 | `UNIT_REPORT:0/1\n` | 单击切换 |
| 预设报告 | `PRESET_REPORT:1-14\n` | 旋钮切换 |
| 流水灯报告 | `STREAMLIGHT_REPORT:0/1\n` | 状态变化 |
| 引擎通知 | `ENGINE_START\n` / `ENGINE_READY\n` | 开机 |
| 按钮事件 | `BTN:type:action\n` | KNOB:CLICK/LONG/TRIPLE |
| 旋钮增量 | `KNOB:delta\n` | 正=顺时针 |
| WiFi IP | `WIFI_IP:x.x.x.x\r\n` | 连接成功 |
| WiFi 错误 | `WIFI_ERR:reason\r\n` | 连接失败 |
| 音频就绪 | `AUDIO_READY:ip:port\r\n` | TCP 服务器就绪 |

---

## 数据完整性

- CRC32：标准 ISO 3309（多项式 0xEDB88320），用于 Logo/OTA/Audio 上传
- 接收缓冲区保护：512 字节未收到 `\n` 则清空
- 命令重试：关键命令 3 秒超时，最多重试 2 次
- 发送间隔：连续多包最小 2ms 间隔
