# Critical 蓝牙通信协议规范

> **版本**: v2.0
> **更新**: 2025-01-15
> **状态**: 已实现（ESP32-S3 + Flutter APP）

---

## 📡 协议概述

Critical APP 与 ESP32-S3 硬件之间使用 **文本协议** 通过 BLE（Bluetooth Low Energy）通信。

| 项目 | 说明 |
|------|------|
| **BLE Service UUID** | 0xFFE0 |
| **BLE Write Characteristic** | 0xFFE1（write-without-response） |
| **BLE Notify Characteristic** | 0xFFE1 |
| **MTU** | 247 字节（有效载荷 244 字节） |
| **命令格式** | 纯文本，以 `\n` 结尾 |
| **响应格式** | 纯文本，命令确认以 `\r\n` 结尾，事件报告以 `\n` 结尾 |

> ⚠️ **历史说明**: v1.0 版本使用二进制协议（0xAA...0x55 帧格式）和 JSON 协议，
> 已在 ESP32 迁移后废弃。旧协议文件 `jdy08_bluetooth_service.dart` 和
> `bluetooth_service.dart` 已删除。

---

## 🔷 设备发现

APP 通过以下方式发现设备：

| 方式 | 匹配条件 | 设备类型 |
|------|---------|---------|
| 设备名 | "T1" | ESP32 |
| Service UUID | 0xFFE0 | ESP32 |
| 设备名 | 包含 "JDY"、"BT05"、"HC" | F4（旧设备，向后兼容） |

---

## 📤 APP → 硬件 命令表

所有命令以 `\n` 结尾。

### 基础控制

| 命令 | 格式 | 参数说明 |
|------|------|---------|
| 风扇速度 | `FAN:xx\n` | xx = 0-100 |
| 雾化器 | `WUHUA:x\n` | x = 0/1 |
| 亮度 | `BRIGHT:xx\n` | xx = 0-100 |
| 预设 | `PRESET:xx\n` | xx = 1-14 |
| 流水灯 | `STREAMLIGHT:x\n` | x = 0/1 |
| 速度显示 | `SPEED:xxx\n` | xxx = 0-999 |
| LED 颜色 | `LED:s:r:g:b\n` | s=区域, r/g/b=0-255 |
| LED 渐变 | `LED_GRADIENT:s:r:g:b:speed\n` | speed=渐变速度 |

### 音量控制

| 命令 | 格式 | 说明 |
|------|------|------|
| 设置音量（ESP32） | `VOL:xx\n` | xx = 0-100 |
| 设置音量（F4） | `AUDIO:VOL:xx\n` | xx = 0-100（旧格式） |
| 查询音量 | `GET:VOL\n` | |

### 状态查询

| 命令 | 格式 | 说明 |
|------|------|------|
| 查询全部状态 | `GET:ALL\n` | 风扇/雾化/亮度 |
| 查询预设 | `GET:PRESET\n` | 当前预设索引 |
| 查询 Logo 槽位 | `GET:LOGO_SLOTS\n` | 3 个槽位状态 |
| 查询音量 | `GET:VOL\n` | 当前音量 |
| 查询流水灯 | `GET:STREAMLIGHT\n` | 流水灯开关状态 |

### WiFi 音频投射

| 命令 | 格式 | 说明 |
|------|------|------|
| 发送 WiFi 凭据 | `WIFI:ssid:password\n` | ESP32 连接指定 WiFi |
| WiFi 扫描 | `WIFI_SCAN\n` | ESP32 返回 USE_PHONE |

### Logo 上传

| 命令 | 格式 | 说明 |
|------|------|------|
| 开始上传（自动槽位） | `LOGO_START:size:crc32\n` | size=字节数, crc32=校验值 |
| 开始上传（指定槽位） | `LOGO_START:slot:size:crc32\n` | slot=0-2 |
| 数据包 | `LOGO_DATA:seq:hex\n` | seq=序号, hex=16字节十六进制 |
| 结束上传 | `LOGO_END\n` | |
| 删除 Logo | `LOGO_DELETE:slot\n` | slot=0-2 |

### OTA 固件升级

| 命令 | 格式 | 说明 |
|------|------|------|
| 开始升级 | `OTA_START:size:crc32\n` | 最大 2.5MB |
| 数据包 | `OTA_DATA:seq:hex\n` | 每包 16 字节 |
| 结束升级 | `OTA_END\n` | |

---

## 📥 硬件 → APP 响应表

命令确认以 `\r\n` 结尾，事件报告以 `\n` 结尾。

### 命令确认

