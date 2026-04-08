# RideWind 蓝牙通信协议规范

> **版本**: v1.0  
> **更新**: 2024-11-28  
> **状态**: 待硬件确认

---

## 📡 协议概述

RideWind App 支持两种蓝牙通信协议:

| 协议类型 | 文件位置 | 推荐度 | 适用场景 |
|---------|---------|--------|---------|
| **统一二进制协议** | `jdy08_bluetooth_service.dart` | ⭐⭐⭐⭐⭐ | 高效、低延迟场景 |
| **JSON文本协议** | `protocol_service.dart` | ⭐⭐⭐ | 调试、灵活扩展场景 |

---

## 🔷 统一二进制协议 (推荐)

### 数据包格式

#### 通用帧结构
```
┌────┬────┬────┬────────┬────┬────┐
│ AA │ LEN│ CMD│  DATA  │ CS │ 55 │
└────┴────┴────┴────────┴────┴────┘
 1B   1B   1B   N Bytes  1B   1B
```

**字段说明**:
| 字段 | 长度 | 说明 |
|------|------|------|
| 帧头 (Header) | 1 Byte | 固定值 `0xAA` |
| 长度 (Length) | 1 Byte | CMD + DATA 的总字节数 |
| 命令 (Command) | 1 Byte | 命令码，见下表 |
| 数据 (Data) | N Bytes | 命令参数，长度由命令决定 |
| 校验和 (Checksum) | 1 Byte | `(LEN + CMD + SUM(DATA)) & 0xFF` |
| 帧尾 (Footer) | 1 Byte | 固定值 `0x55` |

---

### App → 硬件 命令表

#### 0x01 - 查询设备状态
**描述**: 请求设备返回当前状态  
**数据包**: `[AA] [01] [01] [01] [55]`  
**响应**: 见 `0x81 - 状态响应`

---

#### 0x02 - 设置LED颜色
**描述**: 设置指定区域的LED颜色和亮度  
**数据格式**:
```
DATA: [Zone] [R] [G] [B] [Brightness]
      1B     1B  1B  1B   1B
```

**参数说明**:
| 参数 | 取值范围 | 说明 |
|------|---------|------|
| Zone | 0-3 | 0=L(左), 1=M(中), 2=R(右), 3=B(后) |
| R | 0-255 | 红色分量 |
| G | 0-255 | 绿色分量 |
| B | 0-255 | 蓝色分量 |
| Brightness | 0-100 | 亮度百分比 |

**示例**: 设置L区为红色(255,0,0)，亮度100%
```
[AA] [06] [02] [00] [FF] [00] [00] [64] [CS] [55]
 帧头  长度  命令  L区   R    G    B   100%  校验  帧尾
```

**代码调用**:
```dart
await jdy08.setLedColor(0, 255, 0, 0, 100); // L区红色100%
await jdy08.setLedColor(3, 0, 0, 255, 50);  // B区蓝色50%
```

---

#### 0x03 - 设置整体亮度
**描述**: 同时调整所有LED区域的亮度  
**数据格式**: `DATA: [Brightness]` (1 Byte)  
**参数范围**: 0-100 (百分比)

**示例**: 设置亮度为80%
```
[AA] [02] [03] [50] [CS] [55]
 帧头  长度  命令  80   校验  帧尾
```

**代码调用**:
```dart
await jdy08.setBrightness(80);
```

---

#### 0x04 - 设置风扇转速
**描述**: 设置风扇转速百分比  
**数据格式**: `DATA: [Percent]` (1 Byte)  
**参数范围**: 0-100 (百分比)

**示例**: 设置转速为50%
```
[AA] [02] [04] [32] [CS] [55]
 帧头  长度  命令  50   校验  帧尾
```

**代码调用**:
```dart
await jdy08.setFanSpeedPercent(50);
```

---

#### 0x05 - 选择预设方案
**描述**: 切换到预设的颜色/动效方案  
**数据格式**: `DATA: [PresetID]` (1 Byte)  
**参数范围**: 1-8 (预设方案编号)

**预设方案定义** (需硬件确认):
| 编号 | 名称 | 描述 |
|------|------|------|
| 1 | 竞速红 | 红色渐变呼吸 |
| 2 | 冰霜蓝 | 蓝白交替闪烁 |
| 3 | 森林绿 | 绿色常亮 |
| 4 | 极光紫 | 紫色流水灯 |
| 5 | 日落橙 | 橙黄渐变 |
| 6 | 彩虹模式 | 七彩循环 |
| 7 | 警示黄 | 黄色闪烁 |
| 8 | 纯白光 | 白光常亮 |

**示例**: 选择方案6(彩虹模式)
```
[AA] [02] [05] [06] [CS] [55]
```

**代码调用**:
```dart
await jdy08.selectPreset(6); // 彩虹模式
```

---

#### 0x06 - 设置工作模式
**描述**: 切换独立模式或组合模式  
**数据格式**: `DATA: [Mode]` (1 Byte)  
**参数定义**:
- `0x00`: 独立模式 (各区域独立控制)
- `0x01`: 组合模式 (所有区域同步)

