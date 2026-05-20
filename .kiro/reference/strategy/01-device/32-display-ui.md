---
inclusion: manual
---

# 32. 显示驱动与 UI 框架

## 是什么

在资源受限的 MCU 上驱动 LCD 屏幕，实现流畅的图形界面：菜单动画、数字仪表、图标渲染、图片显示。不依赖 LVGL 等重型框架，用轻量自研方案实现 60fps 体验。

## 为什么需要

- 产品需要视觉反馈（速度、模式、状态）
- 好的 UI 动画 = 产品质感 = 用户愿意付更高价格
- 嵌入式 UI 是稀缺技能（大多数固件工程师只会串口打印）
- 理解底层图形原理后，上层框架（LVGL/Flutter）用起来更得心应手

## 技术架构

```
┌─────────────────────────────────────────────────┐
│                  UI 架构分层                      │
├─────────────────────────────────────────────────┤
│                                                  │
│  [应用层] ui_speed.c / ui_menu.c / ui_rgb.c     │
│     │  调用绘图 API，不关心硬件                  │
│     ▼                                            │
│  [框架层] ui_common.c / ui_manager.c            │
│     │  帧缓冲管理、脏区域、动画调度             │
│     │  draw_text / draw_rect / draw_image       │
│     ▼                                            │
│  [驱动层] drv_lcd.c                             │
│     │  SPI DMA 传输、窗口设置、初始化           │
│     ▼                                            │
│  [硬件] ST7789 240x240 SPI LCD                  │
│                                                  │
└─────────────────────────────────────────────────┘

帧缓冲策略：
  全屏 buffer: 240x240x2 = 115KB（PSRAM）
  局部刷新: 只传输变化区域（减少 SPI 带宽）
```

## 技术栈选型

| 组件 | 技术 | 说明 |
|------|------|------|
| LCD 控制器 | ST7789V (240x240, 16-bit RGB565) | 1.3 寸 IPS |
| 通信接口 | SPI (80MHz) + DMA | 全屏刷新 ~14ms |
| 帧缓冲 | PSRAM 全屏 buffer | 115KB，双缓冲可选 |
| 字体 | 预渲染位图字体 | 8x16 ASCII + 自定义大数字 |
| 图片 | RGB565 C 数组 | 编译时转换，运行时零解码 |
| 动画 | 定时器驱动 + 缓动函数 | ease-in/out/cubic |
| UI 框架 | 自研轻量级 | 无 LVGL 依赖，完全可控 |

## 实现步骤

### Phase 1：LCD 驱动（2h）

1. **SPI + DMA 初始化**
   ```c
   // drivers/drv_lcd.c
   void drv_lcd_init(void);
   void drv_lcd_set_window(x, y, w, h);
   void drv_lcd_flush(uint16_t *buf, size_t len);
   void drv_lcd_flush_sync(void);
   ```

2. **ST7789 初始化序列**
   - Software Reset → Sleep Out → 等 120ms
   - Color Mode (RGB565) → Memory Access Control (旋转方向)
   - Display On → 背光 PWM 渐亮

### Phase 2：绘图基础 API（3-4h）

3. **像素级操作**
   ```c
   void ui_fill_rect(int x, int y, int w, int h, uint16_t color);
   void ui_draw_pixel(int x, int y, uint16_t color);
   void ui_draw_hline(int x, int y, int w, uint16_t color);
   void ui_draw_vline(int x, int y, int h, uint16_t color);
   ```

4. **文本渲染**
   ```c
   void ui_draw_char(int x, int y, char c, uint16_t color, uint16_t bg);
   void ui_draw_string(int x, int y, const char *str, ...);
   void ui_draw_big_number(int x, int y, int value, int digits);
   ```

5. **图片绘制**
   ```c
   void ui_draw_image(int x, int y, const ui_image_t *img);
   void ui_draw_image_alpha(int x, int y, const ui_image_t *img);
   ```

### Phase 3：UI 管理器（2-3h）

6. **界面状态机**
   ```c
   typedef enum {
       UI_SCREEN_SPEED,
       UI_SCREEN_MENU,
       UI_SCREEN_COLOR,
       UI_SCREEN_RGB,
       UI_SCREEN_BRIGHT,
       UI_SCREEN_LOGO,
       UI_SCREEN_TREADMILL,
   } ui_screen_t;
   
   void ui_manager_switch(ui_screen_t screen);
   void ui_manager_tick(void);
   ```

7. **切换动画**
   - 滑动过渡：旧界面滑出 + 新界面滑入
   - 渐变过渡：alpha 混合两帧
   - 缩放过渡：从中心放大

### Phase 4：动画系统（2h）

8. **缓动函数库**
   ```c
   typedef float (*easing_fn)(float t); // t: 0.0→1.0
   
   float ease_linear(float t);
   float ease_in_quad(float t);
   float ease_out_quad(float t);
   float ease_in_out_cubic(float t);
   float ease_out_bounce(float t);
   ```

9. **动画调度器**
   ```c
   typedef struct {
       int *target;
       int from, to;
       int duration_ms;
       int elapsed_ms;
       easing_fn easing;
   } animation_t;
   
   void anim_start(animation_t *a);
   bool anim_tick(animation_t *a, int dt_ms);
   ```

### Phase 5：资源工具链（1-2h）

10. **图片转换脚本**
    - PNG/JPG → RGB565 C 数组
    - 支持缩放、裁剪、透明度提取

11. **字体生成脚本**
    - TTF → 位图字体 C 数组
    - 支持指定字号、字符集、抗锯齿级别

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| SPI 带宽瓶颈 | 全屏 60fps 需要 80MHz SPI | 局部刷新，只传脏区域 |
| PSRAM 延迟 | 帧缓冲在 PSRAM 读写慢 | DMA 传输不占 CPU，绘图用 cache |
| 撕裂 | 刷新到一半切换内容 | 双缓冲或 VSync 同步 |
| 字体内存 | 中文字库几百 KB | 只用 ASCII + 预渲染关键中文 |
| 透明度混合慢 | 逐像素 alpha 计算 | 预乘 alpha + 查表优化 |
| 动画卡顿 | 其他任务抢占 UI 任务 | UI 任务固定 30fps tick |

## 与 RideWind 的关系

- 当前状态：已完整实现（自研框架，非 LVGL）
- 已有：ST7789 驱动、帧缓冲、大数字贴图、菜单轮盘动画、图片显示
- 已有工具：`gen_colored_digits.py`、`img_to_rgb565.py`
- 经验总结：自研比 LVGL 更轻量可控，但缺少控件复用能力

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| LCD SPI 驱动（已有） | 0h | ✅ |
| 绘图 API（已有） | 0h | ✅ |
| UI 管理器（已有） | 0h | ✅ |
| 动画系统完善 | 2h | ⭐⭐ |
| 双缓冲优化 | 2-3h | ⭐⭐⭐ |
| 资源工具链完善 | 1-2h | ⭐⭐ |
| **总计（增量）** | **~1 天** | |

## 学到什么

- SPI 通信协议和 DMA 传输
- LCD 控制器初始化序列（数据手册阅读）
- 帧缓冲和双缓冲原理
- 2D 图形基础（光栅化、混合、裁剪）
- 动画数学（缓动函数、插值）
- 嵌入式资源管理（flash 空间 vs 运行时内存）
- 工具链思维（脚本自动化资源转换）
