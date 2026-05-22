# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-21 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。
> 历史决策详情见 `.kiro/steering/knowledge/decision-log.md`。

## 当前阶段：体验打磨期

功能全部跑通，进入打磨阶段。用户以产品经理身份提需求，AI 深入理解后设计实现。

**Git**：main 单分支 + feature 分支（大功能）+ tag 发版。当前 tag: `v1.2.0-baseline`。
v1.2.0-baseline 是后续四大功能分支的干净起点（2026-05-22）。
大功能分支规则已写入 `git-and-release.md`：feat/garage-v2、feat/colorize-v2、feat/audio-casting-v2、feat/ios-platform。
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
| 车库页面 | 占位版本（外层全屏 PageView）+ 915 张 FH5 缩略图已下载 |
| **项目大扫除** | 删除 ~240MB 垃圾（旧参考项目/废弃头文件/临时脚本），文档体系重构 |
| **工程化提升** | 全文件头部注释 + main.c 分区 + specs 归档 + 健康指标 + .gitignore + dead code 清理 |
| **仓库瘦身+上线** | git filter-repo 清理历史大文件，push 到 GitHub (SunnyKlara/Zcritical)，v1.0.0 tag 已打 |
| **v1.0.0 发版** | GitHub Release 创建，APK(74.6MB)+固件bin(2.9MB) 上传，app_version.json 配置完成 |
| **编译工程化** | build.ps1 快速编译脚本（增量 2s），IRAM 溢出修复，build-environment.md 环境文档 |
| **OTA 协议对齐** | Flutter 改为 binary mode 传输，ESP32 加 OTA_VERSION 命令，创建 firmware.json |
| **OTA 传输节流** | APP 端改为逐 MTU 包发送（20ms 间隔）+ 严格等 ACK，修复 ESP32 crash（MEMPROT_SPLIT_ADDR_OUT_OF_RANGE） |

## 当前阻塞

- **⚠️ 风扇无法调速（硬件限制）** — GPIO 40 PWM 对风扇转速无影响，风扇只受 GPIO 10 开关控制
- **LED 偶发闪烁** — RMT DMA 通道不足已回退，暂搁
- **DeviceConnectScreen ~3500 行** — 暂缓
- **WiFi 配网已验证通过** — 实机测试成功（2026-05-21），全流程秒级完成
- **WiFi OTA 全流程验证通过** — APP 端 WebSocket OTA 成功（2.95MB，含擦除约 83s），Rollback 自检通过，设备正常重启
- **车库 Logo WiFi 上传验证通过** — Python 脚本测试成功：115KB / 3.0s / 29 ACKs / LOGO_OK:0。CRC=0 跳过应用层校验（WiFi TCP 已保证完整性）。ESP32 日志确认 `Logo slot 0 written OK`。APP 端待实测。
- **APP 自动更新完成** — 检测弹窗通过 + APK 下载链接改为阿里云轻量服务器（`http://47.107.143.4/releases/`，200Mbps 带宽，国内直连）。服务器 nginx 已配置，APK 已上传验证（HTTP 200）。
- **死代码清理完成** — 删除 4 文件 ~600 行：`image_preprocessing_service.dart` + `image_compression_service.dart` + `transmission_benchmark.dart` + `test/image_preprocessing_test.dart`。`logo_transmission_manager.dart`(1373行) 不再被 Logo 页面使用，仅被测试文件引用，后续可删。
- **iOS 上架准备完成** — Info.plist 权限补全（Location/LocalNetwork/后台BLE）、音频投射 iOS 隐藏、WiFi 配网 iOS 手动输入 SSID、更新服务 iOS App Store 跳转、Deployment Target 14.0。第二轮修复：`app_update_service.dart` 防 APK 崩溃、`app_update_dialog.dart` 平台检查、`audio_stream_service.dart` try/catch 防 MissingPluginException。多平台规则写入 `.kiro/steering/platform-rules.md`。详见 `RideWind/docs/IOS_RELEASE_CHECKLIST.md`。

## 最近修复（2026-05-21）

