# 🚀 RideWind 硬件集成快速指南

> **面向**: 硬件工程师 & App开发者  
> **目标**: 快速完成蓝牙硬件与App的对接

---

## 📋 前置准备清单

### 硬件侧需要提供
- [ ] 蓝牙模块型号和规格书 (如 JDY-08)
- [ ] BLE Service UUID
- [ ] BLE Write Characteristic UUID
- [ ] BLE Notify/Indicate Characteristic UUID
- [ ] 设备名称格式 (如 `RideWind-001`, `LED-XXX`)
- [ ] 通信协议文档 (数据包格式、命令码定义)
- [ ] 测试设备若干台

### App侧现有基础
✅ flutter_blue_plus 蓝牙库已集成  
✅ Android蓝牙权限已配置  
✅ 两套协议实现已准备 (统一协议 + JSON)  
✅ UI交互流程已完成  
✅ 状态管理架构已搭建  

---

## 🔌 三种集成方案

### 方案A: 统一协议 (推荐) ⭐

**适用场景**: 硬件使用 `0xAA...0x55` 格式的二进制协议

**实现文件**: `lib/services/jdy08_bluetooth_service.dart`

**优点**:
- ✅ 传输效率高
- ✅ 数据包小
- ✅ 已实现完整协议栈
- ✅ 支持校验和验证

**数据包格式**:
```
发送: [AA] [LEN] [CMD] [DATA...] [CHECKSUM] [55]
接收: [AA] [LEN] [CMD] [DATA...] [CHECKSUM] [55]
```

**配置步骤**:
1. 打开 `lib/services/jdy08_bluetooth_service.dart`
2. 修改设备名称前缀:
   ```dart
   static const String _deviceNamePrefix = 'RideWind'; // 改为实际设备名
   ```
3. 如需精确匹配UUID，取消注释并填写:
   ```dart
   static const String _serviceUuid = "0000ffe0-...";     // 填入真实UUID
   static const String _writeCharUuid = "0000ffe1-...";   // 填入真实UUID
   static const String _notifyCharUuid = "0000ffe1-...";  // 填入真实UUID
   ```
4. 在UI中使用:
   ```dart
   final jdy08Service = JDY08BluetoothService();
   await jdy08Service.connectToDevice(device);
   await jdy08Service.setLedColor(0, 255, 0, 0, 100); // 设置L区红色
   ```

---

### 方案B: JSON协议

**适用场景**: 硬件通过JSON格式收发命令

**实现文件**: `lib/services/protocol_service.dart`

**优点**:
- ✅ 人类可读
- ✅ 易于调试
- ✅ 灵活性高

**缺点**:
- ⚠️ 数据包大
- ⚠️ 解析开销大

**JSON示例**:
```json
// 发送
{"command": "setFanSpeed", "value": 50}

// 接收
{"status": "ok", "fanSpeed": 50, "brightness": 80}
```

**配置步骤**:
1. 打开 `lib/services/bluetooth_service.dart`
2. 修改UUID:
   ```dart
   static const String serviceUUID = "你的Service UUID";
   static const String writeCharUUID = "你的Write UUID";
   static const String notifyCharUUID = "你的Notify UUID";
   ```
3. 在UI中使用:
   ```dart
   final protocolService = ProtocolService();
   await protocolService.setFanSpeed(50);
   await protocolService.setLedColor(255, 0, 0);
   ```

---

### 方案C: 自定义协议

**适用场景**: 硬件使用特殊格式协议

**实现步骤**:
1. 复制 `jdy08_bluetooth_service.dart` 为 `custom_bluetooth_service.dart`
2. 修改 `sendUnifiedCommand` 方法中的数据包构造逻辑
3. 修改 `_parseReceivedData` 方法中的解析逻辑
4. 更新命令码映射表

---

## 🧪 测试流程

### 第一步: 扫描测试

**测试代码**:
```dart
final jdy08 = JDY08BluetoothService();
List<BluetoothDevice> devices = await jdy08.scanForDevices(timeoutSeconds: 10);

print('找到 ${devices.length} 台设备:');
for (var device in devices) {
  print('- ${device.platformName} (${device.remoteId})');
}
```

**预期结果**:
- 能够扫描到设备
- 设备名称符合预期
- RSSI值合理 (-30 到 -70)

