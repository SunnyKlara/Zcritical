---
inclusion: fileMatch
fileMatchPattern: "ridewind-esp/**/*.c,ridewind-esp/**/*.h,RideWind/lib/**/*.dart"
---

<!-- last-verified: 2026-05-12 -->

# 教训与决策记录

## 教训 1：不要一次性写完所有文件

**问题**：早期尝试一次性生成整个固件框架（20+ 文件），结果接口不一致、编译错误堆积
**结论**：每次最多改 3 个文件，改完编译验证，再继续
**违反后果**：编译错误雪崩，修一个引出三个

## 教训 2：BLE MTU 分片会截断命令

**问题**：APP 发送长命令（如 LOGO_DATA）时，BLE 底层按 MTU 分片，ESP32 收到不完整命令就解析
**结论**：ESP32 必须缓冲到 `\n` 才解析；APP 端 ResponseRouter 同理
**违反后果**：Logo 上传随机失败，协议解析器报 UNKNOWN_CMD

## 教训 3：编码器小幅旋转 delta 丢失

**问题**：drv_encoder.c 的 PCNT 读取逻辑把不足一个"整步"的 count 直接丢弃
**结论**：只消耗映射到整步的 count，保留余数到下次累加（FIX-001）
**违反后果**：用户轻转旋钮无反应，体验差

## 教训 4：Reference 项目（audio参考项目）为什么只能参考不能照搬

**问题**：audio参考项目用 PlatformIO + Arduino 框架，我们用 ESP-IDF 原生
**结论**：只参考其架构思路（HAL 分层、页面状态机），不复制代码
**违反后果**：API 不兼容，FreeRTOS 用法不同，调试困难

## 教训 5：品牌改名只改用户可见部分

**问题**：RideWind → Critical 改名时，如果改了包名/bundle ID，会导致 MethodChannel 断裂、签名失效
**结论**：只改 UI 文案和显示名，内部包名 com.example.ridewind 保持不变
**违反后果**：Android 构建失败，iOS 签名失效，音频捕获 Service 找不到 Channel

## 教训 6：引擎音效不能用 MP3 循环播放

**问题**：最初方案是播放 engine.mp3 + 调音量模拟转速变化，效果像"开关音箱"而非引擎
**结论**：改用 4 层可变采样率实时合成（参考 Rc_Engine_Sound_ESP32），音调随 RPM 变化
**违反后果**：用户体验从"赛车游戏级"降为"手机铃声级"

## 教训 7：Flutter Provider 公开 API 不能变

**问题**：重构 BluetoothProvider 时如果改了公开方法签名，所有 Screen 都要改
**结论**：内部随便重构，公开 API（方法名、参数、Stream）保持不变
**违反后果**：改一个 Provider 要改 10+ 个 Screen，风险不可控

---

## 决策记录

| 日期 | 决策 | 原因 | 替代方案 |
|------|------|------|---------|
| 2026-04 | 引擎声用 4 层合成而非 MP3 | 音调变化需要可变采样率 | MP3 + pitch shift（CPU 太重） |
| 2026-04 | 音频上传用二进制模式而非 hex 文本 | 83KB 采样用 hex 要传 166KB，太慢 | 保持 hex（传输时间翻倍） |
| 2026-04 | WiFi 音频投射而非 A2DP | ESP32-S3 不支持经典蓝牙 A2DP Sink | 外挂蓝牙模块（增加硬件成本） |
| 2026-04 | 保持 Provider 不换 Riverpod | 已有大量 Consumer 代码，迁移成本高 | Riverpod（更好但迁移风险大） |
| 2026-05 | 文档体系重构 | AI 冷启动需要读 400 行才能工作 | 保持现状（每次浪费 5 分钟） |
