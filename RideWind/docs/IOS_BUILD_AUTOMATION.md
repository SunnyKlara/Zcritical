# iOS 构建与签名自动化流程

> 从 Bundle ID 到 App Store Connect 的完整流程。

## 前置条件

| 项目 | 要求 |
|------|------|
| Mac | macOS 14+ |
| Xcode | 15.0+ |
| Flutter | 3.x（与 Windows 端一致） |
| CocoaPods | 最新版 |
| Apple Developer | 已注册（$99/年） |

---

## Step 1: Bundle ID 配置

### 1.1 注册 Bundle ID

1. 登录 [Apple Developer Portal](https://developer.apple.com/account)
2. Certificates, Identifiers & Profiles → Identifiers → +
3. 选择 App IDs → Continue
4. 填写：
   - Description: `Critical T1`
   - Bundle ID: `com.critical.ridewind`（Explicit）
5. Capabilities 勾选：
   - [x] Background Modes
   - [x] Access WiFi Information（如需 NEHotspotHelper）
6. Register

### 1.2 修改项目 Bundle ID

```bash
# 在 Mac 上
cd RideWind/ios
# 用 Xcode 打开 Runner.xcworkspace
# Runner target → General → Bundle Identifier → com.critical.ridewind
```

或直接修改 `project.pbxproj`：
```
PRODUCT_BUNDLE_IDENTIFIER = com.critical.ridewind;
```

> 注意：Android 包名保持 `com.example.ridewind` 不变（改会破坏 MethodChannel）

---

## Step 2: 证书与签名

### 2.1 自动管理（推荐）

Xcode → Runner target → Signing & Capabilities：
- [x] Automatically manage signing
- Team: 选择你的开发者团队
- Xcode 会自动创建 Development + Distribution 证书

### 2.2 手动管理（CI/CD 需要）

```bash
# 创建 CSR
openssl req -new -newkey rsa:2048 -nodes -keyout ios_dist.key -out ios_dist.csr

# 在 Apple Developer Portal 上传 CSR → 下载 .cer
# 导入 Keychain → 导出 .p12（设置密码）

# 创建 Provisioning Profile
# Apple Developer Portal → Profiles → + → App Store Distribution
# 选择 App ID + Certificate → 下载 .mobileprovision
```

### 2.3 CI/CD Secrets 准备

```bash
# 将 .p12 转 base64
base64 -i Certificates.p12 | pbcopy
# → 粘贴到 GitHub Secret: APPLE_CERTIFICATE

# 将 .mobileprovision 转 base64
base64 -i profile.mobileprovision | pbcopy
# → 粘贴到 GitHub Secret: APPLE_PROVISIONING_PROFILE

# 证书密码
# → GitHub Secret: APPLE_CERTIFICATE_PASSWORD
```

---

## Step 3: 本地构建

### 3.1 开发构建（真机调试）

```bash
cd RideWind
flutter pub get
cd ios && pod install && cd ..
flutter run -d [iPhone设备ID]
```

### 3.2 Release 构建（无签名，仅验证编译）

```bash
flutter build ios --release --no-codesign
```

### 3.3 Archive 构建（上架用）

```bash
flutter build ipa --release
# 产物: build/ios/ipa/ridewind.ipa
```

或通过 Xcode：
1. Product → Archive
2. Distribute App → App Store Connect
3. Upload

---

## Step 4: App Store Connect

### 4.1 创建 App

1. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → +
2. 填写：
   - Name: `Critical T1`
   - Primary Language: 简体中文
   - Bundle ID: `com.critical.ridewind`
   - SKU: `critical-t1`

### 4.2 App 信息

| 字段 | 值 |
|------|-----|
| 名称 | Critical T1 |
| 副标题 | 智能风洞模拟器控制 |
| 分类 | 工具 / 娱乐 |
| 内容分级 | 4+ |
| 定价 | 免费 |

### 4.3 截图要求

| 设备 | 尺寸 | 数量 |
|------|------|------|
| iPhone 6.7" (15 Pro Max) | 1290 x 2796 | 3-10 张 |
| iPhone 5.5" (8 Plus) | 1242 x 2208 | 3-10 张 |
| iPad 12.9" (可选) | 2048 x 2732 | 3-10 张 |

### 4.4 审核备注模板

```
This app requires a Critical T1 hardware device (smart wind tunnel simulator) 
to function. The app connects to the device via Bluetooth Low Energy (BLE) 
to control fan speed, LED lighting, audio effects, and other features.

Without the hardware device, the app can still be launched and will show 
the device scanning screen, but no device control features will be available.

Demo video: [URL]
```

### 4.5 隐私政策

必须提供隐私政策 URL。最简方案：
- 在 GitHub Pages 上放一个 `privacy-policy.html`
- 或使用 freeprivacypolicy.com 生成

---

## Step 5: 自动化脚本

### Mac 端一键构建脚本

```bash
#!/bin/bash
# ~/scripts/build_ios.sh
set -e

cd ~/Zcritical/RideWind

echo "Pulling latest code..."
git pull origin main

echo "Installing dependencies..."
flutter pub get
cd ios && pod install && cd ..

echo "Building iOS Release..."
flutter build ipa --release

echo "IPA ready: build/ios/ipa/ridewind.ipa"
echo "Open Xcode Organizer to upload, or use:"
echo "   xcrun altool --upload-app -f build/ios/ipa/ridewind.ipa -t ios -u YOUR_APPLE_ID -p APP_SPECIFIC_PASSWORD"
```

### 使用 xcrun 命令行上传

```bash
# 生成 App-Specific Password: appleid.apple.com → Security → App-Specific Passwords
xcrun altool --upload-app \
  -f build/ios/ipa/ridewind.ipa \
  -t ios \
  -u "your@email.com" \
  -p "xxxx-xxxx-xxxx-xxxx"
```

---

## Step 6: 版本管理

### iOS 版本号规则

- `CFBundleShortVersionString` = pubspec.yaml 的 `version`（如 1.0.0）
- `CFBundleVersion` = pubspec.yaml 的 build number（如 1）
- 每次提交 App Store 必须递增 build number
- 版本号与 Android 保持一致

### app_version.json iOS 字段

```json
{
  "latest_version": "1.0.0",
  "ios_app_store_url": "https://apps.apple.com/app/idXXXXXXXXXX",
  "ios_min_version": "1.0.0"
}
```

---

## 常见问题

| 问题 | 解决 |
|------|------|
| pod install 失败 | `rm -rf Pods Podfile.lock && pod install --repo-update` |
| 签名错误 | Xcode → Clean Build Folder → 重新选择 Team |
| Archive 灰色 | 确保选择 "Any iOS Device" 而非模拟器 |
| 上传后 Processing 卡住 | 等 15-30 分钟，Apple 后台处理 |
| 审核被拒 2.1 | 确保无 crash，提供演示视频 |
| 审核被拒 4.0 | 说明需要硬件配合，提供视频 |
