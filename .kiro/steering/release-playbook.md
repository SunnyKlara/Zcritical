---
inclusion: manual
---

# Release Playbook — 实操经验记录

> 本文件记录发版完整流程，供后续发版参考。
> v2 — 2026-05-24 重写：CI 全自动化，手动步骤降到最少。

## 前置条件

- `gh` CLI 已安装（`winget install GitHub.cli`）
- `gh auth login` 已完成
- Flutter SDK 可用（当前 3.41.6）
- GitHub Secrets 已配置（见下方"一次性配置"）

## 一次性配置（只需做一次）

在 GitHub 仓库 Settings → Secrets and variables → Actions 中添加：

### Android + 部署

| Secret 名称 | 值 | 说明 |
|---|---|---|
| `DEPLOY_HOST` | `47.107.143.4` | 阿里云服务器 IP |
| `DEPLOY_SSH_KEY` | apk.pem 文件的完整内容 | SSH 私钥（用于 SCP 上传） |
| `KEYSTORE_BASE64` | .jks 文件 base64 编码 | Android 签名密钥库 |
| `KEYSTORE_STORE_PASSWORD` | 密钥库密码 | |
| `KEYSTORE_KEY_PASSWORD` | 密钥密码 | |
| `KEYSTORE_KEY_ALIAS` | 密钥别名 | |

### iOS（App Store Connect API 自动签名）

| Secret 名称 | 值 | 说明 |
|---|---|---|
| `APPSTORE_CONNECT_API_KEY_ID` | Key ID（如 `5W432BL26V`） | App Store Connect → 用户和访问 → 集成 → 密钥 |
| `APPSTORE_CONNECT_ISSUER_ID` | Issuer ID（UUID 格式） | 同一页面顶部 |
| `APPSTORE_CONNECT_API_KEY` | `.p8` 文件完整内容（含 BEGIN/END 行） | 创建 Key 时下载，只能下载一次 |

**iOS 签名说明**：
- 使用 App Store Connect API 自动签名，**不需要** .p12 证书或 .mobileprovision 文件
- Xcode 通过 API Key 自动创建/下载证书和 provisioning profile
- API Key 必须有 **Admin** 或 **App Manager** 权限
- 证书过期时 Xcode 自动续期，无需手动干预
- Runner 使用 `macos-26`（Xcode 26 + iOS 26 SDK，Apple 2026 年起强制要求）

## APP 发版流程（4 步完成）

```powershell
# ═══ 1. 更新版本号 ═══
# 编辑 RideWind/pubspec.yaml → version: X.Y.Z+BUILD

# ═══ 2. 更新 CHANGELOG.md ═══
# 记录本次变更内容

# ═══ 3. Commit（必须遵守 git-and-release.md 的 commit 规范） ═══
# 先分析变更：
git diff --stat
# 根据 diff 结果，按 git-and-release.md 的模板写完整 commit message：
# - 标题行：类型(范围): 描述
# - 正文：背景/改动文件/影响范围（≥3 文件时必须写）
# - 不相关改动必须拆分成多个 commit
git add -A
git commit  # 用编辑器写完整 message，不要用 -m 一行带过

# ═══ 4. Tag + Push（触发 CI 全自动流程） ═══
git tag vX.Y.Z
git push origin main --tags
```

**⚠️ 关键规则（来自 git-and-release.md）**：
- 改动 ≥3 文件或 ≥2 模块时，commit message **必须写正文**
- 正文必须列出改了哪些文件/模块 + 为什么这样改
- 不相关的改动不混在一个 commit 里（拆分提交）
- commit 前必须 `git diff --stat` 确认实际变更范围

**就这样。** 推送 tag 后 CI 自动完成：

### Android 流程
1. `flutter analyze` 代码检查
2. `flutter build apk --release --split-per-abi` 构建（按 ABI 分包）
3. 创建 GitHub Release + 上传 APK
4. SCP 上传 APK 到阿里云（国内加速）
5. 验证阿里云部署
6. 自动更新 `app_version.json` 并 push 回 main（`[skip ci]` 避免循环触发）

### iOS 流程
1. `flutter build ios --release --no-codesign`（生成 Xcode 项目）
2. `xcodebuild archive` + App Store Connect API Key 自动签名
3. `xcodebuild -exportArchive` 直接上传 IPA 到 TestFlight
4. 用户在 TestFlight 中即可测试

### 通知
7. Telegram 通知
8. 企业微信通知

## CI 完成后验证

```powershell
# 拉取 CI 自动更新的 app_version.json
git pull

# 验证阿里云下载
curl -I http://47.107.143.4/releases/ridewind-vX.Y.Z.apk
# 应返回 200 OK

# 验证 GitHub Release
gh release view vX.Y.Z
```

## 紧急手动发版（CI 不可用时的 fallback）

```powershell
# 本地构建
cd RideWind
flutter build apk --release

# 重命名
copy build\app\outputs\flutter-apk\app-release.apk build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk

# 上传到阿里云
scp -i "C:\Users\Klara\Downloads\apk.pem" "build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk" root@47.107.143.4:/www/wwwroot/sunnyklara.com/releases/

# 手动更新 app_version.json
# 编辑 RideWind/app_version.json，更新 version + download_url + changelog

# 创建 GitHub Release
gh release create vX.Y.Z --title "vX.Y.Z — 标题" --notes "Release notes"
gh release upload vX.Y.Z "RideWind\build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk" --clobber

# Push
git add RideWind/app_version.json
git commit -m "chore(release): manual update app_version.json for vX.Y.Z"
git push origin main
```

