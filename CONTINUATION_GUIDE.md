# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-22 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。
> 历史决策详情见 `.kiro/steering/knowledge/decision-log.md`。

## 当前阶段：体验打磨期 → 四大功能开发准备 + iOS 首次构建

功能全部跑通，文档体系整理完成，准备进入四大功能分支开发。
Mac 端环境已就绪，即将执行首次 iOS 克隆+编译+真机运行。
**车库联动控制弹窗 (GarageControlSheet) 框架已实现，编译通过。**

## Git 状态

- **分支**：`main`（v1.2.0 已发布）
- **当前 tag**：`v1.2.0`（2026-05-23，车库控制面板v2 + 动态极速 + 车模识别）
- **远程**：origin/main 已同步（push 成功）
- **规范**：见 `git-and-release.md`（唯一 git 规范文件）
- **feat/garage-v2**：已合并到 main，可删除

## 当前阻塞 / 待验证

<!-- 每条必须有 verified 日期。AI 涉及相关模块时必须读代码验证是否仍成立 -->

| 状态 | 问题 | verified |
|------|------|----------|
| ⏳ 待实机验证 | 风扇 PWM 调速（引脚已修正 IO10，代码已实现，未烧录验证） | 2026-05-22 |
| ⏳ 待实机验证 | WiFi+BLE 共存配网流程（代码完成，需全量烧录验证） | 2026-05-21 |
| ⏳ 待实机验证 | 引擎音效最终效果（RC Engine 方案代码完成） | 2026-05-18 |
| 🔲 暂搁 | LED 偶发闪烁（RMT DMA 通道不足，已回退） | 2026-05-18 |
| 🔲 暂搁 | DeviceConnectScreen ~3500 行（需拆分，车库开发前建议先做） | 2026-05-20 |
| ✅ 已完成 | WiFi OTA 全流程（APP 端 WebSocket 验证通过） | 2026-05-21 |
| ✅ 已完成 | WiFi 配网实机测试（秒级完成） | 2026-05-21 |
| ✅ 已完成 | iOS 代码适配（权限/平台条件/BLE UUID） | 2026-05-22 |
| ✅ 已完成 | 多平台抽象体系建立（PlatformCapabilities + ChannelRegistry + CI/CD） | 2026-05-22 |
| ✅ 已完成 | 跨平台协作规范落地（Mac=纯构建机，`cross-platform-workflow.md` 最终版） | 2026-05-22 |
| ⏳ 进行中 | Mac 首次 iOS 克隆+编译+真机运行 | 2026-05-22 |
| 🔲 暂搁 | car_brand_recognition 插件 GPU Delegate 编译失败（已从 pubspec 禁用，待 TFLite 版本修复） | 2026-05-23 |

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
Flutter APP：  ✅ flutter analyze 通过（2026-05-23，无 error，仅 pre-existing warnings）
协议测试：    ✅ flutter test test/protocol/ — 51/51 通过
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

## 本次新增：车模识别功能集成 (2026-05-23)

**仓库**: `RideWind-yolov5`（已克隆到 `c:\Users\Klara\Desktop\4.8\RideWind-yolov5`）
- GitHub: `SunnyKlara/RideWind-yolov5`
- 架构: Flutter Plugin（`car_brand_recognition/`）+ Android 原生 TFLite/ONNX 推理
- 两阶段流水线: YOLOv5 检测车辆 → MobileNetV3 分类品牌（49 个品牌）

**新增/修改文件**:
| 文件 | 变更 |
|------|------|
| `RideWind/pubspec.yaml` | 添加 `car_brand_recognition` 本地 path 依赖 + `camera: ^0.11.0+2` |
| `RideWind/lib/screens/car_recognition_screen.dart` | 新建，车模识别页面（拍照/相册/实时三种模式） |
| `RideWind/lib/screens/device_connect_screen.dart` | 菜单添加"车模识别"入口（Android only） |

**阻塞项**:
- ⚠️ 模型文件缺失：`car_brand_recognition/assets/models/` 目录为空
  - 需要: `yolov5s-fp16-320.tflite`（检测模型）
  - 需要: `car_brand_classifier.onnx`（分类模型）
  - 训练在 5060 显卡电脑上执行，训练脚本在 `RideWind-yolov5/RideWind-yolov5-master/training/`
  - **已配置 Git LFS** 追踪 `*.tflite`/`*.onnx`/`*.pth`，训练机 push 后本机 pull 即可同步
  - `.gitignore` 已注释掉模型排除规则，改由 LFS 管理

**已修复编译问题**:
- `YoloDetector.java`: 移除 `CompatibilityList`（TFLite GPU 2.14.0 API 变更），改用 `new GpuDelegate()` + try/catch fallback CPU
- APK 编译通过（`flutter build apk --debug` 成功）

**两台电脑分工**:
- 本机（开发机）：Flutter/Android 代码集成、UI 调试、推理测试
- 训练机（5060）：运行 training/ 脚本、导出 .tflite/.onnx 模型、push 到仓库

**下一步**:
1. 训练机 clone 仓库，准备数据集（CompCars/Stanford Cars），开始训练
2. 训练完成后将模型文件放入 `car_brand_recognition/assets/models/`
3. 本机 pull 后实机测试识别效果
4. 后续优化：识别结果关联 `car_specs.json` 车库数据库 → 跳转 CarDetailScreen

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
- **P0 引擎声独立录音获取**：YouTube 路线已跑通，yt-dlp+ffmpeg 已安装，批量脚本 `fetch_engine_sounds_yt.py` 正在后台运行（~700辆，预计1-2小时），输出到 `assets/sound/engine_individual/`，有断点续传。完成后需接入 CarDetailScreen 替换通用 profile 预览。
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
