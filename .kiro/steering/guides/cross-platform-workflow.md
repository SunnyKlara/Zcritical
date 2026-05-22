---
inclusion: manual
---

# 跨平台协作工作流（Windows + Mac）

## 概述

本项目在 Windows 上主力开发，Mac 负责 iOS 构建和测试。通过 Git（GitHub）实时同步代码，不需要打包传文件。

## 环境分工

| 平台 | 职责 | 工具链 |
|------|------|--------|
| Windows | 主力开发、ESP32 编译烧录、Android 构建测试 | Kiro/VS Code + ESP-IDF + Flutter + Android Studio |
| Mac | iOS 构建测试、App Store 发布、签名管理 | Xcode + Flutter + CocoaPods |

## 远程仓库

```
origin: git@github.com:SunnyKlara/Zcritical.git
分支策略: main 为唯一长期分支（详见 git-and-release.md）
```

---

## 日常协作流程

### Windows 端（主力开发）

```bash
# 开始工作前（如果 Mac 上有过改动）
git pull origin main

# 正常开发...

# 开发完成
git add .
git commit -m "feat(app): 描述"
git push origin main
```

### Mac 端（iOS 构建测试）

```bash
# 拉取最新代码
git pull origin main

# 恢复依赖（有新依赖时才需要）
cd RideWind
flutter pub get
cd ios && pod install && cd ..

# 运行 iOS
flutter run                          # iPhone 真机
flutter build ios --no-codesign      # 仅验证编译
flutter build ipa                    # 生成可分发包（需签名）

# 如果在 Mac 上修了 iOS 特有 bug
git add .
git commit -m "fix(ios): 描述"
git push origin main
```

### 核心规则

1. **改代码前先 pull** — 避免冲突
2. **改完立刻 push** — 保持两端同步
3. **不要两边同时改同一个文件** — 单人开发无需 branch 隔离
4. **Mac 上的改动仅限 iOS 特有问题** — 主力开发在 Windows

---

## Mac 端初始化（一次性）

### 1. 克隆仓库

```bash
git clone git@github.com:SunnyKlara/Zcritical.git
cd Zcritical
```

### 2. 安装 Flutter

```bash
brew install flutter
flutter doctor    # 确认 Xcode、CocoaPods 正常
```

### 3. 初始化 iOS 项目

```bash
cd RideWind
flutter pub get
cd ios
pod install
cd ..
flutter build ios --no-codesign    # 验证编译通过
```

### 4. ESP-IDF（可选，Mac 也能编译固件）

```bash
# 如果需要在 Mac 上编译/烧录 ESP32
# 参考: https://docs.espressif.com/projects/esp-idf/en/v5.3.5/esp32s3/get-started/
brew install cmake ninja dfu-util
# 然后按官方文档安装 ESP-IDF v5.3.5
```

---

## iOS 签名与证书

### 开发阶段（免费）

- 用个人 Apple ID 即可
- Xcode → Signing & Capabilities → 选择 Personal Team
- 限制：7 天过期，最多 3 台设备

### 发布阶段（付费）

- 需要 Apple Developer Program（¥688/年）
- Xcode 自动管理证书和 Provisioning Profile
- 证书存在 Mac Keychain 中，**不提交 Git**

### 签名相关文件

| 文件 | 提交 Git？ | 说明 |
|------|-----------|------|
| `ios/Runner.xcodeproj/project.pbxproj` | ✅ | 项目配置（含签名 Team ID） |
| `ios/Runner/Info.plist` | ✅ | 权限声明 |
| `ios/Podfile` | ✅ | CocoaPods 依赖 |
| `ios/Podfile.lock` | ✅ | 锁定版本 |
| `ios/Pods/` | ❌ | pod install 生成 |
| `*.p12` / `*.mobileprovision` | ❌ 绝对不提交 | 证书/描述文件 |

---

## 文件同步注意事项

### 已在 .gitignore 中排除的平台文件

```
# iOS 生成文件（已配置）
RideWind/ios/Flutter/Generated.xcconfig
RideWind/ios/Flutter/flutter_export_environment.sh
RideWind/ios/Pods/
RideWind/macos/Flutter/ephemeral/
RideWind/macos/Pods/

# Android 生成文件（已配置）
RideWind/android/.gradle/
RideWind/android/build/
```

