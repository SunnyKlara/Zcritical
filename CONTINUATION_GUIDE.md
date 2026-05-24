# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-24 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。
> 历史决策详情见 `.kiro/steering/knowledge/decision-log.md`。

## 当前阶段：主干整理完毕，准备新功能开发

所有实验性功能分支已暂存保留，工作区已切回 main 干净状态。
可以开始下一个功能开发或继续体验打磨。

## Git 状态

- **分支**：`main`（v1.2.1，工作区干净）
- **当前 tag**：`v1.2.1`（UI polish + new app icon + BLE stability）
- **远程**：origin/main 已同步
- **规范**：见 `git-and-release.md`（唯一 git 规范文件）

### 暂搁功能分支（保留不删，后续有空再开发）

| 分支 | 最新提交 | 说明 |
|------|----------|------|
| `feat/car-recognition` | 94fa7c8 | 车模识别 — YOLOv5+MobileNetV3，实时检测重构，模型待训练 |
| `feat/wifi-main-channel` | 5a433d3 | WiFi图传加速 + 车库Logo WiFi上传 |
| `feat/ota-speed-boost` | 367d7fa | WiFi OTA 流式传输（去掉逐包等ACK） |
| `feat/garage-v2` | 832e46e | 已合并到 main 的历史分支，可删除 |
| `feature/light-mode-pro-popup` | 4ae69ea | 灯效模式相关（旧） |
| `fw/audio-test-demo` | 837d68c | 音频测试 demo（旧） |

## 本次新增：跑步机菜单集成 + UI 优化规划 (2026-05-24)

**已完成**：
- 生成跑步机图标 `ridewind-esp/main/resources/treadmill_icon.c`（68×68 跑步人形 + 80×27 "RUN" 文字，RGB565）
- `board_config.h`: `MENU_PAGE_COUNT` 6→7
- `menu_icons.h`: 添加 `gImage_treadmill_68_68` / `gImage_treadmill_text` extern 声明
- `menu_icons.c`: 第 7 页（index 6），target_ui = 8（跑步机）
- 图标生成脚本: `ridewind-esp/tools/gen_treadmill_icon.py`（Pillow 绘制，可重新生成）

**编译状态**: ⚠️ 未验证（build 目录被其他进程锁定，需关闭占用进程后 `.\build.ps1 -Full`）

**下一步 — 跑步机 UI 优化（ESP 硬件端）**：
1. P0 视觉冲击力：加宽弧形（4px→15px）、指针加粗+发光、速度数字放大
2. P1 动态效果：指针平滑插值、弧形填充动画、数字弹跳
3. P2 信息丰富度：配速文字、图形化挡位、里程/时间计数
4. P3 交互优化：编码器旋转直接调速、单击切换显示模式

**决策**：
- 跑步机放在菜单第 7 页（音量后面），双击退出回菜单逻辑不变
- 图标是临时占位（白色线条跑步人形），后续替换正式设计

## 当前阻塞 / 待验证

<!-- 每条必须有 verified 日期。AI 涉及相关模块时必须读代码验证是否仍成立 -->

