---
inclusion: manual
---

# 发布流程（Release Workflow）

## 版本号规范

- App 版本：`pubspec.yaml` → `version: X.Y.Z+N`（X.Y.Z 用户可见，+N 构建号递增）
- 固件版本：`board_config.h` 或 `version.h` → `FW_VERSION_STRING "X.Y.Z"`
- Git Tag：`vX.Y.Z`（和 App 版本号一致）

## 发布新版本（AI 可执行）

当用户说"发布版本"或"打包演示版"时，执行以下步骤：

### Step 1：确认版本号
```bash
# 查看当前版本
grep "version:" RideWind/pubspec.yaml
```
如果需要升版本，修改 `pubspec.yaml` 的 `version` 字段。

### Step 2：编译 APK
```bash
cd RideWind
flutter build apk --release
# 产物在 build/app/outputs/flutter-apk/app-release.apk
```

### Step 3：编译固件
```bash
cd ridewind-esp
idf.py app
# 产物在 build/ridewind-esp.bin
```

### Step 4：Git Tag
```bash
git add -A
git commit -m "release: vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

### Step 5：GitHub Release
```bash
gh release create vX.Y.Z \
  RideWind/build/app/outputs/flutter-apk/app-release.apk \
  ridewind-esp/build/ridewind-esp.bin \
  --title "vX.Y.Z" \
  --notes "更新内容：xxx"
```
（如果没装 gh CLI，手动在 GitHub 网页创建 Release 上传文件）

### Step 6：更新 app_version.json
```json
{
  "latest_version": "X.Y.Z",
  "latest_build": N,
  "min_version": "1.0.0",
  "download_url": "https://github.com/SunnyKlara/Zcritical/releases/download/vX.Y.Z/app-release.apk",
  "release_notes": "更新内容",
  "force_update": false
}
```
然后 push：
```bash
git add RideWind/app_version.json
git commit -m "update: app_version.json → vX.Y.Z"
git push
```

## 演示版使用

- 需要演示时：从 GitHub Releases 页面下载对应版本的 APK
- 需要回到演示版代码：`git checkout vX.Y.Z`
- 回到最新开发：`git checkout main`

## App 自动升级

- App 启动时自动检查 `app_version.json`（GitHub raw URL）
- 有新版本 → 弹窗提示 → 下载 APK → 安装
- 代码：`RideWind/lib/services/update_service.dart`
- 版本信息：`RideWind/app_version.json`
- GitHub 地址：`https://raw.githubusercontent.com/SunnyKlara/Zcritical/main/RideWind/app_version.json`

## 注意事项

- 每次 Release 的 `+N` 构建号必须递增（Google Play 要求）
- Tag 打了就不要删（用户可能在用那个版本）
- `force_update: true` 只在有安全漏洞时使用
- 固件和 App 版本号建议同步（方便追踪兼容性）
