# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-22 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。
> 历史决策详情见 `.kiro/steering/knowledge/decision-log.md`。

## 当前阶段：体验打磨期 → 四大功能开发准备

功能全部跑通，文档体系整理完成，准备进入四大功能分支开发。

## Git 状态

- **分支**：main（干净）
- **当前 tag**：`v1.2.0-baseline`（2026-05-22，四大功能分支起点）
- **远程**：origin/main 同步
- **规范**：见 `git-and-release.md`（唯一 git 规范文件）

## 当前阻塞 / 待验证

<!-- 每条必须有 verified 日期。AI 涉及相关模块时必须读代码验证是否仍成立 -->

| 状态 | 问题 | verified |
|------|------|----------|
| ⏳ 待实机验证 | 风扇 PWM 调速（引脚已修正 IO10，代码已实现，未烧录验证） | 2026-05-22 |
| ⏳ 待实机验证 | WiFi+BLE 共存配网流程（代码完成，需全量烧录验证） | 2026-05-21 |
| ⏳ 待实机验证 | 引擎音效最终效果（RC Engine 方案代码完成） | 2026-05-18 |
| 🔲 暂搁 | LED 偶发闪烁（RMT DMA 通道不足，已回退） | 2026-05-18 |
| 🔲 暂搁 | DeviceConnectScreen ~3500 行（需拆分，车库开发前建议先做） | 2026-05-20 |
| ✅ 已完成 | WiFi OTA 全流程（APP 端 WebSocket 验证通过） | 2026-05-21 |
| ✅ 已完成 | WiFi 配网实机测试（秒级完成） | 2026-05-21 |
| ✅ 已完成 | iOS 代码适配（权限/平台条件/BLE UUID） | 2026-05-22 |

## 下一步

1. **P0 四大功能分支开发**（详见 `knowledge/feature-roadmap.md`）：
   - `feat/garage-v2` — 车库大更新
   - `feat/colorize-v2` — 灯光系统升级
   - `feat/audio-casting-v2` — 音频投射升级
   - `feat/ios-platform` — iOS 开发体系
2. **P1 WiFi 主通道 Phase 5-6** — APP 通信层切换到 WebSocket + 大数据走 WiFi
3. **P2 体验打磨** — 实玩反馈 → 批量修复

## 编译状态

```
ESP32-S3 固件：✅ idf.py build 通过（2026-05-21，v1.1.1，bin 3.04MB，余量 3%）
Flutter APP：  ✅ flutter analyze 通过（0 errors）
协议测试：    ✅ flutter test test/protocol/ — 51/51 通过
```

## 关键文件速查

| 用途 | 文件 |
|------|------|
| 固件入口 | `ridewind-esp/main/main.c` |
| 固件状态 | `ridewind-esp/main/app/app_state.h` |
| 固件协议 | `ridewind-esp/main/services/protocol.c` |
| 固件音频 | `ridewind-esp/main/services/audio_player.c` |
| 硬件引脚（真值源） | `ridewind-esp/main/config/pin_config.h` |
| APP 入口 | `RideWind/lib/main.dart` |
| APP 核心页面 | `RideWind/lib/screens/device_connect_screen.dart` |
| APP 蓝牙状态 | `RideWind/lib/providers/bluetooth_provider.dart` |
| APP 协议解析 | `RideWind/lib/protocol/protocol_parser.dart` |
