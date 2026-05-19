---
inclusion: manual
---

# 软件战略全景 — 50 项技术系统

> 定位：以 RideWind 为练手项目，全方位学习从设备到云端的完整技术栈。
> 每一项都是一个可独立实现的子系统，按类别分目录详细展开。

## 总表

| # | 名称 | 类别 | 详细文档 |
|---|------|------|----------|
| 1 | 设备端 OTA 升级系统 | 设备端 | [→](strategy/01-device/01-ota.md) |
| 2 | 后端用户系统 | 后端 | [→](strategy/02-backend/02-user-system.md) |
| 3 | 后端设备管理 | 后端 | [→](strategy/02-backend/03-device-management.md) |
| 4 | 后端数据存储 | 后端 | [→](strategy/02-backend/04-data-storage.md) |
| 5 | MQTT 实时通信 | IoT/云 | [→](strategy/03-iot-cloud/05-mqtt.md) |
| 6 | 设备影子/数字孪生 | IoT/云 | [→](strategy/03-iot-cloud/06-device-shadow.md) |
| 7 | 推送通知系统 | 触达/营销 | [→](strategy/07-marketing/07-push-notification.md) |
| 8 | 短信/邮件触达 | 触达/营销 | [→](strategy/07-marketing/08-sms-email.md) |
| 9 | API 网关 | 后端 | [→](strategy/02-backend/09-api-gateway.md) |
| 10 | CI/CD 流水线 | 运维/DevOps | [→](strategy/05-devops/10-cicd.md) |
| 11 | 容器化部署 | 运维/DevOps | [→](strategy/05-devops/11-containerization.md) |
| 12 | 日志收集与监控 | 运维/DevOps | [→](strategy/05-devops/12-logging-monitoring.md) |
| 13 | 自动化测试体系 | 运维/DevOps | [→](strategy/05-devops/13-testing.md) |
| 14 | 灰度发布/Feature Flag | 运维/DevOps | [→](strategy/05-devops/14-feature-flag.md) |
| 15 | 数据埋点与分析 | 数据/分析 | [→](strategy/06-data/15-analytics.md) |
| 16 | 数据看板/BI | 数据/分析 | [→](strategy/06-data/16-bi-dashboard.md) |
| 17 | SEO/内容营销系统 | 内容/SEO | [→](strategy/08-content/17-seo.md) |
| 18 | Web 管理后台 | 前端 | [→](strategy/04-frontend/18-web-admin.md) |
| 19 | 小程序 | 前端 | [→](strategy/04-frontend/19-mini-program.md) |
| 20 | 桌面配置工具 | 前端 | [→](strategy/04-frontend/20-desktop-tool.md) |
| 21 | 固件安全启动 | 设备端 | [→](strategy/01-device/21-secure-boot.md) |
| 22 | 低功耗设计 | 设备端 | [→](strategy/01-device/22-low-power.md) |
| 23 | 传感器融合 | 设备端 | [→](strategy/01-device/23-sensor-fusion.md) |
| 24 | 消息队列 | 后端 | [→](strategy/02-backend/24-message-queue.md) |
| 25 | 工单/客服系统 | 运营/客服 | [→](strategy/09-operation/25-ticket-system.md) |
| 26 | 电商系统 | 商业/电商 | [→](strategy/10-business/26-ecommerce.md) |
| 27 | 支付系统 | 商业/电商 | [→](strategy/10-business/27-payment.md) |
| 28 | 安全合规 | 安全/合规 | [→](strategy/11-security/28-compliance.md) |
| 29 | 基础设施即代码 | 运维/DevOps | [→](strategy/05-devops/29-iac.md) |
| 30 | 服务网格 | 运维/DevOps | [→](strategy/05-devops/30-service-mesh.md) |
| 31 | 音频 DSP 引擎 | 设备端 | [→](strategy/01-device/31-audio-dsp.md) |
| 32 | 显示驱动与 UI 框架 | 设备端 | [→](strategy/01-device/32-display-ui.md) |
| 33 | 文件存储服务 | 后端 | [→](strategy/02-backend/33-file-storage.md) |
| 34 | 用户行为分析 | 数据/分析 | [→](strategy/06-data/34-user-behavior.md) |
| 35 | 社区/论坛系统 | 社区/功能 | [→](strategy/12-community/35-forum.md) |
| 36 | 用户 UGC 分享 | 社区/功能 | [→](strategy/12-community/36-ugc.md) |
| 37 | 成就/勋章系统 | 社区/功能 | [→](strategy/12-community/37-achievement.md) |
| 38 | App 国际化 | 前端 | [→](strategy/04-frontend/38-i18n.md) |
| 39 | App 无障碍 | 前端 | [→](strategy/04-frontend/39-accessibility.md) |
| 40 | 微服务拆分 | 后端 | [→](strategy/02-backend/40-microservices.md) |
| 41 | BLE 协议栈深度 | 设备端 | [→](strategy/01-device/41-ble-deep.md) |
| 42 | 固件配置系统 | 社区/功能 | [→](strategy/12-community/42-firmware-config.md) |
| 43 | 多设备协同 | 社区/功能 | [→](strategy/12-community/43-multi-device.md) |
| 44 | 电机控制算法 | 设备端 | [→](strategy/01-device/44-motor-control.md) |
| 45 | 产测系统 | 设备端 | [→](strategy/01-device/45-production-test.md) |
| 46 | A/B 测试平台 | 数据/分析 | [→](strategy/06-data/46-ab-testing.md) |
| 47 | 裂变/邀请系统 | 触达/营销 | [→](strategy/07-marketing/47-referral.md) |
| 48 | 订阅/会员体系 | 商业/电商 | [→](strategy/10-business/48-subscription.md) |
| 49 | 远程诊断 | 运营/客服 | [→](strategy/09-operation/49-remote-diagnosis.md) |
| 50 | 售后数据闭环 | 运营/客服 | [→](strategy/09-operation/50-after-sales-loop.md) |

## 类别索引

| 类别 | 编号 | 项数 |
|------|------|------|
| 设备端 | 1, 21, 22, 23, 31, 32, 41, 44, 45 | 9 |
| 后端 | 2, 3, 4, 9, 24, 33, 40 | 7 |
| IoT/云设备通信 | 5, 6 | 2 |
| 前端（Web/小程序/桌面） | 18, 19, 20, 38, 39 | 5 |
| 运维/DevOps | 10, 11, 12, 13, 14, 29, 30 | 7 |
| 数据/分析 | 15, 16, 34, 46 | 4 |
| 触达/营销 | 7, 8, 47 | 3 |
| 商业/电商 | 26, 27, 48 | 3 |
| 运营/客服 | 25, 49, 50 | 3 |
| 社区/功能 | 35, 36, 37, 42, 43 | 5 |
| 内容/SEO | 17 | 1 |
| 安全/合规 | 28 | 1 |

## 展开进度

- [x] 设备端（9 项）
- [x] 后端（7 项）
- [x] IoT/云（2 项）
- [x] 前端（5 项）
- [x] 运维/DevOps（7 项）
- [x] 数据/分析（4 项）
- [x] 触达/营销（3 项）
- [x] 商业/电商（3 项）
- [x] 运营/客服（3 项）
- [x] 社区/功能（5 项）
- [x] 内容/SEO（1 项）
- [x] 安全/合规（1 项）
