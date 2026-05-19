# 1. 设备端 OTA 升级系统

## 是什么

固件远程升级（Over-The-Air）。用户不拔线不返厂，App 一键推送新固件到 ESP32。

## 为什么需要

- 出厂后发现 bug 无法修复 = 产品召回
- 新功能无法交付给老用户
- 安全漏洞无法远程修补
- 竞品都有 OTA，没有 = 产品力短板

## 技术架构

```
┌─────────┐    ┌──────────┐    ┌────────────┐
│  云存储  │ ←  │  后端 API │ ←  │  管理后台   │
│ (固件bin)│    │(版本管理) │    │(发布/灰度) │
└────┬────┘    └─────┬────┘    └────────────┘
     │               │
     │  ┌────────────┘
     ▼  ▼
┌──────────┐         ┌──────────┐
│   App    │ ──BLE── │  ESP32   │
│(下载+传输)│         │(接收+写入)│
└──────────┘         └──────────┘
```

两种路径：
- **BLE OTA**（当前场景）：App 从云端下载 bin → BLE 分块传输 → ESP32 写入 ota 分区
- **WiFi OTA**（未来扩展）：ESP32 直连云端 HTTPS 下载 → 自写入

## 技术栈选型

| 层 | 技术 | 理由 |
|----|------|------|
| ESP32 OTA 引擎 | `esp_ota_ops` API + 双分区 | ESP-IDF 原生，成熟稳定 |
| 分区表 | `ota_0` + `ota_1` 各 1.5MB | A/B 分区，写入失败可回滚 |
| BLE 传输协议 | 自定义分块协议（MTU 协商） | 控制粒度，支持断点续传 |
| App 端 | Flutter + `flutter_reactive_ble` | 已有 BLE 基础设施 |
| 后端 | Node.js/Go + 阿里云 OSS | 固件存储 + 版本管理 API |
| 安全 | Secure Boot v2 + 固件签名 | 防止刷入篡改固件 |

## 实现步骤（AI 协作流程）

### Phase 1：ESP32 端 OTA 接收（2-3h）

1. **分区表改造**
   - 当前：`factory`(3MB) + `storage`(1.4MB)
   - 目标：`ota_0`(1.5MB) + `ota_1`(1.5MB) + `storage`(1MB)
   - 文件：`partitions.csv`

2. **OTA 写入逻辑**
   ```c
   // services/ota_service.c
   esp_ota_handle_t handle;
   const esp_partition_t *update = esp_ota_get_next_update_partition(NULL);
   esp_ota_begin(update, OTA_SIZE_UNKNOWN, &handle);
   // 循环接收 BLE 数据包
   esp_ota_write(handle, data, len);
   // 全部写完
   esp_ota_end(handle);
   esp_ota_set_boot_partition(update);
   esp_restart();
   ```

3. **回滚机制**
   - 首次启动标记 `esp_ota_mark_app_valid_and_cancel_rollback()`
   - 如果新固件 crash（watchdog 超时），自动回滚到旧分区

### Phase 2：BLE 传输协议（3-4h）

4. **协议设计**
   ```
   CMD_OTA_BEGIN:  {total_size, chunk_size, firmware_version, crc32}
   CMD_OTA_DATA:   {seq_num, data[chunk_size]}
   CMD_OTA_VERIFY: {crc32_calculated}
   CMD_OTA_ABORT:  {}
   RSP_OTA_ACK:    {seq_num, status}  // 每 N 包确认一次
   ```

5. **MTU 协商**
   - 请求 MTU=517（实际有效载荷 512）
   - 每包 512 字节，1MB 固件 ≈ 2048 包
   - 滑动窗口确认（每 8 包 ACK 一次，减少往返）

6. **断点续传**
   - ESP32 NVS 存储：`ota_progress = {version, last_seq, crc_partial}`
   - App 重连后查询进度 → 从断点继续

### Phase 3：App 端 UI（2h）

7. **固件更新页面**
   - 检查更新 → 显示版本号/更新日志 → 确认下载 → 进度条 → 完成重启
   - 后台下载 bin 到本地缓存
   - BLE 传输进度实时显示（百分比 + 预计剩余时间）

### Phase 4：后端版本管理（2-3h）

8. **API 设计**
   ```
   POST /api/firmware/upload     — 上传新固件（管理员）
   GET  /api/firmware/latest     — 查询最新版本（App 调用）
   GET  /api/firmware/download/:id — 下载固件文件
   POST /api/firmware/rollback/:id — 标记版本为不可用
   ```

9. **灰度规则**
   - 按设备 ID 百分比（先 1% → 10% → 100%）
   - 按固件版本（只有 v1.2+ 可以升级到 v1.3）
   - 按地区/用户标签

### Phase 5：安全（1-2h）

10. **固件签名**
    - 构建时：`espsecure.py sign_data --keyfile private.pem firmware.bin`
    - 设备端：Secure Boot v2 验证签名，不通过拒绝写入
    - 密钥管理：私钥不入库，CI/CD 环境变量注入

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| BLE 带宽限制 | MTU=512 时 1.5MB 需 3000 包 ≈ 5-8 分钟 | 滑动窗口 + 连接参数优化（interval=7.5ms） |
| 传输中途断开 | 从头重传浪费时间 | NVS 存断点 + CRC 校验已写入部分 |
| 写入一半断电 | 新分区不完整 | A/B 分区天然解决：旧分区完好 |
| 版本号未递增 | 降级攻击 | 固件内嵌版本号，OTA 逻辑拒绝降级 |
| 分区大小不够 | 固件膨胀后 OTA 失败 | 预留 20% 余量，监控固件体积 |
| iOS 后台杀进程 | 传输中断 | 前台保活 + 断点续传 |
| 签名密钥泄露 | 任何人可刷恶意固件 | HSM 或 CI 密钥隔离，定期轮换 |

## 与 RideWind 的关系

- 当前状态：`main.c` 中 OTA 命令返回 `NOT_IMPL`，上架前必须实现
- 分区表需要从 factory 模式改为 ota 模式（**破坏性变更，需重新全量烧录**）
- 固件当前 2.69MB，ota 分区 1.5MB 不够 → 需要优化固件体积或加大 flash
- 音频素材走 LittleFS 独立分区，不随 OTA 更新（除非单独做资源 OTA）

## 预计工作量（AI 协作）

| 模块 | 时间 | 难度 |
|------|------|------|
| 分区表 + ESP32 OTA 核心 | 2-3h | ⭐⭐ |
| BLE 传输协议 | 3-4h | ⭐⭐⭐ |
| 断点续传 + 错误恢复 | 2h | ⭐⭐⭐ |
| App UI | 2h | ⭐⭐ |
| 后端 API | 2-3h | ⭐⭐ |
| 安全签名 | 1-2h | ⭐⭐ |
| **总计** | **~2 天** | |

## 学到什么

- ESP-IDF 分区表机制和 A/B 升级原理
- BLE 大数据传输协议设计（分包、确认、重传）
- 固件签名和安全启动链
- 灰度发布策略
- 嵌入式系统的容错设计思维
