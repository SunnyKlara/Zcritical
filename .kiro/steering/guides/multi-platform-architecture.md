---
inclusion: manual
---

# 多平台开发架构指南

> 本文件定义 Critical T1 APP 的多平台抽象体系。
> 目标：新平台接入时只需实现接口 + 注册能力，上层代码零改动。

## 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                    Screen / Widget 层                      │
│         （使用 PlatformCapabilities 决定 UI 显示）          │
├─────────────────────────────────────────────────────────┤
│                  Provider / Service 层                     │
│     （通过 PlatformChannelRegistry 调用平台功能）           │
├─────────────────────────────────────────────────────────┤
│              PlatformChannelRegistry（接口层）              │
│   AudioCaptureChannel │ WifiChannel │ AppUpdateChannel    │
├──────────┬──────────┬──────────┬──────────┬─────────────┤
│ Android  │   iOS    │  macOS   │ Windows  │   Web       │
│ Kotlin   │  Swift   │  Swift   │   C++    │   JS        │
│ Method   │ Method   │ Method   │ Method   │ JS Interop  │
│ Channel  │ Channel  │ Channel  │ Channel  │             │
└──────────┴──────────┴──────────┴──────────┴─────────────┘
```

## 核心组件

### 1. PlatformCapabilities（运行时能力检测）

**文件**: `lib/core/platform_capability.dart`

**职责**:
- 运行时检测当前平台支持哪些功能
- 为 UI 层提供 `supports(feature)` 查询
- 提供不可用原因和降级方案描述

**使用模式**:
```dart
// Screen 中决定是否显示某功能入口
if (PlatformCapabilities.instance.supports(PlatformFeature.audioCapture)) {
  // 显示音频投射按钮
}

// 获取降级提示
final reason = PlatformCapabilities.instance.getUnavailableReason(PlatformFeature.wifiScan);
// → "iOS 不提供 WiFi 扫描 API"
```

**新平台接入**:
1. 创建 `XxxCapabilityProvider implements PlatformCapabilityProvider`
2. 为每个 `PlatformFeature` 定义 `isSupported` + `unavailableReason` + `fallbackDescription`
3. 在 `_detectProvider()` 中注册

### 2. PlatformChannelRegistry（统一接口调用）

**文件**: `lib/core/platform_channel_registry.dart`

**职责**:
- 定义平台特有功能的 Dart 接口
- 根据平台注册对应实现
- 不支持的平台使用空实现（不抛异常）

**接口清单**:

| 接口 | 方法 | Android | iOS | macOS | Windows |
|------|------|---------|-----|-------|---------|
| AudioCaptureChannel | startCapture/stop/isCapturing/getStatus | ✅ Kotlin | ❌ | ❌ | ❌ |
| WifiChannel | scanWifi/getConnectedWifi | ✅ Kotlin | ❌ | ✅ 未来 | ✅ 未来 |
| AppUpdateChannel | performUpdate | ✅ APK | ✅ App Store | ✅ Sparkle | ✅ 下载 |

**新平台接入**:
1. 实现对应接口（如 `MacOSWifiChannel implements WifiChannel`）
2. 在 `_defaultXxx()` 方法中添加平台判断
3. 原生端实现 MethodChannel handler

### 3. 降级策略

| 场景 | 策略 |
|------|------|
| 功能完全不支持 | 隐藏 UI 入口（`PlatformCapabilities.supports()` 返回 false） |
| 功能部分支持 | 显示入口但提示限制（如 iOS WiFi 手动输入） |
| 功能未来支持 | 显示"即将推出"标签 |
| 运行时失败 | try/catch + 用户友好提示 |

---

## Platform Channel 规范

### 通道命名

```
com.example.ridewind/[模块名]
```

当前通道：
- `com.example.ridewind/audio_capture` — 音频捕获 + WiFi 扫描

未来可能新增：
- `com.example.ridewind/system_info` — 系统信息查询
- `com.example.ridewind/file_access` — 文件系统扩展

### 方法命名规范

- 动词开头：`startCapture`, `stopCapture`, `scanWifi`
- 查询用 `get` 前缀：`getStatus`, `getConnectedWifi`
- 布尔查询用 `is` 前缀：`isCapturing`

### 错误处理规范

```dart
// 原生端
result.error("ERROR_CODE", "人类可读描述", detailObject)