| 状态 | 问题 | verified |
|------|------|----------|
| ✅ 已修复 | **v1.2.1 APP 升级失败** — tag 命名不匹配已修复（CI 兼容 `v*`+`app-v*`），APK 已手动上传到 GitHub Release + 阿里云，app_version.json 已加 fallback_download_url | 2026-05-24 |
| ⏳ 待实机验证 | 风扇 PWM 调速（引脚已修正 IO10，代码已实现，未烧录验证） | 2026-05-22 |
| ⏳ 待实机验证 | WiFi+BLE 共存配网流程（代码完成，需全量烧录验证） | 2026-05-21 |
| ⏳ 待实机验证 | 引擎音效最终效果（RC Engine 方案代码完成） | 2026-05-18 |
| 🔲 暂搁 | LED 偶发闪烁（RMT DMA 通道不足，已回退） | 2026-05-18 |
| 🔲 暂搁 | DeviceConnectScreen ~3500 行（需拆分，车库开发前建议先做） | 2026-05-20 |
| 🔲 暂搁 | 车模识别（在 `feat/car-recognition` 分支，模型待训练，后续再开发） | 2026-05-24 |
| 🔲 暂搁 | WiFi图传加速（在 `feat/wifi-main-channel` 分支） | 2026-05-24 |
| ✅ 已完成 | WiFi OTA 全流程（APP 端 WebSocket 验证通过） | 2026-05-21 |
| ✅ 已完成 | WiFi 配网实机测试（秒级完成） | 2026-05-21 |
| ✅ 已完成 | iOS 代码适配（权限/平台条件/BLE UUID） | 2026-05-22 |
| ✅ 已完成 | 多平台抽象体系建立（PlatformCapabilities + ChannelRegistry + CI/CD） | 2026-05-22 |
| ✅ 已完成 | 跨平台协作规范落地（Mac=纯构建机，`cross-platform-workflow.md` 最终版） | 2026-05-22 |
| ⏳ 进行中 | Mac 首次 iOS 克隆+编译+真机运行 | 2026-05-22 |
| ⏳ 待处理 | 背景图左上角 "RideWind T1" 文字需替换为 "T1"（等后续换图时一并处理） | 2026-05-23 |

## 工作流优化记录 (2026-05-24)

**终端命令自动执行**：已配置 `"kiroAgent.trustedCommands": ["*"]`（用户级 settings.json），所有终端命令自动执行不再弹确认。
- 安全保障：`.kiro/steering/terminal-safety.md` 禁止 AI 使用破坏性命令（del/rm/rmdir/Remove-Item 等）
- 删除文件走 Kiro 内置 `delete_file` 工具，不走终端
- 设置路径：`C:\Users\Klara\AppData\Roaming\Kiro\User\settings.json`

## 下一步

1. **P0 四大功能分支开发**（详见 `knowledge/feature-roadmap.md`）：
   - `feat/garage-v2` — 车库大更新 **← 系统设计已完成，见 `RideWind/docs/GARAGE_SYSTEM_DESIGN.md`**
   - `feat/colorize-v2` — 灯光系统升级
   - `feat/audio-casting-v2` — 音频投射升级
   - `feat/ios-platform` — iOS 开发体系 **← 多平台抽象层已建立，见下方"本次新增"**
2. **P1 WiFi 主通道 Phase 5-6** — APP 通信层切换到 WebSocket + 大数据走 WiFi
3. **P2 体验打磨** — 实玩反馈 → 批量修复

## 编译状态

```
ESP32-S3 固件：✅ idf.py build 通过（2026-05-21，v1.1.1，bin 3.04MB，余量 3%）
Flutter APP：  ✅ flutter analyze 通过（2026-05-24，0 error，205 info/warning pre-existing）
Flutter APK：  ✅ flutter build apk --release 通过（2026-05-24，85.6MB，正式签名 com.zcritical.t1）
协议测试：    ✅ flutter test test/protocol/ — 51/51 通过
App 图标：    ✅ flutter_launcher_icons 生成完成（2026-05-23，新 Z 字 logo，全平台）
```

## 本次新增：BLE 连接稳定性 + 雾化器指示器修复 (2026-05-23)

**问题 1a — 设备已被其他手机连接时无提示，无限重试**:
- `ble_service.dart`: 新增 `lastConnectionError` 字段，连接异常时分析错误类型（error 133 / already connected / timeout）
- `ble_service.dart`: `_scheduleReconnect()` 检测到 `device_busy` 时立即停止自动重连
- `bluetooth_provider.dart`: 暴露 `lastConnectionError` getter + `resetBleReconnectState()` 方法
- `device_scan_screen.dart`: 连接失败时根据错误原因显示 "设备已被占用" 或 "连接失败"
- `device_connect_screen.dart`: 重连失败对话框区分 "设备已被占用" vs "连接失败"

**问题 1b — App 进后台再回来重连一直失败**:
- `ble_service.dart`: 新增 `resetReconnectState()` 方法（清除计时器+重置计数器）
- `device_connect_screen.dart`: 添加 `WidgetsBindingObserver`，`didChangeAppLifecycleState(resumed)` 时重置重连状态并重新连接

