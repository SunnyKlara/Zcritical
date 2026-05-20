---
inclusion: manual
---

# 41. BLE 协议栈深度

## 是什么

深入理解 BLE（Bluetooth Low Energy）从物理层到应用层的完整协议栈，掌握 GATT 服务设计、连接参数优化、多设备管理、安全配对、吞吐量极限压榨。不只是"能连上"，而是"连得稳、传得快、功耗低"。

## 为什么需要

- BLE 是 IoT 设备与手机通信的主流方式，必须精通
- 连接不稳定是用户投诉 #1（断连、重连慢、数据丢失）
- OTA 传输速度直接取决于 BLE 吞吐量优化
- 安全配对防止中间人攻击和数据窃听
- 多设备场景（一个 App 控制多台设备）需要连接管理

## 技术架构

```
┌─────────────────────────────────────────────────────┐
│                BLE 协议栈分层                         │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [应用层]                                            │
│   自定义协议 (protocol.c)                            │
│       │                                              │
│       ▼                                              │
│  [GATT 层]                                           │
│   Service → Characteristic → Descriptor             │
│   RideWind Service (UUID: 自定义 128-bit)           │
│     ├─ TX Char (Notify, 设备→App)                   │
│     ├─ RX Char (Write, App→设备)                    │
│     └─ OTA Char (Write No Response, 大数据)         │
│       │                                              │
│       ▼                                              │
│  [ATT 层]                                            │
│   MTU 协商 / 属性读写 / 通知指示                    │
│       │                                              │
│       ▼                                              │
│  [L2CAP 层]                                          │
│   逻辑通道复用 / 流控 / 分片重组                    │
│       │                                              │
│       ▼                                              │
│  [Link Layer]                                        │
│   连接管理 / 跳频 / 加密                            │
│       │                                              │
│       ▼                                              │
│  [PHY 层]                                            │
│   1M / 2M / Coded (Long Range)                      │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型

| 组件 | 技术 | 说明 |
|------|------|------|
| ESP32 BLE 栈 | NimBLE (ESP-IDF 集成) | 比 Bluedroid 更轻量 |
| App 端 | flutter_reactive_ble | 跨平台，API 清晰 |
| GATT 设计 | 自定义 128-bit UUID Service | 避免与标准服务冲突 |
| 安全 | LE Secure Connections (LESC) | ECDH 密钥交换 |
| PHY | 2M PHY (ESP32-S3 支持) | 吞吐量翻倍 |
| 调试 | nRF Connect / Wireshark + nRF Sniffer | 抓包分析 |

## 实现步骤

### Phase 1：GATT 服务设计（2h）

1. **服务结构定义**
   - RideWind Service: 1 个主服务，3 个 Characteristic
   - TX Char: Notify（设备主动推送状态）
   - RX Char: Write（App 发送命令）
   - OTA Char: Write Without Response（大数据高吞吐）

2. **Characteristic 属性选择**
   - Notify vs Indicate：Notify 无确认低延迟，Indicate 有确认可靠
   - Write vs Write No Response：命令用 Write（确保送达），流数据用 WNR（最大速度）

### Phase 2：连接参数优化（2-3h）

3. **参数调优**
   - 高吞吐场景（OTA）：interval=7.5ms, latency=0
   - 低功耗场景（待机）：interval=100-200ms, latency=4
   - 动态切换：传输开始前切快速，传输完切慢速

4. **MTU 协商**
   - 请求 MTU=517（有效载荷 514 bytes）
   - iOS 限制：通常 185-517，取决于设备型号
   - 回退策略：协商失败用默认 23 bytes

5. **2M PHY 切换**
   - ESP32-S3 支持 2M PHY，吞吐量翻倍
   - 需要对端也支持（大部分现代手机都支持）

### Phase 3：吞吐量极限（2-3h）

6. **理论极限**
   - CI=7.5ms, 每 CI 6 包, 每包 251B (DLE) = ~200 KB/s 理论
   - 实际 80-120 KB/s（含协议开销和调度延迟）

7. **Data Length Extension (DLE)**
   - 单包从 27 字节扩展到 251 字节
   - 减少包头开销，显著提升吞吐

8. **批量发送策略**
   - Write Without Response 连续发，不等 ACK
   - 监控 TX buffer 满事件做流控
   - App 端控制发送节奏防止 Controller 溢出

### Phase 4：安全配对（2h）

9. **LE Secure Connections**
   - Just Works（无 IO 能力设备）
   - Bonding：配对信息存 NVS，重启免重配
   - 最多 N 个配对设备，LRU 淘汰

10. **Bonding 管理**
    - 配对信息持久化（NVS）
    - App "忘记设备"时清除 bond
    - 检测 bond 失效（对端删除配对后）自动重配

### Phase 5：稳定性与重连（2h）

11. **断连处理**
    - 记录断连原因码（supervision timeout / remote terminate / etc）
    - 立即重新广播
    - 通知应用层清理状态

12. **连接质量监控**
    - RSSI 定期读取
    - 丢包率统计
    - 自适应：信号弱时降低数据率

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| iOS 连接参数限制 | Apple 拒绝 <15ms interval | 区分平台，iOS 用 15ms |
| MTU 协商失败 | 默认 23 字节，OTA 极慢 | 主动请求 + 回退处理 |
| Android 碎片化 | 不同手机 BLE 行为不一致 | 大量真机测试 + 兼容逻辑 |
| 后台断连 (iOS) | App 进后台 30s 后断开 | Background Mode + 定期心跳 |
| 配对信息丢失 | 用户清 App 数据后无法连接 | 设备端检测 bond 失效，删除重配 |
| 多设备干扰 | 2.4GHz 拥挤环境丢包 | 自适应跳频 + 重传机制 |
| NimBLE 内存不足 | 连接数多时 OOM | 限制最大连接数，调整 mbuf 池 |

## 与 RideWind 的关系

- 当前状态：BLE 基础通信已实现（NimBLE，单连接，自定义协议）
- 已有：GATT 服务、Notify/Write、协议解析
- 缺失：MTU 优化、PHY 切换、安全配对、断连重连策略、OTA 通道
- 痛点：偶尔断连、iOS 后台不稳定、OTA 未实现

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| GATT 重构（加 OTA Char） | 1-2h | ⭐⭐ |
| 连接参数优化 | 2h | ⭐⭐⭐ |
| MTU + DLE + 2M PHY | 2h | ⭐⭐⭐ |
| 安全配对 | 2h | ⭐⭐⭐ |
| 断连重连策略 | 2h | ⭐⭐⭐ |
| 吞吐量测试验证 | 1-2h | ⭐⭐ |
| **总计** | **~2 天** | |

## 学到什么

- BLE 协议栈完整分层理解
- GATT 服务设计最佳实践
- 无线通信参数调优方法论
- 跨平台 BLE 兼容性处理（iOS/Android 差异）
- 嵌入式安全通信（密钥交换、加密）
- 性能测量和瓶颈分析
