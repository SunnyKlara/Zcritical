# RideWind 双向通信完整实施方案

## 📅 创建日期: 2026-01-07
## 🎯 目标: 实现硬件与APP的完整双向通信

---

## 一、功能1: 硬件主动上报

### 1.1 协议设计

硬件端主动上报的数据格式：

```
// 旋钮增量上报
KNOB:delta\n          // delta: 正数=顺时针, 负数=逆时针
例: KNOB:5\n          // 顺时针旋转5格
例: KNOB:-3\n         // 逆时针旋转3格

// 按钮事件上报
BTN:type:action\n     // type=按钮类型, action=动作
例: BTN:KNOB:CLICK\n  // 旋钮按下单击
例: BTN:KNOB:LONG\n   // 旋钮长按
例: BTN:KNOB:TRIPLE\n // 旋钮三击

// 传感器数据上报 (可选)
SENSOR:type:value\n
例: SENSOR:TEMP:45\n  // 温度45°C
例: SENSOR:BAT:85\n   // 电量85%
```

### 1.2 APP端实现

**文件: `lib/services/protocol_service.dart`**

需要添加的解析方法：
- `parseKnobDelta()` ✅ 已实现
- `parseButtonEvent()` 🆕 新增
- `parseSensorData()` 🆕 新增

### 1.3 代码实现

```dart
// ═══════════════════════════════════════════════════════════════
// protocol_service.dart 新增代码
// ═══════════════════════════════════════════════════════════════

/// 解析按钮事件
/// 响应格式: BTN:type:action
/// 返回: Map{type, action}，解析失败返回null
Map<String, String>? parseButtonEvent(String response) {
  response = response.trim();
  
  RegExp btnRegex = RegExp(r'BTN:(\w+):(\w+)');
  Match? match = btnRegex.firstMatch(response);
  
  if (match != null) {
    return {
      'type': match.group(1)!,    // KNOB, POWER, etc.
      'action': match.group(2)!,  // CLICK, LONG, TRIPLE
    };
  }
  return null;
}

/// 解析传感器数据
/// 响应格式: SENSOR:type:value
/// 返回: Map{type, value}，解析失败返回null
Map<String, dynamic>? parseSensorData(String response) {
  response = response.trim();
  
  RegExp sensorRegex = RegExp(r'SENSOR:(\w+):(-?\d+)');
  Match? match = sensorRegex.firstMatch(response);
  
  if (match != null) {
    return {
      'type': match.group(1)!,           // TEMP, BAT, etc.
      'value': int.parse(match.group(2)!),
    };
  }
  return null;
}
```

---

## 二、功能2: APP查询硬件状态并等待响应

### 2.1 问题分析

当前实现的问题：
- `getFanSpeed()` 只发送查询命令，不等待响应
- 响应通过 `responseStream` 异步返回，调用者无法直接获取结果

### 2.2 解决方案: Completer模式

使用 `Completer` 实现请求-响应配对：

```dart
// 请求ID → Completer 映射
Map<String, Completer<String>> _pendingRequests = {};
```

### 2.3 代码实现

