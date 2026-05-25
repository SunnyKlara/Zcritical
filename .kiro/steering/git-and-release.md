---
inclusion: auto
---

# Git 规范与发布流程

## 版本号体系

### 双轨独立版本

| 组件 | 格式 | 存储位置 | 当前版本 |
|------|------|----------|----------|
| ESP32 固件 | `MAJOR.MINOR.PATCH` | `sdkconfig.defaults` → `CONFIG_APP_PROJECT_VER` | 1.0.0 |
| Flutter APP | `MAJOR.MINOR.PATCH+BUILD` | `pubspec.yaml` → `version` | 1.0.0+1 |
| 协议版本 | 整数 | `board_config.h` → `PROTOCOL_VERSION` | 1 |

### 递增规则

- **MAJOR** — 协议不兼容（APP 和固件必须同时升级）
- **MINOR** — 新功能（向后兼容）
- **PATCH** — Bug 修复

### 协议兼容性

连接后 APP 发 `GET:VERSION\n`，固件回复 `VERSION:fw=1.0.0:proto=1\r\n`。
APP 比较 `proto` 字段判断兼容性。旧固件不认识该命令则静默兼容。

---

## Git 分支策略

- **main** — 唯一长期分支，永远可编译
- **feat/xxx** — 大改（预计 >3 天或 >10 文件或涉及协议扩展）时开，完成即合并删除
- 不搞 develop / release / hotfix

### Tag 命名

```
vX.Y.Z        — APP 或联合发版（CI 自动触发构建+部署+更新 app_version.json）
fw-vX.Y.Z     — 固件发版
vX.Y.Z-baseline — 大功能开发前的干净基线（回退锚点）
```

> 注意：旧的 `app-vX.Y.Z` 前缀已废弃。CI workflow 同时兼容 `v*` 和 `app-v*`，
> 但新发版统一使用 `vX.Y.Z`。

### 大功能分支规则（v1.2+ 新增）

**适用场景**：改动 >10 个文件、涉及协议扩展、或预计开发周期 >1 周。

**当前规划分支**：

| 分支名 | 功能 | 依赖 |
|--------|------|------|
| `feat/garage-v2` | 车库大更新（联动风扇/灯光/音效/Logo） | 可能依赖 colorize 协议 |
| `feat/colorize-v2` | Colorize 灯光系统升级 | 独立 |
| `feat/audio-casting-v2` | 音频投射升级 | 独立 |
| `feat/ios-platform` | iOS 开发体系 | 等功能稳定后 |

**生命周期**：

```
1. 从 main 最新 commit 创建：git checkout -b feat/xxx
2. 开发中每周 rebase main 一次：git rebase main（保持同步）
3. 合并条件：flutter analyze 零 error + idf.py build 通过 + 核心功能验证
4. 合并方式：git merge --no-ff feat/xxx（保留分支历史）
5. 合并后：删除分支 + 打 tag + 更新 CHANGELOG
```

**分支间依赖处理**：
- 优先完成被依赖的分支，合回 main 后其他分支 rebase
- 紧急情况可 cherry-pick 单个 commit，但需在 commit message 中注明来源

**回退策略**：
- 分支开发中发现方向错误 → `git branch -D feat/xxx` 直接丢弃
- 已合并后发现问题 → `git revert -m 1 <merge-commit>` 回退整个合并
- 基线 tag（如 `v1.2.0-baseline`）是最后的安全网

---

## Commit 规范

格式：`类型: 中文描述`

| 类型 | 用途 | 示例 |
|------|------|------|
| feat | 新功能 | `feat: 新增油门灯效舞台模式` |
| fix | Bug 修复 | `fix: 修复断连后 PSRAM 泄漏` |
| refactor | 重构 | `refactor: 提取 ColorizeController` |
| docs | 文档 | `docs: 更新协议文档` |
| chore | 杂务 | `chore: 清理未使用 include` |
| perf | 性能 | `perf: LCD 行缓冲渲染` |
| test | 测试 | `test: 新增 AUDIO_STATUS 解析测试` |
| release | 发版 | `release: APP v1.0.0` |

