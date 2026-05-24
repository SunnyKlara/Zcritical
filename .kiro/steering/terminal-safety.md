---
inclusion: auto
---

# 终端命令使用规则

> 核心目标：最小化终端调用次数，绝对禁止破坏性命令。

## 禁止使用的命令（绝对红线）

以下命令或模式**永远不允许出现在终端中**：

- `del` / `rm` / `Remove-Item`（删除文件）
- `rmdir` / `rd` / `Remove-Item -Recurse`（删除目录）
- `format`（格式化磁盘）
- `git clean -f`（删除未跟踪文件）
- `git reset --hard`（丢弃所有修改）
- `git branch -D`（强制删除分支）
- `git push --force`（强制推送覆盖远程）
- 任何包含 `-Recurse -Force` 的删除操作
- 任何 `> file` 重定向覆盖已有文件

## 删除操作的正确方式

- 删除单个文件 → 使用 Kiro 内置的 `delete_file` 工具（有安全检查，不走终端）
- 删除目录 → 先告知用户，获得确认后再用 `delete_file` 逐个处理
- 清理 build 产物 → 只在用户明确要求 fullclean 时才执行，且只删 build/ 目录

## 允许的终端命令（安全白名单）

| 类别 | 命令示例 |
|------|----------|
| 编译 | `build.ps1`、`idf.py build`、`flutter build` |
| 依赖 | `flutter pub get`、`pip install` |
| Git 读操作 | `git status`、`git log`、`git diff` |
| Git 写操作 | `git add`、`git commit`、`git push`（非 force） |
| 运行脚本 | `python xxx.py`、`dart run` |
| 查看信息 | `flutter doctor`、`idf.py size` |

## 减少终端调用的策略

1. **能用内置工具就不走终端** — 文件读写、搜索、创建全用 Kiro 工具
2. **合并命令** — 多个安全命令用 `;` 或 `&` 合并为一次执行
3. **不做无意义的验证** — 如果刚写完文件，不需要 `type` 命令去确认内容
4. **编译验证用最快方式** — 优先 `build.ps1`（增量 ~2s），不用 export.ps1 全流程
5. **git 操作批量化** — `git add . ; git commit -m "xxx" ; git push` 一条搞定

## 例外情况

唯一允许在终端中执行"类删除"操作的场景：
- `idf.py fullclean`（用户明确要求全量重编时）
- 这种情况下只删除 `ridewind-esp/build/` 目录，不涉及源码

## 执行原则

- 如果一个任务可以 100% 通过文件编辑工具完成 → 不调用终端
- 如果必须调用终端 → 确保命令在白名单内
- 如果命令不在白名单内 → 先告知用户，等待确认
