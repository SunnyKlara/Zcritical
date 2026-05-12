# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-12 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。

## 当前阶段：APP 架构重构 → 真机联调

固件已完成，APP 协议层已重构完毕。当前卡在 DeviceConnectScreen 瘦身和真机验证之间。

## 已完成

| 阶段 | 内容 | 验证 |
|------|------|------|
| 1. 固件迁移 | STM32→ESP32-S3 完全重写 | idf.py build 零错误 |
| 2. 菜单 UI | LCD 轮盘菜单 + 滑动动画 | idf.py build 零错误 |
| 3. APP 协议适配 | 14 项需求，17 个任务 | flutter analyze 通过 |
| 4. APP 重构（部分） | 协议层拆分、Provider 重写、DI 引入 | 51 个协议测试通过 |
| 4.5 引擎音效 | 4 层可变采样率合成 | idf.py build 零错误 |
| 5. 自定义音频上传 | BLE 二进制传输 + LittleFS 存储 | idf.py build 零错误 |

## 当前阻塞

- **真机联调未开始** — 协议层完全重写后需要验证 BLE 通信是否正常
- **DeviceConnectScreen 仍有 ~3500 行** — 待提取 ColorizeRGBDetailView (~700行) 和设备菜单 (~250行)

## 下一步

1. **P0 真机联调**（见 `DEBUG_PLAN.md` 第 1 轮）
   - BLE 扫描发现 "T1" → 连接 → 自动状态同步
   - 基础控制验证：风扇/LED/亮度/雾化器/音量
   - 断线重连
2. **P1 继续拆 DeviceConnectScreen**
   - 提取 ColorizeRGBDetailView Widget
   - 删除 Screen 中已迁移的旧变量/方法
   - 提取设备菜单弹窗
3. **P2 go_router 声明式路由**
4. **P3 国际化 + CI/CD**

## 本次对话决策

- 2026-05-12（第三轮）：文档审计 + Git 管理体系建立 + 历史补救提交
  - 审计发现：3400+ 未提交变更，仅 3 个 commit，无分支策略
  - 创建 `guides/git-workflow.md`（auto inclusion）— 分支策略、commit 规范、提交节奏、历史补救方案
  - 补全 .gitignore — 增加 Keil 产物、PlatformIO 产物、Python cache、.vs/
  - 清理文档残留 — 删除 ENGINE_SOUND_REDESIGN.md 空壳、PROTOCOL_SPECIFICATION.md 空壳
  - 修复 README.md 和 RideWind/README.md 中的过时链接 → 指向 steering
  - 执行历史补救：7 个结构化 commit + tag v0.1.0-baseline，工作区干净
  - 移除误提交的 .vs/ 二进制文件和 RideWind.zip
  - 推送状态：后台上传中（~110MB），用户需确认完成

- 2026-05-12（第二轮）：AI 协作操作系统 18 模式全部落地
  - 子系统二完成：协作模式 8-11（探索/手术/脚手架/重构）→ `guides/collaboration-modes.md`
  - 子系统三补完：模式 14（参考项目烂尾分析）→ `knowledge/why-reference-failed.md`
  - 子系统三补完：模式 15（命名统一表）→ `specs/naming-conventions.md`（auto inclusion）
  - 18 模式蓝图元文档 → `steering/AI-COLLAB-OS-BLUEPRINT.md`
  - START-HERE.md 更新索引，新增 4 个文件引用

- 2026-05-12（第一轮）：文档体系大清理，落地子系统一 + 四
  - 创建 `.kiro/steering/` 三层体系（specs/guides/knowledge）
  - 创建 5 个 hooks 把纸面规则变成自动执行机制
  - 删除 f4_26_1.1 两份副本、RideWind/docs/archive/（35文件）、过时规划文档
  - 协议唯一真值源迁移到 steering/specs/protocol-contract.md
  - 引脚唯一真值源确认为 pin_config.h（删除了冗余 .md）
  - CONTINUATION_GUIDE.md 从 400 行精简为纯 session handoff
  - architecture-boundary-guard hook 对所有 write 触发，prompt 中区分代码/非代码文件跳过
  - 深度文档产出：architecture.md（固件全景）、known-pitfalls.md（19 个坑位）

## 编译状态

```
ESP32 固件：idf.py build — ✅ 零错误（2026-04-30 最后验证）
Flutter APP：flutter analyze — ✅ 通过（2026-04-30 最后验证）
协议测试：flutter test test/protocol/ — ✅ 51/51 通过
```

## 关键文件速查

| 用途 | 文件 |
|------|------|
| 固件入口 | `ridewind-esp/main/main.c` |
| 固件状态 | `ridewind-esp/main/app/app_state.h` |
| 固件协议 | `ridewind-esp/main/services/protocol.c` |
| APP 入口 | `RideWind/lib/main.dart` |
| APP 核心页面 | `RideWind/lib/screens/device_connect_screen.dart` |
| APP 蓝牙状态 | `RideWind/lib/providers/bluetooth_provider.dart` |
| APP 协议解析 | `RideWind/lib/protocol/protocol_parser.dart` |
| APP BLE 底层 | `RideWind/lib/services/ble_service.dart` |
