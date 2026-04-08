# 硬件端旋钮问题修复方案

## 问题根本原因

经过代码审查，发现**硬件端根本没有实现发送旋钮增量数据到APP的功能**！

### 当前硬件端实现

在 `f4_26_1.1/Core/Src/xuanniu.c` 中：

```c
int16_t Encoder_GetDelta(void) {
    // ... 读取旋钮增量
    int16_t delta = (int16_t)(current_cnt - last_encoder_cnt);
    // ... 处理增量
    return delta;  // ✅ 返回增量值
}

void Encoder() {
    // ... 周期调用
    if (ui == 1 && wuhuaqi_state != 2) {
        int16_t delta = Encoder_GetDelta();
        Num += delta;  // ✅ 只在本地使用增量，没有发送到APP
        if (Num > 100) Num = 100;
        if (Num < 0) Num = 0;
    }
    // ... 其他逻辑
}
```

**问题**：旋钮增量只在硬件端本地使用，**从未通过蓝牙发送给APP**！

### 为什么旋钮只能减小

用户反馈"旋钮不管怎么旋转只能减小"，可能的原因：

1. **硬件端旋钮方向配置错误**：`Encoder_GetDelta()` 返回的增量符号可能相反
2. **硬件端没有发送增量**：APP端无法知道旋钮的旋转
3. **APP端通过其他方式（如滑块）设置值后，硬件端的 `Num` 值被覆盖**

## 解决方案

### 方案1：硬件端发送旋钮增量到APP（推荐）

在 `xuanniu.c` 的 `Encoder()` 函数中，当检测到旋钮旋转时，通过蓝牙发送增量数据：

```c
void Encoder()
{
    // 周期控制（20ms一次）
    if (uwTick - encoder_process_tick < 20) {
        return;
    }
    encoder_process_tick = uwTick;

    // 获取旋钮增量
    int16_t delta = Encoder_GetDelta();
    
    // ✅ 新增：如果有旋转，发送增量到APP
    if (delta != 0) {
        // 发送格式: KNOB:delta\n
        printf("KNOB:%d\n", delta);
    }

    // 仅在界面1且非油门模式时调整Num值
    if (ui == 1 && wuhuaqi_state != 2) {
        Num += delta;
        if (Num > 100) Num = 100;
        if (Num < 0) Num = 0;
    }
    
    // ... 其他逻辑
}
```

**优点**：
- 简单直接，只需添加一行代码
- APP端可以根据当前界面决定如何使用增量
- 保持硬件端和APP端的独立性

**缺点**：
- 增加蓝牙通信频率（每次旋转都发送）

### 方案2：硬件端只在特定界面发送增量

如果担心通信频率过高，可以只在特定界面发送：

```c
void Encoder()
{
    // 周期控制（20ms一次）
    if (uwTick - encoder_process_tick < 20) {
        return;
    }
    encoder_process_tick = uwTick;

    // 获取旋钮增量
    int16_t delta = Encoder_GetDelta();
    
    // ✅ 只在特定界面发送增量到APP
    // ui=1: 调速界面
    // ui=2: 配色预设界面
    // ui=3: RGB调色界面
    // ui=4: 亮度调节界面
    if (delta != 0 && (ui == 1 || ui == 2 || ui == 3 || ui == 4)) {
        printf("KNOB:%d\n", delta);
    }

    // 本地处理
    if (ui == 1 && wuhuaqi_state != 2) {
        Num += delta;
        if (Num > 100) Num = 100;
        if (Num < 0) Num = 0;
    }
    
    // ... 其他逻辑
}
```

### 方案3：修复旋钮方向（如果方向相反）

如果旋钮方向相反（顺时针减小，逆时针增加），在 `Encoder_GetDelta()` 函数中取反：

```c
int16_t Encoder_GetDelta(void) {
    // ... 现有代码
    
    // 计算增量（有符号差值）
    int16_t delta = (int16_t)(current_cnt - last_encoder_cnt);
    
    // ... 防止溢出的代码
    
    // ✅ 如果方向相反，取反
    delta = -delta;  // 取消注释此行如果方向相反
    
    return delta;
}
```

## 完整修复代码

### 修改 `xuanniu.c` 文件

在 `Encoder()` 函数中添加蓝牙发送逻辑：

