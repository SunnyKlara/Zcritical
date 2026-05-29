---
inclusion: manual
---

# 双机协作工作流（单人 · 双 Windows 主机轮换）

> 本文件适用场景：**同一个人，在两台 Windows 电脑之间轮换开发**（A 机为主，B 机为辅或备机），两台都装了 Kiro + ESP-IDF + Flutter + Android Studio。
>
> 与 `cross-platform-workflow.md` 区别：那份是 Windows 主机 + Mac iOS 构建机（异构、分工），本份是同构主机轮换（同质、防错位）。

## 核心原则（两条铁律）

1. **Git 是唯一同步通道**。不开 OneDrive / 网盘 / Syncthing 同步项目目录——任何同步工具碰到 `.git/` 都会损坏仓库。
2. **任意时刻只有一台机器在"工作中"**。另一台必须关掉 Kiro 和 IDE，或者至少明确意识到自己处于"待机"状态。

---

## 切机仪式（必须形成肌肉记忆）

### 离开 A 机前（关机仪式 · 1 分钟）

无论开发是否完成，**必须 push**：

```cmd
git status
git add .
git commit -m "wip: 切机前快照-当前在做xxx"
git push origin main
```

> Commit message 用中文（项目铁律），`wip:` 前缀表示半成品，回到另一台后可以 `git reset --soft HEAD~1` 撤回继续编辑，最后再合成正式 commit。

**额外动作**（如果当前进展影响下一阶段）：
- 更新 `CONTINUATION_GUIDE.md` 的"当前进行中"段落，写清楚你停在哪一步
- 这比 commit message 更直观，AI 在另一台启动时能立即接上

### 到达 B 机后（开机仪式 · 30 秒）

```cmd
git status         # 必须干净，不干净说明上次离开时漏了 push
git pull origin main
```

如果 `git status` 不干净：
- **不要直接 pull**——先把本地未提交的东西处理掉（commit 或 stash）
- 通常这是上次在 B 机做了未推送的改动 → 检查这些改动还要不要，要就 commit + push，不要就 `git stash` 或 `git checkout .`

---

## 项目特定的注意点

### 1. Kiro 配置：哪些进 Git，哪些不进

| 路径 | 进 Git？ | 说明 |
|------|---------|------|
| `.kiro/steering/` | ✅ | AI 行为规范，两机必须一致 |
| `.kiro/specs/` | ✅ | spec 三件套，历史决策依据 |
| `.kiro/reference/` | ✅ | 参考资料 |
| `CONTINUATION_GUIDE.md` | ✅ | session handoff，**每次切机前更新** |
| `.kiro/cache/` `.kiro/logs/` `.kiro/.tmp/` | ❌ | 本地缓存 |
| `~/AppData/Roaming/Kiro/User/settings.json` | ❌（不在 repo 内） | Kiro 用户级配置，两台分别配 |
| `~/.kiro/settings/mcp.json` | ❌ | MCP 服务器配置，两台分别配 |
| 任意 hook（`.kiro/hooks/`） | ✅ | hook 是项目级的，要同步 |

### 2. ESP-IDF 端口差异

两台电脑 ESP32 的 COM 口不一样（A 机可能是 COM3，B 机可能是 COM5）。

- `sdkconfig` 进 Git，保持构建一致
- 烧录端口走命令行参数：`idf.py -p COMx flash`，不固化在文件里
- `.vscode/settings.json` 里的 `idf.portWin` 是本机配置——如果两台冲突，**保留本机版本**，不要 commit 错误的端口
- 推荐：把 `.vscode/settings.json` 中只与端口相关的字段提取到 `.vscode/settings.local.json`（gitignore），项目共享配置留在 `settings.json`

### 3. Flutter / Android 本地状态

**绝对不进 Git**（确认 `.gitignore` 已包含）：

```
RideWind/.dart_tool/
RideWind/build/
RideWind/android/.gradle/
RideWind/android/local.properties      ← 含本机 Android SDK 路径
RideWind/ios/Pods/
ridewind-esp/build/
ridewind-esp/managed_components/       ← 视情况，IDF 5.x 一般可保留
```

**B 机首次 pull 后**：
```cmd
cd RideWind
flutter pub get
cd ..\ridewind-esp
idf.py reconfigure
```

### 4. Git LFS（项目已使用）

新机器或全新 clone 后**必须**：
```cmd
git lfs install
git lfs pull
```
否则 GLB 模型 / 音频 / 字体 / 固件包等大文件只是指针，编译会失败。

### 5. 签名与密钥（永远不进 Git）