```dart
// ═══════════════════════════════════════════════════════════════
// protocol_service.dart 新增代码 - 请求响应配对
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

class ProtocolService {
  final BLEService bleService;
  
  // 🆕 等待响应的请求队列
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};
  
  // 🆕 响应超时时间
  static const Duration _responseTimeout = Duration(seconds: 3);

  ProtocolService(this.bleService) {
    // 监听BLE接收数据
    bleService.rxDataStream.listen(_handleResponse);
  }

  /// 🆕 统一响应处理
  void _handleResponse(List<int> data) {
    String response = String.fromCharCodes(data).trim();
    print('📩 收到响应: $response');
    
    // 尝试匹配等待中的请求
    _matchPendingRequest(response);
    
    // 广播到响应流（保持原有逻辑）
    _responseController.add(response);
  }

  /// 🆕 匹配等待中的请求
  void _matchPendingRequest(String response) {
    // 解析响应类型
    String? requestKey;
    Map<String, dynamic>? result;
    
    if (response.startsWith('FAN:') || response.contains('FAN:')) {
      requestKey = 'GET:FAN';
      int? speed = parseFanSpeed(response);
      if (speed != null) {
        result = {'success': true, 'speed': speed};
      }
    } 
    else if (response.startsWith('WUHUA:') || response.contains('WUHUA:')) {
      requestKey = 'GET:WUHUA';
      int? status = parseWuhuaqiStatus(response);
      if (status != null) {
        result = {'success': true, 'status': status};
      }
    }
    else if (response.startsWith('AUDIO:') && response.contains(':')) {
      requestKey = 'GET:AUDIO';
      var audioStatus = parseAudioStatus(response);
      if (audioStatus != null) {
        result = {'success': true, ...audioStatus};
      }
    }
    
    // 完成等待中的请求
    if (requestKey != null && _pendingRequests.containsKey(requestKey)) {
      _pendingRequests[requestKey]!.complete(result ?? {'success': false});
      _pendingRequests.remove(requestKey);
    }
  }

  /// 🆕 查询风扇速度（等待响应版本）
  /// 返回: {success: bool, speed: int?}
  Future<Map<String, dynamic>> queryFanSpeed() async {
    const requestKey = 'GET:FAN';
    
    // 创建Completer
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;
    
    // 发送查询命令
    await bleService.sendString('GET:FAN\n');
    
    // 等待响应（带超时）
    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      return {'success': false, 'error': 'timeout'};
    }
  }

  /// 🆕 查询雾化器状态（等待响应版本）
  Future<Map<String, dynamic>> queryWuhuaqiStatus() async {
    const requestKey = 'GET:WUHUA';
    
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;
    
    await bleService.sendString('GET:WUHUA\n');
    
    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      return {'success': false, 'error': 'timeout'};
    }
  }

  /// 🆕 查询音频状态（等待响应版本）
  Future<Map<String, dynamic>> queryAudioStatus() async {
    const requestKey = 'GET:AUDIO';
    
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestKey] = completer;
    
    await bleService.sendString('GET:AUDIO\n');
    
    try {
      return await completer.future.timeout(_responseTimeout);
    } on TimeoutException {
      _pendingRequests.remove(requestKey);
      return {'success': false, 'error': 'timeout'};
    }
  }
}
```

### 2.4 使用示例

```dart
// 在 UI 中使用
void _checkDeviceStatus() async {
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  
  // 查询风扇速度（会等待硬件响应）
  final fanResult = await btProvider.queryFanSpeedSync();
  if (fanResult['success']) {
    print('当前风扇速度: ${fanResult['speed']}%');
    setState(() => _fanSpeed = fanResult['speed']);
  } else {
    print('查询超时或失败');
  }
  
  // 查询雾化器状态
  final wuhuaResult = await btProvider.queryWuhuaqiStatusSync();
  if (wuhuaResult['success']) {
    print('雾化器状态: ${wuhuaResult['status'] == 1 ? "开启" : "关闭"}');
  }
}
```

---

## 三、功能3: 旋钮控制与UI联动

### 3.1 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                     旋钮控制UI联动架构                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  硬件旋钮 ──► KNOB:delta ──► BLEService ──► ProtocolService    │
│                                                   │             │
│                                                   ▼             │
│                                          BluetoothProvider      │
│                                          knobDeltaStream        │
│                                                   │             │
│                    ┌──────────────────────────────┼─────────┐   │
│                    │                              │         │   │
│                    ▼                              ▼         ▼   │
│              RunningMode                   ColorizeMode   其他  │
│              速度滚轮联动                   颜色选择联动         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 当前实现状态

✅ 已实现:
- `parseKnobDelta()` 解析旋钮增量
- `knobDeltaStream` 广播旋钮事件

🔧 需要完善:
- UI组件订阅 `knobDeltaStream`
- 根据当前模式分发旋钮事件
- 实现具体的UI联动逻辑

### 3.3 代码实现

