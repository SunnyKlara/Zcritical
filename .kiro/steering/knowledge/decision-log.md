---
inclusion: manual
---

<!-- 历史决策归档。从 CONTINUATION_GUIDE.md 拆出，按需查阅。 -->

# 决策日志（Decision Log）

> 按时间倒序记录所有重要的技术决策和实现细节。
> 新 AI 通常不需要读这个文件，除非需要理解"为什么当时这样做"。

---

## 2026-05-20

### 车库全屏滑动页面（占位版本）
- 技术方案：外层全屏 PageView 包裹，不动 DeviceConnectScreen 内部代码
- `MainPagerScreen` + `GarageScreen`，结构：[Garage(0)] ← [DeviceConnect(1, 默认)]
- 路由修改：3 处导航入口改为 MainPagerScreen
- 功能定位：选一辆车 = 选一套引擎音效

### 弹窗调整 — 删除流水灯+可滚动ListView
- 弹窗现有4项：静态 / 波浪呼吸 / 风浪联动PRO / 舞台灯光秀

### 舞台灯光秀效果(mode=8)
- 算法：9颗灯各自独立状态机，不规则明暗变化
- v2：70%概率选两极(0或255)，渐变速度加大，停留时间加长

### 驾驶风格弹窗 UI 视觉优化
- 5 层灰度色彩系统，iOS 控制中心风格滑条，HapticFeedback

### App 自动升级系统
- GitHub Releases 作为分发源，零后端成本
- URL: `https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json`

### 灯光模式 Pro 版弹窗
- 分支 `feature/light-mode-pro-popup`，4 选项弹窗
- 默认模式改为"静态"（基础版不动，Pro 版才有动画）
- 风浪联动极速周期限制 1500ms

### APP 音量控制
- 长按紧急停止按钮 → 悬浮音量条，3秒无操作自动消失
- ESP32 端 CMD_VOLUME 补全了 player 音量同步和 NVS 持久化

### 车库页面设计探讨（已回退）
- 正确方案：DeviceConnectScreen 外层再包全屏 PageView

---

## 2026-05-18

### 波浪效果v4宽波版确认
- tag: `wave-v4-wide-confirmed`
- 最终参数：相位间距25，20fps，底亮15%+潮汐8s(15%↔30%)，峰值100%，周期2.5s

### 风速联动波浪效果
- v1: 周期2500→1200ms / 底亮38→3 / 相位25→40 / 潮汐8s→4s
- v2: 加大幅度 周期2500→800ms / 底亮38→0 / 相位25→55 / 潮汐8s→3s

### 产测自检固件
- 开机按住编码器进入，测试 10 项硬件
- 产测锁：ALL PASS 后写 NVS `selftest.passed=1`

### 引擎音频架构重构 — RC Engine 方案
- 抛弃 5 层 RPM 分段，改用 TheDIYGuy999 的 idle+rev+knock+start 架构
- 素材：LaFerrari V12（GPL-3.0），246KB 编译进固件
- 最终决策：100% 照搬参考项目的 variablePlaybackTimer()，8-bit 范围内混合

### Git 分支整合
- 合并所有修改到 main，删除 10 个旧分支
- 新工作流：只在 main 上开发，用 tag 标记版本

---

## 2026-05-17

### 波浪效果迭代（11 轮）
- 核心教训：6颗灯做不了空间波，只能做整体明暗
- 最终方案：潮汐呼吸+微延迟（v4 宽波版）

### 油门灯效 BLE 协议 + APP 弹窗
- THROTTLE_FX:1-6 协议，ThrottleEffectSelector 底部弹窗

---

## 2026-05-16

### 预设颜色 LCD 色条修复
- 根因：preset_colors.h 排列顺序和 draw_color_bar() 不一致

### 油门模式 LED 灯效系统（6 种效果）
- 硬件布局确认：Main 6 颗 + Tail 3 颗（Left/Right 已去掉）

---

## 2026-05-15

### 方向转向「体验打磨期」
- 协作模式：用户=产品经理，AI=工程师，说了就是确认
- 按键映射重构：单击=油门，长按=雾化器，双击=菜单
- 油门模式视觉：彩色数字贴图（538KB，11档×10数字）

### 烧录实测反馈
- BUG-C: drv_pwm.c gpio_config 锁定 GPIO matrix → 纯 LEDC 初始化
- BUG-D: 速度降0自动退出 → 不退出，只停风扇
- BUG-E: GPIO 40 PWM → 去掉所有 GPIO 预配置

---

## 2026-05-12

### 文档体系大清理
- 创建 steering 三层体系 + 5 个 hooks
- 协议真值源迁移到 protocol-contract.md

### AI 协作操作系统 18 模式落地

### Git 管理体系建立
- 历史补救：7 个结构化 commit + tag v0.1.0-baseline
