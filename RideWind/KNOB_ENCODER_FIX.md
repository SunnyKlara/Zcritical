# 旋钮增量控制修复方案

## 问题描述

用户反馈：旋钮不管怎么旋转只能减小，转速从零怎么转都是零，亮度从100怎么转最后都减小为0。

## 根本原因

1. **硬件端**：旋转编码器（TIM1）正在发送旋钮的增量数据
2. **APP端**：没有监听和处理硬件发送的旋钮增量数据
3. **结果**：旋钮数据被忽略，或者增量符号处理错误

## 解决方案

### 1. 协议定义

硬件端应该发送以下格式的旋钮增量数据：

```
KNOB:5\n        // 顺时针旋转5个刻度
KNOB:-3\n       // 逆时针旋转3个刻度
```

或者：

```
ENCODER:5\n     // 顺时针旋转5个刻度
ENCODER:-3\n    // 逆时针旋转3个刻度
```

### 2. APP端修改

已在以下文件中添加旋钮增量处理：

#### `lib/services/protocol_service.dart`

添加了 `parseKnobDelta()` 方法来解析旋钮增量数据：

```dart
/// 解析旋钮增量数据
///
/// 响应格式: KNOB:delta 或 ENCODER:delta
/// delta: 正数=顺时针旋转，负数=逆时针旋转
///
/// 返回: 增量值，null=解析失败
int? parseKnobDelta(String response) {
  response = response.trim();

  // 匹配 KNOB:数字 或 ENCODER:数字（支持负数）
  RegExp knobRegex = RegExp(r'(?:KNOB|ENCODER):(-?\d+)');
  Match? match = knobRegex.firstMatch(response);

  if (match != null) {
    int delta = int.parse(match.group(1)!);
    print('🎛️ 解析到旋钮增量: $delta');
    return delta;
  }

  return null;
}
```

#### `lib/providers/bluetooth_provider.dart`

1. 添加了旋钮增量流控制器：

```dart
// 🎛️ 旋钮增量流控制器
final StreamController<int> _knobDeltaController =
    StreamController<int>.broadcast();

// 🎛️ 旋钮增量流getter
Stream<int> get knobDeltaStream => _knobDeltaController.stream;
```

2. 在响应监听中添加旋钮增量解析：

```dart
// 🎛️ 解析旋钮增量数据
int? knobDelta = _protocolService.parseKnobDelta(response);
if (knobDelta != null) {
  _knobDeltaController.add(knobDelta);
}
```

### 3. UI界面使用示例

在需要响应旋钮的界面中，监听旋钮增量流：

#### 示例1：调节风扇速度

```dart
class FanControlWidget extends StatefulWidget {
  @override
  State<FanControlWidget> createState() => _FanControlWidgetState();
}

class _FanControlWidgetState extends State<FanControlWidget> {
  int _fanSpeed = 50;
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    // 监听旋钮增量
    _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
      setState(() {
        // 应用增量，限制范围0-100
        _fanSpeed = (_fanSpeed + delta).clamp(0, 100);
      });
      
      // 发送新的速度到硬件
      btProvider.setFanSpeed(_fanSpeed);
      
      // 震动反馈
      HapticFeedback.selectionClick();
    });
  }

  @override
  void dispose() {
    _knobSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('风扇速度: $_fanSpeed%'),
        Slider(
          value: _fanSpeed.toDouble(),
          min: 0,
          max: 100,
          onChanged: (value) {
            setState(() => _fanSpeed = value.toInt());
            btProvider.setFanSpeed(_fanSpeed);
          },
        ),
      ],
    );
  }
}
```

#### 示例2：调节亮度

```dart
class BrightnessControlWidget extends StatefulWidget {
  @override
  State<BrightnessControlWidget> createState() => _BrightnessControlWidgetState();
}

class _BrightnessControlWidgetState extends State<BrightnessControlWidget> {
  int _brightness = 100;
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    // 监听旋钮增量
    _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
      setState(() {
        // 应用增量，限制范围0-100
        _brightness = (_brightness + delta).clamp(0, 100);
      });
      
      // 发送新的亮度到硬件
      btProvider.setBrightness(_brightness);
      
      // 震动反馈
      HapticFeedback.selectionClick();
    });
  }

  @override
  void dispose() {
    _knobSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('亮度: $_brightness%'),
        Slider(
          value: _brightness.toDouble(),
          min: 0,
          max: 100,
          onChanged: (value) {
            setState(() => _brightness = value.toInt());
            btProvider.setBrightness(_brightness);
          },
        ),
      ],
    );
  }
}
```