```dart
// ═══════════════════════════════════════════════════════════════
// device_connect_screen.dart 新增代码 - 旋钮联动
// ═══════════════════════════════════════════════════════════════

class _DeviceConnectScreenState extends State<DeviceConnectScreen> {
  // 🆕 旋钮事件订阅
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    // ... 其他初始化代码 ...
    
    // 🆕 订阅旋钮增量流
    _subscribeToKnobEvents();
  }

  /// 🆕 订阅旋钮事件
  void _subscribeToKnobEvents() {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
      print('🎛️ 收到旋钮增量: $delta');
      _handleKnobDelta(delta);
    });
  }

  /// 🆕 处理旋钮增量（根据当前模式分发）
  void _handleKnobDelta(int delta) {
    if (!_modeActivated) {
      // 模式选择页面：切换模式
      _handleKnobInModeSelection(delta);
    } else {
      // 已进入模式：根据具体模式处理
      switch (_currentMode) {
        case ControlMode.running:
          _handleKnobInRunningMode(delta);
          break;
        case ControlMode.colorize:
          _handleKnobInColorizeMode(delta);
          break;
        case ControlMode.cleaning:
          // Cleaning模式暂不响应旋钮
          break;
        case ControlMode.bluetoothTest:
          // 测试模式暂不响应旋钮
          break;
      }
    }
  }

  /// 🆕 模式选择页面的旋钮处理
  void _handleKnobInModeSelection(int delta) {
    HapticFeedback.selectionClick();
    
    setState(() {
      // 计算新的模式索引
      int newIndex = _currentModeIndex + (delta > 0 ? 1 : -1);
      // 循环切换 (0-3)
      _currentModeIndex = newIndex.clamp(0, 3);
    });
    
    // 同步PageView
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        _currentModeIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  /// 🆕 Running Mode的旋钮处理
  void _handleKnobInRunningMode(int delta) {
    if (!_showSpeedControl) return; // 只有调速界面显示时才响应
    
    HapticFeedback.selectionClick();
    
    setState(() {
      // 每格旋钮增量对应5km/h
      int speedStep = delta * 5;
      _currentSpeed = (_currentSpeed + speedStep).clamp(0, _maxSpeed);
    });
    
    // 同步到硬件
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    btProvider.setRunningSpeed(_currentSpeed);
  }

  /// 🆕 Colorize Mode的旋钮处理
  void _handleKnobInColorizeMode(int delta) {
    HapticFeedback.selectionClick();
    
    if (_colorizeState == ColorizeState.preset) {
      // 预设选择：切换颜色预设
      setState(() {
        int newIndex = _selectedColorIndex + (delta > 0 ? 1 : -1);
        _selectedColorIndex = newIndex.clamp(0, 7);
      });
      
      // 同步PageView
      if (_colorPageController.hasClients) {
        _colorPageController.animateToPage(
          _selectedColorIndex,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
      
      // 同步到硬件
      _syncPresetToHardware(_selectedColorIndex);
    } 
    else if (_colorizeState == ColorizeState.rgbDetail) {
      // RGB调节：调整当前选中灯带的亮度
      setState(() {
        // 每格旋钮增量对应5%亮度
        double brightnessStep = delta * 0.05;
        _brightnessValue = (_brightnessValue + brightnessStep).clamp(0.0, 1.0);
      });
      
      // 同步到硬件
      final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
      btProvider.setBrightness((_brightnessValue * 100).toInt());
    }
  }

  @override
  void dispose() {
    _knobSubscription?.cancel(); // 🆕 取消订阅
    // ... 其他清理代码 ...
    super.dispose();
  }
}
```

### 3.4 Running Mode Widget 旋钮联动

```dart
// ═══════════════════════════════════════════════════════════════
// running_mode_widget.dart 新增代码 - 外部旋钮控制
// ═══════════════════════════════════════════════════════════════

class RunningModeWidget extends StatefulWidget {
  // ... 现有参数 ...
  
  // 🆕 外部旋钮增量流（可选）
  final Stream<int>? knobDeltaStream;

  const RunningModeWidget({
    // ... 现有参数 ...
    this.knobDeltaStream,
  });
}

class _RunningModeWidgetState extends State<RunningModeWidget> {
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    // ... 现有初始化 ...
    
    // 🆕 订阅外部旋钮流
    _knobSubscription = widget.knobDeltaStream?.listen(_handleExternalKnob);
  }

  /// 🆕 处理外部旋钮输入
  void _handleExternalKnob(int delta) {
    if (!_showSpeedControl) return;
    
    HapticFeedback.selectionClick();
    
    // 计算新速度
    int speedStep = delta * 5; // 每格5km/h
    int newSpeed = (_currentSpeed + speedStep).clamp(0, widget.maxSpeed);
    
    if (newSpeed != _currentSpeed) {
      setState(() {
        _currentSpeed = newSpeed;
      });
      
      // 同步滚轮位置
      if (_speedScrollController?.hasClients ?? false) {
        _speedScrollController!.animateToItem(
          _currentSpeed,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
      
      // 回调通知
      widget.onSpeedChanged(_currentSpeed);
    }
  }

  @override
  void dispose() {
    _knobSubscription?.cancel();
    // ... 现有清理 ...
    super.dispose();
  }
}
```

