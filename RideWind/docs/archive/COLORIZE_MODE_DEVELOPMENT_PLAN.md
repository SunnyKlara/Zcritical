# Colorize Mode LED 灯光控制 - 严谨开发方案

## 🎯 **开发目标**
实现 App 通过蓝牙远程控制 STM32 硬件的 WS2812B RGB LED 灯带颜色变化

---

## 📋 **Step 1: 硬件端分析（已完成）**

### **1.1 硬件配置**
```c
// LED 灯带配置
#define LED1_COUNT 30  // 灯带1：30个LED
#define LED2_COUNT 30  // 灯带2：30个LED

// GPIO 引脚
- PC11: LED1 数据线（灯带1）
- PA12: LED2 数据线（灯带2）
```

### **1.2 LED 分组映射**
根据 `ws2812.c` 中的代码分析：

```c
// 灯带分组（strip_num 参数）
strip_num = 1: LED1 灯带，索引 3-8  (6个LED) - 对应 App 的 "M" (Middle)
strip_num = 2: LED1 灯带，索引 0-2  (3个LED) - 对应 App 的 "L" (Left)
strip_num = 3: LED1 灯带，索引 9-11 (3个LED) - 对应 App 的 "R" (Right)
strip_num = 4: LED2 灯带，索引 0-2  (3个LED) - 对应 App 的 "B" (Bottom)
```

### **1.3 硬件端已有函数**
```c
// 设置所有LED颜色（3个LED）
void WS2812B_SetAllLEDs(uint8_t strip_num, uint8_t r, uint8_t g, uint8_t b);

// 设置2+3组LED颜色（6个LED）
void WS2812B_Set23LEDs(uint8_t strip_num, uint8_t r, uint8_t g, uint8_t b);

// 更新显示
void WS2812B_Update(uint8_t strip_num);
```

### **1.4 调用流程**
```c
// 示例：设置 strip_num=1 (M位置) 为红色
WS2812B_SetAllLEDs(1, 255, 0, 0);  // 设置颜色到缓冲区
WS2812B_Update(1);                  // 更新显示
```

---

## 📋 **Step 2: App 端现状分析**

### **2.1 UI 界面已实现**
```dart
// Colorize Mode 界面组件
- 4个灯光位置选择按钮：L, M, R, B
- 循环速度滑动条（0-1）
- 颜色选择器（色环）
- RGB 设置界面
```

### **2.2 状态变量**
```dart
String _selectedLightPosition = 'B';  // 当前选中位置：L/M/R/B
double _loopSpeed = 0.5;              // 循环速度：0-1
int _selectedColorIndex = 0;          // 当前选中颜色索引
```

### **2.3 缺失的功能**
- ❌ **蓝牙协议定义** - LED 控制命令格式未定义
- ❌ **协议实现** - ProtocolService 中无 LED 控制方法
- ❌ **UI 回调连接** - 颜色选择后未发送蓝牙命令
- ❌ **位置映射** - App 的 L/M/R/B 未映射到硬件的 strip_num

---

## 📋 **Step 3: 蓝牙协议设计**

### **3.1 协议格式定义**

#### **命令1: 设置LED颜色**
```
格式: LED:strip:r:g:b\n
参数:
  - strip: 灯带编号 (1-4)
    1 = M (Middle)
    2 = L (Left)
    3 = R (Right)
    4 = B (Bottom)
  - r: 红色值 (0-255)
  - g: 绿色值 (0-255)
  - b: 蓝色值 (0-255)

示例:
  LED:1:255:0:0\n    // 设置M位置为红色
  LED:2:0:255:0\n    // 设置L位置为绿色
  LED:3:0:0:255\n    // 设置R位置为蓝色
  LED:4:255:255:0\n  // 设置B位置为黄色

响应:
  OK:LED:strip\r\n   // 成功
  ERR:message\r\n    // 失败
```

#### **命令2: 查询LED状态**（可选）
```
格式: GET:LED:strip\n
参数:
  - strip: 灯带编号 (1-4)

示例:
  GET:LED:1\n

响应:
  LED:1:255:0:0\r\n  // 返回当前颜色
```