**原则：**
- 一个逻辑完整的改动 = 一个 commit。不攒，改完就提。
- 改动涉及 ≥3 个文件或 ≥2 个模块时，必须写正文。
- 正文列出"改了哪些文件/模块"和"为什么这样改"。
- 每次对话结束前，如果有代码变更且用户确认满意，AI 主动提议 commit。
- 不相关的改动不混在一个 commit 里（删文件、加功能、改配置 = 分开提交）。

### Commit Message 模板

```
类型(范围): 标题 — 一句话说清楚做了什么

为什么做这个改动（背景/动机）：
- 原来的问题是什么
- 这次怎么解决的

改动内容：
- 文件1: 做了什么
- 文件2: 做了什么
- 文件3: 做了什么

影响范围：
- 是否影响协议兼容性：否
- 是否需要重新烧录固件：是/否
- 是否需要重新编译 APP：是/否
```

### 好的示例

```
fix(ble): 修复断连后 PSRAM 缓冲区泄漏 — Logo/Audio 上传中断连不释放内存

问题：
用户在 Logo 或 Audio 上传过程中断开蓝牙连接，ESP32 端的 PSRAM
缓冲区（最大 115KB）不会被释放，直到下次 *_START 命令才回收。
多次断连可能耗尽 PSRAM。

解决方案：
在 ble_service.c 的 ESP_GATTS_DISCONNECT_EVT 处理中，
主动调用 logo_rx_cleanup() 和 audio_rx_cleanup()。

改动文件：
- services/ble_service.c: DISCONNECT_EVT 增加 cleanup 调用
- main.c: logo_rx_cleanup/audio_rx_cleanup 改为非 static（供外部调用）

影响：不影响协议，不需要 APP 端改动。
```

```
feat(protocol): 新增协议版本握手 GET:VERSION — 防止 APP/固件版本不匹配

背景：
APP 和固件独立升级，用户可能出现"新 APP + 旧固件"的情况。
没有版本检查时，新 APP 发送旧固件不认识的命令会静默失败。

实现：
- ESP32 收到 GET:VERSION 回复 VERSION:fw=1.0.0:proto=1
- APP 连接后自动查询，proto 不匹配时弹窗提示升级
- 旧固件不认识 GET:VERSION 会忽略，APP 超时后静默兼容

改动文件：
- config/board_config.h: 新增 PROTOCOL_VERSION 定义
- services/protocol.c: 新增 CMD_GET_VERSION 解析
- main.c: dispatch 新增 VERSION 响应
- RideWind/lib/protocol/command_sender.dart: 新增 getVersion()
- RideWind/lib/providers/bluetooth_provider.dart: 连接后自动查询

影响：协议向后兼容（旧固件忽略新命令），不需要强制升级。
```

### 不好的示例（太简洁，没有信息量）

```
fix: 修复内存泄漏          ← 哪里泄漏？什么条件触发？改了什么？
feat: 加了版本检查          ← 怎么检查的？影响什么？
chore: 更新配置             ← 更新了什么配置？为什么？
```

---

## Release Checklist

### APP 发版（自动化流程）

发版现在只需 4 步，CI 自动完成构建、部署、版本更新：

```
□ flutter analyze — 零 error
□ 更新 pubspec.yaml 版本号 + build 号
□ 更新 CHANGELOG.md
□ git commit + tag + push：
    git add -A
    git commit -m "release: APP vX.Y.Z"
    git tag vX.Y.Z
    git push origin main --tags
```

**CI 自动完成**（无需手动操作）：
- ✅ flutter build apk --release
- ✅ 创建 GitHub Release + 上传 APK
- ✅ SCP 上传 APK 到阿里云服务器（国内加速）
- ✅ 验证阿里云部署是否成功
- ✅ 自动更新 app_version.json 并 push 回 main

**CI 需要的 GitHub Secrets**（一次性配置）：
- `DEPLOY_HOST` — 阿里云服务器 IP（47.107.143.4）
- `DEPLOY_SSH_KEY` — SSH 私钥（apk.pem 的内容）

