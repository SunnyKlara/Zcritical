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
- **Crash_Monitor**: 集成到 APP 中的崩溃监控 SDK（Sentry），负责捕获未处理异常并上报
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

1. WHEN the APP 启动时, THE Crash_Monitor SHALL 在 5 秒内完成 Sentry SDK 初始化，并注册 Flutter 层未处理同步异常与异步异常的全局捕获
2. IF Sentry SDK 初始化失败, THEN THE Crash_Monitor SHALL 将初始化失败事件写入本地日志，并在下次启动时重试初始化
3. WHEN an unhandled exception occurs in Flutter layer, THE Crash_Monitor SHALL 捕获完整异常堆栈（包含 class 名、方法名、行号）并在网络可用时于 30 秒内上报到 Sentry 平台
4. WHEN a native crash occurs on Android, THE Crash_Monitor SHALL 捕获 native 崩溃信息并持久化到本地，在下次 APP 启动后 60 秒内自动上报
5. THE Crash_Monitor SHALL 在每条上报数据中包含以下字段：APP 版本号（versionName+buildNumber）、设备型号、OS 版本、崩溃堆栈，且不得包含用户个人身份信息
6. IF the network is unavailable at crash time, THEN THE Crash_Monitor SHALL 将崩溃数据缓存到本地存储，缓存上限为 20 条记录或 5MB（先到者为准），并在网络恢复后按先进先出顺序逐条上报
7. WHEN the CI_Pipeline 构建 release APK 时, THE CI_Pipeline SHALL 自动上传 Android ProGuard mapping 文件到 Sentry，并在上传失败时将该构建步骤标记为失败
8. WHEN the CI_Pipeline 构建 release iOS 包时, THE CI_Pipeline SHALL 自动上传 dSYM 符号文件到 Sentry，并在上传失败时将该构建步骤标记为失败

### Requirement 2: APK 体积优化

**User Story:** As a 用户, I want 下载的 APK 体积尽可能小, so that 下载更快、占用存储更少。

#### Acceptance Criteria

1. THE APK_Builder SHALL 使用 --split-per-abi 参数构建按 CPU 架构拆分的 APK，生成 armeabi-v7a、arm64-v8a、x86_64 三个架构的独立 APK 文件
2. WHEN building with --split-per-abi, THE APK_Builder SHALL 生成 arm64-v8a 单架构 APK 且体积不超过 40MB
3. WHEN release tag 被推送时, THE CI_Pipeline SHALL 将所有架构（armeabi-v7a、arm64-v8a、x86_64）的 APK 文件上传到 GitHub Release，文件名格式为 zcritical-t1-v{版本号}-{架构名}.apk
4. WHEN release tag 被推送时, THE CI_Pipeline SHALL 将 arm64-v8a APK 部署到国内服务器（sunnyklara.com/releases/）作为主下载地址
5. WHEN release tag 被推送时, THE CI_Pipeline SHALL 更新 app_version.json 中的 download_url 指向国内服务器的 arm64-v8a APK 文件，同时更新 fallback_download_url 指向 GitHub Release 对应的 arm64-v8a APK 文件
6. IF 国内服务器部署失败（HTTP 响应码非 200）, THEN THE CI_Pipeline SHALL 输出警告信息，且 GitHub Release 中的 APK 仍可作为备用下载源

### Requirement 3: 灰度发布

**User Story:** As a 开发者, I want 新版本按比例推送给部分用户, so that 我能在小范围验证新版本稳定性后再全量推送。

#### Acceptance Criteria

1. THE CI_Pipeline SHALL 在 app_version.json 中支持 rollout_percentage 字段（整数，范围 0-100，含边界值）
2. WHEN the Update_Service 获取到版本信息时, THE Update_Service SHALL 读取 rollout_percentage 字段
3. WHEN rollout_percentage 为 100、字段缺失、或字段值为 null 时, THE Update_Service SHALL 向所有设备展示更新提示
4. WHEN rollout_percentage 小于 100 时, THE Grayscale_Controller SHALL 将 Device_ID 字符串进行哈希计算后对 100 取模（结果范围 0-99），判断该设备是否在灰度范围内
5. WHEN 设备哈希值取模结果小于 rollout_percentage, THE Update_Service SHALL 展示更新提示
6. WHEN 设备哈希值取模结果大于等于 rollout_percentage, THE Update_Service SHALL 不展示更新提示，且不向用户显示任何新版本相关信息
7. THE Grayscale_Controller SHALL 对同一 Device_ID 在相同 rollout_percentage 下始终返回相同的灰度判定结果（幂等性）
8. THE Grayscale_Controller SHALL 保证单调递增特性：当 rollout_percentage 从 A 增大到 B（A < B）时，所有在 A 阶段被纳入灰度的设备在 B 阶段仍然被纳入
9. IF rollout_percentage 字段值不是 0-100 范围内的整数（包括负数、大于 100、小数、或非数字类型）, THEN THE Update_Service SHALL 将其视为 100 并向所有设备展示更新提示
10. IF 设备无法获取 Device_ID（ANDROID_ID 不可用且 SharedPreferences 中无已存储 UUID）, THEN THE Update_Service SHALL 生成并持久化一个新的 UUID 作为 Device_ID 后再进行灰度判定