**常见问题**:
| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 扫描不到设备 | 设备未开启 | 检查硬件电源和蓝牙状态 |
| 设备名称不匹配 | 过滤条件太严格 | 调整 `_isTargetDevice` 方法 |
| 权限错误 | 蓝牙权限未授予 | 检查应用权限设置 |

---

### 第二步: 连接测试

**测试代码**:
```dart
final jdy08 = JDY08BluetoothService();
List<BluetoothDevice> devices = await jdy08.scanForDevices();
if (devices.isNotEmpty) {
  bool success = await jdy08.connectToDevice(devices.first);
  print('连接${success ? "成功" : "失败"}');
  
  // 监听连接状态
  jdy08.connectionStateStream.listen((state) {
    print('连接状态: $state');
  });
}
```

**预期结果**:
- 连接成功返回 true
- 能够发现服务和特征
- 连接状态变为 `connected`

**常见问题**:
| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 连接超时 | 设备距离太远或干扰 | 靠近设备重试 |
| 服务未找到 | UUID不匹配 | 用nRF Connect验证UUID |
| 特征权限不足 | Characteristic不支持写入 | 检查硬件Characteristic配置 |

---

### 第三步: 命令测试

**测试代码**:
```dart
// 连接成功后
await jdy08.queryDeviceStatus();           // 查询状态
await jdy08.setLedColor(0, 255, 0, 0, 100); // L区设为红色
await jdy08.setFanSpeedPercent(50);        // 风扇50%速度

// 监听设备响应
jdy08.dataReceivedStream.listen((data) {
  print('收到数据: ${data.map((e) => e.toRadixString(16)).join(' ')}');
});

jdy08.statusStream.listen((status) {
  print('设备状态: $status');
});
```

**预期结果**:
- 命令发送成功
- 硬件有相应动作 (LED颜色变化、风扇转速变化)
- 能收到设备响应数据

**调试技巧**:
1. 用示波器/逻辑分析仪监控蓝牙数据线
2. 用nRF Connect发送原始十六进制命令验证硬件
3. 打印发送和接收的原始字节数组
4. 对比协议文档验证数据包格式

---

### 第四步: 状态监听测试

**测试代码**:
```dart
// 监听设备状态更新
jdy08.statusStream.listen((status) {
  print('LED区域颜色: ${status['zoneColors']}');
  print('风扇速度: ${status['fanPercent']}%');
  print('亮度: ${status['brightness']}%');
  print('当前UI: ${status['ui']}');
  print('工作模式: ${status['mode']}');
});
```

**预期结果**:
- 能接收到设备主动上报的状态
- 状态数据格式正确
- UI能实时更新

---

## 🔧 调试工具推荐

### 移动端工具
| 工具名称 | 平台 | 用途 |
|---------|------|------|
| nRF Connect | Android/iOS | BLE设备扫描、连接、数据收发 |
| LightBlue | iOS | iOS专用BLE调试工具 |
| BLE Scanner | Android | 简单易用的扫描工具 |

### 桌面端工具
| 工具名称 | 平台 | 用途 |
|---------|------|------|
| Wireshark + Bluetooth HCI | All | 抓包分析蓝牙数据 |
| Serial Bluetooth Terminal | Windows | 串口蓝牙调试 |

### 调试步骤
1. **用nRF Connect连接设备**: 验证UUID和特征属性
2. **手动发送命令**: 用十六进制发送器测试硬件响应
3. **对比App日志**: 确认App发送的数据与手动发送一致
4. **抓包分析**: 对比成功和失败的数据包差异

---

## ⚠️ 常见坑点和解决方案

### 1. UUID大小写问题
```dart
// ❌ 错误: UUID大小写不匹配
"0000FFE0-0000-1000-8000-00805F9B34FB"

// ✅ 正确: flutter_blue_plus统一使用小写
"0000ffe0-0000-1000-8000-00805f9b34fb"

// 解决方案: 使用 toLowerCase()
charUuid.toString().toLowerCase().contains('ffe1')
```

### 2. MTU问题
```dart
// 默认MTU是23字节 (20字节数据 + 3字节协议头)
// 如果数据包超过20字节需要协商MTU
await device.requestMtu(512); // 请求更大MTU
```

