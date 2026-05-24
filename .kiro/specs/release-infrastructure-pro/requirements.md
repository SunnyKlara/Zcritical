# Requirements Document

## Introduction

本文档定义 RideWind 项目"发布基础设施专业化"功能的需求。目标是将现有的 CI/CD 流程从"能用"提升到"生产级"，涵盖崩溃监控、APK 体积优化、灰度发布、自动化测试门禁、发版通知、代码重构、HTTPS 强制跳转、证书续期监控和 CDN 加速等方面。

项目背景：
- Flutter 移动应用 (RideWind) + ESP32 固件项目
- 已有 GitHub Actions CI workflow（tag 触发构建部署）
- 已有 APK 正式签名、HTTPS、域名配置、双 URL fallback、APK 文件验证、app_version.json CI 自动更新
- 目标用户主要是国内用户

## Glossary

- **CI_Pipeline**: GitHub Actions 中定义的持续集成/持续部署工作流
- **Crash_Monitor**: 集成到 APP 中的崩溃监控 SDK（Bugly 或 Sentry），负责捕获未处理异常并上报
- **APK_Builder**: CI 中负责构建 Android 安装包的 job
- **Grayscale_Controller**: 控制灰度发布的逻辑模块，决定设备是否展示新版本更新
- **Test_Gate**: CI 中在构建前执行自动化测试的门禁步骤
- **Notification_Service**: CI 发版结果通知服务，通过 webhook 发送消息
- **Update_Service**: APP 内统一的版本检查与下载安装服务（合并后）
- **Nginx_Server**: 部署在国内服务器上的 Nginx 反向代理/静态文件服务
- **Cert_Monitor**: 定时检查 TLS 证书过期时间的监控脚本
- **CDN_Service**: 阿里云 CDN 加速服务，用于加速 APK 下载和静态资源分发
- **Device_ID**: 设备唯一标识符，用于灰度发布分组判定
- **Rollout_Percentage**: app_version.json 中的灰度比例字段（0-100），控制新版本推送范围

## Requirements

### Requirement 1: 崩溃监控集成

**User Story:** As a 开发者, I want APP 崩溃信息自动上报到监控平台, so that 我能及时发现并修复线上崩溃问题而不依赖用户反馈。

#### Acceptance Criteria

1. WHEN the APP 启动时, THE Crash_Monitor SHALL 完成 SDK 初始化并开始捕获未处理异常
2. WHEN an unhandled exception occurs in Flutter layer, THE Crash_Monitor SHALL 捕获异常堆栈并在网络可用时上报到监控平台
3. WHEN a native crash occurs on Android, THE Crash_Monitor SHALL 捕获 native 崩溃信息并在下次启动时上报
4. THE Crash_Monitor SHALL 在上报数据中包含 APP 版本号、设备型号、OS 版本和崩溃堆栈
5. IF the network is unavailable at crash time, THEN THE Crash_Monitor SHALL 缓存崩溃数据并在网络恢复后自动上报
6. THE CI_Pipeline SHALL 在构建 release APK 时自动上传符号表（mapping 文件）到监控平台

### Requirement 2: APK 体积优化

**User Story:** As a 用户, I want 下载的 APK 体积尽可能小, so that 下载更快、占用存储更少。

#### Acceptance Criteria

1. THE APK_Builder SHALL 使用 --split-per-abi 参数构建按 CPU 架构拆分的 APK
2. WHEN building with --split-per-abi, THE APK_Builder SHALL 生成 arm64-v8a 单架构 APK 且体积不超过 40MB
3. THE CI_Pipeline SHALL 将所有架构的 APK 文件上传到 GitHub Release
4. THE CI_Pipeline SHALL 将 arm64-v8a APK 部署到国内服务器作为主下载地址
5. THE CI_Pipeline SHALL 更新 app_version.json 中的 download_url 指向 arm64-v8a APK 文件

### Requirement 3: 灰度发布

**User Story:** As a 开发者, I want 新版本按比例推送给部分用户, so that 我能在小范围验证新版本稳定性后再全量推送。

#### Acceptance Criteria

1. THE CI_Pipeline SHALL 在 app_version.json 中支持 rollout_percentage 字段（整数，范围 0-100）
2. WHEN the Update_Service 获取到版本信息时, THE Update_Service SHALL 读取 rollout_percentage 字段
3. WHEN rollout_percentage 为 100 或未设置时, THE Update_Service SHALL 向所有设备展示更新提示
4. WHEN rollout_percentage 小于 100 时, THE Grayscale_Controller SHALL 基于 Device_ID 的哈希值对 100 取模，判断该设备是否在灰度范围内
5. WHEN 设备哈希值取模结果小于 rollout_percentage, THE Update_Service SHALL 展示更新提示
6. WHEN 设备哈希值取模结果大于等于 rollout_percentage, THE Update_Service SHALL 不展示更新提示
7. THE Grayscale_Controller SHALL 对同一 Device_ID 在相同 rollout_percentage 下始终返回相同的灰度判定结果

