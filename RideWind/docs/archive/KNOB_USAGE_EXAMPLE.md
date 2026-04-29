# 旋钮控制使用示例

## 快速集成指南

### 在现有界面中添加旋钮支持

只需3步即可在任何界面中添加旋钮控制：

#### 步骤1：添加订阅变量

```dart
class _YourWidgetState extends State<YourWidget> {
  StreamSubscription<int>? _knobSubscription;  // 添加这一行
  int _yourValue = 50;  // 你要控制的值
  
  // ... 其他代码
}
```

#### 步骤2：在initState中监听旋钮

```dart
@override
void initState() {
  super.initState();
  
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  
  // 监听旋钮增量
  _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
    setState(() {
      // 应用增量，限制范围
      _yourValue = (_yourValue + delta).clamp(0, 100);
    });
    
    // 发送到硬件（根据你的需求选择对应的方法）
    btProvider.setFanSpeed(_yourValue);  // 或其他控制方法
    
    // 震动反馈（可选）
    HapticFeedback.selectionClick();
  });
}
```

#### 步骤3：在dispose中取消订阅

```dart
@override
void dispose() {
  _knobSubscription?.cancel();  // 添加这一行
  super.dispose();
}
```

## 完整示例

### 示例1：在RGB调色界面中使用旋钮调节亮度

```dart
// 在 rgb_color_screen.dart 中
class _RgbColorScreenState extends State<RgbColorScreen> {
  double _brightness = 1.0;
  StreamSubscription<int>? _knobSubscription;

  @override
  void initState() {
    super.initState();
    
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    
    _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
      setState(() {
        // 每次旋转改变5%的亮度
        double change = delta * 0.05;
        _brightness = (_brightness + change).clamp(0.0, 1.0);
      });
      
      // 发送到硬件（0-100）
      int brightnessInt = (_brightness * 100).round();
      btProvider.setBrightness(brightnessInt);
      
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
    return Scaffold(
      body: Column(
        children: [
          Text('亮度: ${(_brightness * 100).toInt()}%'),
          Slider(
            value: _brightness,
            onChanged: (value) {
              setState(() => _brightness = value);
              btProvider.setBrightness((value * 100).round());
            },
          ),
        ],
      ),
    );
  }
}
```

### 示例2：在Running Mode中使用旋钮调节速度

```dart
// 在 running_mode_widget.dart 的 _RunningModeWidgetState 中添加

StreamSubscription<int>? _knobSubscription;

@override
void initState() {
  super.initState();
  _currentSpeed = widget.initialSpeed;
  _initAudio();
  
  // 添加旋钮监听
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
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
  _accelerationTimer?.cancel();
  _accelerationTimer = null;
  _stopEngineSound();
  _speedScrollController?.dispose();
  _enginePlayer.dispose();
  _knobSubscription?.cancel();  // 添加这一行
  
  if (_isAccelerating) {
    widget.onThrottleStatusChanged?.call(false);
  }
  
  super.dispose();
}
```

### 示例3：在Colorize Mode中使用旋钮切换预设

```dart
// 在 device_connect_screen.dart 的 _DeviceConnectScreenState 中添加

StreamSubscription<int>? _knobSubscription;

@override
void initState() {
  super.initState();
  
  // ... 其他初始化代码
  
  // 添加旋钮监听
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  _knobSubscription = btProvider.knobDeltaStream.listen((delta) {
    // 只在Colorize预设界面响应旋钮
    if (_modeActivated && 
        _currentMode == ControlMode.colorize && 
        _colorizeState == ColorizeState.preset) {
      
      setState(() {
        // 切换预设索引（0-7循环）
        _selectedColorIndex = (_selectedColorIndex + delta) % 8;
        if (_selectedColorIndex < 0) _selectedColorIndex += 8;
      });
      
      // 滚动到新位置
      if (_colorPageController.hasClients) {
        _colorPageController.animateToPage(
          _selectedColorIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      
      // 同步到硬件
      _syncPresetToHardware(_selectedColorIndex);
      
      HapticFeedback.selectionClick();
    }
  });
}

@override
void dispose() {
  _pageController.dispose();
  _colorPageController.dispose();
  _connectionSub?.cancel();
  _knobSubscription?.cancel();  // 添加这一行
  _stopCycleAnimation();
  super.dispose();
}
```

