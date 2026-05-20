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
- **feature/xxx** — 仅大改（预计 >3 天）时开，完成即合并删除
- 不搞 develop / release / hotfix

### Tag 命名

```
app-v1.0.0    — APP 发版
fw-v1.0.0     — 固件发版
v1.0.0        — 联合发版（协议变更时）
```

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

### APP 发版

```
□ flutter analyze — 零 error
□ flutter test test/protocol/ — 全部通过
□ 更新 pubspec.yaml 版本号 + build 号
□ 更新 CHANGELOG.md
□ git commit -m "release: APP vX.Y.Z"
□ git tag app-vX.Y.Z
□ flutter build apk --release
□ 上传 APK 到 GitHub Release
□ 更新 app_version.json（触发自动升级）
□ git push && git push --tags
```

### 固件发版

```
□ idf.py build — 零 error 零 warning
□ idf.py size — flash 余量 >10%
□ 更新 sdkconfig.defaults 中 CONFIG_APP_PROJECT_VER
□ 更新 CHANGELOG.md
□ git commit -m "release: 固件 vX.Y.Z"
□ git tag fw-vX.Y.Z
□ 烧录实机验证核心功能
□ 上传 .bin 到 GitHub Release（OTA 分发）
□ git push && git push --tags
```

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
