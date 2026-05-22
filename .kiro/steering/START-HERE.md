---
inclusion: auto
---

# Critical T1 — AI 启动入口

## 产品
智能风洞模拟器。ESP32-S3 固件(C/ESP-IDF) + Flutter APP(Dart)，BLE 控制 + WiFi 音频投射。
品牌名 Critical，代码内部仍用 ridewind（改名会破坏构建）。

## 当前状态
→ 见 `CONTINUATION_GUIDE.md`（session handoff，≤100 行）

## AI 能力边界

| 能力 | 状态 |
|------|------|
| 读/写项目所有源文件 | ✅ |
| 运行 `flutter pub get / analyze / test` | ✅ |
| 运行 `idf.py build`（需 ESP-IDF 环境） | ⚠️ 用户确认环境后可执行 |
| 烧录固件到硬件 | ❌ 用户操作 |
| 实机测试验证 | ❌ 用户反馈结果 |
| 联网查文档 | ✅ |

## 必知规则

1. **唯一协议真值源** → `.kiro/steering/specs/protocol-contract.md`，代码中的协议实现必须与此文件一致
2. **改代码必须同步文档** — 改了协议/引脚/架构 → 更新对应 steering 文件
3. **对话结束更新 handoff** — 更新 `CONTINUATION_GUIDE.md` 的当前状态和下一步
4. **有担忧就说** — 对用户方案有疑虑时必须提出，最多争论 2 轮，用户坚持后记录分歧并执行
5. **ESP 固件分层不可破** — drivers/ 不调 services/，services/ 不调 ui/，所有状态走 AppState
6. **不创建 spec 文件** — 不要在 `.kiro/specs/` 下创建任何文件。设计在对话中讨论，不走形式化流程。详见 `guides/dev-workflow.md`

## 项目结构

```
├── ridewind-esp/     ESP32-S3 固件（drivers/services/app/ui/config/resources）
├── RideWind/         Flutter APP（protocol/services/providers/screens/widgets）
└── .kiro/            AI 协作体系（steering/hooks/specs/reference）
```

## 深入（按需读取）

| 主题 | 文件 |
|------|------|
| BLE 协议完整定义 | `.kiro/steering/specs/protocol-contract.md` |
| 固件架构全景 | `.kiro/steering/specs/architecture.md` |
| 命名统一表（三端映射） | `.kiro/steering/specs/naming-conventions.md` |
| 硬件引脚定义（唯一真值源） | `ridewind-esp/main/config/pin_config.h` |
| 硬件常量/时序参数 | `ridewind-esp/main/config/board_config.h` |
| 已知坑位（19 个） | `.kiro/steering/knowledge/known-pitfalls.md` |
| 教训与决策记录 | `.kiro/steering/knowledge/lessons-learned.md` |
| 历史决策日志（归档） | `.kiro/steering/knowledge/decision-log.md` |
| 引擎音效架构 | `.kiro/steering/knowledge/engine-sound-design.md` |
| 参考项目为何不能照搬 | `.kiro/steering/knowledge/why-reference-failed.md` |
| Git 工作流规范 | `.kiro/steering/git-and-release.md` |
| 跨平台协作（Win+Mac） | `.kiro/steering/guides/cross-platform-workflow.md` |
| 构建/测试命令 | `.kiro/steering/guides/build-and-test.md` |
| AI 行为规范（含协作模式） | `.kiro/steering/guides/ai-behavior.md` |
| 发布流程 | `.kiro/steering/guides/release-workflow.md` |
| 真机调试计划 | `DEBUG_PLAN.md` |
| APP 交互逻辑 | `RideWind/docs/app-interaction-guide.md` |
| 全功能测试清单 | `RideWind/docs/FULL_TEST_CHECKLIST.md` |
| APP 架构 | `RideWind/README.md` |
| 固件 Kiro Specs | `.kiro/specs/`（3 个已完成 spec，历史参考） |
| 50 项技术学习路线图 | `.kiro/reference/SOFTWARE-STRATEGY.md` |
| 18 模式蓝图（元文档） | `.kiro/reference/AI-COLLAB-OS-BLUEPRINT.md` |
