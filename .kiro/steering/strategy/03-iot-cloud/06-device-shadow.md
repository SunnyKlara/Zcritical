# 6. 设备影子/数字孪生

## 是什么
云端维护每台设备的"虚拟副本"（Shadow/Twin）。即使设备离线，云端仍能查询其最后已知状态，也能预设期望状态等设备上线后同步。

## 为什么需要
- 设备经常离线（BLE 断开、无 WiFi），但用户/管理员需要随时查看状态
- 下发配置时设备可能不在线 → 存入影子 → 设备上线自动同步
- 解耦"查询设备状态"和"设备是否在线"
- 数字孪生是工业 IoT 的核心概念，学会后可做更复杂场景

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              设备影子架构                             │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [设备端]                                            │
│   上报当前状态 → reported state                     │
│   上线时拉取 → desired state → 执行 → 上报 reported│
│                                                      │
│  [云端影子]                                          │
│   ┌─────────────────────────────────────┐           │
│   │  Device Shadow (per device)          │           │
│   │  {                                   │           │
│   │    "reported": {                     │           │
│   │      "brightness": 80,              │           │
│   │      "mode": "wave",                │           │
│   │      "firmware": "1.2.0",           │           │
│   │      "speed": 25                    │           │
│   │    },                                │           │
│   │    "desired": {                      │           │
│   │      "brightness": 100,             │           │
│   │      "mode": "static"               │           │
│   │    },                                │           │
│   │    "delta": {                        │           │
│   │      "brightness": 100,             │           │
│   │      "mode": "static"               │           │
│   │    },                                │           │
│   │    "metadata": { "timestamp": ... }  │           │
│   │  }                                   │           │
│   └─────────────────────────────────────┘           │
│                                                      │
│  [应用端]                                            │
│   查询影子 → 获取设备最后状态（即使离线）          │
│   更新 desired → 等设备上线自动同步               │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 说明 |
|------|------|------|
| 云托管 | AWS IoT Device Shadow / 阿里云设备影子 | 开箱即用 |
| 自建 | Redis Hash + PostgreSQL | 灵活可控 |
| 同步协议 | MQTT ($shadow/get, $shadow/update) | 标准 IoT 影子 topic |
| 冲突解决 | 时间戳 + 版本号 | 最后写入胜出 |
| 存储 | Redis (热) + PostgreSQL (持久化) | 读快写快 + 不丢数据 |

## 实现步骤

### Phase 1：影子数据模型（1-2h）
1. 定义影子 JSON Schema（reported/desired/delta/metadata）
2. 数据库表设计：`device_shadows` (sn, reported JSONB, desired JSONB, version, updated_at)
3. Redis 缓存：`shadow:{sn}` → 最新影子 JSON

### Phase 2：影子 API（2-3h）
4. GET /api/devices/{sn}/shadow — 查询当前影子
5. PUT /api/devices/{sn}/shadow/desired — 更新期望状态
6. Delta 计算：desired 和 reported 的差集 → 需要同步的字段
7. 版本控制：每次更新 version+1，防止并发冲突

### Phase 3：设备同步逻辑（2-3h）
8. 设备上线 → 拉取影子 → 比较 delta → 执行变更 → 上报 reported
9. 设备状态变化 → 上报 reported → 云端更新影子
10. 冲突处理：如果 desired 和 reported 一致 → 清除 delta

### Phase 4：App 集成（1-2h）
11. App 查询影子显示设备状态（即使 BLE 未连接）
12. App 修改 desired → 下次 BLE 连接时同步到设备
13. 实时通知：影子变化时推送 App（WebSocket/Push）

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| 影子过大 | 存储和传输成本高 | 只存关键状态，不存遥测流数据 |
| 并发更新 | 数据覆盖 | 乐观锁（version 字段） |
| 离线太久 | desired 堆积大量变更 | 只保留最新 desired，不累积 |
| 同步延迟 | 用户以为设置了但设备没变 | UI 明确显示"待同步"状态 |
| 循环更新 | 设备上报 → 触发 desired → 又上报 | 只在 delta 非空时才下发 |

## 与 RideWind 的关系
- 当前状态：无云端，设备状态只在 BLE 连接时可见
- 优先级：P4（有 MQTT 后自然扩展）
- 场景：用户打开 App 时立即看到设备上次状态（不用等 BLE 连接）
- 依赖：#5 MQTT 通信 或 App 代理上报

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| 数据模型 + API | 2-3h | ⭐⭐ |
| Delta 计算逻辑 | 1-2h | ⭐⭐⭐ |
| 设备同步协议 | 2-3h | ⭐⭐⭐ |
| App 集成 | 1-2h | ⭐⭐ |
| **总计** | **~1.5 天** | |

## 学到什么
- 设备影子/数字孪生概念
- 最终一致性在 IoT 中的应用
- 离线优先（Offline-First）架构
- 状态同步和冲突解决策略
- JSON Patch / Diff 算法
- 云 IoT 平台核心能力理解