---

## 四、完整实施步骤

### 步骤1: 修改 protocol_service.dart

添加以下功能：
- [ ] `parseButtonEvent()` 方法
- [ ] `parseSensorData()` 方法
- [ ] `_pendingRequests` 请求队列
- [ ] `queryFanSpeed()` 同步查询方法
- [ ] `queryWuhuaqiStatus()` 同步查询方法
- [ ] `queryAudioStatus()` 同步查询方法

### 步骤2: 修改 bluetooth_provider.dart

添加以下功能：
- [ ] 按钮事件流 `buttonEventStream`
- [ ] 传感器数据流 `sensorDataStream`
- [ ] 同步查询方法包装

### 步骤3: 修改 device_connect_screen.dart

添加以下功能：
- [ ] 订阅 `knobDeltaStream`
- [ ] `_handleKnobDelta()` 分发逻辑
- [ ] 各模式的旋钮处理方法

### 步骤4: 修改 running_mode_widget.dart

添加以下功能：
- [ ] 接收外部旋钮流参数
- [ ] `_handleExternalKnob()` 处理方法

---

## 五、硬件端协议要求

### 5.1 硬件需要实现的上报功能

```c
// ═══════════════════════════════════════════════════════════════
// STM32 硬件端代码示例 (protocol.c)
// ═══════════════════════════════════════════════════════════════

// 旋钮增量上报
void Report_KnobDelta(int16_t delta) {
    char buf[32];
    sprintf(buf, "KNOB:%d\n", delta);
    BLE_SendString(buf);
}

// 按钮事件上报
void Report_ButtonEvent(const char* type, const char* action) {
    char buf[32];
    sprintf(buf, "BTN:%s:%s\n", type, action);
    BLE_SendString(buf);
}

// 传感器数据上报
void Report_SensorData(const char* type, int value) {
    char buf[32];
    sprintf(buf, "SENSOR:%s:%d\n", type, value);
    BLE_SendString(buf);
}

// 在旋钮中断中调用
void TIM1_IRQHandler(void) {
    static int16_t last_count = 0;
    int16_t current = __HAL_TIM_GET_COUNTER(&htim1);
    int16_t delta = current - last_count;
    
    if (delta != 0) {
        Report_KnobDelta(delta);
        last_count = current;
    }
}

// 在按钮检测中调用
void Check_KnobButton(void) {
    static uint32_t press_time = 0;
    static uint8_t click_count = 0;
    
    if (KNOB_BTN_PRESSED) {
        press_time = HAL_GetTick();
    }
    else if (press_time > 0) {
        uint32_t duration = HAL_GetTick() - press_time;
        
        if (duration > 1000) {
            Report_ButtonEvent("KNOB", "LONG");
        } else {
            click_count++;
            // 等待300ms判断是否有后续点击
        }
        press_time = 0;
    }
    
    // 300ms内无后续点击，上报点击事件
    if (click_count > 0 && /* 超时判断 */) {
        if (click_count >= 3) {
            Report_ButtonEvent("KNOB", "TRIPLE");
        } else if (click_count == 2) {
            Report_ButtonEvent("KNOB", "DOUBLE");
        } else {
            Report_ButtonEvent("KNOB", "CLICK");
        }
        click_count = 0;
    }
}
```

### 5.2 硬件需要实现的查询响应

