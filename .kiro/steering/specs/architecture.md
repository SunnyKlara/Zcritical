---
inclusion: fileMatch
fileMatchPattern: "ridewind-esp/**/*.c,ridewind-esp/**/*.h"
---

<!-- last-verified: 2026-05-12 | verified-by: deep code read of all source files -->

# Critical T1 固件架构 — 全景文档

> 本文档是固件架构的权威描述。新 AI 读完本文件应能理解：
> 代码为什么这样组织、数据怎么流动、哪些边界不可逾越、哪些是有意的妥协。

## 一、架构全景

```
┌─────────────────────────────────────────────────────────────────┐
│                        app_main() 初始化                         │
│  NVS → AppState → Storage → LCD → LED → Encoder → PWM/GPIO     │
│  → Audio → WiFi → BLE → Effects → UI → main_task               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────── Core 0 ──────────────────┐  ┌──── Core 1 ────────────────────┐
│  Bluedroid (BLE GATTS + GAP)                 │  │  main_task (pri 5, 20ms loop)  │
│  WiFi STA + tcp_audio (pri 4)               │  │    ├─ drain cmd_queue           │
│                                              │  │    ├─ ui_manager_update()       │
│  BLE write → reassemble → parse → queue ──────→│    ├─ led_effects_process()     │
│  TCP recv → ring buffer ─────────────────────→│    └─ vTaskDelay(20ms)           │
│                                              │  │                                 │
│                                              │  │  audio_out (pri 6, lazy start)  │
│                                              │  │    └─ ringbuf → vol → I2S       │
│                                              │  │                                 │
│                                              │  │  eng_synth (pri 6, dynamic)     │
│                                              │  │    └─ 4-layer blend → I2S       │
└──────────────────────────────────────────────┘  └─────────────────────────────────┘
```

## 二、四层分离与依赖规则

| 层 | 目录 | 职责 | 可以调用 | 禁止调用 |
|----|------|------|---------|---------|
| UI | ui/ | 状态机 + LCD 渲染 | drivers/, app/, services/ble_service | — |
| APP | app/ | 全局状态 + 灯效引擎 | drivers/drv_led | services/, ui/ |
| Services | services/ | BLE、协议、WiFi、音频、存储 | drivers/drv_audio, ESP-IDF 网络/蓝牙 | ui/, app/ |
| Drivers | drivers/ | 纯硬件抽象 | ESP-IDF 外设 API only | services/, app/, ui/ |

### 有意的妥协（不是 bug，不要"修复"）

| 现象 | 原因 |
|------|------|
| ui_speed.c 直接调用 drv_pwm/drv_gpio | 单任务架构，UI 在 main_task 内运行，无竞态。多一层间接调用无意义 |
| ui_rgb/preset/bright 直接调用 drv_led | 同上。LED 调色需要实时反馈 |
| ble_service.c 用 Bluedroid API | 它本身就是 BLE 抽象层 |
| wifi_audio_service.c 用 esp_wifi API | 它本身就是 WiFi 抽象层 |

## 三、状态管理

### AppState — 唯一可变状态源

```c
extern app_state_t       g_app_state;      // 全局唯一实例
extern SemaphoreHandle_t g_app_state_mutex; // FreeRTOS 互斥锁
```

**写入规则：**
- main_task 是唯一写入者（通过 dispatch_ble_command 或 ui_xxx_update）
- BLE 回调（Core 0）通过 cmd_queue 发消息，绝不直接写 AppState
- UI 层直接读写（因为运行在 main_task 内）

**NVS 持久化策略：**
- 只在用户显式保存时写入（双击退出 UI）
- 启动时一次性加载到 AppState
- 不在每次值变化时写入（避免 Flash 磨损）

## 四、核心数据流

### BLE 命令 → 硬件

```
APP "FAN:50\n" → BLE write (Core 0) → 缓冲到 '\n' → protocol_parse()
  → cmd_queue → main_task (Core 1) → dispatch_ble_command()
  → LOCK → g_app_state.fan_speed=50 → drv_pwm_set_duty(50) → UNLOCK
  → "OK:FAN:50\r\n" notify
```

### 编码器 → BLE 上报

```
旋钮转动 → main_task 20ms → ui_speed_update() → drv_encoder_poll()
  → g_app_state.current_speed_kmh++ → drv_pwm_set_duty()
  → audio_player_set_target_rpm() → "SPEED_REPORT:34:0\n" notify
  → draw_speed_screen() [只重绘变化区域]
```

### 音频互斥

```
引擎声启动: audio_engine_pause() → eng_synth 任务创建 → I2S 独占
引擎声停止: eng_synth 自删除 → audio_engine_resume() → WiFi 音频恢复
```

两个音频源共享同一个 I2S 通道，通过 pause/resume 实现互斥。

## 五、FreeRTOS 任务表

| 任务 | 核心 | 优先级 | 栈 | 生命周期 |
|------|------|--------|-----|---------|
| main_task | 1 | 5 | 8KB | 永久 |
| tcp_audio | 0 | 4 | 4KB | 永久（等 WiFi） |
| audio_out | 1 | 6 | 4KB | 懒创建 |
| eng_synth | 1 | 6 | 8KB | 动态创建/销毁 |

## 六、内存预算

| 资源 | 位置 | 大小 | 用途 |
|------|------|------|------|
| LCD DMA buffer | 内部 SRAM | 115KB | 全屏 RGB565 blit |
| I2S DMA | 内部 SRAM | 12KB | 6 desc × 512 frames |
| Bluedroid | 内部 SRAM | ~80KB | BLE 协议栈 |
| PCM ring buffer | PSRAM | 64KB | WiFi 音频缓冲 |
| 自定义音频 | PSRAM | ≤1MB | 4 层 × 256KB max |
| Logo 上传 | PSRAM | 115KB | 临时缓冲 |
| WiFi/LWIP | PSRAM | 动态 | 自动分配 |

## 七、已知技术债务

| # | 位置 | 问题 | 建议 |
|---|------|------|------|
| 1 | main.c dispatch | 500+ 行 switch | 可提取为 command_handler service |
| 2 | main.c logo/audio | 上传状态机 ~400 行 | 可提取为 upload_service |
| 3 | encoder_handler.c | 死代码 | 可删除 |
| 4 | OTA | 返回 NOT_IMPL | 上架前必须实现 |
| 5 | ui_speed.c | 油门逻辑混合 UI + 硬件控制 | 可接受，不拆 |