| 响应 | 格式 | 说明 |
|------|------|------|
| 风扇 OK | `OK:FAN:xx\r\n` | |
| 雾化 OK | `OK:WUHUA:x\r\n` | |
| 亮度 OK | `OK:BRIGHT:xx\r\n` | |
| 预设 OK | `OK:PRESET:xx\r\n` | |
| 流水灯 OK | `OK:STREAMLIGHT:x\r\n` | |
| LED OK | `OK:LED\r\n` | |
| LED 渐变 OK | `OK:LED_GRADIENT\r\n` | |
| 速度 OK | `OK:SPEED\r\n` | |

### 状态查询响应

| 响应 | 格式 | 说明 |
|------|------|------|
| 全部状态 | `STATUS:FAN:x:WUHUA:x:BRIGHT:x\r\n` | |
| 预设报告 | `PRESET_REPORT:x\r\n` | x = 1-14 |
| Logo 槽位 | `LOGO_SLOTS:v0:v1:v2:active\r\n` | v0/v1/v2=0/1, active=槽位索引 |
| 音量 | `VOL:xx\r\n` | xx = 0-100 |
| 流水灯状态 | `STREAMLIGHT:x\r\n` | x = 0/1 |

### WiFi 相关通知

| 响应 | 格式 | 说明 |
|------|------|------|
| WiFi 连接成功 | `WIFI_IP:x.x.x.x\r\n` | ESP32 的 IP 地址 |
| WiFi 连接失败 | `WIFI_ERR:reason\r\n` | 错误原因 |
| WiFi 扫描响应 | `WIFI_SCAN:USE_PHONE\r\n` | 由手机端扫描 |
| 音频就绪 | `AUDIO_READY:ip:port\r\n` | TCP 音频服务器就绪 |

### Logo 上传响应

| 响应 | 格式 | 说明 |
|------|------|------|
| Flash 擦除中 | `LOGO_ERASING\r\n` | |
| 就绪 | `LOGO_READY:slot\r\n` | 分配的槽位 |
| 累积 ACK | `LOGO_ACK:seq\r\n` | 确认到 seq |
| 选择性 ACK | `LOGO_SACK:base:bitmap\r\n` | base=基准序号, bitmap=位图 |
| 上传成功 | `LOGO_OK:slot\r\n` | |
| 上传失败 | `LOGO_FAIL:reason\r\n` | CRC/WRITE |
| 错误 | `LOGO_ERROR:reason\r\n` | MEM/INVALID_SLOT/SIZE_MISMATCH |

### OTA 升级响应

| 响应 | 格式 | 说明 |
|------|------|------|
| 就绪 | `OTA_READY\r\n` | |
| ACK | `OTA_ACK:seq\r\n` | |
| 成功 | `OTA_OK\r\n` | |
| 失败 | `OTA_FAIL:reason\r\n` | 失败后自动回滚 |

### 硬件事件报告

| 响应 | 格式 | 说明 |
|------|------|------|
| 速度报告 | `SPEED_REPORT:value:unit\n` | 旋钮调整速度 |
| 油门报告 | `THROTTLE_REPORT:x\n` | 0=退出, 1=进入 |
| 单位报告 | `UNIT_REPORT:x\n` | 0=km/h, 1=mph |
| 预设报告 | `PRESET_REPORT:x\n` | 旋钮切换预设 |
| 引擎通知 | `ENGINE_START\n` / `ENGINE_READY\n` | 开机通知 |
| 按钮事件 | `BTN:type:action\n` | KNOB:CLICK 等 |
| 传感器数据 | `SENSOR:type:value\n` | TEMP/BAT 等 |

---

## 🔧 数据完整性

### CRC32 校验

Logo 和 OTA 上传使用标准 CRC32（ISO 3309，多项式 0xEDB88320）校验数据完整性。

### 接收缓冲区保护

- ProtocolService 缓冲区超过 512 字节未收到 `\n`：清空并记录警告
- BluetoothProvider 缓冲区超过 1024 字节：清空并记录警告

### 命令重试机制

关键命令（LOGO_ACK、OTA_ACK 等）在 3 秒内未收到响应时自动重发，最多重试 2 次。

---

## 📊 预设颜色定义

| 编号 | 名称 | 颜色值 |
|------|------|--------|
| 1-12 | 原有预设 | 与 F4 相同 |
| 13 | Ocean Blue | #0066CC |
| 14 | Warm Amber | #FFBF00 |

---

## ⚠️ 注意事项

1. **MTU**: 连接后请求 MTU 247，有效载荷 244 字节
2. **发送间隔**: 连续发送多包时保持最小 2ms 间隔
3. **连接参数**: 请求 High Priority（11.25ms interval）
4. **重连策略**: 指数退避，最多 5 次，每次重连前重置缓冲区
5. **Logo 图片**: 240×240 RGB565 格式，115200 字节
6. **OTA 固件**: 最大 2.5MB（ESP32 OTA 分区大小）
7. **音频投射**: 通过 WiFi TCP:8080，44100Hz 16-bit 立体声 PCM

---

**文档版本控制**: 每次协议更新后请同步修改此文档
