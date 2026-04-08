# Running Mode 风扇控制 - 测试文档

## ✅ 已完成的修改

### 1. 导入必要的包
```dart
import 'package:provider/provider.dart';
import '../providers/bluetooth_provider.dart';
```

### 2. 实现速度控制回调
```dart
onSpeedChanged: (speed) async {
  setState(() => _currentSpeed = speed);
  
  // 获取蓝牙Provider
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  
  // 映射速度：0-340 km/h → 0-100%
  int percentage = (speed * 100 / _maxSpeed).round().clamp(0, 100);
  
  // 发送蓝牙命令
  bool success = await btProvider.setFanSpeed(percentage);
}
```

### 3. 实现紧急停止回调
```dart
onEmergencyStop: () async {
  setState(() => _currentSpeed = 0);
  
  // 发送停止命令（速度=0）
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  bool success = await btProvider.setFanSpeed(0);
}
```

---

## 🔄 完整的数据流

```
UI滑块 (0-340 km/h)
    ↓
映射计算 (percentage = speed * 100 / 340)
    ↓
BluetoothProvider.setFanSpeed(percentage)
    ↓
ProtocolService.setFanSpeed(percentage)
    ↓
BLEService.sendString("FAN:percentage\n")
    ↓
JDY-08 蓝牙模块
    ↓
STM32 UART2 接收
    ↓
Protocol_Process("FAN:percentage")
    ↓
CMD_SetFanSpeed(percentage)
    ↓
Num = percentage
    ↓
PWM 输出
    ↓
风扇转速变化 ✅
```

---

## 📱 测试步骤

### **前提条件**
- ✅ 硬件已上电
- ✅ JDY-08 蓝牙模块正常工作
- ✅ App 已连接到设备

### **测试流程**

#### **Step 1: 启动应用**
```bash
flutter run
```

#### **Step 2: 连接设备**
1. 应用启动后，自动扫描蓝牙设备
2. 识别到 JDY-08 模块
3. 自动连接
4. 进入设备控制页面

#### **Step 3: 进入 Running Mode**
1. 在设备控制页面，左右滑动模式文字
2. 滑动到 "Running Mode"
3. 点击文字进入 Running Mode

#### **Step 4: 测试速度控制**

**测试用例 1: 设置 50% 速度**
- 操作：拖动滑块到 170 km/h（中间位置）
- 预期：
  - UI 显示：170 km/h
  - 计算：170 * 100 / 340 = 50%
  - 发送命令：`FAN:50\n`
  - 硬件响应：风扇转速 = 50%
  - 控制台日志：
    ```
    🏃 Running Mode: 速度 170 km/h → 50%
    📤 发送命令: FAN:50
    ✅ 风扇速度命令发送成功: 50%
    ```

**测试用例 2: 设置最大速度**
- 操作：拖动滑块到 340 km/h（最右侧）
- 预期：
  - UI 显示：340 km/h
  - 计算：340 * 100 / 340 = 100%
  - 发送命令：`FAN:100\n`
  - 硬件响应：风扇转速 = 100%
  - 控制台日志：
    ```
    🏃 Running Mode: 速度 340 km/h → 100%
    📤 发送命令: FAN:100
    ✅ 风扇速度命令发送成功: 100%
    ```

**测试用例 3: 设置最小速度**
- 操作：拖动滑块到 0 km/h（最左侧）
- 预期：
  - UI 显示：0 km/h
  - 计算：0 * 100 / 340 = 0%
  - 发送命令：`FAN:0\n`
  - 硬件响应：风扇停止
  - 控制台日志：
    ```
    🏃 Running Mode: 速度 0 km/h → 0%
    📤 发送命令: FAN:0
    ✅ 风扇速度命令发送成功: 0%
    ```

**测试用例 4: 紧急停止**
- 操作：点击"紧急停止"按钮
- 预期：
  - UI 显示：0 km/h
  - 发送命令：`FAN:0\n`
  - 硬件响应：风扇立即停止
  - 控制台日志：
    ```
    🛑 Running Mode: 紧急停止
    📤 发送命令: FAN:0
    ✅ 紧急停止命令发送成功
    ```

#### **Step 5: 验证硬件响应**

观察硬件端：
1. **LCD 显示**：应该显示当前速度值（0-100）
2. **风扇转速**：应该与设置的百分比一致
3. **蓝牙响应**：硬件会发送 `OK:FAN:XX\r\n` 确认