#### **命令3: 设置亮度**（可选，后续扩展）
```
格式: BRIGHT:value\n
参数:
  - value: 亮度值 (0-100)

示例:
  BRIGHT:50\n

响应:
  OK:BRIGHT:50\r\n
```

---

## 📋 **Step 4: 硬件端协议实现**

### **4.1 修改 `protocol.h`**
```c
/* LED控制命令 */
void CMD_SetLEDColor(uint8_t strip, uint8_t r, uint8_t g, uint8_t b);
void CMD_GetLEDColor(uint8_t strip);
void CMD_SetBrightness(uint8_t brightness);
```

### **4.2 修改 `protocol.c`**

#### **添加全局变量**
```c
// LED颜色状态存储（用于查询）
typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} LED_ColorState;

static LED_ColorState led_states[4] = {
    {0, 0, 0},  // strip 1 (M)
    {0, 0, 0},  // strip 2 (L)
    {0, 0, 0},  // strip 3 (R)
    {0, 0, 0},  // strip 4 (B)
};

static uint8_t led_brightness = 100;  // 默认亮度100%
```

#### **添加协议解析**
```c
void Protocol_Process(char* cmd) {
    // ... 现有代码 ...
    
    // LED:strip:r:g:b 命令
    else if(strncmp(cmd, "LED:", 4) == 0) {
        int strip, r, g, b;
        if(sscanf(cmd + 4, "%d:%d:%d:%d", &strip, &r, &g, &b) == 4) {
            if(strip >= 1 && strip <= 4 && 
               r >= 0 && r <= 255 && 
               g >= 0 && g <= 255 && 
               b <= 255) {
                CMD_SetLEDColor((uint8_t)strip, (uint8_t)r, (uint8_t)g, (uint8_t)b);
            } else {
                BLE_SendString("ERR:LED parameters out of range\r\n");
            }
        } else {
            BLE_SendString("ERR:LED command format error\r\n");
        }
    }
    
    // GET:LED:strip 命令
    else if(strncmp(cmd, "GET:LED:", 8) == 0) {
        int strip = atoi(cmd + 8);
        if(strip >= 1 && strip <= 4) {
            CMD_GetLEDColor((uint8_t)strip);
        } else {
            BLE_SendString("ERR:Invalid strip number\r\n");
        }
    }
    
    // BRIGHT:value 命令
    else if(strncmp(cmd, "BRIGHT:", 7) == 0) {
        int brightness = atoi(cmd + 7);
        if(brightness >= 0 && brightness <= 100) {
            CMD_SetBrightness((uint8_t)brightness);
        } else {
            BLE_SendString("ERR:Brightness out of range (0-100)\r\n");
        }
    }
}
```

#### **实现命令函数**
```c
/**
 * @brief 设置LED颜色
 * @param strip 灯带编号 (1-4)
 * @param r 红色值 (0-255)
 * @param g 绿色值 (0-255)
 * @param b 蓝色值 (0-255)
 */
void CMD_SetLEDColor(uint8_t strip, uint8_t r, uint8_t g, uint8_t b) {
    // 应用亮度调整
    uint8_t adj_r = (r * led_brightness) / 100;
    uint8_t adj_g = (g * led_brightness) / 100;
    uint8_t adj_b = (b * led_brightness) / 100;
    
    // 设置LED颜色
    WS2812B_SetAllLEDs(strip, adj_r, adj_g, adj_b);
    
    // 更新显示
    WS2812B_Update(strip);
    
    // 保存状态
    led_states[strip - 1].r = r;
    led_states[strip - 1].g = g;
    led_states[strip - 1].b = b;
    
    // 发送确认响应
    char response[32];
    sprintf(response, "OK:LED:%d\r\n", strip);
    BLE_SendString(response);
    
    debugPrint("💡 LED Strip %d: R=%d, G=%d, B=%d", strip, r, g, b);
}

/**
 * @brief 查询LED颜色
 * @param strip 灯带编号 (1-4)
 */
void CMD_GetLEDColor(uint8_t strip) {
    char response[64];
    LED_ColorState* state = &led_states[strip - 1];
    sprintf(response, "LED:%d:%d:%d:%d\r\n", strip, state->r, state->g, state->b);
    BLE_SendString(response);
}

/**
 * @brief 设置亮度
 * @param brightness 亮度值 (0-100)
 */
void CMD_SetBrightness(uint8_t brightness) {
    led_brightness = brightness;
    
    // 重新应用所有LED的颜色（使用新亮度）
    for(uint8_t i = 1; i <= 4; i++) {
        LED_ColorState* state = &led_states[i - 1];
        if(state->r != 0 || state->g != 0 || state->b != 0) {
            CMD_SetLEDColor(i, state->r, state->g, state->b);
        }
    }
    
    // 发送确认响应
    char response[32];
    sprintf(response, "OK:BRIGHT:%d\r\n", brightness);
    BLE_SendString(response);
}
```