### Requirement 4: CI 自动化测试门禁

**User Story:** As a 开发者, I want CI 在构建前自动运行测试, so that 有测试失败时构建被阻止，避免发布有缺陷的版本。

#### Acceptance Criteria

1. THE Test_Gate SHALL 在 flutter analyze 步骤成功完成之后、APK/IPA 构建步骤之前执行 flutter test，且 flutter analyze 失败时不执行测试步骤
2. WHEN any test fails, THE Test_Gate SHALL 以非零退出码终止 CI job，使 GitHub Actions 将该 job 状态标记为 failed，并阻止所有依赖该 job 的后续构建步骤执行
3. THE Test_Gate SHALL 在 CI 日志中输出测试结果摘要，包含通过数、失败数、跳过数三项数值
4. THE Test_Gate SHALL 递归执行 RideWind/test/ 目录下所有子目录（包括 protocol/、services/、utils/、widgets/ 及根目录测试文件）中的全部测试用例
5. IF 测试执行时间超过 10 分钟, THEN THE Test_Gate SHALL 超时终止测试并将 CI job 标记为失败
6. IF RideWind/test/ 目录下未发现任何测试用例, THEN THE Test_Gate SHALL 将 CI job 标记为失败并在日志中输出无测试发现的提示信息

### Requirement 5: 发版通知

**User Story:** As a 开发者, I want CI 发版成功或失败时收到即时通知, so that 我能及时知道发版状态而不需要手动检查 CI。

#### Acceptance Criteria

1. WHEN release job 成功完成, THE Notification_Service SHALL 向所有已配置的 webhook 渠道发送通知，消息中包含版本号、构建状态（成功）、GitHub Release 链接
2. WHEN release job 失败, THE Notification_Service SHALL 向所有已配置的 webhook 渠道发送通知，消息中包含版本号、构建状态（失败）、失败的 job 名称、GitHub Actions 运行链接
3. THE Notification_Service SHALL 支持 Telegram Bot API（HTTPS POST 至 api.telegram.org）和企业微信 webhook（HTTPS POST 至 qyapi.weixin.qq.com）两种通知渠道，当两个渠道均已配置时分别独立发送
4. IF webhook 地址未配置（对应 GitHub repository secret 未设置或值为空字符串）, THEN THE Notification_Service SHALL 跳过该渠道的通知发送，不影响其他渠道，且不导致 CI job 失败
5. IF webhook HTTP 请求在 30 秒内未收到 2xx 响应, THEN THE Notification_Service SHALL 重试最多 2 次（共 3 次尝试），最终仍失败时记录警告日志但不导致 CI job 失败

### Requirement 6: 合并 UpdateService

**User Story:** As a 开发者, I want APP 内只有一个统一的更新服务, so that 代码不重复、维护更简单、行为一致。

#### Acceptance Criteria

