---
inclusion: auto
---

# 多平台开发规则

## 核心原则

**每个新功能必须同时考虑 Android + iOS 兼容性。**
Android 是主力调试平台，但代码提交前必须确认 iOS 不会 crash。

## 开发检查清单（每个功能/修复）

1. **平台通道调用** — 如果用了 MethodChannel，iOS 端是否有对应实现或 graceful fallback？
2. **Platform.isXxx 条件** — 平台独占功能必须用条件隐藏，不能让 iOS 用户看到不可用的入口
3. **权限声明** — Android `AndroidManifest.xml` 加了权限 → 同步检查 iOS `Info.plist`
4. **依赖兼容** — 新增 pub 依赖时确认其 iOS 支持状态（查 pub.dev 平台标签）
5. **BLE 差异** — iOS 不暴露 MAC 地址，设备 ID 用 `remoteId`（UUID），不要硬编码 MAC 格式

## 平台能力矩阵

| 能力 | Android | iOS | 处理方式 |
|------|---------|-----|----------|
| 系统音频捕获 | ✅ MediaProjection | ❌ | `Platform.isAndroid` 隐藏 |
| WiFi SSID 自动获取 | ✅ platform channel | ⚠️ 需 NEHotspotHelper | iOS 手动输入 fallback |
| APK 下载安装 | ✅ open_filex | ❌ | iOS 跳转 App Store |
| 后台 BLE | ✅ | ✅ 需 UIBackgroundModes | Info.plist 已配置 |
| 文件系统访问 | ✅ | ✅ 沙盒限制 | 用 path_provider |

## 后续扩展平台

如果未来要支持 macOS / Windows / Web：
- macOS：BLE 可用（Core Bluetooth），大部分 iOS 逻辑可复用
- Windows：BLE 需要 `win_ble` 或类似插件，flutter_blue_plus 不支持
- Web：BLE 需要 Web Bluetooth API，浏览器兼容性差，暂不考虑

## 规则执行

- 写新功能时，如果涉及平台特有 API，必须在 PR/commit 中注明 iOS 兼容状态
- 如果 iOS 端暂时无法实现（如缺少 Mac 环境），在代码中加 `// TODO(ios):` 注释 + 在 IOS_RELEASE_CHECKLIST.md 中记录