**示例**: 切换到组合模式
```
[AA] [02] [06] [01] [CS] [55]
```

**代码调用**:
```dart
await jdy08.setMode(1); // 组合模式
```

---

#### 0x08 - 紧急停止
**描述**: 立即关闭所有LED和风扇  
**数据包**: `[AA] [01] [08] [08] [55]`  
**无参数**

**代码调用**:
```dart
await jdy08.emergencyStop();
```

---

#### 0x10 - 保存配置
**描述**: 将当前设置保存到Flash，下次开机自动恢复  
**数据包**: `[AA] [01] [10] [10] [55]`  
**无参数**

**代码调用**:
```dart
await jdy08.saveConfig();
```

---

#### 0x11 - 恢复出厂设置
**描述**: 清除所有保存的配置，恢复默认值  
**数据包**: `[AA] [01] [11] [11] [55]`  
**无参数**

**代码调用**:
```dart
await jdy08.restoreDefaults();
```

---

### 硬件 → App 响应表

#### 0x81 - 状态响应
**描述**: 设备主动上报或响应查询的状态数据  
**数据格式**:
```
DATA: [L_R][L_G][L_B][L_Br] [M_R][M_G][M_B][M_Br] [R_R][R_G][R_B][R_Br] [B_R][B_G][B_B][B_Br] [Fan%][Bright][UI][Mode]
       4B                    4B                    4B                    4B                    1B    1B      1B  1B
      ├─ L区 RGB+亮度 ────┤  ├─ M区 RGB+亮度 ────┤  ├─ R区 RGB+亮度 ────┤  ├─ B区 RGB+亮度 ────┤
```

**总长度**: 19 Bytes

**字段说明**:
| 字段 | 偏移 | 长度 | 说明 |
|------|------|------|------|
| L区颜色 | 0 | 4B | R, G, B, Brightness |
| M区颜色 | 4 | 4B | R, G, B, Brightness |
| R区颜色 | 8 | 4B | R, G, B, Brightness |
| B区颜色 | 12 | 4B | R, G, B, Brightness |
| 风扇速度 | 16 | 1B | 百分比 (0-100) |
| 整体亮度 | 17 | 1B | 百分比 (0-100) |
| 当前UI | 18 | 1B | 当前显示的界面 (1=Cleaning, 2=Running, 3=Colorize) |
| 工作模式 | 19 | 1B | 0=独立, 1=组合 |

**示例数据包**:
```
[AA] [14] [81] [FF][00][00][64] [00][FF][00][64] [00][00][FF][64] [FF][00][00][64] [32][50][02][00] [CS] [55]
              ↑ L区红色100%   ↑ M区绿色100%   ↑ R区蓝色100%   ↑ B区红色100%   ↑50% ↑80% ↑界面2 ↑独立
```

**代码解析**:
```dart
jdy08.statusStream.listen((status) {
  List<List<int>> colors = status['zoneColors']; // [[R,G,B], [R,G,B], ...]
  int fanSpeed = status['fanPercent'];           // 50
  int brightness = status['brightness'];         // 80
  int ui = status['ui'];                        // 2
  int mode = status['mode'];                    // 0
});
```

---

#### 0x82 - 操作成功
**描述**: 命令执行成功的确认  
**数据格式**: `DATA: [原命令码]` (1 Byte)

**示例**: 设置颜色成功
```
[AA] [02] [82] [02] [CS] [55]
              ↑ 原命令码 0x02
```

---

#### 0x83 - 操作失败
**描述**: 命令执行失败的错误响应  
**数据格式**: `DATA: [原命令码] [错误码]` (2 Bytes)

**错误码定义**:
| 错误码 | 说明 |
|--------|------|
| 0x01 | 参数超出范围 |
| 0x02 | 命令不支持 |
| 0x03 | 设备忙碌 |
| 0x04 | 校验和错误 |
| 0x05 | 数据长度错误 |
| 0xFF | 未知错误 |

**示例**: 设置颜色失败(参数错误)
```
[AA] [03] [83] [02] [01] [CS] [55]
              ↑命令码 ↑参数错误
```

---

## 🔶 JSON文本协议 (备用方案)

### App → 硬件 命令

#### 设置风扇转速
```json
{
  "command": "setFanSpeed",
  "value": 50
}
```

#### 设置LED颜色
```json
{
  "command": "setLightColor",
  "value": 16711680
}
```
说明: `value` 是32位整数，格式为 `0x00RRGGBB`  
示例: 红色 = `0x00FF0000` = 16711680

#### 设置LED亮度
```json
{
  "command": "setLightBrightness",
  "value": 80
}
```

#### 设置LED模式
```json
{
  "command": "setLightMode",
  "mode": 1,
  "frequency": 2
}
```
模式: `0`=常亮, `1`=呼吸, `2`=闪烁

#### 设置烟雾开关
```json
{
  "command": "setSmokeStatus",
  "value": 1
}
```
值: `0`=关闭, `1`=开启

---

### 硬件 → App 状态