**问题 2 — 雾化器开启提示一直显示不消失**:
- `device_connect_screen.dart`: 将 `if (_isAirflowStarted)` 静态显示改为 `ValueListenableBuilder` 监听 `_airflowController.isVisible`
- 指示器现在切换时短暂显示 1.5s（开启）/ 1s（关闭）后自动隐藏
- 同时在 `onTap` 中调用 `_airflowController.showOnIndicator()` / `showOffIndicator()`

**编译验证**: `flutter analyze` 通过，无新增 error/warning

## 本次新增：BLE 连接生命周期管理 (2026-05-23)

**问题**：A 手机 App 进后台后 BLE 连接不释放，B 手机无法连接设备，必须杀掉 A 的进程才行。

**固件端修复** (`ridewind-esp/main/services/ble_service.c`):
- 新增 30 秒空闲超时机制（FreeRTOS 软件定时器，每 10s 检查一次）
- `CONNECT_EVT` / `WRITE_EVT` 时刷新 `s_last_rx_time`
- 超时后调用 `esp_ble_gatts_close()` 主动踢掉空闲连接，重新广播
- ⚠️ 需 `idf.py build` 验证编译 + 烧录实测

**APP 端修复** (`device_connect_screen.dart`):
- `AppLifecycleState.paused` → 启动 10 秒计时器，到期主动 `disconnect()`
- `_disconnectedByBackground` 标记：后台断开不弹对话框
- `AppLifecycleState.resumed` → 取消计时器 + 静默重连
- 10 秒内回前台（还连着）→ 无感知；超过 10 秒 → 回来自动重连

**双重保险设计**：APP 10s + 固件 30s，即使 APP 计时器被系统杀掉，固件也能兜底释放。

**编译验证**: Flutter ✅ 通过 | ESP32 ⚠️ 待 idf.py build 验证

## 本次新增：BLE 断开事件去抖 (2026-05-23)

**问题**：使用中时不时弹出"蓝牙断开连接"对话框，点重连秒成功。原因是 BLE 瞬间抖动（信号波动/Android 系统短暂挂起 BLE 栈）被立即当作真断开处理。

**修复** (`device_connect_screen.dart`):
- 收到断开事件后不立即弹对话框，启动 2 秒去抖计时器
- 2 秒内如果连接恢复（`connected == true`）→ 取消计时器，当作没发生过
- 2 秒后再次检查 `isConnected`，确认真断了才弹对话框
- 新增 `_disconnectDebounceTimer` 字段，dispose 时取消

**编译验证**: Flutter ✅ 通过

## 本次新增：发布自动化 + v1.2.1 紧急修复 (2026-05-24)

**问题**：v1.2.1 tag 命名 `v1.2.1` 不匹配 CI 触发条件 `app-v*`，导致 APK 从未构建上传，用户升级 404。

**紧急修复**：
- 本地 `flutter build apk --release` → 81.5MB
- `gh release upload v1.2.1` 上传到 GitHub Release ✅
- `scp` 上传到阿里云 47.107.143.4 ✅
- 用户现在可以正常升级

**CI/CD 全自动化改造**：
- `.github/workflows/multi-platform-build.yml` 重写：tag `v*` 或 `app-v*` 均触发
- Release job 自动：构建 APK → GitHub Release → SCP 阿里云 → 验证部署 → 更新 app_version.json → push 回 main
- GitHub Secrets 已配置：`DEPLOY_HOST` + `DEPLOY_SSH_KEY` + `KEYSTORE_BASE64` + `KEYSTORE_STORE_PASSWORD` + `KEYSTORE_KEY_PASSWORD` + `KEYSTORE_KEY_ALIAS`
- 以后发版只需 4 步：改版本号 → CHANGELOG → commit → tag+push

**APK 正式签名**：
- Keystore 已生成：`zcritical-release.jks`（RSA 2048, 有效期 27 年，alias=zcritical）
- 本地 `key.properties` 已配置（.gitignore 已排除）
- CI 自动解码 keystore + 签名（仅 tag 构建时）
- 版本号从 tag 自动提取（`--build-name` 覆盖 pubspec）

