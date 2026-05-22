# 新平台接入 Checklist — [平台名称]

> 复制此模板，替换 [平台名称]，逐项完成。

## 基本信息

| 项目 | 值 |
|------|-----|
| 平台 | [Android / iOS / macOS / Windows / Web] |
| 接入日期 | YYYY-MM-DD |
| 负责人 | |
| 目标版本 | |
| BLE 插件 | [flutter_blue_plus / win_ble / web_bluetooth / 其他] |

---

## Phase 1: 环境搭建

- [ ] 开发机器准备（OS 版本、IDE、SDK）
- [ ] Flutter 平台支持启用（`flutter create --platforms=xxx .`）
- [ ] 平台 SDK 安装（Xcode / Android Studio / Visual Studio）
- [ ] `flutter doctor` 全绿
- [ ] `flutter pub get` 成功
- [ ] 平台特有依赖安装（CocoaPods / Gradle / NuGet）
- [ ] 空项目 `flutter run` 成功

## Phase 2: 编译验证

- [ ] `flutter build [平台] --release` 编译通过
- [ ] `flutter analyze` 零 error
- [ ] 启动后不 crash（空白页面也算通过）
- [ ] BLE 插件在该平台可用（或有替代方案）
- [ ] 所有 pub 依赖兼容该平台（查 pub.dev 平台标签）

## Phase 3: 平台能力适配

### 3.1 Platform Channel 实现

| 通道方法 | 状态 | 备注 |
|----------|------|------|
| startCapture | [ ] 实现 / [ ] 不支持 | |
| stopCapture | [ ] 实现 / [ ] 不支持 | |
| isCapturing | [ ] 实现 / [ ] 不支持 | |
| getStatus | [ ] 实现 / [ ] 不支持 | |
| scanWifi | [ ] 实现 / [ ] 不支持 | |
| getConnectedWifi | [ ] 实现 / [ ] 不支持 | |

### 3.2 能力注册

- [ ] 在 `lib/core/platform_capability.dart` 中添加 `[Platform]CapabilityProvider`
- [ ] 在 `PlatformCapabilities._detectProvider()` 中注册
- [ ] 在 `lib/core/platform_channel_registry.dart` 中添加平台实现（如有原生通道）

### 3.3 权限声明

| 权限 | 声明文件 | 状态 |
|------|----------|------|
| 蓝牙 | | [ ] |
| 位置（BLE 扫描需要） | | [ ] |
| 网络/WiFi | | [ ] |
| 相机 | | [ ] |
| 存储/文件 | | [ ] |
| 通知 | | [ ] |

### 3.4 UI 适配

- [ ] 不支持的功能入口已隐藏（使用 `PlatformCapabilities.instance.supports()`）
- [ ] 平台特有 UI 风格适配（iOS: Cupertino / macOS: 窗口布局）
- [ ] 屏幕尺寸适配（手机 / 平板 / 桌面）

## Phase 4: 核心功能验证

| 功能 | 模拟器 | 真机 | 备注 |
|------|--------|------|------|
| BLE 扫描 | [ ] | [ ] | |
| BLE 连接 | N/A | [ ] | 模拟器无 BLE |
| 风扇控制 | N/A | [ ] | |
| LED 灯效 | N/A | [ ] | |
| 音量调节 | N/A | [ ] | |
| Logo 上传 | N/A | [ ] | |
| OTA 升级 | N/A | [ ] | |
| WiFi 配网 | [ ] | [ ] | |
| 音频投射 | [ ] | [ ] | 仅 Android |
| 引擎声浪 | [ ] | [ ] | |
| 车库模式 | [ ] | [ ] | |

## Phase 5: 发布准备

### 应用商店配置

- [ ] 开发者账号注册
- [ ] 应用 ID / Bundle ID 注册
- [ ] 签名证书创建
- [ ] 应用商店页面创建
- [ ] 截图准备（各尺寸）
- [ ] 隐私政策 URL
- [ ] 应用描述和关键词

### 构建与签名

- [ ] Release 构建成功
- [ ] 签名配置正确
- [ ] CI/CD 流水线集成
- [ ] 自动分发配置

### 审核准备

- [ ] 审核备注（说明需要硬件配合）
- [ ] 演示视频
- [ ] 测试账号（如需要）

## Phase 6: 文档更新

- [ ] `platform-rules.md` 更新能力矩阵
- [ ] `IOS_RELEASE_CHECKLIST.md`（或对应平台 checklist）创建
- [ ] `cross-platform-workflow.md` 更新协作流程
- [ ] `CONTINUATION_GUIDE.md` 记录当前状态
- [ ] `app_version.json` 添加平台特有字段

---

## 已知限制

| 限制 | 影响 | 解决方案 |
|------|------|----------|
| | | |

## 回退方案

如果该平台接入失败或需要暂停：
1. 代码改动在 `feat/[platform]-platform` 分支，不影响 main
2. `PlatformCapabilities` 自动降级，不会影响其他平台
3. CI/CD 中该平台构建可单独禁用
