---
inclusion: auto
---

<!-- last-verified: 2026-05-12 -->

# Git 工作流规范

> 单人开发 + AI 协作的 Git 管理策略。平衡安全性和效率。

---

## 分支策略（Trunk-Based + 保护）

```
main ─────────────────────────────────── 稳定版本，可随时烧录/打包
  │
  ├── feat/xxx ──── 功能开发分支（完成后 merge 回 main）
  ├── fix/xxx ───── Bug 修复分支
  └── refactor/xxx ─ 重构分支
```

### 规则

1. **main 分支始终可编译** — merge 前必须 `idf.py build` + `flutter analyze` 通过
2. **功能开发在 feature 分支** — 命名 `feat/功能名`，如 `feat/ota-ui`、`feat/wifi-audio`
3. **Bug 修复在 fix 分支** — 命名 `fix/问题描述`，如 `fix/encoder-delta-loss`
4. **重构在 refactor 分支** — 命名 `refactor/目标`，如 `refactor/split-device-screen`
5. **文档/配置可以直接 commit 到 main** — 不影响编译的纯文档变更

### 分支生命周期

```
创建 → 开发 → 验证编译 → merge 到 main → 删除分支
```

- 分支存活不超过 3 天（避免 merge 冲突积累）
- 如果超过 3 天，考虑拆分为更小的任务

---

## Commit 规范

### 格式

```
[模块] 动作: 简述

可选正文（解释 why，不解释 what）
```

### 模块标签

| 标签 | 范围 |
|------|------|
| `esp/drivers` | 固件驱动层 |
| `esp/services` | 固件服务层 |
| `esp/app` | 固件应用层 |
| `esp/ui` | 固件 UI 层 |
| `esp/config` | 固件配置 |
| `app/protocol` | Flutter 协议层 |
| `app/services` | Flutter 服务层 |
| `app/providers` | Flutter 状态管理 |
| `app/screens` | Flutter 页面 |
| `app/widgets` | Flutter 组件 |
| `docs` | 文档变更 |
| `infra` | 构建配置、CI、gitignore |
| `meta` | AI 协作体系（steering/hooks） |

### 动作词

| 动作 | 含义 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `refactor` | 重构（不改行为） |
| `style` | 格式调整（不改逻辑） |
| `docs` | 文档 |
| `chore` | 杂务（依赖更新、清理） |

### 示例

```
[esp/ui] feat: add menu wheel slide animation
[app/protocol] fix: exclude OK:VOL prefix in parseVolume
[esp/drivers] refactor: extract encoder remainder logic
[docs] docs: add why-reference-failed analysis
[meta] feat: complete 18-pattern AI collab OS
```

---

## 提交节奏

### 何时提交

| 场景 | 提交时机 |
|------|----------|
| 完成一个功能点 | 立即提交 |
| 修复一个 bug | 立即提交 |
| 重构一步完成（可编译） | 立即提交 |
| 对话结束 | 如果有未提交的可编译变更，提交 |
| 文档更新 | 可以攒几个一起提交 |

### 何时不提交

- 代码不能编译
- 改了一半还没验证
- 混合了多个不相关的变更（先拆分）

### 提交粒度

- **太细：** 每改一行就提交 ❌
- **太粗：** 3000+ 行一个提交 ❌
- **刚好：** 一个提交 = 一个可描述的变更单元 ✅

---

## 紧急恢复

### 场景 1：改坏了想回退

```bash
# 回退最近一次提交（保留文件变更）
git reset --soft HEAD~1

# 回退最近一次提交（丢弃文件变更）
git reset --hard HEAD~1
```

### 场景 2：想保存当前状态但不提交

```bash
git stash
# ... 做其他事 ...
git stash pop
```

### 场景 3：创建安全快照

```bash
git tag snapshot-YYYYMMDD-描述
```

---

## AI 协作中的 Git 操作

### AI 可以做的

- 建议 commit message
- 帮助 stage 特定文件（`git add 具体文件`）
- 创建分支（`git checkout -b feat/xxx`）
- 查看 diff 和 status

### AI 不做的（需要用户确认）

- `git push`（推送到远程）
- `git reset --hard`（不可逆操作）
- `git force-push`（覆盖远程历史）
- `git branch -D`（删除分支）

### 每次对话结束前的 Git 自检

- [ ] 有未提交的代码变更吗？→ 建议提交
- [ ] 当前在哪个分支？→ 确认是否需要 merge
- [ ] 变更是否可编译？→ 不可编译不提交

---

## AI 自主执行规则

当已有完善的 git tag 管理时，AI 直接执行实验性改动，不等用户确认。

**流程：**
1. 说明方案（1-2句）
2. 保存当前版本（tag）
3. 直接执行改动 + 编译
4. 呈现结果供用户评判

**前提：**
- 有 tag 可随时回退
- 不涉及破坏性操作（删分支、force push）

用户只需看结果说"好"或"不好"，不需要中间确认步骤。

---

## 当前 Git 状态

- 历史补救已完成（2026-05-12），tag `v0.1.0-baseline`
- 当前工作在 main 分支，tag `v0.3-unified-main`
- 分支 `feature/light-mode-pro-popup` 待合入