### Requirement 4: CI 自动化测试门禁

**User Story:** As a 开发者, I want CI 在构建前自动运行测试, so that 有测试失败时构建被阻止，避免发布有缺陷的版本。

#### Acceptance Criteria

1. THE Test_Gate SHALL 在 flutter analyze 之后、APK 构建之前执行 flutter test
2. WHEN any test fails, THE Test_Gate SHALL 将 CI job 标记为失败并阻止后续构建步骤
3. THE Test_Gate SHALL 在 CI 日志中输出测试结果摘要（通过数、失败数、跳过数）
4. THE Test_Gate SHALL 执行 RideWind/test/ 目录下的所有测试用例

### Requirement 5: 发版通知

**User Story:** As a 开发者, I want CI 发版成功或失败时收到即时通知, so that 我能及时知道发版状态而不需要手动检查 CI。

#### Acceptance Criteria

1. WHEN the release job completes successfully, THE Notification_Service SHALL 发送成功通知到配置的 webhook 地址
2. WHEN the release job fails, THE Notification_Service SHALL 发送失败通知到配置的 webhook 地址
3. THE Notification_Service SHALL 在通知消息中包含版本号、构建状态和 GitHub Release 链接
4. THE Notification_Service SHALL 支持 Telegram Bot API 和企业微信 webhook 两种通知渠道
5. IF webhook 地址未配置（secret 为空）, THEN THE Notification_Service SHALL 跳过对应渠道的通知而不导致 CI 失败

### Requirement 6: 合并 UpdateService

**User Story:** As a 开发者, I want APP 内只有一个统一的更新服务, so that 代码不重复、维护更简单、行为一致。

#### Acceptance Criteria

1. THE Update_Service SHALL 合并 update_service.dart 和 app_update_service.dart 为单一服务文件
2. THE Update_Service SHALL 保留双 URL 版本检测（GitHub Raw + jsdelivr CDN fallback）
3. THE Update_Service SHALL 保留双 URL 下载（国内服务器 + GitHub Release fallback）
4. THE Update_Service SHALL 保留 APK 文件大小验证（至少 1MB）
5. THE Update_Service SHALL 支持强制更新和可选更新两种模式
6. THE Update_Service SHALL 提供下载进度回调和取消下载功能
7. WHEN the merge is complete, THE Update_Service SHALL 删除冗余的服务文件并更新所有引用

### Requirement 7: HTTP 强制跳转 HTTPS

**User Story:** As a 用户, I want 所有 HTTP 请求自动跳转到 HTTPS, so that 下载链接始终安全加密。

#### Acceptance Criteria

1. WHEN a client sends an HTTP request to port 80, THE Nginx_Server SHALL 返回 301 永久重定向到对应的 HTTPS URL
2. THE Nginx_Server SHALL 保留原始请求路径和查询参数在重定向目标中
3. WHEN the redirect is configured, THE Nginx_Server SHALL 对所有域名下的路径生效

### Requirement 8: 证书续期监控

**User Story:** As a 运维人员, I want 证书即将过期时收到告警, so that 我能在证书过期前完成续期避免服务中断。

#### Acceptance Criteria

1. THE Cert_Monitor SHALL 每天定时检查 TLS 证书的剩余有效天数
2. WHEN 证书剩余有效天数少于 14 天, THE Cert_Monitor SHALL 发送告警通知
3. THE Cert_Monitor SHALL 在告警消息中包含域名和证书过期日期
4. IF 证书检查脚本执行失败, THEN THE Cert_Monitor SHALL 发送执行失败告警

### Requirement 9: CDN 加速

**User Story:** As a 国内用户, I want APK 下载速度更快, so that 更新体验更流畅。

#### Acceptance Criteria

1. THE CDN_Service SHALL 为 APK 下载域名配置阿里云 CDN 加速
2. WHEN a new APK is deployed to origin server, THE CDN_Service SHALL 在 CI 中触发 CDN 缓存刷新
3. THE Update_Service SHALL 将 CDN 加速域名作为主下载地址，原始服务器地址作为 fallback
4. IF CDN 节点返回错误, THEN THE Update_Service SHALL 自动回退到原始服务器下载