// Dart 端
try {
  await channel.invokeMethod('xxx');
} on PlatformException catch (e) {
  // 处理已知错误码
} on MissingPluginException {
  // 平台未实现 - graceful fallback
}
```

### 数据格式规范

- 简单值：直接传 String/int/bool
- 复杂对象：Map<String, dynamic>（JSON-like）
- 列表：List<Map<String, dynamic>>
- 二进制：Uint8List

---

## 测试策略

### 分层测试矩阵

```
┌─────────────────────────────────────────┐
│ Layer 1: 单元测试（所有平台，CI 中运行）    │
│ - Provider 逻辑                          │
│ - Protocol 解析                          │
│ - Service 业务逻辑                       │
│ - PlatformCapabilities 查询              │
├─────────────────────────────────────────┤
│ Layer 2: Widget 测试（所有平台，CI 中运行） │
│ - 功能入口显示/隐藏                       │
│ - 降级 UI 正确渲染                        │
├─────────────────────────────────────────┤
│ Layer 3: 集成测试 - 模拟器                 │
│ - UI 流程完整性                           │
│ - 非 BLE 功能验证                         │
│ - 平台特有 UI 适配                        │
├─────────────────────────────────────────┤
│ Layer 4: 真机测试                         │
│ - BLE 连接 + 通信                         │
│ - WiFi 配网                              │
│ - 音频投射（Android）                     │
│ - OTA 升级                               │
│ - 性能（电池、内存）                       │
└─────────────────────────────────────────┘
```

### 测试设备矩阵

| 平台 | 模拟器/虚拟机 | 真机 | 最低版本 |
|------|--------------|------|----------|
| Android | Android 10+ 模拟器 | 实体手机 | API 29 (Android 10) |
| iOS | iPhone 15 模拟器 | iPhone（需 Mac） | iOS 14.0 |
| macOS | - | Mac 本机 | macOS 13 |
| Windows | - | Windows 本机 | Windows 10 |

### BLE 测试特殊说明

- **模拟器无法测试 BLE** — 所有 BLE 功能必须真机验证
- Android 模拟器：可测试 UI 流程、非 BLE 功能
- iOS 模拟器：同上，但 BLE 相关 UI 会显示"请使用真机"
- 真机测试需要 ESP32 硬件在线

---

## CI/CD 流水线

### 触发规则

| 事件 | 动作 |
|------|------|
| Push to main（RideWind/ 变更） | analyze + build Android + build iOS |
| Tag `app-v*` | 上述 + 创建 GitHub Release |
| 手动触发 | 可选择构建哪些平台 |

### 流水线文件

`.github/workflows/multi-platform-build.yml`

### Secrets 配置（iOS 签名需要）

| Secret | 用途 |
|--------|------|
| `APPLE_CERTIFICATE` | Base64 编码的 .p12 证书 |
| `APPLE_CERTIFICATE_PASSWORD` | 证书密码 |
| `APPLE_PROVISIONING_PROFILE` | Base64 编码的 .mobileprovision |
| `KEYCHAIN_PASSWORD` | 临时 Keychain 密码 |

### 本地构建 vs CI 构建

| 场景 | 推荐方式 |
|------|----------|
| 日常开发验证 | 本地 `flutter build apk --release` |
| iOS 编译验证 | Mac 上 `flutter build ios --no-codesign` |
| 正式发版 | CI 自动构建 + 手动上传到阿里云/App Store |
| 紧急修复 | 本地构建 + 手动分发 |

---

## 各平台接入路线图

### Android（已完成）
- 全功能支持
- Platform Channel 完整实现
- APK 自动分发（阿里云服务器）

### iOS（代码适配完成，待 Mac 构建）
- BLE 通信：flutter_blue_plus 跨平台
- 音频投射：不支持，已隐藏
- WiFi 配网：手动输入 SSID
- 应用更新：App Store 跳转
- 待完成：Mac 构建 + 签名 + 上架

### macOS（规划中）
- 定位：桌面配置工具（高级设置、批量管理）
- BLE：Core Bluetooth（与 iOS 共享）
- 额外功能：文件拖拽上传 Logo、多设备管理
- 依赖：iOS 上架完成后启动

### Windows（远期）
- 定位：桌面配置工具
- BLE：需要 `win_ble` 或 `universal_ble` 插件
- 挑战：flutter_blue_plus 不支持 Windows
- 依赖：macOS 版本验证架构后启动

### Web（暂不考虑）
- Web Bluetooth API 兼容性差
- 无法后台保持 BLE 连接
- 不适合硬件控制场景