#### 示例3：调节Running Mode速度

```dart
// 在 running_mode_widget.dart 中添加旋钮监听
class _RunningModeWidgetState extends State<RunningModeWidget> {
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    // 监听旋钮增量
    _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
      // 只在显示调速界面时响应旋钮
      if (_showSpeedControl) {
        setState(() {
          // 应用增量，限制范围0-maxSpeed
          _currentSpeed = (_currentSpeed + delta).clamp(0, widget.maxSpeed);
        });
        
        // 滚动到新位置
        if (_speedScrollController != null && _speedScrollController!.hasClients) {
          _speedScrollController!.animateToItem(
            _currentSpeed,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
        
        // 通知外部
        widget.onSpeedChanged(_currentSpeed);
        
        // 震动反馈
        HapticFeedback.selectionClick();
      }
    });
  }

  @override
  void dispose() {
    _knobSubscription?.cancel();
    super.dispose();
  }
}
```

## 硬件端需要确认的事项

### 1. 旋钮数据格式

请确认硬件端发送的旋钮数据格式：

- [ ] 使用 `KNOB:delta\n` 格式
- [ ] 使用 `ENCODER:delta\n` 格式
- [ ] 使用其他格式（请说明）

### 2. 增量符号

请确认增量的符号定义：

- [ ] 正数 = 顺时针旋转（增加）
- [ ] 负数 = 逆时针旋转（减少）
- [ ] 相反（需要修改APP端代码）

### 3. 增量大小

请确认每次旋转发送的增量值：

- [ ] 每个刻度 = 1
- [ ] 每个刻度 = 5
- [ ] 其他值（请说明）

### 4. 发送频率

请确认旋钮数据的发送频率：

- [ ] 每次旋转立即发送
- [ ] 累积后定时发送
- [ ] 其他方式（请说明）

## 测试步骤

### 1. 硬件端测试

在硬件端添加调试输出，确认旋钮数据正确发送：

```c
// 在旋钮中断或处理函数中添加
printf("KNOB:%d\n", delta);  // 或 printf("ENCODER:%d\n", delta);
```

### 2. APP端测试

1. 运行APP并连接设备
2. 进入任意需要旋钮控制的界面
3. 旋转旋钮，观察日志输出：

```
🎛️ 解析到旋钮增量: 5
🎛️ 解析到旋钮增量: -3
```

4. 确认界面数值正确变化

### 3. 调试工具

如果旋钮仍然不工作，可以使用蓝牙调试工具（如nRF Connect）查看硬件实际发送的数据：

1. 连接设备
2. 订阅通知特征（0xFFE1）
3. 旋转旋钮
4. 查看接收到的原始数据

## 常见问题

### Q1: 旋钮只能减小，不能增加

**可能原因**：
- 硬件端增量符号错误（总是发送负数）
- APP端增量符号处理相反

**解决方法**：
1. 检查硬件端旋钮增量计算逻辑
2. 如果硬件端符号相反，在APP端取反：

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 如果硬件符号相反，取反
  delta = -delta;
  
  setState(() {
    _currentSpeed = (_currentSpeed + delta).clamp(0, widget.maxSpeed);
  });
});
```

### Q2: 旋钮增量过大或过小

**可能原因**：
- 硬件端发送的增量值不合适
- 需要调整增量的缩放比例

**解决方法**：
在APP端调整增量缩放：

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 调整增量大小（例如缩小到1/5）
  delta = (delta / 5).round();
  
  setState(() {
    _currentSpeed = (_currentSpeed + delta).clamp(0, widget.maxSpeed);
  });
});
```

### Q3: 旋钮响应延迟

**可能原因**：
- 硬件端发送频率过低
- 蓝牙通信延迟

**解决方法**：
1. 增加硬件端发送频率
2. 在APP端添加本地预测（立即更新UI，后台同步硬件）

## 总结

修复后，旋钮应该能够：
- ✅ 顺时针旋转增加数值
- ✅ 逆时针旋转减少数值
- ✅ 在任何界面正确响应
- ✅ 提供震动反馈
- ✅ 实时同步到硬件

如果问题仍然存在，请提供：
1. 硬件端旋钮相关代码
2. APP端日志输出
3. 蓝牙调试工具抓取的原始数据
