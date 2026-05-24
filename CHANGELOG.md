# Changelog

所有重要变更记录在此文件。格式基于 [Keep a Changelog](https://keepachangelog.com/)。

---

## [v1.2.3] - 2026-05-25

CI/CD 基础设施完善：iOS 自动签名 + TestFlight 全自动上传。

### CI/CD
- iOS 构建改用 App Store Connect API 自动签名（彻底移除手动 .p12 + .mobileprovision）
- xcodebuild + `-allowProvisioningUpdates` 自动创建/下载证书和 provisioning profile
- 构建完成后直接上传 TestFlight（`destination: upload`）
- Runner 升级到 `macos-26`（Xcode 26 + iOS 26 SDK，满足 Apple 2026 新要求）
- 不再需要 APPLE_CERTIFICATE / APPLE_CERTIFICATE_PASSWORD / APPLE_PROVISIONING_PROFILE secrets

### 文档
- Release Playbook 更新：补充 iOS 签名配置说明和踩坑记录

---

## [v1.2.2] - 2026-05-24

设备列表首页 + 专业级软硬件版本协商系统。

### APP 新功能
- 设备列表首页：启动后直接显示已保存设备列表，点击连接进入控制页面
- 导航栈重构：设备列表为栈底，控制页面在上面，返回键回到列表
- HELLO 双向握手：连接时获取固件 capabilities bitmap，精确知道设备支持哪些功能
- ERR:UNKNOWN_CMD 检测：固件不支持的命令有明确回复，不再静默失败

### APP 修复
- 彻底关闭 APP 端引擎音效（所有音频由硬件端处理）
- 移除自动重连逻辑（用户手动点击连接，避免竞态问题）
- 修复控制页面返回导航（pop 回设备列表，不再 pushReplacement）

### 固件新功能
- HELLO 握手命令：回复固件版本 + 协议版本 + 硬件型号 + capabilities bitmap
- ERR:UNKNOWN_CMD 回复：未知命令不再静默丢弃，回复错误码供 APP 降级
- 18 位 capability bitmap 定义（speed/led/atomizer/ota/wifi/audio 等）

### 架构改进
- DeviceCapabilities 重写为 bitmap 驱动（与固件 board_config.h 同步）
- 三级 fallback：HELLO → GET:VERSION → 基础模式
- 设备管理功能合并到首页（DeviceManagementScreen 废弃独立入口）

---

## [v1.2.0] - 2026-05-23

车库控制面板 v2 + 动态极速系统 + 车模识别集成。

### APP 新功能
- 车库控制面板：风力 RangeSlider 双滑块（设定怠速/极速风力区间）
- ACTIVATE 等待固件 OK 确认 + loading 动画
- 车模识别入口（YOLOv5 + MobileNetV3，Android only，模型待训练）
- 极速范围扩展到 0-999（用户可自定义任意极速）

### 固件新功能
- `SPEED_MAX:1-999` 命令 — 动态设置 LCD 极速上限
- `FAN_RANGE:min,max` 命令 — 风力区间映射（速度联动）
- NVS 持久化 — SPEED_MAX/FAN_RANGE/VOL 断电不丢失
- 音量控制引擎音（`audio_player_set_master_volume` 同步）

### Bug 修复
- 修复普通模式误触发引擎音播放
- 修复音量调节对油门引擎音无效
- 修复 APP SPEED 命令强制映射到 0-340（现在直接发显示值）
- 修复油门模式下 APP 滑动干扰硬件（现在忽略）
- 禁用 APP 端 EngineAudioManager（音频全部由硬件处理）
- 修复 YoloDetector.java TFLite GPU API 兼容问题

---

## [v1.0.0] - 2026-05-21

首个正式版本。ESP32-S3 固件从 STM32 F4 完全重写，Flutter APP 全功能适配。

### APP 新功能
- 速度仪表盘 + 油门模式（长按加速/松手减速）
- 14 色 LED 预设 + RGB 自定义调色
- 8 种油门灯效（转速条/脉冲/追逐/交替/波浪/闪电/风浪联动/舞台灯光秀）
- 流水灯循环动画
- WiFi 音频投射（系统音频 → ESP32 扬声器）
- 自定义引擎音效上传（4 层 PCM）
- Logo 上传（二进制高速模式，3 槽位）
- OTA 固件升级（BLE 传输 + Rollback 保护）
- APP 自动升级检测（GitHub Releases）
- 功能引导教程（首次使用）
- 设备特定偏好保存/恢复

### 固件新功能
- ESP32-S3 全功能固件（BLE + WiFi 共存）
- GC9A01 240×240 圆屏 UI（6 页滑动菜单 + 8 帧动画）
- WS2812B 双灯带（10+3 颗）+ 亮度缩放
- RC Engine 5 层 16-bit 音效合成（变速率 + 交叉淡入）
- LEDC PWM 风扇（非线性曲线 + 平滑加减速）
- EC11 编码器（PCNT 四倍频 + 单击/双击/三击/长按）
- NVS 持久化存储 + LittleFS 文件系统
- OTA 升级 + Rollback 自检
- 产测自检模式（10 项硬件验证 + NVS 锁）

### 工程化
- 全文件头部注释（@file + 职责说明）
- main.c 命令分发 8 分区注释
- 协议测试 51/51 覆盖
- 项目健康指标监控
- Git 规范 + 版本管理 + Release 流程

---

## [v0.3-unified-main] - 2026-05-18

开发阶段里程碑（非正式发布）。

- STM32→ESP32 迁移完成
- APP 协议适配 14 项需求
- 基础 UI + LED + 音频功能跑通