**APP 端容错增强**：
- `update_service.dart`：版本检测双 URL（GitHub raw + jsdelivr CDN），下载 fallback（阿里云 → GitHub Release），APK 文件大小验证
- `app_update_service.dart`：修复 `_versionUrl` 指向错误路径（`version.json` → `RideWind/app_version.json`），加 CDN 备用，下载支持多 URL fallback + 文件验证
- `app_version.json`：新增 `fallback_download_url` / `fallbackDownloadUrl` 字段

**决策**：
- Tag 命名统一用 `vX.Y.Z`（废弃 `app-vX.Y.Z`），CI 兼容两种
- 下载地址主用阿里云（国内快），GitHub Release 作为 fallback
- 版本检测主用 GitHub raw，jsdelivr CDN 作为 fallback
- APK 命名改为 `zcritical-t1-vX.Y.Z.apk`（品牌统一）

**待完成**：
- ⏳ HTTPS：需在宝塔面板申请 Let's Encrypt 证书（certbot 已安装，SSH 超时未完成）
- ⏳ 本地构建验证签名：Windows 文件锁导致 clean build 失败（CI 在 Linux 不受影响）

**编译验证**: Flutter ✅ 通过（零 error）| 本地签名构建 ⚠️ Windows 文件锁需重启后验证

## 本次新增：工作区整理 (2026-05-24)

**操作**：将 `feat/car-recognition` 分支所有进度提交保存，切回 `main`。
- 车模识别（YOLOv5 + flutter_vision 实时检测）→ 暂搁在 `feat/car-recognition`
- WiFi图传加速 → 暂搁在 `feat/wifi-main-channel`
- 清理了切换分支后残留的嵌套 git 仓库目录
- 工作区现在干净在 `main` v1.2.1 上

**决策**：车模识别和 WiFi 图传都是"有空再做"的功能，不阻塞主线开发。

## 本次新增：产品化整改决策 (2026-05-24)

## 本次新增：产品化整改决策 (2026-05-24)

**品牌切换**：RideWind 品牌已退出，全面切换到 Zcritical。详见 `.kiro/steering/brand-rules.md`。
- 包名：`com.example.ridewind` → `com.zcritical.t1`
- 所有面向用户的 ridewind 字样必须清除
- `ridewind-esp/` 目录名暂保留（纯内部）

**产品化 P0 已完成（2026-05-24）**：
1. ✅ 品牌重命名 — 包名/Kotlin目录/MethodChannel/APP文字/JSON全部替换
2. ✅ 资源瘦身 — 移除 car_thumbnails PNG(88MB) + engine_individual WAV(299MB)，APK 400MB+ → 85.6MB
3. ✅ Release 签名 — keystore 生成，signingConfig 配置，正式签名构建通过
4. ⏳ 服务器加 HTTPS — 需要用户在阿里云轻量服务器上操作

**编译状态**：
- `flutter analyze`: ✅ 0 error（205 info/warning，全是 pre-existing）
- `flutter build apk --release`: ✅ 85.6MB，正式签名
- R8 minification 暂时关闭（缺 Play Core 类，后续修复）

**资源托管方案**：继续用阿里云轻量服务器（47.107.143.4），加 HTTPS。资源瘦身后单次下载量小，带宽够用。用户量起来后再加 CDN/OSS。

**下一步 P1**：
- ✅ 修复 CI workflow（加 LFS checkout + 资源获取步骤）— 已完成
- ✅ 接入崩溃上报（Sentry）— 框架已接入，DSN 待填入
- ✅ app_version.json 已统一字段（本次完成）
- ✅ 设置页反馈入口实现（邮箱可复制）

**待用户操作**：
- `git push` 推送到 GitHub
- 注册 sentry.io → 创建 Flutter 项目 → 把 DSN 填入 `main.dart` 的 `_sentryDsn`
- 服务器加 HTTPS（certbot）
- 上传新 APK（`zcritical-t1-v1.2.1.apk`）到服务器
- 确认反馈邮箱（当前占位 `support@zcritical.com`）