### 3. Write类型选择
```dart
// Write with response (等待确认, 慢但可靠)
await characteristic.write(data, withoutResponse: false);

// Write without response (不等确认, 快但可能丢包)
await characteristic.write(data, withoutResponse: true);

// 建议: 状态查询用 false, 高频控制用 true
```

### 4. 连接状态监听
```dart
// ❌ 错误: 忘记取消订阅导致内存泄漏
device.connectionState.listen((state) { ... });

// ✅ 正确: 保存订阅并在dispose时取消
_subscription = device.connectionState.listen((state) { ... });
// 在dispose中
_subscription?.cancel();
```

### 5. 校验和算法
```dart
// 统一协议校验和: 对LEN、CMD、DATA求和取低8位
int checksum = 0;
for (int i = 1; i < packet.length; i++) {
  checksum += packet[i];
}
checksum = checksum & 0xFF;

// 注意: 不同协议校验算法不同，需参考硬件文档
```

---

## 📊 性能优化建议

### 扫描优化
```dart
// ❌ 扫描时间过长
await FlutterBluePlus.startScan(timeout: Duration(seconds: 30));

// ✅ 3-5秒足够
await FlutterBluePlus.startScan(timeout: Duration(seconds: 3));

// ✅ 找到目标设备后立即停止
await FlutterBluePlus.stopScan();
```

### 连接优化
```dart
// ✅ 设置合理的连接超时
await device.connect(
  timeout: Duration(seconds: 15),
  autoConnect: false, // 不自动重连，手动控制
);

// ✅ 断开后清理资源
await device.disconnect();
await Future.delayed(Duration(milliseconds: 500)); // 等待断开完成
```

### 数据发送优化
```dart
// ❌ 频繁发送小数据包
for (int i = 0; i < 100; i++) {
  await sendCommand(i);
}

// ✅ 合并数据包或限流
await Future.delayed(Duration(milliseconds: 100)); // 限流
```

---

## 📝 集成检查清单

### 开发前
- [ ] 获取完整硬件协议文档
- [ ] 确认UUID和设备名称
- [ ] 准备测试设备
- [ ] 安装调试工具 (nRF Connect)

### 开发中
- [ ] 更新UUID配置
- [ ] 修改设备名称过滤规则
- [ ] 实现协议编码/解码
- [ ] 添加错误处理
- [ ] 编写单元测试

### 测试阶段
- [ ] 扫描功能测试
- [ ] 连接功能测试
- [ ] 命令收发测试
- [ ] 状态监听测试
- [ ] 异常场景测试 (断线重连、信号干扰等)
- [ ] 性能测试 (连接速度、命令响应时间)

### 发布前
- [ ] 代码审查
- [ ] 删除调试日志
- [ ] 优化用户提示文案
- [ ] 编写用户文档
- [ ] 准备常见问题FAQ

---

## 🆘 问题排查流程

```
┌─────────────────────────┐
│   扫描不到设备?         │
└───────┬─────────────────┘
        │
        ├─→ 检查蓝牙权限是否授予
        ├─→ 检查设备是否开启蓝牙
        ├─→ 检查设备名称过滤规则
        ├─→ 用nRF Connect验证设备可见性
        │
┌───────▼─────────────────┐
│   连接失败?             │
└───────┬─────────────────┘
        │
        ├─→ 检查设备距离是否过远
        ├─→ 检查是否有其他设备已连接
        ├─→ 检查UUID是否正确
        ├─→ 重启设备和App
        │
┌───────▼─────────────────┐
│   发送命令无响应?       │
└───────┬─────────────────┘
        │
        ├─→ 检查Write特征是否正确
        ├─→ 用nRF Connect手动发送验证
        ├─→ 检查数据包格式和校验和
        ├─→ 检查硬件日志
        │
┌───────▼─────────────────┐
│   收不到设备响应?       │
└───────┬─────────────────┘
        │
        ├─→ 检查Notify是否已启用
        ├─→ 检查监听器是否正确订阅
        ├─→ 检查硬件是否主动发送数据
        └─→ 用抓包工具验证数据传输
```

---

## 📞 技术支持

遇到问题请提供以下信息:
1. 硬件型号和固件版本
2. App版本和Flutter版本
3. 完整的错误日志
4. nRF Connect连接截图
5. 重现步骤

**祝开发顺利!** 🎉
