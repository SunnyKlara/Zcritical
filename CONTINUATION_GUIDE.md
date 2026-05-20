# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-21 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。
> 历史决策详情见 `.kiro/steering/knowledge/decision-log.md`。

## 当前阶段：体验打磨期

功能全部跑通，进入打磨阶段。用户以产品经理身份提需求，AI 深入理解后设计实现。

**Git**：main 单分支 + tag 发版。当前 tag: `v1.0.0`。
Commit 规范：`类型: 中文描述`（feat/fix/refactor/docs/chore/perf/test/release）。
详见 `.kiro/steering/git-and-release.md`。

## 已完成

| 阶段 | 内容 |
|------|------|
| 固件迁移 | STM32→ESP32-S3 完全重写，idf.py build 零错误 |
| 菜单 UI | LCD 轮盘菜单 + 滑动动画 |
| APP 协议适配 | 14 项需求，51 个协议测试通过 |
| 引擎音效 | RC Engine 方案（idle+rev+knock+start），8-bit 混合 |
| 波浪灯效 | v4 宽波版确认 + 风速联动 + 舞台灯光秀 |
| 灯光 Pro 弹窗 | 4 效果（静态/波浪/风浪联动PRO/舞台灯光秀） |
| APP 音量控制 | 悬浮音量条，ESP32+APP 双端完成 |
| 产测自检 | 10 项硬件自检，NVS 产测锁 |
| App 自动升级 | GitHub Releases 分发 |
| 车库页面 | 占位版本（外层全屏 PageView） |
| **项目大扫除** | 删除 ~240MB 垃圾（旧参考项目/废弃头文件/临时脚本），文档体系重构 |
| **工程化提升** | 全文件头部注释 + main.c 分区 + specs 归档 + 健康指标 + .gitignore + dead code 清理 |

## 当前阻塞

- **⚠️ 风扇无法调速（硬件限制）** — GPIO 40 PWM 对风扇转速无影响，风扇只受 GPIO 10 开关控制
- **⚠️ 风扇无法调速（硬件限制）** — GPIO 40 PWM 对风扇转速无影响，风扇只受 GPIO 10 开关控制
- **LED 偶发闪烁** — RMT DMA 通道不足已回退，暂搁
- **DeviceConnectScreen ~3500 行** — 暂缓
- **分支 `feature/light-mode-pro-popup`** — 5 个 commit 待合入 main（用户已验证满意）

## 下一步

1. **P0 体验打磨** — 用户实玩记录体验问题 → 分类 → 批量修复
2. **P1 引擎音效调参** — RC Engine 方案待烧录验证最终效果
3. **P2 DeviceConnectScreen 拆分**
4. **P3 OTA 编译验证** — ESP32 端代码已完成，用户需手动 `idf.py build` 验证
5. **P4 OTA App 端** — Flutter BLE OTA 页面（下载 bin + 传输 + 进度条）
6. **P5 go_router + 国际化 + CI/CD**

## OTA 实现进度（Phase 10, 2026-05-21）

**ESP32 端：代码已完成，待编译验证**
- `services/ota_service.c/.h` — 流式写入（4KB 内部 SRAM 缓冲，不用 PSRAM）
- `ble_service.c` — OTA binary mode 路由（优先级最高）
- `protocol.c` — 支持 `OTA_BEGIN:size` / `OTA_END` / `OTA_ABORT`
- `main.c` — OTA 命令分发 + `ota_service_init()` rollback 自检
- `CMakeLists.txt` — 添加 `ota_service.c` + `app_update mbedtls` 依赖
- `sdkconfig.defaults` — `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y` + 版本号 1.0.0

**关键设计决策：**
- 不用 PSRAM 缓冲（flash 写入时 PSRAM 不可访问 — 硬件限制）
- 4KB 内部 SRAM 缓冲 + `esp_ota_write()` 流式写入
- SHA256 增量计算（可选）+ `esp_ota_end()` 内部 image 校验
- Rollback：首次启动自动确认（到达 app_main = pass）
- BLE 协议：`OTA_BEGIN:size\n` → binary mode → `OTA_END\n`

**⚠️ 首次编译注意：** 启用 ROLLBACK 改变 bootloader，需删除旧 `sdkconfig` 重新生成，首次烧录需全量（含 bootloader）。

## 编译状态

```
ESP32 固件：idf.py build — ⏳ 待验证（OTA 代码已加入，2026-05-21）
  ⚠️ idf.py build 全量可能报 littlefs-python 错误（Python 3.14），用 idf.py app 绕过
  ⚠️ sdkconfig.defaults 新增 ROLLBACK + APP_VER，需删除 sdkconfig 重新 fullclean
Flutter APP：flutter analyze — 待验证
协议测试：flutter test test/protocol/ — ✅ 51/51 通过
```

## 关键文件速查

| 用途 | 文件 |
|------|------|
| 固件入口 | `ridewind-esp/main/main.c` |
| 固件状态 | `ridewind-esp/main/app/app_state.h` |
| 固件协议 | `ridewind-esp/main/services/protocol.c` |
| 固件音频 | `ridewind-esp/main/services/audio_player.c` |
| APP 入口 | `RideWind/lib/main.dart` |
| APP 核心页面 | `RideWind/lib/screens/device_connect_screen.dart` |
| APP 蓝牙状态 | `RideWind/lib/providers/bluetooth_provider.dart` |
| APP 协议解析 | `RideWind/lib/protocol/protocol_parser.dart` |