**下一步 P2**：
- device_connect_screen 拆分（2072 行 god object）
- R8 minification 修复（添加 Play Core keep rules）
- 车辆缩略图按需下载 service 实现
- 清理暂搁分支

## 本次新增：车库联动控制弹窗 (2026-05-22 → 2026-05-23 硬件联调区重构)

**文件**: `lib/widgets/garage_control_sheet.dart`
- 长按紧急停止按钮 → 弹出 GarageControlSheet（替代 DrivingStyleSheet）
- 赛车轮播: PageView viewportFraction=0.72，中间大两边小
- 2×2 参数面板: HP / TORQUE / TOP SPEED / 0-100 进度条（已恢复，在车辆轮播与波形之间）

**分隔线以下 — 硬件联调区域（2026-05-23 重构）**:
- 引擎波形: 全宽 CustomPaint 正弦波充当视觉分隔线（上下 36px 间距），上方小字居中显示引擎类型+播放按钮
- 控制面板: 速度/音量/风力 竖列排列（标签+数字一行 + Slider一行，TweenAnimationBuilder 600ms动画）
  - 切换车辆时三值按比例连续变化 + Slider 平滑伸缩
  - 过滤非赛车车辆 + 四参数+引擎信息必须完整（420辆合格，随机取50）
  - DraggableScrollableSheet + ListView 上下滚动，ACTIVATE 固定底部
- 音量触摸时 UI:7，松手 800ms 后 UI:1
- ACTIVATE 按钮: 批量发送 `FAN:$windPower` + `SPEED:$maxSpeed` + `VOL` + `UI:1`

**2026-05-23 风力/ACTIVATE 修复**:
- ❌ 旧行为: 风力滑块拖动立即发送 `FAN:x`，ACTIVATE 只发 VOL+UI:1
- ✅ 新行为: 风力改为 RangeSlider 双滑块（min/max），ACTIVATE 发送 `SPEED_MAX` + `FAN_RANGE` + `VOL` + `UI:1`
- 风力区间设计: 速度 0% → fan_min，速度 100% → fan_max，中间线性插值
- 极速上限动态化: LCD 显示用 `speed_max_display` 替代硬编码 3.4 倍率
- 新增协议命令: `SPEED_MAX:xxx`（1-999）、`FAN_RANGE:min,max`（0-100）
- 固件改动: `app_state.h/c` + `protocol.h/c` + `main.c` + `ui_speed.c`
- 修复: CMD_SPEED 引擎音频只在油门模式(wuhuaqi_state==2)播放，普通模式不再误触发
- 修复: CMD_VOLUME 同时调用 audio_engine_set_volume + audio_player_set_master_volume，音量控制油门引擎音
- 速度范围: SPEED 命令上限从 340 扩展到 999，SPEED_MAX 范围 1-999
- APP 编译: ✅ flutter analyze 通过
- 固件编译: ⚠️ 需在 ESP-IDF 终端 `idf.py build` 验证（本机无 idf.py 环境）
- ⚠️ 需烧录最新固件验证 LCD 响应 + 风扇 PWM 区间映射
- ⚠️ 待排查: APP 控制卡顿问题（需确认是 UI 卡还是 BLE 响应慢）
- ✅ 修复: APP 发 SPEED 命令时强制映射回 0-340 的旧逻辑（device_connect_screen.dart），现在直接发显示值
- ✅ 修复: command_sender.dart SPEED 范围从 0-340 扩展到 0-999
- ✅ 禁用: APP 端 EngineAudioManager 完全关闭（main.dart + bluetooth_provider.dart），所有音频由硬件端处理

**待实现（下一步）**:
- ✅ NVS 持久化: SPEED_MAX/FAN_RANGE/VOL 写入 flash，开机自动恢复（已实现）
- ✅ ACTIVATE 等待 OK 确认: 用 sendCommandWithRetry 等固件回复后才关闭弹窗（已实现）
- ❌ APP 端适配: ACTIVATE 成功后，RunningModeWidget 滚轮范围需同步更新到新极速