### 固件发版（自动化流程）

固件发版与 APP 一样，CI 自动构建 + 创建 Release + 上传 .bin + 更新 firmware.json。
触发方式：推 `fw-vX.Y.Z` tag 即可。

```
□ idf.py build — 本地验证（可选，CI 会重跑）
□ idf.py size — flash 余量 >10%（CI 也会跑）
□ 更新 sdkconfig.defaults 中 CONFIG_APP_PROJECT_VER（必须与 tag 版本一致）
□ 更新 firmware.json 的 changelog 字段（size/sha256/download_url 由 CI 自动填）
□ 更新 CHANGELOG.md
□ git add -A
□ git commit -m "release: 固件 vX.Y.Z"
□ git tag fw-vX.Y.Z
□ git push origin main --tags
```

**CI 自动完成**（无需手工）：
- ✅ ESP-IDF Docker 镜像构建（`espressif/idf:release-v5.3`，缓存 managed_components + ccache）
- ✅ 校验 tag 版本号与 sdkconfig.defaults 一致（不一致直接 fail）
- ✅ 重命名 `ridewind-esp.bin` → `zcritical-fw-vX.Y.Z.bin`
- ✅ 创建 GitHub Release + 上传 .bin（OTA 端点可用）
- ✅ 自动用 jq 把准确 size / sha256 / download_url 写回 `firmware.json` 与 `RideWind/assets/firmware.json`
- ✅ 推送 firmware.json 更新回 main（commit message 带 `[skip ci]`）
- ✅ Telegram + 企业微信通知

**配置要求**（一次性）：
- 默认权限够用：`permissions: contents: write` 已在 workflow 里
- 可选：`RELEASE_BOT_TOKEN`（PAT），如果默认 GITHUB_TOKEN 推 main 受 branch protection 阻拦再加

**烧录验证**（CI 之外）：
- 用户从 Release 下载 .bin 烧录到实机，或等 OTA 自动推送
- 验证后回到工作流标记 release 状态

---

### 固件发版（旧的手工流程，已废弃）

> ⚠️ 仅在 CI 出问题时作为备用：

---

## APP 自动升级

`app_version.json` 结构：

```json
{
  "version": "1.0.0",
  "buildNumber": 1,
  "minSupportedVersion": "1.0.0",
  "downloadUrl": "https://github.com/.../releases/download/app-v1.0.0/ridewind-v1.0.0.apk",
  "changelog": "- 新增油门灯效\n- 修复断连问题",
  "releaseDate": "2026-05-21",
  "forceUpdate": false
}
```

- `forceUpdate: true` — 协议不兼容时强制升级
- `minSupportedVersion` — 低于此版本强制升级

---

## 环境区分

| 环境 | 构建 | 特征 |
|------|------|------|
| Debug | `flutter run` / `idf.py flash` | 有日志、有 debugPrint |
| Release | `flutter build apk --release` | 无调试日志、ProGuard 混淆 |

不搞 staging（单人 + 单硬件，无意义）。

---

## 紧急恢复

```bash
# 回退最近一次提交（保留文件变更）
git reset --soft HEAD~1

# 回退最近一次提交（丢弃文件变更）
git reset --hard HEAD~1

# 保存当前状态但不提交
git stash
git stash pop

# 创建安全快照
git tag snapshot-YYYYMMDD-描述
```

---

## AI 协作中的 Git 规则

### AI 可以直接做的
- commit（用户确认满意后）
- 创建分支
- 查看 diff/status/log
- push（常规推送）

### AI 不做的（需要用户明确确认）
- `git reset --hard`（不可逆）
- `git force-push`（覆盖远程历史）
- `git branch -D`（删除分支）

### 每次对话结束前的 Git 自检
- [ ] 有未提交的代码变更吗？→ 建议提交
- [ ] 变更是否可编译？→ 不可编译不提交
- [ ] CONTINUATION_GUIDE.md 是否需要更新？