---

## 📋 **Step 5: App 端协议实现**

### **5.1 修改 `ProtocolService`**

#### **添加 LED 控制方法**
```dart
/// 设置LED颜色
/// [strip] 灯带编号 (1-4)
/// [r] 红色值 (0-255)
/// [g] 绿色值 (0-255)
/// [b] 蓝色值 (0-255)
/// 返回: true=发送成功, false=发送失败
Future<bool> setLEDColor(int strip, int r, int g, int b) async {
  // 参数校验
  if (strip < 1 || strip > 4) {
    print('❌ 灯带编号超出范围: $strip (应为1-4)');
    return false;
  }
  if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
    print('❌ RGB值超出范围: R=$r, G=$g, B=$b (应为0-255)');
    return false;
  }

  // 构造命令: LED:strip:r:g:b\n
  String command = 'LED:$strip:$r:$g:$b\n';
  print('📤 发送LED命令: ${command.trim()}');

  try {
    await bleService.sendString(command);
    return true;
  } catch (e) {
    print('❌ 发送失败: $e');
    return false;
  }
}

/// 查询LED颜色
Future<bool> getLEDColor(int strip) async {
  if (strip < 1 || strip > 4) {
    print('❌ 灯带编号超出范围: $strip');
    return false;
  }

  String command = 'GET:LED:$strip\n';
  print('📤 发送查询命令: ${command.trim()}');

  try {
    await bleService.sendString(command);
    return true;
  } catch (e) {
    print('❌ 发送失败: $e');
    return false;
  }
}

/// 设置亮度
Future<bool> setBrightness(int brightness) async {
  if (brightness < 0 || brightness > 100) {
    print('❌ 亮度超出范围: $brightness (应为0-100)');
    return false;
  }

  String command = 'BRIGHT:$brightness\n';
  print('📤 发送亮度命令: ${command.trim()}');

  try {
    await bleService.sendString(command);
    return true;
  } catch (e) {
    print('❌ 发送失败: $e');
    return false;
  }
}

/// 解析LED响应
Map<String, int>? parseLEDResponse(String response) {
  // 格式: LED:strip:r:g:b
  if (response.startsWith('LED:')) {
    final parts = response.substring(4).split(':');
    if (parts.length == 4) {
      return {
        'strip': int.tryParse(parts[0]) ?? 0,
        'r': int.tryParse(parts[1]) ?? 0,
        'g': int.tryParse(parts[2]) ?? 0,
        'b': int.tryParse(parts[3]) ?? 0,
      };
    }
  }
  return null;
}
```

### **5.2 修改 `BluetoothProvider`**

#### **添加 LED 控制方法**
```dart
/// 设置LED颜色
Future<bool> setLEDColor(int strip, int r, int g, int b) async {
  if (!isConnected) {
    debugPrint('❌ 蓝牙未连接');
    return false;
  }
  
  return await _protocolService.setLEDColor(strip, r, g, b);
}

/// 设置亮度
Future<bool> setBrightness(int brightness) async {
  if (!isConnected) {
    debugPrint('❌ 蓝牙未连接');
    return false;
  }
  
  return await _protocolService.setBrightness(brightness);
}
```

