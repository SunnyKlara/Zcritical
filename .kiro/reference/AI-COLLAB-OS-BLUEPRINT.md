---
inclusion: manual
---

<!-- last-verified: 2026-05-12 -->

# AI 协作操作系统 — 18 模式蓝图

> 元文档。定义整个 AI 协作体系的完整架构。
> 每个模式对应一个具体的协作机制，分布在 4 个子系统中。

---

## 子系统一：知识管理（Knowledge）

让 AI 快速获得项目上下文，避免重复犯错。

| # | 模式名 | 落地文件 | 状态 |
|---|--------|----------|------|
| 1 | 分层入口 | `steering/START-HERE.md` | ✅ |
| 2 | 已知坑位 | `steering/knowledge/known-pitfalls.md` | ✅ |
| 3 | 教训与决策 | `steering/knowledge/lessons-learned.md` | ✅ |
| 4 | 引擎音效设计 | `steering/knowledge/engine-sound-design.md` | ✅ |
| 5 | 架构全景 | `steering/specs/architecture.md` | ✅ |
| 6 | 协议真值源 | `steering/specs/protocol-contract.md` | ✅ |
| 7 | 构建测试指南 | `steering/guides/build-and-test.md` | ✅ |

---

## 子系统二：AI 协作模式（Collaboration Modes）

定义不同任务类型的交互节奏，让 AI 用对的方式做对的事。

| # | 模式名 | 落地文件 | 状态 |
|---|--------|----------|------|
| 8 | 探索模式 | `steering/guides/collaboration-modes.md` §探索 | ✅ |
| 9 | 手术模式 | `steering/guides/collaboration-modes.md` §手术 | ✅ |
| 10 | 脚手架模式 | `steering/guides/collaboration-modes.md` §脚手架 | ✅ |
| 11 | 重构模式 | `steering/guides/collaboration-modes.md` §重构 | ✅ |

---

## 子系统三：质量防线（Quality Guards）

防止代码腐烂、命名混乱、参考项目误用。

| # | 模式名 | 落地文件 | 状态 |
|---|--------|----------|------|
| 12 | 七道防线 | `steering/guides/ai-behavior.md` §代码质量自检 | ✅ |
| 13 | 争议义务 | `steering/guides/ai-behavior.md` §争议义务 | ✅ |
| 14 | 参考项目烂尾分析 | `steering/knowledge/why-reference-failed.md` | ✅ |
| 15 | 命名统一表 | `steering/specs/naming-conventions.md` | ✅ |

---

## 子系统四：自动化执行（Hooks）

把纸面规则变成自动触发的检查机制。

| # | 模式名 | 落地文件 | 触发时机 |
|---|--------|----------|----------|
| 16 | 架构边界守卫 | `hooks/architecture-boundary-guard.kiro.hook` | preToolUse:write |
| 17 | 协议同步检查 | `hooks/protocol-sync-check.kiro.hook` | postToolUse:write |
| 18 | 冷启动上下文 | `hooks/cold-start-context-load.kiro.hook` | promptSubmit |

**附加 hooks（非核心模式但支撑体系运转）：**
- `hooks/hardware-config-sync.kiro.hook` — 硬件配置变更同步
- `hooks/session-handoff-update.kiro.hook` — 对话结束更新 handoff

---

## 体系运转逻辑

```
新对话启动
    │
    ▼
[Hook 18] cold-start → 自动加载 START-HERE.md
    │
    ▼
AI 读取分层入口 [模式 1] → 按需深入 [模式 2-7]
    │
    ▼
用户提出任务
    │
    ▼
AI 识别任务类型 → 选择协作模式 [模式 8-11]
    │
    ▼
执行过程中：
  ├─ 写代码前 → [Hook 16] 架构边界检查 [模式 12]
  ├─ 写代码时 → 遵循命名统一表 [模式 15]
  ├─ 遇到分歧 → 争议义务 [模式 13]
  ├─ 想参考旧项目 → 先读烂尾分析 [模式 14]
  └─ 写完代码后 → [Hook 17] 协议同步检查
    │
    ▼
对话结束
    │
    ▼
[Hook] session-handoff → 更新 CONTINUATION_GUIDE.md
```

---

## 设计原则

1. **渐进式加载** — 不一次性灌入所有文档，按需读取
2. **自动化优先** — 能用 hook 自动检查的不靠人记忆
3. **单一真值源** — 每个知识点只存一处，其他地方引用
4. **可演进** — 新模式可以随时加入，不破坏现有体系
5. **最小认知负担** — AI 冷启动只需读 START-HERE.md（~60 行）

---

## 演进路线

### 已完成
- [x] 子系统一：7 个知识文件全部就位
- [x] 子系统二：4 个协作模式定义完成
- [x] 子系统三：4 个质量防线全部落地
- [x] 子系统四：5 个 hooks 全部激活

### 未来可扩展
- 模式 19+：CI/CD 集成模式（GitHub Actions 自动触发）
- 模式 20+：多人协作模式（多个 AI session 共享上下文）
- 模式 21+：版本发布模式（changelog 自动生成）
- Hook 扩展：fileCreated 时自动检查命名规范
- Hook 扩展：postTaskExecution 时自动运行测试

---

## 文件索引（快速定位）

```
.kiro/
├── steering/
│   ├── START-HERE.md                    ← 唯一入口 [模式 1]
│   ├── AI-COLLAB-OS-BLUEPRINT.md        ← 本文件（元文档）
│   ├── specs/
│   │   ├── architecture.md              ← 固件架构 [模式 5]
│   │   ├── protocol-contract.md         ← 协议真值源 [模式 6]
│   │   └── naming-conventions.md        ← 命名统一表 [模式 15]
│   ├── guides/
│   │   ├── ai-behavior.md              ← 行为规范 [模式 12, 13]
│   │   ├── build-and-test.md           ← 构建指南 [模式 7]
│   │   └── collaboration-modes.md      ← 协作模式 [模式 8-11]
│   └── knowledge/
│       ├── known-pitfalls.md           ← 坑位清单 [模式 2]
│       ├── lessons-learned.md          ← 教训决策 [模式 3]
│       ├── engine-sound-design.md      ← 音效设计 [模式 4]
│       └── why-reference-failed.md     ← 参考项目分析 [模式 14]
└── hooks/
    ├── architecture-boundary-guard.kiro.hook  ← [模式 16]
    ├── protocol-sync-check.kiro.hook          ← [模式 17]
    ├── cold-start-context-load.kiro.hook      ← [模式 18]
    ├── hardware-config-sync.kiro.hook         ← 附加
    └── session-handoff-update.kiro.hook       ← 附加
```
