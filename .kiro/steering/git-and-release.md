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

**原则：一个逻辑完整的改动 = 一个 commit。**

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