**修改**: `lib/widgets/running_mode_widget.dart`
- `onLongPress` 改为调用 `GarageControlSheet.show()`
- `onSettingsApplied` 回调返回 `GarageSettings`（maxSpeed/volume/windPower）

**下一步**:
- ~~CarDetailScreen 参数进度条升级~~ ✅ 已完成 2026-05-23
- ~~车辆规格数据补全（915/915 = 100% 覆盖）~~ ✅ 已完成 2026-05-23
- ~~引擎声音 Profile 系统建立（22种 profile + 915车映射 + 88个PCM）~~ ✅ 已完成 2026-05-23
- ~~CarDetailScreen 接入引擎声音 Profile 显示~~ ✅ 已完成 2026-05-23
- ~~CarDetailScreen 引擎声音试听播放（点击卡片播放 3s WAV 预览）~~ ✅ 已完成 2026-05-23
- ~~接入 maxSpeed 动态更新 RunningModeWidget 滚轮范围~~ ✅ 已完成 2026-05-23
  - 纯显示层映射（底层永远 0-340 步不变）
  - GarageControlSheet ACTIVATE → onGarageSettingsApplied → DeviceConnectScreen._maxSpeed 更新
  - RunningModeWidget.didUpdateWidget 按比例映射当前速度到新范围
  - 发给硬件反向映射 `hardwareStep = displayValue * 340 / maxSpeed`
  - 收到 SPEED_REPORT 正向映射 `displayValue = hardwareStep * maxSpeed / 340`
  - 固件端 LCD 同理映射待后续实现
- 接入收藏/最近使用车辆列表
- 硬件端 SPEED_RANGE 命令（让 LCD 数字范围同步）
- 硬件端引擎声联动：ESP32 LittleFS 烧录 + SOUND 协议命令 + audio_engine 改造
- 车辆故事集：第一批 20 辆已写入 car_stories.json + UI 已接入 CarDetailScreen，剩余 895 辆后续补充（低优先级）
- **P0 引擎声独立录音获取**：✅ 已完成。715/729 辆车有独立 YouTube 引擎声（299MB WAV），17辆特殊车用通用 profile 兜底。CarDetailScreen 播放逻辑已改好（优先独立→fallback通用）。WAV 文件未入 git（太大），发布时需 LFS 或单独处理。
- 弹窗下半部分：自定义速度范围 + 硬件联调设计

## 本次新增：多平台开发体系（2026-05-22）

| 文件 | 用途 |
|------|------|
| `lib/core/platform_capability.dart` | 运行时平台能力检测 + 降级机制 |
| `lib/core/platform_channel_registry.dart` | Platform Channel 统一接口抽象 |
| `.github/workflows/multi-platform-build.yml` | 多平台 CI/CD（Android + iOS 同步构建） |
| `docs/PLATFORM_ONBOARDING_TEMPLATE.md` | 新平台接入标准 checklist |
| `docs/IOS_BUILD_AUTOMATION.md` | iOS 构建签名全流程 |
| `.kiro/steering/guides/multi-platform-architecture.md` | 架构设计文档 |
| `.kiro/steering/platform-rules.md` | 已更新，集成新抽象体系 |

**下一步**：现有 `Platform.isAndroid` 判断逐步迁移到 `PlatformCapabilities.supports()`。

## 关键文件速查

| 用途 | 文件 |
|------|------|
| 固件入口 | `ridewind-esp/main/main.c` |
| 固件状态 | `ridewind-esp/main/app/app_state.h` |
| 固件协议 | `ridewind-esp/main/services/protocol.c` |
| 固件音频 | `ridewind-esp/main/services/audio_player.c` |
| 硬件引脚（真值源） | `ridewind-esp/main/config/pin_config.h` |
| APP 入口 | `RideWind/lib/main.dart` |
| APP 核心页面 | `RideWind/lib/screens/device_connect_screen.dart` |
| APP 蓝牙状态 | `RideWind/lib/providers/bluetooth_provider.dart` |
| APP 协议解析 | `RideWind/lib/protocol/protocol_parser.dart` |
