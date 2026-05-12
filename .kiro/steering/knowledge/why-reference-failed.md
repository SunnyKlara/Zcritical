---
inclusion: manual
---

<!-- last-verified: 2026-05-12 -->

# 模式 14：为什么参考项目不能直接用

> 前车之鉴。每个"参考项目"都有它不能照搬的原因。新 AI 想复制代码前必须读这里。

---

## f4_26_1.1（旧 STM32F405 固件）

### 项目状态：已废弃，仅供逻辑参考

**为什么废弃：**
- 硬件从 STM32F405 迁移到 ESP32-S3，外设 API 完全不同
- 原项目用 Keil MDK + HAL 库，新项目用 ESP-IDF + FreeRTOS
- 原项目无 WiFi/BLE 能力（靠外挂蓝牙模块），新项目 SoC 内置

**可以参考什么：**
| 可参考 | 不可参考 |
|--------|----------|
| 协议命令格式设计思路 | HAL_GPIO / HAL_SPI 调用 |
| 菜单状态机逻辑流程 | 定时器中断写法 |
| LED 灯效算法（颜色计算） | DMA 配置方式 |
| 编码器交互逻辑 | 内存布局 / linker script |
| NVS 存储的 key 设计 | Flash 分区表 |

**照搬会怎样：**
- 编译直接报错（API 不存在）
- 即使手动适配 API，FreeRTOS 任务模型不同（STM32 裸机 superloop vs ESP32 多任务）
- 中断优先级体系完全不同
- 内存模型不同（STM32 单一地址空间 vs ESP32 内部SRAM/PSRAM/Flash 分区）

---

## audio参考项目（PlatformIO + Arduino）

### 项目状态：独立参考，不合并

**为什么不能合并：**
- 框架不同：Arduino 框架 vs ESP-IDF 原生
- 构建系统不同：PlatformIO vs CMake/idf.py
- API 层次不同：Arduino `analogWrite()` vs ESP-IDF `ledc_set_duty()`
- 任务模型不同：Arduino `loop()` vs FreeRTOS `xTaskCreate()`

**可以参考什么：**
| 可参考 | 不可参考 |
|--------|----------|
| HAL 分层思想 | 具体 HAL 实现代码 |
| 页面状态机设计 | LVGL UI 代码（我们用直接 LCD 绘制） |
| BLE 键盘交互思路 | Arduino BLE 库调用 |
| 音频播放架构 | I2S 配置（参数不同） |
| 多轨混音概念 | AudioFileSourceSPIFFS 等 Arduino 库 |

**照搬会怎样：**
- `#include <Arduino.h>` 直接报错
- LVGL 引入会占用大量 RAM（我们的 LCD 只有 135×240，不需要）
- PlatformIO 的 lib_deps 在 ESP-IDF 中不存在

---

## Tixing-main（Pico Python 显示项目）

### 项目状态：完全独立，不同硬件

**为什么完全独立：**
- 硬件：Raspberry Pi Pico（RP2040）vs ESP32-S3
- 语言：MicroPython vs C
- 用途：纯显示仪表盘 vs 全功能控制器
- 通信：无 BLE/WiFi vs BLE + WiFi

**可以参考什么：**
- UI 布局美学（仪表盘设计）
- 颜色方案
- 字体渲染思路

**不可参考：** 任何代码实现

---

## ESPtest（早期 ESP32 测试）

### 项目状态：已过时的 Hello World

**为什么过时：**
- 基于 ESP-IDF 示例模板，只有 LED 闪烁
- 引脚定义与最终硬件不同
- 无任何业务逻辑

**唯一价值：** 确认 ESP-IDF 环境能正常编译

---

## 总结：参考项目使用原则

1. **只参考思路，不复制代码** — 框架/API/任务模型都不同
2. **参考前先确认兼容性** — 同一个概念在不同框架中实现方式可能完全不同
3. **有疑问查 ESP-IDF 官方文档** — 不要用参考项目的写法推断 ESP-IDF 的正确用法
4. **协议设计可以参考 f4** — 命令格式是跨平台的，但解析实现要重写
5. **音频架构可以参考 audio参考项目** — 多轨混音概念通用，但 I2S 配置要查 ESP-IDF 文档
