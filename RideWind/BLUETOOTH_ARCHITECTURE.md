# RideWind 蓝牙通信架构分析文档

> **更新时间**: 2024-11-28  
> **项目状态**: 蓝牙基础架构已搭建，等待真实硬件集成

---

## 📋 项目概况

**RideWind** 是一款基于 Flutter 开发的智能 LED 风扇控制应用，通过蓝牙 BLE 与硬件设备通信。项目从"花瓶应用"阶段过渡到真实硬件连接阶段，现有代码架构完善但**蓝牙通信层仍使用模拟数据**。

### 核心技术栈
- **框架**: Flutter (SDK ^3.9.2)
- **蓝牙库**: flutter_blue_plus ^1.32.12
- **状态管理**: Provider ^6.1.2
- **本地存储**: shared_preferences ^2.2.3
- **权限管理**: permission_handler ^11.3.1

---

## 🏗️ 蓝牙架构层级

### 架构图

```
┌─────────────────────────────────────────────┐
│           UI Layer (Screens)                │
│  - device_scan_screen.dart                  │
│  - device_list_screen.dart                  │
│  - device_connect_screen.dart               │
│  - rgb_color_screen.dart                    │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│      State Management (Providers)           │
│  - BluetoothProvider                        │
│  - DeviceProvider                           │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│        Service Layer (Services)             │
│  - BluetoothService      (基础BLE服务)      │
│  - JDY08BluetoothService (JDY-08专用)       │
│  - ProtocolService       (JSON协议)         │
│  - DeviceControlService  (高层控制接口)     │
└────────────────┬────────────────────────────┘
                 │
┌────────────────▼────────────────────────────┐
│       Hardware Communication Layer          │
│  - flutter_blue_plus (BLE底层)              │
│  - 真实硬件设备 (STM32 + JDY-08)            │
└─────────────────────────────────────────────┘
```

---

## 📦 核心模块详解

### 1️⃣ **BluetoothService** (基础蓝牙服务)

**文件**: `lib/services/bluetooth_service.dart`

**功能**:
- ✅ 蓝牙设备扫描和连接管理
- ✅ 基础UUID定义（需根据实际硬件修改）
- ✅ 数据发送/接收通道管理
- ✅ 设备状态监听

**关键方法**:
```dart
Future<bool> isBluetoothAvailable()           // 检查蓝牙可用性
Stream<List<ScanResult>> startScan()          // 扫描设备
Future<bool> connectToDevice(device)          // 连接设备
Future<void> sendSpeedCommand(int speed)      // 发送速度命令
Future<void> sendModeCommand(DeviceMode mode) // 发送模式命令
Future<void> sendColorCommand(zone, rgb)      // 发送RGB颜色命令
```

**UUID配置** (当前占位符，需根据实际硬件修改):
```dart
static const String serviceUUID = "0000fff0-0000-1000-8000-00805f9b34fb";
static const String writeCharUUID = "0000fff1-0000-1000-8000-00805f9b34fb";
static const String notifyCharUUID = "0000fff2-0000-1000-8000-00805f9b34fb";
```

⚠️ **注意**: 这些UUID是占位符，必须替换为真实硬件的UUID！

---

### 2️⃣ **JDY08BluetoothService** (JDY-08专用服务)

**文件**: `lib/services/jdy08_bluetooth_service.dart`

**功能**:
- ✅ 专为STM32+JDY-08蓝牙模块设计
- ✅ 统一协议封装 (0xAA...0x55格式)
- ✅ 自动设备名称识别 (`RideWind`, `JDY-08`, `LED`)
- ✅ 双向数据流管理
- ✅ 设备状态解析

**协议格式**:
```
发送数据包:
┌────┬────┬────┬────────┬────┬────┐
│ AA │ LEN│ CMD│  DATA  │ CS │ 55 │
└────┴────┴────┴────────┴────┴────┘
 帧头  长度 命令  数据载荷 校验 帧尾

接收数据包:
┌────┬────┬────┬──────────────────┬────┬────┐
│ AA │ LEN│ 81 │  状态数据 (19字节)│ CS │ 55 │
└────┴────┴────┴──────────────────┴────┴────┘
```

**支持的命令**:
| 命令码 | 功能 | 参数 |
|--------|------|------|
| 0x01 | 查询设备状态 | 无 |
| 0x02 | 设置LED颜色 | zone, R, G, B, brightness |
| 0x03 | 设置整体亮度 | brightness (0-100) |
| 0x04 | 设置风扇转速 | percent (0-100) |
| 0x05 | 选择预设方案 | preset (1-8) |
| 0x06 | 设置工作模式 | mode (0=独立, 1=组合) |
| 0x08 | 紧急停止 | 无 |
| 0x10 | 保存配置 | 无 |
| 0x11 | 恢复出厂 | 无 |

**响应码**:
| 响应码 | 说明 |
|--------|------|
| 0x81 | 设备状态数据 |
| 0x82 | 操作成功 |
| 0x83 | 操作失败 |