---

## 📋 **Step 6: UI 回调连接**

### **6.1 位置映射**
```dart
// App 位置 → 硬件 strip_num 映射
Map<String, int> _positionToStrip = {
  'L': 2,  // Left
  'M': 1,  // Middle
  'R': 3,  // Right
  'B': 4,  // Bottom
};
```

### **6.2 颜色选择回调**
```dart
// 在 device_connect_screen.dart 中
// 当用户选择颜色时
void _onColorSelected(Color color) async {
  // 提取RGB值
  int r = color.red;
  int g = color.green;
  int b = color.blue;
  
  // 获取当前选中的位置
  int strip = _positionToStrip[_selectedLightPosition] ?? 1;
  
  debugPrint('🎨 Colorize Mode: 位置=$_selectedLightPosition (strip=$strip), RGB=($r,$g,$b)');
  
  // 发送蓝牙命令
  final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
  bool success = await btProvider.setLEDColor(strip, r, g, b);
  
  if (success) {
    debugPrint('✅ LED颜色命令发送成功');
  } else {
    debugPrint('❌ LED颜色命令发送失败');
  }
}
```

---

## 📋 **Step 7: 开发步骤规划**

### **阶段1: 硬件端协议实现** ✅
1. 修改 `protocol.h` 添加函数声明
2. 修改 `protocol.c` 添加协议解析
3. 实现 `CMD_SetLEDColor()` 函数
4. 实现 `CMD_GetLEDColor()` 函数
5. 实现 `CMD_SetBrightness()` 函数
6. 编译测试硬件代码

### **阶段2: App 端协议实现** ✅
1. 修改 `ProtocolService` 添加 LED 控制方法
2. 修改 `BluetoothProvider` 添加封装方法
3. 添加位置映射逻辑
4. 测试协议方法

### **阶段3: UI 回调连接** ✅
1. 找到颜色选择的回调位置
2. 添加蓝牙命令发送逻辑
3. 添加调试日志
4. 测试UI交互

### **阶段4: 完整测试** ✅
1. 测试单个位置颜色控制
2. 测试所有位置切换
3. 测试颜色变化响应
4. 测试亮度调节（可选）

---

## 📊 **预期效果**

### **用户操作流程**：
1. 进入 Colorize Mode
2. 点击选择位置（L/M/R/B）
3. 选择颜色（色环或RGB滑块）
4. 硬件LED立即变色

### **技术流程**：
```
UI选择颜色
    ↓
提取RGB值
    ↓
映射位置到strip_num
    ↓
BluetoothProvider.setLEDColor(strip, r, g, b)
    ↓
ProtocolService.setLEDColor(strip, r, g, b)
    ↓
BLEService.sendString("LED:strip:r:g:b\n")
    ↓
JDY-08 蓝牙模块
    ↓
STM32 UART2 接收
    ↓
Protocol_Process("LED:strip:r:g:b")
    ↓
CMD_SetLEDColor(strip, r, g, b)
    ↓
WS2812B_SetAllLEDs(strip, r, g, b)
    ↓
WS2812B_Update(strip)
    ↓
LED灯带变色 ✅
```

---

## ⚠️ **注意事项**

### **1. 硬件限制**
- WS2812B 需要精确时序，中断会被关闭
- 更新LED时会有短暂的阻塞
- 建议控制发送频率，避免过于频繁

### **2. 协议安全**
- 参数范围严格校验
- 错误处理完善
- 响应格式统一

### **3. 用户体验**
- 颜色变化应该实时响应
- 添加适当的震动反馈
- 提供视觉反馈

---

## 🎯 **下一步行动**

**建议顺序**：
1. **先实现硬件端协议** - 修改 `protocol.c` 和 `protocol.h`
2. **编译测试硬件** - 确保编译通过
3. **实现 App 端协议** - 修改 `ProtocolService`
4. **连接 UI 回调** - 在 `device_connect_screen.dart` 中添加逻辑
5. **完整测试** - 验证端到端功能

**要不要我现在开始实现第一步：硬件端协议代码？** 🚀
