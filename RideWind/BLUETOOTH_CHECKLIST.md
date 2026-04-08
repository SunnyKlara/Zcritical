# ✅ RideWind 蓝牙集成检查清单

> 快速参考 - 硬件对接时请逐项确认

---

## 📋 硬件信息收集 (最优先)

### 必需信息
- [ ] **Service UUID**: `____________________________`
- [ ] **Write Characteristic UUID**: `____________________________`
- [ ] **Notify Characteristic UUID**: `____________________________`
- [ ] **设备名称前缀**: `____________________________` (如: RideWind-XXX)
- [ ] **通信协议类型**: 
  - [ ] 统一二进制协议 (0xAA...0x55)
  - [ ] JSON协议
  - [ ] 其他自定义协议

### 可选信息
- [ ] **固件版本号**: `____________________________`
- [ ] **MTU支持**: [ ] 默认23字节  [ ] 可协商 (最大: _____)
- [ ] **状态上报频率**: `____________________________`
- [ ] **硬件版本**: `____________________________`

---

## 🔧 代码配置修改

### 1. 选择协议方案 (二选一)

#### 方案A: 统一二进制协议 (推荐)
- [ ] 打开文件: `lib/services/jdy08_bluetooth_service.dart`
- [ ] 修改设备名称前缀 (第10行):
  ```dart
  static const String _deviceNamePrefix = 'RideWind'; // 改为实际名称
  ```
- [ ] 如需精确UUID匹配，取消注释第14-16行并填入真实UUID
- [ ] 在需要使用的界面导入服务:
  ```dart
  import '../services/jdy08_bluetooth_service.dart';
  final jdy08 = JDY08BluetoothService();
  ```

#### 方案B: JSON协议
- [ ] 打开文件: `lib/services/bluetooth_service.dart`
- [ ] 修改UUID配置 (第20-22行):
  ```dart
  static const String serviceUUID = "你的Service UUID";
  static const String writeCharUUID = "你的Write UUID";
  static const String notifyCharUUID = "你的Notify UUID";
  ```

### 2. 调整设备过滤规则 (如有需要)
- [ ] 打开文件: `lib/providers/bluetooth_provider.dart`
- [ ] 修改第45-49行的设备名称过滤条件

---

## 🧪 测试流程

### 第一步: 扫描测试
```dart
// 测试代码
final jdy08 = JDY08BluetoothService();
List<BluetoothDevice> devices = await jdy08.scanForDevices();
print('找到 ${devices.length} 台设备');
```

**预期结果**:
- [ ] 能扫描到设备
- [ ] 设备名称正确
- [ ] RSSI值在 -30 到 -80 之间

**如果失败**:
- [ ] 检查设备是否开启
- [ ] 检查蓝牙权限是否授予
- [ ] 用nRF Connect验证设备可见性

---

### 第二步: 连接测试
```dart
// 测试代码
bool success = await jdy08.connectToDevice(devices.first);
print('连接${success ? "成功" : "失败"}');
```

**预期结果**:
- [ ] 连接成功返回 true
- [ ] 能发现服务和特征
- [ ] 连接状态变为 connected

**如果失败**:
- [ ] 用nRF Connect验证UUID是否正确
- [ ] 检查设备是否已被其他设备连接
- [ ] 增大连接超时时间

---

### 第三步: 命令测试
```dart
// 测试代码
await jdy08.queryDeviceStatus();           // 查询状态
await jdy08.setLedColor(0, 255, 0, 0, 100); // 设置L区红色
await jdy08.setFanSpeedPercent(50);        // 风扇50%
```

**预期结果**:
- [ ] 命令发送无异常
- [ ] 硬件有相应动作 (LED变色、风扇转速变化)
- [ ] 能收到设备响应

**如果失败**:
- [ ] 用nRF Connect手动发送十六进制命令
- [ ] 检查数据包格式和校验和
- [ ] 查看硬件日志

---

### 第四步: 状态监听测试
```dart
// 测试代码
jdy08.statusStream.listen((status) {
  print('设备状态: $status');
});
```

**预期结果**:
- [ ] 能接收到状态数据
- [ ] 数据格式正确
- [ ] UI能实时更新