**关键方法**:
```dart
Future<List<BluetoothDevice>> scanForDevices()       // 扫描JDY-08设备
Future<bool> connectToDevice(device)                 // 连接设备
Future<bool> sendUnifiedCommand(cmd, data)          // 发送统一协议命令
Future<bool> setLedColor(zone, r, g, b, brightness) // 设置LED颜色
Future<bool> setFanSpeedPercent(percent)            // 设置风扇转速
```

---

### 3️⃣ **ProtocolService** (JSON协议服务)

**文件**: `lib/services/protocol_service.dart`

**功能**:
- ✅ JSON格式命令封装 (备用方案)
- ✅ 人性化API接口

**JSON命令示例**:
```json
{
  "command": "setFanSpeed",
  "value": 50
}

{
  "command": "setLightColor",
  "value": 0xFF0000  // 红色
}

{
  "command": "setSmokeStatus",
  "value": 1  // 开启烟雾
}
```

⚠️ **注意**: 当前使用JSON协议，如果硬件不支持需要切换到JDY08BluetoothService！

---

### 4️⃣ **DeviceControlService** (高层控制服务)

**文件**: `lib/services/device_control_service.dart`

**功能**:
- ✅ 业务层抽象接口
- ✅ 简化UI调用复杂度
- ✅ 设备状态流管理

**关键方法**:
```dart
Future<void> controlFan(int speed)                      // 控制风扇 (0-100)
Future<void> controlLedColor(int r, int g, int b)       // 控制LED颜色
Future<void> controlLedBrightness(int brightness)       // 控制LED亮度
Future<void> controlLedMode(int mode, {int frequency}) // 控制LED模式
Future<void> controlSmoke(bool turnOn)                  // 控制烟雾
Stream<Map<String, dynamic>>? get statusStream         // 设备状态流
```

---

### 5️⃣ **BluetoothProvider** (状态管理)

**文件**: `lib/providers/bluetooth_provider.dart`

**功能**:
- ✅ 全局蓝牙状态管理
- ✅ 设备列表维护
- ✅ 连接状态通知
- ✅ 设备过滤策略

**设备过滤规则**:
```dart
// 只显示以下设备:
// 1. 包含 "RideWind" 的设备
// 2. 包含 "HM-10" 或 "JDY" 的蓝牙模块
// 3. RSSI > -90 (信号强度足够)
```

**状态属性**:
```dart
bool isScanning                    // 是否正在扫描
bool isBluetoothEnabled           // 蓝牙是否已启用
List<DeviceModel> devices         // 扫描到的设备列表
DeviceModel? connectedDevice      // 当前连接的设备
bool isConnected                  // 是否已连接
```

---

## 🔧 硬件协议对接指南

### 当前状态
- ✅ 蓝牙基础架构完善
- ✅ 两套协议方案 (统一协议 + JSON)
- ⚠️ **UUID和协议细节需要根据实际硬件调整**
- ⚠️ **当前仍使用模拟数据，未与真实硬件测试**

### 硬件对接步骤

#### Step 1: 确认硬件参数
```
[ ] 1. 获取真实设备的Service UUID
[ ] 2. 获取真实设备的Write Characteristic UUID
[ ] 3. 获取真实设备的Notify Characteristic UUID
[ ] 4. 确认设备名称前缀 (如 "RideWind-XXX")
[ ] 5. 确认数据包格式 (统一协议 or JSON)
```

#### Step 2: 修改UUID配置

**方案A**: 使用统一协议 (推荐)
```dart
// 修改 lib/services/jdy08_bluetooth_service.dart
// 取消注释以下常量并填入真实UUID
static const String _serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";  // 替换为真实UUID
static const String _writeCharUuid = "0000ffe1-0000-1000-8000-00805f9b34fb"; // 替换为真实UUID
```

**方案B**: 使用JSON协议
```dart
// 修改 lib/services/bluetooth_service.dart
static const String serviceUUID = "实际Service UUID";
static const String writeCharUUID = "实际Write UUID";
static const String notifyCharUUID = "实际Notify UUID";
```

#### Step 3: 调整设备名称过滤
```dart
// 修改 lib/services/jdy08_bluetooth_service.dart
static const String _deviceNamePrefix = 'RideWind';  // 改为实际设备名称前缀
```

#### Step 4: 验证数据包格式
```dart
// 在 lib/services/jdy08_bluetooth_service.dart 中
// 验证 sendUnifiedCommand 方法的数据包构造是否符合硬件协议
```

#### Step 5: 测试连接流程
1. 运行应用扫描设备
2. 查看控制台日志确认设备是否被识别
3. 尝试连接并检查服务发现是否成功
4. 发送测试命令 (如查询状态)
5. 监听设备响应数据

---

## 📱 Android权限配置

**文件**: `android/app/src/main/AndroidManifest.xml`