```c
// GET命令响应
void Protocol_HandleGet(const char* param) {
    char buf[64];
    
    if (strcmp(param, "FAN") == 0) {
        sprintf(buf, "FAN:%d\r\n", current_fan_speed);
        BLE_SendString(buf);
    }
    else if (strcmp(param, "WUHUA") == 0) {
        sprintf(buf, "WUHUA:%d\r\n", wuhuaqi_status);
        BLE_SendString(buf);
    }
    else if (strcmp(param, "AUDIO") == 0) {
        sprintf(buf, "AUDIO:%s:%d:%d:%d\r\n", 
            audio_state,      // PLAYING/PAUSED/STOPPED
            audio_volume,     // 0-100
            current_file,     // 当前文件索引
            total_files);     // 总文件数
        BLE_SendString(buf);
    }
    else if (strcmp(param, "ALL") == 0) {
        // 返回所有状态
        sprintf(buf, "STATUS:FAN:%d:WUHUA:%d:BRIGHT:%d\r\n",
            current_fan_speed,
            wuhuaqi_status,
            brightness);
        BLE_SendString(buf);
    }
}
```

---

## 六、测试计划

### 6.1 单元测试

```dart
// test/protocol_service_test.dart

void main() {
  group('ProtocolService 解析测试', () {
    test('解析旋钮增量 - 正数', () {
      final service = ProtocolService(MockBLEService());
      expect(service.parseKnobDelta('KNOB:5'), equals(5));
    });
    
    test('解析旋钮增量 - 负数', () {
      final service = ProtocolService(MockBLEService());
      expect(service.parseKnobDelta('KNOB:-3'), equals(-3));
    });
    
    test('解析按钮事件', () {
      final service = ProtocolService(MockBLEService());
      final result = service.parseButtonEvent('BTN:KNOB:CLICK');
      expect(result, equals({'type': 'KNOB', 'action': 'CLICK'}));
    });
  });
}
```

### 6.2 集成测试

1. **旋钮联动测试**
   - 旋转硬件旋钮 → 观察APP界面变化
   - Running Mode: 速度滚轮跟随
   - Colorize Mode: 颜色选择跟随

2. **查询响应测试**
   - 调用 `queryFanSpeed()` → 验证返回值
   - 测试超时情况 → 验证错误处理

3. **主动上报测试**
   - 按下硬件按钮 → 观察APP日志
   - 验证事件流正确触发

---

## 七、注意事项

1. **线程安全**: Flutter UI更新必须在主线程
2. **节流控制**: 旋钮高频事件需要节流处理
3. **超时处理**: 查询请求必须有超时机制
4. **错误恢复**: 通信异常时的重试策略
5. **状态同步**: 断线重连后需要重新同步状态

---

## 八、后续优化

1. **批量查询**: `GET:ALL` 一次获取所有状态
2. **心跳机制**: 定期检测连接状态
3. **数据缓存**: 减少重复查询
4. **离线队列**: 断线时缓存命令，重连后发送


---

## 九、已完成的代码修改

### ✅ 已修改文件

#### 1. `lib/services/protocol_service.dart`

新增功能：
- `_buttonEventController` - 按钮事件流控制器
- `_sensorDataController` - 传感器数据流控制器
- `_pendingRequests` - 等待响应的请求队列
- `_handleReceivedData()` - 统一数据处理入口
- `_matchPendingRequest()` - 请求响应配对
- `_parseProactiveReport()` - 解析主动上报数据
- `queryFanSpeedSync()` - 同步查询风扇速度
- `queryWuhuaqiStatusSync()` - 同步查询雾化器状态
- `queryAudioStatusSync()` - 同步查询音频状态
- `queryAllStatusSync()` - 同步查询所有状态
- `parseButtonEvent()` - 解析按钮事件
- `parseSensorData()` - 解析传感器数据
- `parseAllStatus()` - 解析所有状态响应

#### 2. `lib/providers/bluetooth_provider.dart`

新增功能：
- `_buttonEventController` - 按钮事件流
- `_sensorDataController` - 传感器数据流
- `buttonEventStream` - 按钮事件流getter
- `sensorDataStream` - 传感器数据流getter
- `queryFanSpeedSync()` - 同步查询风扇速度
- `queryWuhuaqiStatusSync()` - 同步查询雾化器状态
- `queryAudioStatusSync()` - 同步查询音频状态
- `queryAllStatusSync()` - 同步查询所有状态

---

## 十、使用示例

### 10.1 同步查询设备状态