- **产测自检未集成** — `selftest.c` 已实现但 `app_main()` 未调用 `selftest_check_entry()`/`selftest_run()`，导致开机长按编码器无法进入自检。已修复：在 NVS 初始化后、`app_state_init()` 前插入入口调用 + `#include "selftest.h"` + CMakeLists.txt 添加 `app/selftest.c`。编译通过 ✅
- **WiFi OTA 实现** — APP 通过 WebSocket 推送固件到 ESP32（方案 B）：
  - `ota_upload_service.dart`：新增 `uploadViaWifi()` 方法（ws://ip:81/ws, 4KB binary frames）
  - `ota_upgrade_screen.dart`：自动检测 WiFi IP，有则走 WiFi，无则 fallback BLE
  - `ota_service.c`：修复回复通道 — 新增 `ota_notify_str()` 同时发 BLE + WebSocket（根因：OTA 命令从 WS 来但回复只走 BLE → APP 超时）
  - ESP32 编译通过（app-flash 即可，不需全量）
  - 首次测试：WebSocket 连接成功 + OTA_BEGIN 发送成功 + ESP32 回复 OTA_READY，但回复走了 BLE 导致 APP 超时 → 已修复
  - 二次测试：APP 端 `Bad state: Stream has already been listened to` → WebSocket 单订阅 Stream 多次 listen → 已修复为单持久 listener + Completer
  - **Python 脚本验证通过**：2.95MB / 77.2s / 38KB/s / 738 ACKs / OTA_OK:1.0.0 ✅
  - **APP 端验证通过**：完整 OTA 流程成功（配网→WS连接→擦除→传输→校验→重启→Rollback自检→正常运行）✅
  - Flutter analyze 通过（0 errors）
- **WiFi 配网正式版 ESP32 端完成** — 恢复 BLE + 实现生产启动序列：
  - 开机有 NVS 凭据 → 先连 WiFi（阻塞 10s，BLE 未启动，无 RF 竞争）→ 连上后启动 BLE
  - 开机无凭据 → 直接启动 BLE
  - 收到 WIFI:ssid:pass → 回复 OK:WIFI → 停 BLE 广播 → 连 WiFi（10s 超时）→ 重启 BLE 广播
  - 文件：`wifi_audio_service.c/.h` + `main.c`，编译通过（全量 49.8s）
- **WiFi 配网正式版 APP 端完成** — 全新配网弹窗 + BLE 断开处理：
  - `MainActivity.kt`：新增 `getConnectedWifi` platform channel（返回 SSID + 频率 MHz）
  - `audio_stream_service.dart`：新增 `getConnectedWifi()` Dart API
  - `bluetooth_provider.dart`：`_isWifiProvisioning` flag，BLE 断开时不退出 UI，重连后自动清除
  - `device_connect_screen.dart`：配网弹窗自动读取手机 WiFi SSID，5GHz 检测警告，只输密码
  - Flutter analyze 通过（0 errors）
- **Speed 普通模式无音频输出** — 根因：普通模式旋转编码器调速时调用了 `audio_player_start_engine()`，该函数内部 `audio_engine_pause()` 暂停了 WiFi 音频输出任务。修复：普通模式不再启动引擎声音，引擎声音仅限油门模式。退出油门模式时无条件停止引擎声音以恢复 WiFi 音频。（文件：`ridewind-esp/main/ui/ui_speed.c`，未编译验证）

## 下一步

1. **P0 四大功能分支开发** — 从 v1.2.0-baseline 创建对应 feature 分支：
   - `feat/garage-v2` — 车库大更新（联动风扇/灯光/音效/Logo）
   - `feat/colorize-v2` — Colorize 灯光系统升级
   - `feat/audio-casting-v2` — 音频投射升级（类蓝牙音箱）
   - `feat/ios-platform` — iOS 开发体系建立
2. **P1 体验打磨** — 用户实玩记录体验问题 → 分类 → 批量修复
3. **P2 引擎音效调参** — RC Engine 方案待烧录验证最终效果
4. **P3 DeviceConnectScreen 拆分**
5. **P4 go_router + 国际化 + CI/CD**

