---
inclusion: manual
---

# Release Playbook — 实操经验记录

> 本文件记录发版完整流程，供后续发版参考。

## 前置条件

- `gh` CLI 已安装（`winget install GitHub.cli`）
- `gh auth login` 已完成
- Flutter SDK 可用（当前 3.41.6）
- SSH 密钥：`C:\Users\Klara\Downloads\apk.pem`
- 阿里云服务器：`47.107.143.4`（APK 分发）

## APP 发版完整流程

```powershell
# ═══ 1. 更新版本号 ═══
# RideWind/pubspec.yaml → version: X.Y.Z+BUILD
# RideWind/app_version.json → 更新 latest_version + download_url

# ═══ 2. 构建 Release APK ═══
cd RideWind
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk

# ═══ 3. 重命名 APK ═══
copy build\app\outputs\flutter-apk\app-release.apk build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk

# ═══ 4. 上传 APK 到阿里云服务器（国内加速） ═══
scp -i "C:\Users\Klara\Downloads\apk.pem" "build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk" root@47.107.143.4:/www/wwwroot/sunnyklara.com/releases/

# ═══ 5. 验证下载链接 ═══
# 浏览器访问: http://47.107.143.4/releases/ridewind-vX.Y.Z.apk

# ═══ 6. 更新 app_version.json ═══
# download_url → http://47.107.143.4/releases/ridewind-vX.Y.Z.apk
# latest_version → X.Y.Z

# ═══ 7. Commit + Tag + Push ═══
cd ..
git add RideWind/pubspec.yaml RideWind/app_version.json
git commit -m "release: APP vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags

# ═══ 8. 创建 GitHub Release（备份） ═══
gh release create vX.Y.Z --title "vX.Y.Z — 标题" --notes "Release notes"
gh release upload vX.Y.Z "RideWind\build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk" --clobber
```

## 关键路径

| 用途 | 路径/地址 |
|------|-----------|
| APK 产物 | `RideWind/build/app/outputs/flutter-apk/app-release.apk` |
| 版本配置 | `RideWind/pubspec.yaml` |
| 自动升级配置 | `RideWind/app_version.json` |
| **APK 下载地址** | `http://47.107.143.4/releases/ridewind-vX.Y.Z.apk` |
| 服务器 APK 目录 | `/www/wwwroot/sunnyklara.com/releases/` |
| SSH 密钥 | `C:\Users\Klara\Downloads\apk.pem` |
| GitHub Release | `https://github.com/SunnyKlara/Zcritical/releases` |
| 版本检测 URL | `https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json` |

## app_version.json 格式

```json
{
  "latest_version": "X.Y.Z",
  "latest_build": N,
  "min_version": "1.0.0",
  "download_url": "http://47.107.143.4/releases/ridewind-vX.Y.Z.apk",
  "release_notes": "更新内容...",
  "force_update": false,
  "version": "X.Y.Z",
  "buildNumber": N,
  "minSupportedVersion": "1.0.0",
  "downloadUrl": "http://47.107.143.4/releases/ridewind-vX.Y.Z.apk",
  "changelog": "更新内容...",
  "releaseDate": "YYYY-MM-DD",
  "forceUpdate": false
}
```

> ⚠️ 必须同时包含 snake_case 和 camelCase 字段（兼容两个 UpdateService）

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
| GitHub Releases 国内下载极慢/超时 | APK 放阿里云服务器，国内直连 |
| `app_version.json` 字段名不匹配 | 同时包含 snake_case 和 camelCase |
| nginx 404（IP 访问走错 server block） | APK 放 `/www/wwwroot/sunnyklara.com/releases/`（IP 对应的 root） |
| GitHub raw 缓存延迟 | 等 5-10 分钟，或用 `?t=timestamp` 参数 |
| SSH Permission denied | 用密钥：`ssh -i apk.pem root@47.107.143.4` |
| APK 体积 165MB | 含 car_thumbnails 资源，后续可用 `--split-per-abi` 减小 |

## 自动更新触发条件

- APP 在 `device_connect_screen` 连接设备后自动检查
- 从 GitHub raw 读取 `app_version.json`
- 比较 `latest_version` 和本地 `PackageInfo.version`
- 新版本 → 弹窗提示 → 用户点"立即更新" → 从阿里云下载 APK → 安装
