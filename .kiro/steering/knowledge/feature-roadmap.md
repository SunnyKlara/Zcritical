---
inclusion: auto
---

# 功能路线图（v1.2+）

> 这不是 spec，是开发方向参考。每个功能在对话中逐步推进，不需要一次性设计完。
> 基线：`v1.2.0-baseline`（2026-05-22），所有 feature 分支从此创建。

## 1. 车库（Garage）大更新

**分支**：`feat/garage-v2`
**目标**：选车后联动风扇/灯光/音效/Logo，沉浸式体验。

**已有基础**：
- 车库页面占位版（全屏 PageView）+ 915 张 FH5 缩略图
- car_index.json + car_specs.json 车辆数据
- 引擎音效 RC Engine 方案（idle/rev/knock/start）
- LED 14 预设 + RGB + 波浪 + 舞台灯光秀
- Logo WiFi 上传已验证（115KB/3s）
- 风扇 PWM 调速已实现（IO10 LEDC，非线性曲线+平滑加减速），待实机验证

**推进顺序**（每步一个对话或多步一个对话，看复杂度）：
1. 车辆数据结构设计 — car_specs.json 扩展（品牌分类、参数映射字段）
2. 车辆选择 UI — 品牌分类/搜索/收藏
3. 参数映射算法 — 马力/扭矩 → 风速/音效/灯光参数
4. 协议扩展 — 新增 GARAGE_SET 命令（一次性下发整套参数）
5. 风扇联动 + 调速弹窗 UI
6. 引擎声联动（不同车型类别对应不同音效参数）
7. Logo 联动（选车后推送品牌 Logo）
8. 长按紧急停止 → 调速弹窗交互

---

## 2. Colorize Mode 灯光系统升级

**分支**：`feat/colorize-v2`
**目标**：更多灯光模式 + 手机端调控优化 + 硬件适配。

**已有基础**：
- 4 条 WS2812B（左/中/右/底），RMT 驱动
- led_effects.c/h 灯效引擎
- 14 预设 + RGB + 波浪 + 舞台灯光秀
- colorize_rgb_detail_view.dart 四区调色
- RMT DMA 闪烁问题（已回退，暂搁）

**推进顺序**：
1. 新灯效算法实现（呼吸/渐变/火焰/极光）— 纯固件端
2. 协议扩展 — 新灯效命令定义
3. APP 端 UI 更新 — 新模式入口 + 参数调节
4. 灯光场景系统（一键切换整套方案）
5. RMT DMA 闪烁根因分析（硬件层面）

---

## 3. 音频投射功能升级

**分支**：`feat/audio-casting-v2`
**目标**：类蓝牙音箱体验，音质优化，适配主流音乐 App。

**已有基础**：
- Android MediaProjection → WiFi TCP → ESP32 I2S DAC
- wifi_audio_service.c + audio_stream_service.dart
- AudioCaptureService.kt 原生音频捕获
- 多轨混音（引擎 + WiFi 音频）
- iOS 不支持系统音频捕获（已隐藏）

**推进顺序**：
1. 音频质量诊断 — 当前延迟/音质/丢包率测量
2. 编码优化 — PCM vs Opus，缓冲策略调整
3. 播放控制集成 — 通知栏媒体信息显示
4. iOS 替代方案调研（AirPlay 接收 / 本地播放器）
5. 音频可视化 + 灯光律动联动

---

## 4. iOS 开发体系

**分支**：`feat/ios-platform`
**目标**：建立多平台开发规范，iOS 上架。

**已有基础**：
- iOS 代码适配已完成（权限/平台条件/BLE UUID）
- platform-rules.md 多平台规则
- IOS_RELEASE_CHECKLIST.md 上架步骤
- 需要 Mac 环境

**推进顺序**：
1. Platform Channel 抽象层设计
2. iOS 构建验证（需 Mac）
3. Bundle ID + 签名配置
4. App Store 提交
5. 多平台 CI/CD（GitHub Actions）

---

## 如何开始一个功能

新对话时直接说：

> "我要开始做车库大更新，先从车辆数据结构设计开始"

AI 会：
1. 创建 feature 分支
2. 读相关代码
3. 提出方案
4. 等你确认后动手

不需要额外的提示词工程。steering 文件会自动提供上下文。