---

## 🐛 可能的问题和解决方案

### **问题 1: 命令发送失败**
**现象**：控制台显示 `❌ 风扇速度命令发送失败`

**可能原因**：
- 蓝牙未连接
- 蓝牙连接断开

**解决方案**：
1. 检查蓝牙连接状态
2. 重新连接设备
3. 查看 `BluetoothProvider.isConnected` 状态

### **问题 2: 硬件无响应**
**现象**：命令发送成功，但风扇不转

**可能原因**：
- 硬件端未收到数据
- 协议格式错误
- 硬件端代码未运行

**解决方案**：
1. 检查硬件端串口是否正常接收
2. 查看硬件端 LCD 显示是否更新
3. 确认硬件端 `BLE_Process()` 是否在主循环中调用

### **问题 3: 速度映射不准确**
**现象**：设置 170 km/h，但硬件显示不是 50%

**可能原因**：
- 映射公式错误
- 浮点数精度问题

**解决方案**：
1. 检查映射公式：`(speed * 100 / 340).round()`
2. 查看控制台日志中的计算结果
3. 确认 `_maxSpeed` 值是否为 340

---

## 📊 速度映射表

| UI 显示 (km/h) | 计算公式 | 百分比 (%) | 硬件 Num 值 |
|---------------|---------|-----------|------------|
| 0             | 0*100/340 | 0         | 0          |
| 34            | 34*100/340 | 10        | 10         |
| 68            | 68*100/340 | 20        | 20         |
| 102           | 102*100/340 | 30        | 30         |
| 136           | 136*100/340 | 40        | 40         |
| 170           | 170*100/340 | 50        | 50         |
| 204           | 204*100/340 | 60        | 60         |
| 238           | 238*100/340 | 70        | 70         |
| 272           | 272*100/340 | 80        | 80         |
| 306           | 306*100/340 | 90        | 90         |
| 340           | 340*100/340 | 100       | 100        |

---

## 🔍 调试技巧

### **1. 查看控制台日志**
```
🏃 Running Mode: 速度 170 km/h → 50%
📤 发送命令: FAN:50
✅ 风扇速度命令发送成功: 50%
```

### **2. 使用 Bluetooth Test 界面**
如果 Running Mode 有问题，可以先用 Bluetooth Test 界面测试：
1. 切换到 "Bluetooth Test" 模式
2. 手动设置速度
3. 观察硬件响应
4. 确认基础通信正常

### **3. 硬件端调试**
在硬件端添加调试输出：
```c
void CMD_SetFanSpeed(uint8_t speed) {
    printf("Received: FAN:%d\n", speed);  // 添加调试输出
    Num = speed;
    // ...
}
```

---

## ✅ 验收标准

### **功能验收**
- ✅ 拖动滑块，风扇转速实时变化
- ✅ 速度映射准确（170 km/h = 50%）
- ✅ 紧急停止按钮立即停止风扇
- ✅ 控制台日志正确显示命令发送状态

### **性能验收**
- ✅ 命令发送延迟 < 100ms
- ✅ 滑块拖动流畅，无卡顿
- ✅ 蓝牙连接稳定，无断连

### **用户体验验收**
- ✅ 操作直观，响应及时
- ✅ 错误提示清晰
- ✅ 界面流畅，无闪烁

---

## 🎉 成功标志

当你看到以下现象时，说明功能已成功实现：

1. **App 端**：
   - 拖动滑块，UI 实时更新
   - 控制台显示正确的日志
   - 无错误提示

2. **硬件端**：
   - LCD 显示速度值实时更新
   - 风扇转速与设置值一致
   - 紧急停止按钮立即生效

3. **通信**：
   - 蓝牙连接稳定
   - 命令发送成功率 100%
   - 硬件响应及时

---

## 📞 下一步

完成 Running Mode 测试后，可以继续：

1. **优化用户体验**
   - 添加速度变化动画
   - 添加震动反馈
   - 添加声音提示

2. **实现 Colorize Mode**
   - 定义 LED 控制协议
   - 实现颜色选择功能
   - 实现亮度调节功能

3. **添加错误处理**
   - 蓝牙断连重连
   - 命令发送失败重试
   - 用户友好的错误提示

---

**祝测试顺利！🚀**
