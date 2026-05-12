---
inclusion: manual
---

<!-- last-verified: 2026-05-12 | status: IMPLEMENTED -->

> ⚠️ 此文档记录已完成的引擎音效系统设计。实现代码在 `ridewind-esp/main/services/audio_player.c`。

# 引擎音效系统架构

## 概述

4 层可变采样率实时合成引擎，对标 Rc_Engine_Sound_ESP32 方案。
从 speed_percent(0-100) 映射到 RPM，通过非线性惯性平滑后驱动 4 层采样的交叉淡入淡出。

## 信号流

```
speed_percent → target_rpm → 非线性惯性平滑 → current_rpm
    → find_blend()（选相邻 2 层 + 混合比）
    → calc_step()（定点步进 = rpm / layer_rpm × 0.5）
    → 线性插值读取 2 层采样 → 交叉淡入淡出混合
    → 8-bit → 16-bit 上采样 × vol_gain
    → stereo I2S DMA → MAX98357 → 扬声器
```

## 4 层采样

| 层 | RPM | 文件 | 大小 |
|----|-----|------|------|
| IDLE | 800 | engine_idle.h | 84893 samples (83KB) |
| LOW | 2000 | engine_low.h | 83KB |
| MID | 4000 | engine_mid.h | 83KB |
| HIGH | 7000 | engine_high.h | 83KB |

格式：22050Hz 8-bit signed PCM mono，无缝循环。
素材由 enginesound (DasEtwas, MIT) 程序化生成。

## 关键参数

```c
#define ENGINE_RPM_IDLE       800
#define ENGINE_RPM_MAX        8000
#define ENGINE_ACCEL_RATE_LO  100    // 低转速加速慢
#define ENGINE_ACCEL_RATE_HI  200    // 高转速加速快
#define ENGINE_DECEL_RATE     50     // 减速慢（飞轮惯性）
#define ENGINE_DECEL_RATE_HI  200    // 急减速快
#define ENGINE_OUTPUT_RATE    44100  // I2S 输出采样率
#define ENGINE_BUFFER_FRAMES  512    // DMA buffer 大小
```

## 与其他模块的关系

- `ui_speed.c`：传 speed_percent → audio_player_set_target_rpm()
- `audio_engine.c`：WiFi 音频投射，与引擎声互斥（start 时 pause，stop 时 resume）
- `drv_audio.c`：I2S 驱动层，不动
- `main.c`：CMD_SPEED 处理时同步调用 set_target_rpm

## 用户自定义音频

用户可通过 APP 上传 4 层自定义引擎声到 LittleFS：
- 路径：`/storage/engine_{idle,low,mid,high}.pcm`
- 格式：raw signed 8-bit PCM, 22050Hz, mono
- 最大 256KB/层，建议 2-4 秒循环
- 4 层全部到齐后自动重载（audio_player_reload_layers）
- 自定义音频存 PSRAM，不占内部 SRAM