1. THE Update_Service SHALL 以单例模式提供唯一实例，合并原有 update_service.dart 和 app_update_service.dart 为单一服务文件
2. WHEN 版本检测被触发时, THE Update_Service SHALL 依次尝试 GitHub Raw URL 和 jsdelivr CDN URL 获取版本信息，单个 URL 请求超时时间为 8 秒；IF 主 URL 请求失败或超时, THEN THE Update_Service SHALL 自动尝试备用 CDN URL
3. IF 所有版本检测 URL 均失败, THEN THE Update_Service SHALL 返回空结果并通过调试日志记录失败原因，不向用户弹出错误提示
4. WHEN 远程 buildNumber 大于本地 buildNumber 时, THE Update_Service SHALL 依次尝试国内服务器 URL 和 GitHub Release URL 下载 APK；IF 主下载地址失败, THEN THE Update_Service SHALL 自动切换至备用下载地址
5. WHEN APK 下载完成后, THE Update_Service SHALL 验证文件大小不小于 1MB；IF 文件小于 1MB, THEN THE Update_Service SHALL 删除该文件并向调用方报告下载异常错误
6. IF 版本信息中 forceUpdate 字段为 true, THEN THE Update_Service SHALL 标记为强制更新模式，对应弹窗不可被用户关闭且不显示"稍后再说"按钮；IF forceUpdate 为 false, THEN THE Update_Service SHALL 标记为可选更新模式，用户可关闭弹窗跳过本次更新
7. THE Update_Service SHALL 通过进度回调报告下载进度（0.0 到 1.0），并提供取消下载方法；WHEN 用户取消下载时, THE Update_Service SHALL 立即中止网络请求并将下载状态重置为未下载
8. WHEN 合并完成后, THE Update_Service SHALL 确保删除冗余的旧服务文件，并更新项目中所有 import 引用指向新的统一服务文件

### Requirement 7: HTTP 强制跳转 HTTPS

**User Story:** As a 用户, I want 所有 HTTP 请求自动跳转到 HTTPS, so that 下载链接始终安全加密。

#### Acceptance Criteria

1. WHEN 客户端向端口 80 发送 HTTP GET 或 HEAD 请求时, THE Nginx_Server SHALL 返回 301 永久重定向响应，其 Location 头值为将原始 URL 的 scheme 从 http 替换为 https 后的完整 URL
2. WHEN Nginx_Server 执行 HTTP 到 HTTPS 重定向时, THE Nginx_Server SHALL 在 Location 头中完整保留原始请求的路径（包括 /releases/ 等子路径）和查询参数（即 ?key=value 部分）
3. THE Nginx_Server SHALL 对 sunnyklara.com 域名下的所有路径（包括根路径 / 和任意深度子路径）执行 HTTP 到 HTTPS 的 301 重定向
4. IF 客户端向端口 80 发送非 GET/HEAD 的 HTTP 请求（如 POST、PUT）, THEN THE Nginx_Server SHALL 返回 308 永久重定向以保证客户端使用原始 HTTP 方法重新请求 HTTPS 目标地址

### Requirement 8: 证书续期监控

**User Story:** As a 运维人员, I want 证书即将过期时收到告警, so that 我能在证书过期前完成续期避免服务中断。

#### Acceptance Criteria

1. THE Cert_Monitor SHALL 每天在固定时间（00:00–06:00 时间窗口内）检查 sunnyklara.com 的 TLS 证书剩余有效天数
2. IF 证书剩余有效天数少于 14 天, THEN THE Cert_Monitor SHALL 通过 Telegram 或企业微信 webhook 发送告警通知，且在证书续期完成前每天重复发送一次
3. THE Cert_Monitor SHALL 在告警消息中包含域名、证书过期日期和剩余有效天数
4. IF 证书检查脚本在 60 秒内未返回结果或以非零退出码结束, THEN THE Cert_Monitor SHALL 通过相同 webhook 通道发送执行失败告警
5. IF 证书剩余有效天数恢复至 14 天及以上, THEN THE Cert_Monitor SHALL 停止发送过期告警

### Requirement 9: CDN 加速

**User Story:** As a 国内用户, I want APK 下载速度更快, so that 更新体验更流畅。

#### Acceptance Criteria

1. THE CDN_Service SHALL 为 APK 下载域名配置阿里云 CDN 加速，使用独立子域名（cdn.sunnyklara.com）指向源站（sunnyklara.com/releases/），缓存过期时间设置为 30 天
2. WHEN a new APK is deployed to origin server, THE CDN_Service SHALL 在 CI 中通过阿里云 CLI 触发 CDN 缓存刷新，并在 120 秒内完成刷新操作
3. THE Update_Service SHALL 将 CDN 加速域名作为主下载地址，原始服务器地址作为 fallback
4. IF CDN 节点返回 HTTP 4xx/5xx 状态码或连接超时超过 10 秒, THEN THE Update_Service SHALL 自动回退到原始服务器下载，且回退过程对用户无需手动操作
5. IF CI 缓存刷新操作在 120 秒内未完成或返回失败状态, THEN THE CDN_Service SHALL 将刷新失败状态报告至 CI 日志并标记该部署步骤为失败