```c
void Encoder()
{
    // 周期控制（20ms一次）
    if (uwTick - encoder_process_tick < 20) {
        return;
    }
    encoder_process_tick = uwTick;

    // 获取旋钮增量
    int16_t delta = Encoder_GetDelta();
    
    // ✅✅✅ 核心修复：发送旋钮增量到APP ✅✅✅
    if (delta != 0) {
        // 发送格式: KNOB:delta\n
        // 例如: KNOB:5\n (顺时针5格) 或 KNOB:-3\n (逆时针3格)
        printf("KNOB:%d\n", delta);
    }

    // 仅在界面1且非油门模式时调整Num值
    if (ui == 1 && wuhuaqi_state != 2) {
        Num += delta;
        if (Num > 100) Num = 100;
        if (Num < 0) Num = 0;
    }
    
    // 读取按键状态
    uint8_t key_now = (HAL_GPIO_ReadPin(ENC_PORT, ENC_KEY_PIN) == 0) ? 1 : 0;
    
    // ... 其余代码保持不变
}
```

### 测试步骤

1. **编译并烧录固件**
2. **连接串口调试工具**（如PuTTY、SecureCRT）
3. **旋转旋钮**，观察串口输出：
   ```
   KNOB:5
   KNOB:3
   KNOB:-2
   KNOB:-4
   ```
4. **确认方向**：
   - 顺时针旋转应该输出正数
   - 逆时针旋转应该输出负数
   - 如果相反，在 `Encoder_GetDelta()` 中取反

5. **连接APP测试**：
   - 运行APP并连接设备
   - 旋转旋钮
   - 观察APP日志：`🎛️ 解析到旋钮增量: 5`
   - 确认界面数值正确变化

## 调试技巧

### 1. 确认旋钮硬件工作正常

在 `Encoder_GetDelta()` 函数中添加调试输出：

```c
int16_t Encoder_GetDelta(void) {
    // ... 现有代码
    
    int16_t delta = (int16_t)(current_cnt - last_encoder_cnt);
    
    // 调试输出
    if (delta != 0) {
        printf("[DEBUG] Encoder delta: %d, current_cnt: %u, last_cnt: %u\n", 
               delta, current_cnt, last_encoder_cnt);
    }
    
    // ... 其余代码
}
```

### 2. 确认蓝牙发送成功

在 `Encoder()` 函数中添加发送确认：

```c
if (delta != 0) {
    printf("KNOB:%d\n", delta);
    printf("[DEBUG] Sent KNOB command\n");
}
```

### 3. 使用蓝牙调试工具

使用nRF Connect或类似工具：
1. 连接设备
2. 订阅通知特征（0xFFE1）
3. 旋转旋钮
4. 查看接收到的数据：`KNOB:5\n`

## 常见问题

### Q1: 旋钮方向相反怎么办？

A: 在 `Encoder_GetDelta()` 函数末尾添加：

```c
delta = -delta;  // 取反
return delta;
```

### Q2: 旋钮增量过大或过小怎么办？

A: 调整 `Encoder_GetDelta()` 中的限幅值：

```c
// 当前限幅
if (delta > 3) delta = 3;
if (delta < -3) delta = -3;

// 如果需要更灵敏，增大限幅
if (delta > 5) delta = 5;
if (delta < -5) delta = -5;

// 如果需要更平滑，减小限幅
if (delta > 1) delta = 1;
if (delta < -1) delta = -1;
```

### Q3: 旋钮发送频率过高导致蓝牙拥堵怎么办？

A: 添加节流机制：

```c
static uint32_t last_knob_send_tick = 0;

void Encoder()
{
    // ... 现有代码
    
    int16_t delta = Encoder_GetDelta();
    
    // 节流：最多每50ms发送一次
    if (delta != 0 && (uwTick - last_knob_send_tick >= 50)) {
        printf("KNOB:%d\n", delta);
        last_knob_send_tick = uwTick;
    }
    
    // ... 其余代码
}
```

### Q4: 如何确认APP端正确接收？

A: 在APP端添加日志：

```dart
// 在 bluetooth_provider.dart 中
_knobSubscription = btProvider.knobDeltaStream.listen((delta) {
  debugPrint('🎛️ APP收到旋钮增量: $delta');
  // ... 其他代码
});
```

## 总结

**核心问题**：硬件端没有发送旋钮增量数据到APP

**解决方法**：在 `xuanniu.c` 的 `Encoder()` 函数中添加一行代码：

```c
if (delta != 0) {
    printf("KNOB:%d\n", delta);
}
```

**预期效果**：
- ✅ 旋钮顺时针旋转，数值增加
- ✅ 旋钮逆时针旋转，数值减少
- ✅ APP端实时响应旋钮操作
- ✅ 提供震动反馈

修复后，旋钮应该能够正常工作！
