---
inclusion: manual
---

# 22. 低功耗设计

## 是什么

通过硬件和软件协同，让设备在不活跃时大幅降低功耗，延长电池寿命或减少发热。包括睡眠模式管理、外设按需开关、时钟动态调频。

## 为什么需要

- 便携设备靠电池供电，功耗直接决定续航
- 即使 USB 供电，高功耗 = 高发热 = 元器件寿命缩短
- 用户体验：设备不用时应该"安静"，不该持续发热/耗电
- 产品差异化：同类产品续航长 = 竞争力

## 技术架构

```
┌────────────────────────────────────────────┐
│           ESP32-S3 功耗状态机               │
├────────────────────────────────────────────┤
│                                            │
│  Active (240MHz, ~80mA)                    │
│    │                                       │
│    │ 无操作 30s                            │
│    ▼                                       │
│  Light Sleep (~2mA)                        │
│    │ BLE 保持连接(sniff interval)          │
│    │ GPIO/Timer 可唤醒                     │
│    ▼                                       │
│  Deep Sleep (~10μA)                        │
│    │ 仅 RTC 域存活                         │
│    │ 按键/定时器唤醒 → 重启               │
│                                            │
│  外设功耗管理：                             │
│    LCD 背光 → PWM 调光 / 关闭             │
│    LED 灯带 → 全灭 / 降亮度              │
│    喇叭放大器 → EN 脚拉低                 │
│    风扇 → PWM=0                           │
│    雾化器 → GPIO 拉低                     │
└────────────────────────────────────────────┘
```

## 技术栈选型

| 组件 | 技术 | 说明 |
|------|------|------|
| 睡眠管理 | `esp_sleep` API | Light/Deep Sleep 切换 |
| 电源域控制 | `esp_pm` 动态调频 | CPU 频率随负载调整 |
| 唤醒源 | GPIO / Timer / BLE | 多种唤醒方式组合 |
| 外设电源 | GPIO 控制 EN 脚 | 硬件级断电 |
| BLE 低功耗 | Connection Interval 调整 | 不活跃时拉长间隔 |
| 功耗测量 | INA219 电流传感器 / Nordic PPK2 | 开发阶段量化验证 |

## 实现步骤

### Phase 1：外设按需开关（2h）

1. **建立外设电源管理表**
   ```c
   typedef struct {
       const char *name;
       gpio_num_t en_pin;    // 使能脚（-1 表示无硬件开关）
       bool is_on;
       void (*shutdown)(void);
       void (*wakeup)(void);
   } peripheral_power_t;
   ```

2. **实现各外设的休眠/唤醒**
   - LCD：背光 PWM→0，发送 Sleep In 命令（ST7789 0x10）
   - LED：全灭（`memset(0)` + `rmt_transmit`）
   - 喇叭：`drv_audio_stop()` + 放大器 EN 拉低
   - 风扇/雾化器：PWM=0 / GPIO=0

### Phase 2：Light Sleep 集成（2-3h）

3. **动态调频配置**
   ```c
   esp_pm_config_t pm_config = {
       .max_freq_mhz = 240,
       .min_freq_mhz = 80,
       .light_sleep_enable = true
   };
   esp_pm_configure(&pm_config);
   ```

4. **BLE + Light Sleep 共存**
   - 启用 `CONFIG_BT_CTRL_SLEEP_MODE_1`（Modem Sleep）
   - BLE Connection Interval：活跃时 15ms，空闲时 500ms
   - Light Sleep 期间 BLE 硬件自动唤醒收发

5. **唤醒源配置**
   ```c
   // 编码器按键唤醒
   esp_sleep_enable_gpio_wakeup();
   gpio_wakeup_enable(GPIO_ENCODER_BTN, GPIO_INTR_LOW_LEVEL);
   // BLE 事件唤醒（自动）
   ```

### Phase 3：Deep Sleep（1-2h）

6. **Deep Sleep 进入条件**
   - BLE 断开 + 无操作 5 分钟 → Deep Sleep
   - 唤醒：按键 GPIO（RTC GPIO）或定时器

7. **RTC 数据保持**
   ```c
   RTC_DATA_ATTR static uint8_t last_preset_index;  // Deep Sleep 后恢复
   RTC_DATA_ATTR static uint8_t last_brightness;
   ```

### Phase 4：功耗验证（1h）

8. **测量方法**
   - Nordic PPK2 串联电源线，实时采样电流
   - 记录各状态功耗：Active / Light Sleep / Deep Sleep
   - 目标：Light Sleep < 5mA，Deep Sleep < 50μA

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| Light Sleep 中断延迟 | 按键响应变慢 | 唤醒后立即切 240MHz |
| BLE 断连 | Sleep 参数不对导致超时 | 严格遵循 BLE spec 的 supervision timeout |
| LCD 唤醒闪屏 | Sleep Out 后需要等 120ms | 先恢复 RAM 再开背光 |
| GPIO 状态丢失 | Deep Sleep 后外设状态不确定 | 唤醒后完整初始化 |
| 电流毛刺 | WiFi/BLE 发射瞬间 300mA+ | 电源去耦电容要够大 |
| I2S DMA 冲突 | Light Sleep 中断 DMA 传输 | 音频播放时锁定 Active |

## 与 RideWind 的关系

- 当前状态：设备始终全速运行，所有外设常开
- 优先级：P4（产品稳定后优化）
- 场景：RideWind 通常 USB 供电，低功耗不是刚需，但减少发热有价值
- 快速收益：LCD 无操作 30s 关背光（最简单的省电）

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| 外设电源管理 | 2h | ⭐⭐ |
| Light Sleep + BLE | 2-3h | ⭐⭐⭐ |
| Deep Sleep + 唤醒 | 1-2h | ⭐⭐ |
| 功耗测量验证 | 1h | ⭐⭐ |
| **总计** | **~1.5 天** | |

## 学到什么

- MCU 电源域和时钟树架构
- 睡眠模式与外设的交互关系
- BLE 低功耗连接参数调优
- 功耗预算和测量方法
- 硬件设计对软件功耗优化的约束
