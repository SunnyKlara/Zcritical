---
inclusion: manual
---

# Release Playbook — 实操经验记录

> 本文件记录 v1.0.0 发版时跑通的完整流程，供后续发版自动化参考。

## 前置条件

- `gh` CLI 已安装（`winget install GitHub.cli`）
- `gh auth login` 已完成（浏览器 OAuth 流程，token 存 keyring）
- Flutter SDK 可用（当前 3.41.6）
- Android SDK 可用（Gradle 构建 release APK）

## APP 发版完整命令序列

```powershell
# 0. 设置 PATH（新安装的工具可能不在当前 session PATH 中）
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# 1. 更新版本号
# - RideWind/pubspec.yaml → version: X.Y.Z+BUILD
# - CHANGELOG.md → 新增版本条目

# 2. Commit 版本变更
git add RideWind/pubspec.yaml CHANGELOG.md
git commit -m "release: APP vX.Y.Z"

# 3. 打 tag
git tag app-vX.Y.Z
# 或联合发版用 git tag vX.Y.Z

# 4. 构建 Release APK
cd RideWind
flutter clean
flutter pub get
flutter build apk --release
# 产物: build\app\outputs\flutter-apk\app-release.apk (约 74MB)
# ⚠️ "Building with plugins requires symlink support" 警告可忽略，不影响 APK 构建

# 5. 重命名 APK
copy build\app\outputs\flutter-apk\app-release.apk build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk

# 6. 创建 GitHub Release + 上传 APK
gh release create vX.Y.Z --title "vX.Y.Z — 标题" --notes "Release notes 内容"
gh release upload vX.Y.Z "build\app\outputs\flutter-apk\ridewind-vX.Y.Z.apk" --clobber

# 7. 更新 app_version.json（触发 APP 自动升级检测）
# downloadUrl → https://github.com/SunnyKlara/Zcritical/releases/download/vX.Y.Z/ridewind-vX.Y.Z.apk

# 8. Commit + Push
git add RideWind/app_version.json
git commit -m "chore: 更新 app_version.json 下载链接 → vX.Y.Z"
git push origin main --tags
```

## 踩坑记录

| 问题 | 解决方案 |
|------|----------|
| `gh` 未安装 | `winget install GitHub.cli` 一行搞定 |
| `gh` 安装后当前 session 找不到 | 刷新 PATH：`$env:Path = [System.Environment]::GetEnvironmentVariable(...)` |
| `gh auth login` 需要交互 | 用 `--web` 走浏览器 OAuth，复制 one-time code 到 github.com/login/device |
| `git push` 网络超时 | GitHub 443 端口偶发连接重置，重试即可（可能是 VPN/防火墙） |
| `flutter pub get` 报 symlink 错误 | 需要 Windows Developer Mode，但不影响 APK 构建 |
| `flutter build apk` Java 警告 | "源值 8 已过时" 是 Gradle 兼容性警告，不影响产物 |
| APK 体积 74MB | 正常（含 Flutter engine + 所有 assets），后续可用 `--split-per-abi` 减小 |

## 关键路径

| 用途 | 路径 |
|------|------|
| APK 产物 | `RideWind/build/app/outputs/flutter-apk/app-release.apk` |
| 版本配置 | `RideWind/pubspec.yaml` |
| 自动升级配置 | `RideWind/app_version.json` |
| Release 地址 | `https://github.com/SunnyKlara/Zcritical/releases` |

## gh CLI 常用命令速查

```powershell
gh auth status                    # 查看登录状态
gh release list                   # 列出所有 release
gh release create TAG --title T --notes N   # 创建 release
gh release upload TAG FILE --clobber        # 上传/覆盖附件
gh release delete TAG --yes                 # 删除 release
gh release view TAG                         # 查看 release 详情
```