| 文件 | 处理方式 |
|------|---------|
| Android keystore (`*.jks`) | 私密渠道传输，两台各放一份本地副本 |
| `RideWind/android/key.properties` | 同上 |
| 任何 `.env` / API key / token | 同上 |
| ESP32 烧录的 device_id | 物理唯一，与代码无关，不需要同步 |

建议在密码管理器（1Password / Bitwarden）里存一份这些文件的备份。

### 6. SSH key

两台电脑分别生成 SSH key，分别加到 GitHub。**不要复制 SSH 私钥**——这是基础安全卫生。

```cmd
ssh-keygen -t ed25519 -C "klara-machine-b"
```

---

## 不推荐的方案（避坑清单）

| 方案 | 为什么不推荐 |
|------|-------------|
| OneDrive / iCloud / Dropbox 同步整个项目目录 | `.git/` 索引被并发写入会损坏仓库——血泪级踩坑 |
| Syncthing 同步项目 | 同上，且即使排除 `.git/` 也会和 Git 抢节奏 |
| 网络共享盘开发 | I/O 慢，IDE 索引炸，编译时间翻倍 |
| 两台同时打开 Kiro 改同一 spec | AI 各改一半，merge 时无法挽救 |
| 复制 SSH 私钥到第二台 | 基础安全卫生问题 |
| 用 `git push --force` 解决冲突 | 会丢另一台的改动；**单人双机更要避免** |

---

## 常见冲突场景与处理

### 场景 1：忘了在 A 机 push，跑去 B 机继续改

**症状**：B 机改完准备 push 时发现 A 机有未推送的 commit（实际上是本地未推送的改动）。

**处理**：
- 如果 A 机还能开机 → 回 A 机 push，B 机 pull 合并
- 如果 A 机暂时不可用 → B 机继续工作并 push，等 A 机恢复后用 `git pull --rebase` 把 A 机本地未推送的改动 rebase 到 B 机已推送的之上

### 场景 2：两台都有未推送 commit

**处理**：
```cmd
# 在后启动的那台
git pull --rebase origin main
# 如有冲突，手动解决（看 <<<< ==== >>>> 标记）
git rebase --continue
git push origin main
```

### 场景 3：CONTINUATION_GUIDE.md 在两台上都改过

最容易冲突的文件就是它。建议规则：**只在切机前更新一次**，不在工作过程中频繁改。冲突了就保留双方内容手工合并，时间戳新的为准。

### 场景 4：Kiro 在 B 机上不知道项目状态

正常情况——`.kiro/steering/START-HERE.md` 和 `CONTINUATION_GUIDE.md` 进 Git 就是为了让 AI 在任何机器上都能 5 分钟内进入状态。如果发现 AI 状态错乱，检查这两个文件是否已同步。

---

## 推荐工具（可选）

| 工具 | 用途 | 必要性 |
|------|------|-------|
| Tailscale | 两台电脑组虚拟内网，方便 SSH/远程桌面 | ⭐⭐⭐ 强烈推荐 |
| GitHub | 代码同步 | ⭐⭐⭐ 已在用 |
| 1Password / Bitwarden | 存 keystore / .env / SSH passphrase | ⭐⭐ 推荐 |
| VS Code Remote SSH | 偶尔从 B 机远程编辑 A 机的文件 | ⭐ 按需 |

---

## 推荐的全局 Git 配置（两台都设）

```cmd
git config --global pull.rebase true          :: pull 默认 rebase，history 干净
git config --global push.default current      :: push 默认推当前分支
git config --global core.autocrlf true        :: Windows 行尾正确处理
git config --global rebase.autostash true     :: rebase 时自动 stash
```

---

## 最小可执行 checklist（贴在显示器上）

```
离开 A 机：
  □ git status 干净？
  □ git add . && git commit -m "wip: ..."
  □ git push origin main
  □ 更新 CONTINUATION_GUIDE.md（如有进展）
  □ 关掉 Kiro 和 IDE

到达 B 机：
  □ git pull origin main
  □ 看一眼 CONTINUATION_GUIDE.md 当前状态
  □ 如有依赖更新：flutter pub get / idf.py reconfigure
```

---

## AI 协作注意事项（给 Kiro 自己看）

- 双机场景下，**用户的状态可能不在你看到的最新 commit 里**——优先读 `CONTINUATION_GUIDE.md`
- 如果发现工作区有大量未提交改动（`git status` > 10 个修改），且用户提到要切机，**主动提醒用户先 push**
- 切勿在用户即将切机时启动跨多文件的大重构——很容易留一半未推送的烂摊子
- 跨平台改动检查清单（同 `cross-platform-workflow.md`）：新增权限 / 新增 native 插件 / 改 BLE 逻辑时，提醒用户在另一台 Windows 上重新 `flutter pub get`