### 平台特有代码位置

| 平台 | 路径 | 说明 |
|------|------|------|
| Android 原生 | `RideWind/android/app/src/main/kotlin/` | AudioCaptureService 等 |
| iOS 原生 | `RideWind/ios/Runner/` | AppDelegate、Info.plist |
| 共享 Dart | `RideWind/lib/` | 所有业务逻辑 |

---

## 常见问题处理

### Q: Mac pull 后 pod install 报错

```bash
cd RideWind/ios
rm -rf Pods Podfile.lock
pod install --repo-update
```

### Q: Mac 上 flutter pub get 版本冲突

```bash
flutter clean
flutter pub get
```

### Q: 两边同时改了同一个文件产生冲突

```bash
# 在后 push 的那一端
git pull origin main
# 手动解决冲突（看 <<<< ==== >>>> 标记）
git add .
git commit -m "fix: 解决合并冲突"
git push origin main
```

### Q: Mac 上 Xcode 签名报错

1. Xcode → Preferences → Accounts → 确认 Apple ID 已登录
2. Runner target → Signing & Capabilities → 勾选 Automatically manage signing
3. 选择正确的 Team

### Q: 大文件（car_thumbnails）同步慢

这些 PNG 已在 .gitignore 中排除。Mac 端如需要：
```bash
cd RideWind
python tools/fetch_fh5_thumbnails.py    # 如果有此脚本
# 或手动从 Windows 拷贝 assets/car_thumbnails/ 到 Mac
```

---

## 进阶：自动化构建（可选）

### 方案 A：Mac 上的快捷脚本

```bash
#!/bin/bash
# ~/scripts/ridewind_ios_build.sh
cd ~/Zcritical/RideWind
git pull origin main
flutter pub get
cd ios && pod install && cd ..
flutter build ios --no-codesign
echo "✅ iOS 构建完成: $(date)"
```

### 方案 B：GitHub Actions + 自托管 Mac Runner

适合频繁发版时使用，push 后自动在 Mac 上构建：

```yaml
# .github/workflows/ios-build.yml
name: iOS Build
on:
  push:
    branches: [main]
    paths: ['RideWind/**']
jobs:
  build:
    runs-on: self-hosted    # 你的 Mac 作为 runner
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: |
          cd RideWind
          flutter pub get
          cd ios && pod install && cd ..
          flutter build ios --no-codesign
```

### 方案 C：VS Code Remote SSH

从 Windows 直接编辑 Mac 上的文件（适合调试 iOS 特有代码）：

```bash
# Mac 上开启 SSH
# 系统设置 → 通用 → 共享 → 远程登录 → 开启

# Windows 上 VS Code 安装 Remote-SSH 扩展
# 连接: ssh user@mac-ip
# 打开远程目录: ~/Zcritical
```

---

## AI 协作注意事项

### Windows 端 AI（Kiro）

- 正常开发所有功能
- 可以编译 ESP32 固件、构建 Android APK
- **不能**编译 iOS（没有 Xcode）
- 改完代码后提醒用户 push 并去 Mac 测试 iOS

### Mac 端 AI（如果用 Kiro/Cursor）

- 主要做 iOS 特有问题修复
- 改动前先 `git pull`
- 改动后立刻 commit + push
- commit message 遵循项目规范（见 git-and-release.md）
- 不要大规模重构——主力开发在 Windows 端

### 跨平台改动检查清单

当改动可能影响 iOS 时（新增权限、新增 native 插件、改 BLE 逻辑）：

```
□ Windows 端 commit + push
□ Mac 端 git pull
□ flutter pub get + pod install
□ flutter build ios --no-codesign（编译通过）
□ 真机测试核心功能
□ 如有修复，commit + push 回来
```

---

## 网络工具推荐

| 工具 | 用途 | 备注 |
|------|------|------|
| Tailscale | 组虚拟局域网 | 免费，两台电脑互通 |
| GitHub | 代码同步 | 已在用 |
| VS Code Remote SSH | 远程编辑 Mac 文件 | 调试 iOS 代码时用 |