```dart
// 在 Widget 中使用
void _refreshDeviceStatus() async {
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  
  // 显示加载指示器
  setState(() => _isLoading = true);
  
  // 同步查询所有状态
  final result = await btProvider.queryAllStatusSync();
  
  setState(() => _isLoading = false);
  
  if (result['success']) {
    print('风扇速度: ${result['fan']}%');
    print('雾化器: ${result['wuhua'] == 1 ? "开启" : "关闭"}');
    print('亮度: ${result['brightness']}%');
  } else {
    // 显示错误提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('查询失败: ${result['error']}')),
    );
  }
}
```

### 10.2 监听按钮事件

```dart
class _MyWidgetState extends State<MyWidget> {
  StreamSubscription<Map<String, String>>? _buttonSub;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    // 监听按钮事件
    _buttonSub = btProvider.buttonEventStream.listen((event) {
      final type = event['type'];   // KNOB, POWER, etc.
      final action = event['action']; // CLICK, LONG, TRIPLE
      
      print('按钮事件: $type - $action');
      
      if (type == 'KNOB' && action == 'TRIPLE') {
        // 旋钮三击：进入油门模式
        _enterThrottleMode();
      } else if (type == 'KNOB' && action == 'LONG') {
        // 旋钮长按：打开设置
        _openSettings();
      }
    });
  }

  @override
  void dispose() {
    _buttonSub?.cancel();
    super.dispose();
  }
}
```

### 10.3 监听旋钮控制UI

```dart
class _RunningModeState extends State<RunningMode> {
  StreamSubscription<int>? _knobSub;
  int _speed = 0;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    // 监听旋钮增量
    _knobSub = btProvider.knobDeltaStream.listen((delta) {
      setState(() {
        // 每格旋钮增量对应5km/h
        _speed = (_speed + delta * 5).clamp(0, 340);
      });
      
      // 同步到硬件
      btProvider.setRunningSpeed(_speed);
      
      // 震动反馈
      HapticFeedback.selectionClick();
    });
  }

  @override
  void dispose() {
    _knobSub?.cancel();
    super.dispose();
  }
}
```

---

## 十一、协议汇总表

| 方向 | 命令/响应 | 格式 | 说明 |
|------|----------|------|------|
| APP→硬件 | 设置风扇 | `FAN:0-100\n` | 风扇速度百分比 |
| APP→硬件 | 查询风扇 | `GET:FAN\n` | 查询当前速度 |
| APP→硬件 | 设置雾化器 | `WUHUA:0/1\n` | 0=关闭, 1=开启 |
| APP→硬件 | 查询雾化器 | `GET:WUHUA\n` | 查询当前状态 |
| APP→硬件 | 设置LED | `LED:strip:r:g:b\n` | strip=1-4 |
| APP→硬件 | 查询所有 | `GET:ALL\n` | 查询所有状态 |
| 硬件→APP | 风扇状态 | `FAN:50\r\n` | 当前速度 |
| 硬件→APP | 雾化器状态 | `WUHUA:0/1\r\n` | 当前状态 |
| 硬件→APP | 所有状态 | `STATUS:FAN:50:WUHUA:1:BRIGHT:80\r\n` | 批量状态 |
| 硬件→APP | 旋钮增量 | `KNOB:delta\n` | 正=顺时针 |
| 硬件→APP | 按钮事件 | `BTN:type:action\n` | CLICK/LONG/TRIPLE |
| 硬件→APP | 传感器 | `SENSOR:type:value\n` | TEMP/BAT等 |

---

**文档完成时间**: 2026-01-07
**状态**: ✅ APP端和硬件端代码均已实现

---

## 十二、已完成的硬件端修改

### 修改文件

#### 1. `Core/Inc/rx.h`
- 新增 `BLE_SendString()` 函数声明
- 新增 `BLE_ReportKnobDelta()` 函数声明
- 新增 `BLE_ReportButtonEvent()` 函数声明

#### 2. `Core/Src/rx.c`
- 新增 `GET:xxx` 查询命令处理（GET:FAN, GET:WUHUA, GET:BRIGHT, GET:ALL, GET:UI）
- 新增 `BLE_SendString()` 蓝牙发送函数
- 新增 `BLE_ReportKnobDelta()` 旋钮增量上报函数
- 新增 `BLE_ReportButtonEvent()` 按钮事件上报函数

#### 3. `Core/Src/xuanniu.c`
- 在 `Encoder()` 函数中添加旋钮增量上报
- 在单击、双击、三击检测中添加按钮事件上报
- 添加 `#include "rx.h"` 引用
