# iOS 上架准备 Checklist

## ✅ 已完成（代码层面）

- [x] Info.plist 权限声明完整
  - 蓝牙: `NSBluetoothAlwaysUsageDescription` + `NSBluetoothPeripheralUsageDescription`
  - 相机: `NSCameraUsageDescription`
  - 相册: `NSPhotoLibraryUsageDescription`
  - 位置(WiFi SSID): `NSLocationWhenInUseUsageDescription`
  - 本地网络: `NSLocalNetworkUsageDescription`
  - 后台 BLE: `UIBackgroundModes` → `bluetooth-central`
- [x] iOS Deployment Target 设为 14.0
- [x] 音频投射功能在 iOS 上隐藏（`Platform.isAndroid` 条件）
- [x] WiFi 配网对话框 iOS 适配（手动输入 SSID + 密码）
- [x] APP 更新逻辑 iOS 适配（`update_service.dart` 跳转 App Store）
- [x] APP 更新逻辑 iOS 适配（`app_update_service.dart` 防止 APK 下载崩溃）
- [x] APP 更新弹窗 iOS 适配（`app_update_dialog.dart` 平台检查）
- [x] `audio_stream_service.dart` — `scanWifi()`/`getConnectedWifi()` 加 try/catch 防 MissingPluginException
- [x] `app_version.json` 添加 `ios_app_store_url` 字段
- [x] BLE 无 MAC 地址依赖（flutter_blue_plus 使用 remoteId，iOS 兼容）
- [x] OTA 固件升级 — BLE + WebSocket 跨平台，无需改动
- [x] Logo 管理 — image_picker + WebSocket 跨平台，无需改动
- [x] 多平台规则写入 `.kiro/steering/platform-rules.md`（auto inclusion）

## ⬜ 需要在 Mac 上完成

### 1. 开发者账号
- [ ] 注册 Apple Developer Program ($99/年)
- [ ] 如果公司名义：申请 D-U-N-S 编号（需 2-4 周）

### 2. Bundle ID
- [ ] 在 Apple Developer Portal 注册 Bundle ID
- [ ] 当前是 `com.example.ridewind`，需改为正式 ID（如 `com.yourcompany.ridewind`）
- [ ] 修改 `project.pbxproj` 中所有 `PRODUCT_BUNDLE_IDENTIFIER`

### 3. 证书和签名
- [ ] 创建 iOS Distribution Certificate
- [ ] 创建 App Store Provisioning Profile
- [ ] 在 Xcode 中配置 Signing & Capabilities

### 4. 构建环境
- [ ] Mac 电脑 + Xcode 15+
- [ ] 运行 `flutter pub get`（生成 Podfile 和 Pods/）
- [ ] 运行 `pod install`（在 ios/ 目录）
- [ ] 运行 `flutter build ios --release` 验证编译

### 5. App Store Connect 配置
- [ ] 创建 App 记录
- [ ] 填写 App 信息（名称、描述、关键词、分类）
- [ ] 上传截图（6.7" iPhone 15 Pro Max + 5.5" iPhone 8 Plus）
- [ ] 填写隐私政策 URL
- [ ] 配置 App 定价（免费）

### 6. 审核准备
- [ ] 审核备注：说明 app 需要配合 RideWind 硬件设备使用
- [ ] 提供演示视频（展示 BLE 连接 + 功能操作）
- [ ] 如有需要，提供测试账号信息

### 7. 提交
- [ ] Archive → Upload to App Store Connect
- [ ] 选择构建版本 → 提交审核
- [ ] 审核通过后发布

## 注意事项

### iOS 与 Android 功能差异
| 功能 | Android | iOS |
|------|---------|-----|
| 音频投射 | ✅ 系统音频捕获 | ❌ 不支持 |
| WiFi 配网 | 自动获取 SSID | 手动输入 SSID |
| APP 更新 | APK 下载安装 | App Store 跳转 |
| BLE 设备 ID | MAC 地址 | UUID（每次配对可能变化） |

### App Store 审核常见拒绝原因
1. **2.1 性能** — 确保 app 不 crash，所有功能可用
2. **2.5.1 蓝牙** — 必须使用 Core Bluetooth（flutter_blue_plus 已符合）
3. **4.0 设计** — 需要硬件配合的 app 要提供演示视频
4. **5.1.1 隐私** — 必须有隐私政策，权限描述要具体

### `ios_app_store_url` 格式
上架后填入：`https://apps.apple.com/app/idXXXXXXXXXX`