## 高级用法

### 1. 根据界面状态动态启用/禁用旋钮

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 根据不同的界面状态执行不同的操作
  if (_currentMode == ControlMode.running && _showSpeedControl) {
    // Running Mode: 调节速度
    _adjustSpeed(delta);
  } else if (_currentMode == ControlMode.colorize) {
    if (_colorizeState == ColorizeState.preset) {
      // Colorize预设: 切换预设
      _switchPreset(delta);
    } else if (_colorizeState == ColorizeState.rgbDetail) {
      // RGB详情: 调节亮度
      _adjustBrightness(delta);
    }
  }
});
```

### 2. 添加加速度支持（快速旋转时增量更大）

```dart
DateTime _lastKnobTime = DateTime.now();
int _knobAcceleration = 1;

_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  final now = DateTime.now();
  final timeDiff = now.difference(_lastKnobTime).inMilliseconds;
  
  // 如果旋转很快（<100ms），增加加速度
  if (timeDiff < 100) {
    _knobAcceleration = (_knobAcceleration + 1).clamp(1, 5);
  } else {
    _knobAcceleration = 1;
  }
  
  // 应用加速度
  int adjustedDelta = delta * _knobAcceleration;
  
  setState(() {
    _yourValue = (_yourValue + adjustedDelta).clamp(0, 100);
  });
  
  _lastKnobTime = now;
});
```

### 3. 添加防抖（避免频繁发送命令到硬件）

```dart
Timer? _knobDebounceTimer;

_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  setState(() {
    _yourValue = (_yourValue + delta).clamp(0, 100);
  });
  
  // 取消之前的定时器
  _knobDebounceTimer?.cancel();
  
  // 300ms后才发送到硬件
  _knobDebounceTimer = Timer(Duration(milliseconds: 300), () {
    btProvider.setFanSpeed(_yourValue);
  });
});

@override
void dispose() {
  _knobSubscription?.cancel();
  _knobDebounceTimer?.cancel();
  super.dispose();
}
```

## 调试技巧

### 1. 打印旋钮增量

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  debugPrint('🎛️ 旋钮增量: $delta');
  // ... 其他代码
});
```

### 2. 显示旋钮状态指示器

```dart
bool _knobActive = false;
Timer? _knobIndicatorTimer;

_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  setState(() {
    _knobActive = true;
    // ... 应用增量
  });
  
  // 500ms后隐藏指示器
  _knobIndicatorTimer?.cancel();
  _knobIndicatorTimer = Timer(Duration(milliseconds: 500), () {
    setState(() => _knobActive = false);
  });
});

// 在UI中显示
if (_knobActive)
  Positioned(
    top: 20,
    right: 20,
    child: Icon(Icons.rotate_right, color: Colors.green),
  ),
```

## 常见问题

### Q: 旋钮响应太灵敏怎么办？

A: 减小增量的影响：

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 将增量缩小到1/5
  delta = (delta / 5).round();
  // 或者只取符号
  delta = delta.sign;
  
  setState(() {
    _yourValue = (_yourValue + delta).clamp(0, 100);
  });
});
```

### Q: 旋钮响应太慢怎么办？

A: 增大增量的影响：

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 将增量放大5倍
  delta = delta * 5;
  
  setState(() {
    _yourValue = (_yourValue + delta).clamp(0, 100);
  });
});
```

### Q: 如何让旋钮只在特定界面工作？

A: 使用条件判断：

```dart
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  // 只在特定条件下响应
  if (!_isMyScreenActive) return;
  
  setState(() {
    _yourValue = (_yourValue + delta).clamp(0, 100);
  });
});
```

## 总结

旋钮控制的核心就是：
1. 监听 `btProvider.knobDeltaStream`
2. 应用增量到你的值
3. 更新UI和硬件
4. 记得在dispose中取消订阅

就这么简单！