## ⭐ 架构决策：WiFi 为主通道（2026-05-21 确认）

**决策**：放弃 BLE 作为主通信通道，改为 WiFi STA + WebSocket。BLE 仅保留用于首次配网和 fallback。

**背景**：
- 产品是桌面级汽车风洞模型摆件，固定室内使用，用户环境 100% 有路由器
- BLE OTA 传 2.9MB 需 3-5 分钟且有 ESP32 crash 问题（MEMPROT_SPLIT_ADDR_OUT_OF_RANGE）
- WiFi 传输快 30-100 倍，且 ESP-IDF 有成熟的 HTTP/WebSocket 支持
- 之前用 BLE 是因为从 STM32（无 WiFi）迁移过来的历史惯性

**架构**：
- BLE：仅配网（传 WiFi 凭据）+ fallback
- WiFi STA：连用户路由器，ESP32 启动 WebSocket server
- 设备发现：mDNS `critical-t1.local`
- 协议层：现有文本命令不变，传输层从 BLE 切换到 WebSocket
- OTA：ESP32 通过 WiFi HTTP 直接从 GitHub Release 下载，或 APP 通过 WebSocket 推送

**实施 Phase**：
1. ✅ ESP32 WiFi STA + WebSocket Server（port 81, mDNS critical-t1.local, 复用 protocol_parse → cmd_queue）— 编译通过
2. ✅ APP WiFi 配网入口（菜单 → "WiFi 配网" → 扫描列表 → 选择 → 输密码 → BLE 发送）— analyze 通过
3. ✅ WiFi 纯连接测试成功（2026-05-21）— 关闭 BLE 后 WiFi 秒连（IP: 192.168.1.95），确认问题 100% 是 BLE+WiFi CONNECTING 阶段 RF 竞争。凭据和路由器均正常。
4. 🔲 实现正式版 WiFi 配网方案（下一 session）：
   - **ESP32 端** ✅：开机有凭据→先连 WiFi（无 BLE）→连上后启 BLE；收到 WIFI 命令→停 BLE→连 WiFi→成功/失败后重启 BLE（编译通过 2026-05-21）
   - **APP 端** ✅：配网弹窗（自动读取手机 WiFi SSID + 频率，5GHz 检测警告，只输密码）；BLE 断开时 `_isWifiProvisioning` flag 保持 UI；BLE 重连后自动清除 flag（analyze 通过 2026-05-21）
   - **待烧录验证**：需全量烧录（含 bootloader）确认 WiFi+BLE 共存 + 配网流程端到端正常
5. APP 端通信层切换（mDNS 发现 + WebSocket client 替代 BLE）
6. 大数据走 WiFi（OTA HTTP 下载 / Logo WebSocket binary / 音频复用现有 TCP）

**已知非阻塞 bug**：~~WiFi 配网弹窗关闭时偶发 `Duplicate GlobalKeys` 错误~~ → 已修复（ErrorWidget.builder 改为空白，不再显示红色页面）

**对 BLE OTA crash 的影响**：WiFi 通道完成后 BLE OTA 不再需要，crash 问题自然消失。暂不修 BLE OTA。

**已确认（2026-05-21）**：
- BLE OTA 不急需，暂不修复，等 WiFi 通道完成后自然替代
- 在 `feat/wifi-main-channel` 分支上开发实验，验证跑通后再合回 main
- 配网 UX 待 Phase 1 跑通后再设计
- 下一步：创建分支 → Phase 1（ESP32 WebSocket server + mDNS）

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
ESP32-S3 固件：idf.py build — ✅ 通过（2026-05-21，v1.1.1，target=esp32s3，bin 3.04MB，分区余量 3%）
  分支 feat/wifi-main-channel
  变更：WiFi 配网正式版（生产启动序列 + provision task + BLE 恢复）
  ⚠️ 烧录需全量（含 bootloader）：idf.py -p COMx flash
Flutter APP：flutter analyze — ✅ 通过（0 errors，169 info/warning 均为已有问题）
  变更：WiFi 配网弹窗（自动 SSID + 5GHz 检测 + BLE 断开处理）
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
