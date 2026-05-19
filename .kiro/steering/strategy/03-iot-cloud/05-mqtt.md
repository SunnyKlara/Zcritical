# 5. MQTT 实时通信

## 是什么
基于 MQTT 协议的设备-云端双向实时通信。设备上报状态（遥测数据），云端下发指令（远程控制）。是 IoT 系统的"神经网络"。

## 为什么需要
- 设备需要实时上报状态（在线、速度、温度、错误码）
- 云端需要实时下发指令（远程重启、配置更新、OTA 触发）
- HTTP 轮询太浪费资源，WebSocket 不适合低功耗设备
- MQTT 专为 IoT 设计：轻量、低带宽、支持离线消息、QoS 保证

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              MQTT 通信架构                            │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [设备端] ESP32 (通过 App 代理或直连 WiFi)          │
│       │ MQTT Client                                  │
│       │ 发布: device/{sn}/telemetry                  │
│       │ 订阅: device/{sn}/command                    │
│       ▼                                              │
│  [MQTT Broker]                                       │
│   EMQX / Mosquitto / 阿里云 IoT Core               │
│   ├─ 认证：Token / 证书 / 用户名密码               │
│   ├─ ACL：设备只能访问自己的 topic                  │
│   ├─ 持久会话：离线消息保留                         │
│   └─ 桥接：转发到后端消息队列                       │
│       │                                              │
│       ▼                                              │
│  [后端服务]                                          │
│   订阅所有设备 topic → 处理遥测 → 存储/告警        │
│   发布命令到指定设备 topic → 设备执行              │
│                                                      │
│  [管理后台/App]                                      │
│   WebSocket 实时展示设备状态                        │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 说明 |
|------|------|------|
| Broker | EMQX (开源版) | 百万级连接，集群支持 |
| 云托管 | 阿里云 IoT Core / AWS IoT | 零运维，设备认证集成 |
| 设备端 | esp-mqtt (ESP-IDF 组件) | 原生支持，TLS 加密 |
| App 代理 | App 作为 MQTT 网关 | BLE 设备无 WiFi 时通过 App 转发 |
| QoS | QoS 1 (至少一次) | 平衡可靠性和性能 |
| 序列化 | JSON / Protobuf / CBOR | JSON 可读，Protobuf 省带宽 |

## 实现步骤

### Phase 1：Broker 部署（1-2h）
1. EMQX Docker 部署（单节点开发环境）
2. 认证配置：用户名=设备SN，密码=Token（后端签发）
3. ACL 规则：设备只能 pub/sub 自己 SN 的 topic
4. TLS 加密：Let's Encrypt 证书

### Phase 2：Topic 设计（1h）
5. 命名规范：
   - 上行遥测：`device/{sn}/telemetry`
   - 下行命令：`device/{sn}/command`
   - 设备状态：`device/{sn}/status`（Will Message 实现离线检测）
   - 广播：`broadcast/all`（全设备通知）

### Phase 3：设备端集成（2-3h）
6. ESP32 MQTT 客户端（esp-mqtt）
7. 自动重连 + 指数退避
8. Last Will 消息（设备异常断开时 Broker 自动发布离线状态）
9. 遥测上报：定时（每 30s）+ 事件触发（状态变化时立即上报）

### Phase 4：后端消费（2h）
10. 后端订阅 `device/+/telemetry`（通配符匹配所有设备）
11. 消息解析 → 存储时序数据库
12. 异常检测 → 触发告警
13. 命令下发 API：`POST /api/devices/{sn}/command`

### Phase 5：App 代理模式（2-3h）
14. RideWind 场景：设备无 WiFi，通过 App BLE 连接
15. App 作为 MQTT 网关：BLE 收到设备数据 → MQTT 发布到云端
16. 云端命令 → App MQTT 订阅 → BLE 转发到设备

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| 海量连接 | Broker 内存/CPU 不够 | EMQX 集群 + 连接池 |
| 消息风暴 | 设备频繁上报打垮后端 | 限流 + 聚合（每 30s 一次） |
| 离线消息堆积 | 设备上线后收到大量旧消息 | 设置消息过期时间 |
| 认证泄露 | 伪造设备接入 | 一机一密 + Token 定期轮换 |
| QoS 2 性能差 | 四次握手延迟高 | 用 QoS 1 + 应用层去重 |
| WiFi 不稳定 | 频繁断连重连 | 指数退避 + 本地缓存待发消息 |

## 与 RideWind 的关系
- 当前状态：设备纯 BLE 通信，无云端连接
- 优先级：P4（有后端后扩展）
- 场景：设备状态云端监控、远程诊断、OTA 触发通知
- 特殊：RideWind 无 WiFi，需要 App 代理模式（BLE→App→MQTT→Cloud）

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| Broker 部署 | 1-2h | ⭐⭐ |
| Topic 设计 | 1h | ⭐ |
| ESP32 MQTT 客户端 | 2-3h | ⭐⭐⭐ |
| 后端消费 | 2h | ⭐⭐ |
| App 代理模式 | 2-3h | ⭐⭐⭐ |
| **总计** | **~2 天** | |

## 学到什么
- MQTT 协议深入（QoS、Retain、Will、Session）
- IoT 通信架构设计
- 消息 Broker 运维（EMQX/Mosquitto）
- 设备认证和访问控制
- 实时数据管线（采集→传输→存储→展示）
- 网关模式（BLE 设备通过 App 代理上云）