#### 设备状态上报
```json
{
  "status": "ok",
  "fanSpeed": 50,
  "ledColor": 16711680,
  "brightness": 80,
  "ledMode": 0,
  "smokeStatus": 0,
  "timestamp": 1234567890
}
```

---

## 🔧 校验和算法

### 统一协议校验和
```dart
int calculateChecksum(List<int> packet) {
  int sum = 0;
  // 从 LEN 开始，到 DATA 结束
  for (int i = 1; i < packet.length - 2; i++) {
    sum += packet[i];
  }
  return sum & 0xFF; // 取低8位
}
```

**示例计算**:
```
数据包: [AA] [06] [02] [00] [FF] [00] [00] [64] [?] [55]
        帧头  LEN  CMD  数据...              校验 帧尾

校验和 = (06 + 02 + 00 + FF + 00 + 00 + 64) & 0xFF
       = 0x165 & 0xFF
       = 0x65
```

---

## 📊 数据类型转换

### RGB颜色转换

#### App内部 (Flutter Color)
```dart
Color color = Color(0xFFFF0000); // 红色
int r = color.red;   // 255
int g = color.green; // 0
int b = color.blue;  // 0
```

#### 统一协议 (分量传输)
```dart
// 拆分为独立分量
await jdy08.setLedColor(zone, 255, 0, 0, 100);
```

#### JSON协议 (32位整数)
```dart
// 合并为单个整数
int colorValue = (r << 16) | (g << 8) | b; // 0x00FF0000
```

---

## 🧪 测试用例

### 基础连接测试
```dart
// 1. 扫描设备
List<BluetoothDevice> devices = await jdy08.scanForDevices();
assert(devices.isNotEmpty);

// 2. 连接设备
bool connected = await jdy08.connectToDevice(devices[0]);
assert(connected == true);

// 3. 查询状态
await jdy08.queryDeviceStatus();
await Future.delayed(Duration(seconds: 1));
// 检查 statusStream 是否有数据
```

### LED颜色测试
```dart
// 测试所有区域
for (int zone = 0; zone < 4; zone++) {
  await jdy08.setLedColor(zone, 255, 0, 0, 100); // 红色
  await Future.delayed(Duration(milliseconds: 500));
  
  await jdy08.setLedColor(zone, 0, 255, 0, 100); // 绿色
  await Future.delayed(Duration(milliseconds: 500));
  
  await jdy08.setLedColor(zone, 0, 0, 255, 100); // 蓝色
  await Future.delayed(Duration(milliseconds: 500));
}
```

### 风扇转速测试
```dart
// 渐进测试
for (int speed = 0; speed <= 100; speed += 10) {
  await jdy08.setFanSpeedPercent(speed);
  await Future.delayed(Duration(milliseconds: 500));
}
```

### 预设方案测试
```dart
// 遍历所有预设
for (int preset = 1; preset <= 8; preset++) {
  await jdy08.selectPreset(preset);
  await Future.delayed(Duration(seconds: 2));
}
```

---

## ⚠️ 注意事项

### 1. 数据包大小限制
- 默认BLE MTU = 23字节 (20字节数据 + 3字节协议头)
- 如果数据包 > 20字节，需要协商更大MTU
- 建议单包数据不超过 18字节

### 2. 发送频率限制
- 建议命令间隔 ≥ 50ms
- 避免在循环中无延迟连续发送
- 高频数据(如滑块)建议加防抖

### 3. 字节序问题
- 本协议使用**大端序** (Big-Endian)
- 多字节数据高位在前

### 4. 异常处理
- 发送命令后等待响应 (超时1秒)
- 收到 0x83 错误响应需重试或提示用户
- 连接断开需清理资源并尝试重连

---

## 📋 硬件工程师检查清单

请硬件团队确认以下内容:

- [ ] **UUID确认**
  - [ ] Service UUID: `________________`
  - [ ] Write Characteristic UUID: `________________`
  - [ ] Notify Characteristic UUID: `________________`

- [ ] **协议选择**
  - [ ] 使用统一二进制协议
  - [ ] 使用JSON协议
  - [ ] 使用自定义协议 (提供文档)

- [ ] **命令支持情况**
  - [ ] 0x01 查询状态
  - [ ] 0x02 设置LED颜色
  - [ ] 0x03 设置整体亮度
  - [ ] 0x04 设置风扇转速
  - [ ] 0x05 选择预设方案
  - [ ] 0x06 设置工作模式
  - [ ] 0x08 紧急停止
  - [ ] 0x10 保存配置
  - [ ] 0x11 恢复出厂

- [ ] **响应格式**
  - [ ] 0x81 状态响应 (19字节)
  - [ ] 0x82 操作成功
  - [ ] 0x83 操作失败

- [ ] **设备信息**
  - [ ] 设备名称格式: `________________`
  - [ ] 固件版本: `________________`
  - [ ] MTU支持: [ ] 默认23  [ ] 协商更大
  - [ ] 主动上报频率: `________________` (如每秒1次)

---

**文档版本控制**: 每次硬件协议更新后请同步修改此文档