## 关键路径

| 用途 | 路径/地址 |
|------|-----------|
| APK 产物 | `RideWind/build/app/outputs/flutter-apk/app-release.apk` |
| 版本配置 | `RideWind/pubspec.yaml` |
| 自动升级配置 | `RideWind/app_version.json`（CI 自动更新） |
| **APK 下载地址（主）** | `http://47.107.143.4/releases/ridewind-vX.Y.Z.apk` |
| **APK 下载地址（备）** | `https://github.com/SunnyKlara/Zcritical/releases/download/vX.Y.Z/ridewind-vX.Y.Z.apk` |
| 服务器 APK 目录 | `/www/wwwroot/sunnyklara.com/releases/` |
| SSH 密钥 | `C:\Users\Klara\Downloads\apk.pem` |
| GitHub Release | `https://github.com/SunnyKlara/Zcritical/releases` |
| 版本检测 URL（主） | `https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json` |
| 版本检测 URL（备） | `https://cdn.jsdelivr.net/gh/SunnyKlara/Zcritical@main/RideWind/app_version.json` |

## app_version.json 格式

```json
{
  "latest_version": "X.Y.Z",
  "latest_build": N,
  "min_version": "1.0.0",
  "download_url": "http://47.107.143.4/releases/ridewind-vX.Y.Z.apk",
  "fallback_download_url": "https://github.com/SunnyKlara/Zcritical/releases/download/vX.Y.Z/ridewind-vX.Y.Z.apk",
  "ios_app_store_url": "",
  "release_notes": "更新内容...",
  "force_update": false,
  "version": "X.Y.Z",
  "buildNumber": N,
  "minSupportedVersion": "1.0.0",
  "downloadUrl": "http://47.107.143.4/releases/ridewind-vX.Y.Z.apk",
  "fallbackDownloadUrl": "https://github.com/SunnyKlara/Zcritical/releases/download/vX.Y.Z/ridewind-vX.Y.Z.apk",
  "changelog": "更新内容...",
  "releaseDate": "YYYY-MM-DD",
  "forceUpdate": false
}
```

> ⚠️ 必须同时包含 snake_case 和 camelCase 字段（兼容两个 UpdateService）
> ⚠️ `fallback_download_url` 是新增字段，APP 主地址下载失败时自动尝试此地址

## 自动更新容错机制（APP 端）

APP 更新检测和下载都有多重容错：

| 环节 | 主 | 备用 | 说明 |
|------|-----|------|------|
| 版本检测 | GitHub raw | jsdelivr CDN | 国内 GitHub raw 偶尔超时 |
| APK 下载 | 阿里云服务器 | GitHub Release | 阿里云挂了自动切 GitHub |
| 文件验证 | 检查 APK 大小 ≥1MB | — | 防止下载到 404 HTML 页面 |

## 服务器信息

| 项目 | 值 |
|------|-----|
| IP | 47.107.143.4 |
| 系统 | Alibaba Cloud Linux 3.21.04 |
| 带宽 | 200 Mbps |
| Web 服务 | nginx 1.26.1 |
| SSH 用户 | root（密钥登录） |
| APK 目录 | `/www/wwwroot/sunnyklara.com/releases/` |
| nginx server_name | `sunnyklara.com www.sunnyklara.com 47.107.143.4` |

## 踩坑记录

| 问题 | 解决方案 |
|------|----------|
| **iOS 手动签名证书和 profile 不匹配** | 彻底放弃手动签名，改用 App Store Connect API 自动签名 |
| **iOS API Key 401 认证失败** | `.p8` 文件内容粘贴到 GitHub Secret 时格式损坏，重新创建 Key 解决 |
| **iOS SDK 版本不满足 Apple 要求** | 2026 年起 Apple 要求 iOS 26 SDK，改用 `macos-26` runner（含 Xcode 26） |
| **exportArchive destination:upload 不生成本地 IPA** | 设置 `destination: upload` 时 xcodebuild 直接上传，不需要 cp 本地文件 |
| **tag 命名不匹配 CI 触发条件** | CI 现在兼容 `v*` 和 `app-v*`，统一用 `vX.Y.Z` |
| **手动步骤太多容易遗漏** | CI 全自动：构建→部署→更新 version.json |
| **app_version.json 忘记更新** | CI 自动更新并 push 回 main |
| **APK 没上传到服务器** | CI 自动 SCP + 验证 HTTP 200 |
| GitHub Releases 国内下载极慢 | APK 放阿里云，GitHub 作为 fallback |
| `app_version.json` 字段名不匹配 | 同时包含 snake_case 和 camelCase |
| nginx 404（IP 访问走错 server block） | APK 放 `/www/wwwroot/sunnyklara.com/releases/` |
| GitHub raw 缓存延迟 | APP 端加了 jsdelivr CDN 备用 |
| SSH Permission denied | 用密钥：`ssh -i apk.pem root@47.107.143.4` |
| APK 体积 165MB | 含 car_thumbnails 资源，后续用 `--split-per-abi` 减小 |
| **下载地址 404 用户报错** | APP 端自动 fallback 到 GitHub Release |