**已配置权限**:
```xml
✅ BLUETOOTH               (蓝牙基础权限)
✅ BLUETOOTH_ADMIN         (蓝牙管理权限)
✅ BLUETOOTH_SCAN          (Android 12+ 扫描权限)
✅ BLUETOOTH_CONNECT       (Android 12+ 连接权限)
✅ BLUETOOTH_ADVERTISE     (Android 12+ 广播权限)
✅ ACCESS_FINE_LOCATION    (定位权限-用于蓝牙扫描)
✅ ACCESS_COARSE_LOCATION  (粗略定位权限)
✅ POST_NOTIFICATIONS      (通知权限 Android 13+)
```

---

## 🎯 关键待办事项

### 优先级 P0 (必须完成)
- [ ] **获取真实硬件的UUID和协议文档**
- [ ] **更新 BluetoothService 或 JDY08BluetoothService 的UUID配置**
- [ ] **确认使用哪套协议方案** (统一协议 or JSON)
- [ ] **真机测试设备扫描和连接**
- [ ] **验证数据包格式和校验和算法**

### 优先级 P1 (重要功能)
- [ ] 实现设备状态实时监听和UI更新
- [ ] 添加连接断开重连机制
- [ ] 实现设备配置保存到本地存储
- [ ] 添加错误处理和用户友好提示
- [ ] 实现多设备管理 (如果需要)

### 优先级 P2 (优化项)
- [ ] 优化扫描性能和功耗
- [ ] 添加蓝牙日志记录和调试工具
- [ ] 实现OTA固件升级功能 (如果硬件支持)
- [ ] 添加设备信息查询 (电量、版本号等)
- [ ] 优化数据传输性能 (MTU协商)

---

## 🐛 已知问题和限制

### 当前限制
1. **模拟数据**: 所有蓝牙通信当前使用占位符UUID，未与真实硬件测试
2. **协议不确定**: 同时存在两套协议实现，需根据硬件选择
3. **单设备连接**: 当前架构仅支持连接一台设备
4. **权限处理简单**: 需要更完善的权限请求流程和错误处理

### 潜在风险
- iOS平台蓝牙权限需要额外配置 `Info.plist`
- 不同Android版本权限请求行为差异
- 蓝牙连接稳定性依赖硬件质量
- 数据包丢失和乱序处理尚未实现

---

## 💡 开发建议

### 调试技巧
1. **启用详细日志**:
```dart
// 在 main.dart 中添加
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
FlutterBluePlus.setLogLevel(LogLevel.verbose);
```

2. **使用蓝牙调试工具**:
- Android: nRF Connect
- iOS: LightBlue
- 用于验证硬件设备的UUID和数据格式

3. **分步测试**:
   - 先验证扫描功能
   - 再验证连接功能
   - 最后验证数据收发

### 代码组织
- **保持两套协议实现**: 作为备用方案
- **统一使用 DeviceControlService**: 避免UI直接调用底层服务
- **完善错误处理**: 每个蓝牙操作都应有try-catch

### 性能优化
- 扫描时长控制在3-5秒
- 连接超时设置为15秒
- 数据发送使用 `withoutResponse: true` (适用于高频命令)
- 状态查询使用轮询而非持续连接 (节省电量)

---

## 📚 参考资料

### flutter_blue_plus 文档
- GitHub: https://github.com/boskokg/flutter_blue_plus
- API文档: https://pub.dev/packages/flutter_blue_plus

### BLE基础知识
- GATT协议: https://www.bluetooth.com/specifications/gatt/
- UUID规范: https://www.bluetooth.com/specifications/assigned-numbers/

### 相关代码文件
```
lib/services/
  ├── bluetooth_service.dart         (基础BLE服务)
  ├── jdy08_bluetooth_service.dart   (JDY-08专用服务) ⭐推荐
  ├── protocol_service.dart          (JSON协议)
  └── device_control_service.dart    (高层控制接口)

lib/providers/
  ├── bluetooth_provider.dart        (蓝牙状态管理)
  └── device_provider.dart           (设备状态管理)

lib/models/
  └── device_model.dart              (设备数据模型)

lib/screens/
  ├── device_scan_screen.dart        (扫描页面)
  ├── device_list_screen.dart        (设备列表)
  ├── device_connect_screen.dart     (设备连接/控制)
  └── rgb_color_screen.dart          (RGB颜色设置)
```

---

## ✅ 下一步行动清单

1. **立即行动**:
   - [ ] 向硬件工程师获取蓝牙UUID和协议文档
   - [ ] 确认设备名称格式 (如 "RideWind-001")
   - [ ] 准备一台测试设备用于开发

2. **准备阶段**:
   - [ ] 更新UUID配置到代码
   - [ ] 编写单元测试用例
   - [ ] 准备测试用例清单

3. **集成阶段**:
   - [ ] 真机测试扫描功能
   - [ ] 真机测试连接功能
   - [ ] 真机测试命令收发
   - [ ] 记录所有异常情况

4. **优化阶段**:
   - [ ] 性能测试和优化
   - [ ] 用户体验优化
   - [ ] 边界情况处理

---

**文档维护**: 请在硬件对接过程中及时更新此文档，记录真实的UUID、协议细节和遇到的问题。

**联系方式**: 如有技术问题，请通过项目issues反馈。