---

## 🐛 常见问题快速诊断

### 扫描不到设备
- [ ] 设备蓝牙是否开启？
- [ ] 应用蓝牙权限是否授予？
- [ ] 设备名称过滤是否太严格？
- [ ] 用nRF Connect能否扫描到？

### 连接失败
- [ ] UUID是否正确？ (用nRF Connect验证)
- [ ] 设备是否已被其他设备连接？
- [ ] 设备距离是否太远？
- [ ] 是否有蓝牙干扰？

### 发送命令无反应
- [ ] Write特征是否找到？
- [ ] 数据包格式是否正确？
- [ ] 校验和是否计算正确？
- [ ] 硬件是否正常工作？

### 收不到响应
- [ ] Notify是否已启用？
- [ ] 监听器是否正确订阅？
- [ ] 硬件是否主动发送数据？
- [ ] 数据解析逻辑是否正确？

---

## 📱 Android权限检查

打开 `android/app/src/main/AndroidManifest.xml` 确认:

- [x] BLUETOOTH
- [x] BLUETOOTH_ADMIN
- [x] BLUETOOTH_SCAN (Android 12+)
- [x] BLUETOOTH_CONNECT (Android 12+)
- [x] ACCESS_FINE_LOCATION
- [x] ACCESS_COARSE_LOCATION

**已配置 ✅** - 无需修改

---

## 🍎 iOS权限配置

打开 `ios/Runner/Info.plist` 添加:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙权限以连接 RideWind 设备</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙权限以连接 RideWind 设备</string>
```

- [ ] 已添加权限描述

---

## 📊 协议命令快速参考

### 统一协议命令码
| 命令 | 代码 | 功能 |
|------|------|------|
| 0x01 | `queryDeviceStatus()` | 查询状态 |
| 0x02 | `setLedColor(zone, r, g, b, br)` | 设置LED |
| 0x03 | `setBrightness(br)` | 设置亮度 |
| 0x04 | `setFanSpeedPercent(pct)` | 设置转速 |
| 0x05 | `selectPreset(id)` | 选预设 |
| 0x06 | `setMode(mode)` | 设置模式 |
| 0x08 | `emergencyStop()` | 紧急停止 |
| 0x10 | `saveConfig()` | 保存配置 |
| 0x11 | `restoreDefaults()` | 恢复出厂 |

### JSON协议命令
```dart
protocolService.setFanSpeed(50);
protocolService.setLedColor(255, 0, 0);
protocolService.setLedBrightness(80);
```

---

## 🚀 快速启动命令

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run

# 启用蓝牙详细日志
# 在 main.dart 添加: FlutterBluePlus.setLogLevel(LogLevel.verbose);

# 查看连接的设备
adb logcat | grep -i bluetooth
```

---

## 📚 参考文档

- **完整架构**: [BLUETOOTH_ARCHITECTURE.md](BLUETOOTH_ARCHITECTURE.md)
- **集成指南**: [HARDWARE_INTEGRATION_GUIDE.md](HARDWARE_INTEGRATION_GUIDE.md)
- **协议规范**: [PROTOCOL_SPECIFICATION.md](PROTOCOL_SPECIFICATION.md)
- **项目README**: [README.md](README.md)

---

## 🎯 完成标准

### 基础功能
- [ ] 能扫描到设备
- [ ] 能成功连接
- [ ] 能发送命令
- [ ] 能接收响应
- [ ] UI能实时更新

### 核心功能
- [ ] LED颜色控制正常
- [ ] 风扇转速控制正常
- [ ] 状态查询正常
- [ ] 配置保存正常
- [ ] 断线重连正常

### 用户体验
- [ ] 连接速度 < 5秒
- [ ] 命令响应 < 500ms
- [ ] 无明显卡顿
- [ ] 错误提示友好
- [ ] 引导流程清晰

---

## 📞 获取帮助

遇到问题时:
1. 查看对应文档的详细说明
2. 使用nRF Connect验证硬件
3. 检查控制台日志
4. 提交GitHub Issue并附上日志

---

**最后更新**: 2024-11-28  
**下次检查**: 硬件对接完成后
