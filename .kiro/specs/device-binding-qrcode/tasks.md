# Implementation Plan: Device Binding via QR Code

## Overview

按 4 个 Phase 增量推进设备一对一绑定特性。每个 Phase 独立可验证、独立可 rollback：

- **Phase 1（设备端）**：`bind_service` 状态机 + NVS + QR 屏渲染。无任何 BLE 改动，能在 UNBOUND 状态显示二维码、BOUND 状态走原 UI 流。
- **Phase 2（设备端）**：协议层加 3 条命令 + BLE 准入 gate。能用串口/调试工具手发 BIND 命令完成绑定。
- **Phase 3（App 端）**：扫码界面 + bind_flow_controller + secure_storage。能完成首次绑定。
- **Phase 4（App + 设备端）**：解绑流程双端 + 保底重置验证 + 文档/测试清单。

每个 Phase 独立 commit + 中文 commit message，符合项目规范。

## Tasks

### Phase 1 — 设备端绑定状态机 + QR 屏

- [ ] 1. 引入 qrcode 组件并验证编译
  - [ ] 1.1 在 `ridewind-esp/main/idf_component.yml` 添加 `espressif/qrcode: "^0.1.0"` 依赖
    - 运行 `idf.py reconfigure` 拉取组件
    - 验证 `idf.py build` 仍能通过
    - _Requirements: 2.3_

  - [ ] 1.2 写一个最小验证：在 `main.c` 临时调用 `esp_qrcode_generate` 生成测试 payload，仅 LOGI 打印模块矩阵尺寸
    - 验证组件能正确链接、运行不崩溃
    - 验证完后删除测试代码
    - _Requirements: 2.3_

- [ ] 2. 实现 `bind_service` 模块（核心状态机）
  - [ ] 2.1 创建 `ridewind-esp/main/services/bind_service.h` 定义公共接口
    - `void bind_service_init(void)` — 启动时调用，处理 NVS / cold_boot_count / 保底
    - `bool bind_service_is_bound(void)` — gate 函数依赖
    - `const char *bind_service_get_phone_id(void)` — BOUND 状态返回 phone_id；否则 NULL
    - `void bind_service_get_qr_payload(char *buf, size_t len)` — 输出 `ridewind://bind?...`
    - `bool bind_service_handle_bind_request(const char *phone_id, const char *token, const char *nonce, uint8_t *out_result)` — 0=ok,1=token_mismatch,2=already_bound_other,3=phone_id_invalid,4=nonce_replay
    - `void bind_service_handle_unbind(void)` — 清 NVS + 切 UNBOUND + 重生 token + 重渲 QR
    - `void bind_service_tick(void)` — 主循环每秒调用：检查 token 轮换、检查 boot 后稳定 10s 清 cold_boot_count
    - _Requirements: 1.1, 1.2, 1.6_

  - [ ] 2.2 创建 `ridewind-esp/main/services/bind_service.c` 实现状态机
    - 模块级 `bind_state_t s_bs` 静态变量保存运行时状态
    - `bind_service_init`：nvs_open(`bind`) → 读 schema_version（缺失则写 1）→ 累加 cold_boot_count → 读 phone_id → 检查保底（≥5 且 BOUND 则擦）→ 生成首个 Pair_Token via `esp_random()`
    - 包含 NVS 写错误处理：写失败 LOGE 但不死锁，保留内存态 UNBOUND
    - `bind_service_get_qr_payload`：`snprintf(buf, "ridewind://bind?mac=%s&token=%s&v=1", mac, token_hex)`，MAC 从 `esp_read_mac` 取
    - `bind_service_handle_bind_request`：phone_id 长度=36 + 4 个 hyphen 校验 → token 字节比 → nonce 与 last_bind_nonce 比 → 写 NVS phone_id → set is_bound=true
    - `bind_service_handle_unbind`：仅在 BOUND 且 phone_id 匹配时清 NVS（`nvs_erase_key("phone_id")`）
    - `bind_service_tick`：检查 `esp_timer_get_time() - token_generated_us > 600_000_000` 则 regen token + 触发 UI 重渲事件
    - 严格遵循 services 分层：不直接调 GPIO/PWM；UI 重渲通过 `ui_manager_request_qr_refresh()`
    - _Requirements: 1.1, 1.4, 1.5, 1.6, 2.1, 2.6, 3.2-3.4, 3.7-3.8, 5.6, 6.1-6.5, 7.1-7.5_

- [ ] 3. 创建 QR 渲染屏幕 `ui_qr.c`
  - [ ] 3.1 创建 `ridewind-esp/main/ui/ui_qr.h` + `ui_qr.c`
    - `void ui_qr_init(void)` — 注册到 ui_manager 路由表（ID = 9）
    - `void ui_qr_enter(void)` — 屏幕进入：清屏白色 → 调 `bind_service_get_qr_payload` → 调 `esp_qrcode_generate` → 把模块矩阵画到 240x240 中心
    - `void ui_qr_process(void)` — 主循环回调：检测 token rotation 标志，重渲；不响应任何编码器/按键事件（旋钮 / 点击 / 长按全无效）
    - 文字行 "请用 RideWind App 扫码绑定"：先尝试用 `drv_lcd_draw_text_8x16`（如不支持中文则改 ASCII "Scan with RideWind App" 作为 PoC，task 5 之前不阻塞主流程）
    - _Requirements: 2.1-2.5, 2.7, 9.4_

  - [ ] 3.2 在 `ui_manager.c` 注册 UI_QR (id=9) 到 UI 路由表
    - 加 `case 9: ui_qr_enter(); break;` 等分发
    - 加 `case 9: ui_qr_process(); break;` 主循环 tick
    - 验证 `ui_manager_set_ui(9)` 能正确切换
    - _Requirements: 1.2, 1.4, 9.1_

- [ ] 4. 修改启动顺序集成绑定检查
  - [ ] 4.1 修改 `ridewind-esp/main/main.c`
    - 顺序：`nvs_flash_init` → `app_state_init` → `bind_service_init` → `drv_lcd_init` → `ui_manager_init` → `ble_service_init`
    - 分流：`if (bind_service_is_bound()) { boot_logo_show(); ui_manager_set_ui(1); } else { ui_manager_set_ui(9); }`
    - 主循环每秒调一次 `bind_service_tick()`
    - _Requirements: 9.1, 9.2_

  - [ ] 4.2 实现外设冻结（UNBOUND 状态）
    - 在 `bind_service.h` 加 `bool bind_service_periph_frozen(void)` 接口
    - 在以下位置开头检查并跳过输出：`drv_led.c` 的 `drv_led_apply()`、`drv_pwm.c` 的 `drv_pwm_set_duty()`（仅 PWM 1 风扇）、`drv_audio.c` 的播放入口
    - 这样 UNBOUND 状态下即使 app_state 内有残值也不输出
    - 注意层级：`drv_*` 不能 include `bind_service.h`（违反 driver 不依赖 service 规则）。改成：让 `bind_service` 启动 UNBOUND 时调用 `drv_led_set_enabled(false)`、`drv_pwm_set_enabled(false)` 这样的 driver-side gate API（如不存在则按需新增）
    - _Requirements: 9.4_

- [ ] 5. Phase 1 验证 + commit
  - [ ] 5.1 运行 `idf.py build` — 0 error
  - [ ] 5.2 烧录到设备测试（实机）
    - 全新设备首次开机：进入 UI_QR，显示二维码（用手机扫码工具能识别 URI）
    - 手动用 `idf.py monitor` 注入 `nvs set bind phone_id "test-uuid-..."` 重启 → 跳过 QR 进 UI1
    - 手动 erase NVS → 回 QR 屏
    - 验证 token 10 分钟轮换（可临时改成 30s 测）
    - 验证 cold_boot_count 累加 + 5 次清绑定（实机断电重启 5 次验证）
  - [ ] 5.3 提交 commit：`feat: 设备端绑定状态机与二维码屏（Phase 1）`
  - _Requirements: 10.1_

### Phase 2 — 协议层 + BLE 准入 gate

- [ ] 6. 协议扩展
  - [ ] 6.1 修改 `ridewind-esp/main/services/protocol.h`
    - `cmd_type_t` 添加 `CMD_BIND_REQUEST`, `CMD_UNBIND`（注意 CMD_BIND_ACK 是设备发出，不是 cmd_type）
    - `cmd_msg_t.param` union 添加 `struct { char phone_id[37]; char token[33]; char nonce[33]; } bind_req;`
    - _Requirements: 3.1_

  - [ ] 6.2 修改 `ridewind-esp/main/services/protocol.c`
    - 在 `protocol_parse` 加分支：`if (strncmp(buf, "BIND:", 5) == 0)` → 用 `:` 分割，验证 phone_id 长度=36 且符合 UUID 格式（`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-...`）→ 填 cmd_msg 返回 `CMD_BIND_REQUEST`
    - 加 `if (strcmp(buf, "UNBIND") == 0)` → 返回 `CMD_UNBIND`
    - 加格式化函数 `int protocol_format_bind_ack(char *buf, size_t len, uint8_t result, const char *device_name)`
    - _Requirements: 3.7_

- [ ] 7. BLE 准入 gate 集成
  - [ ] 7.1 修改 `ridewind-esp/main/services/ble_service.c` 的 `process_rx_data` 命令分发段
    - `protocol_parse` 成功后，先调 `bool bind_service_can_dispatch_cmd(cmd_type_t)`：如果返回 false → 回 `ERR:NOT_BOUND\n` 并不入 cmd_queue
    - `bind_service_can_dispatch_cmd` 内部规则按 design.md 准入控制表
    - _Requirements: 8.3, 8.4_

  - [ ] 7.2 增加 BIND/UNBIND 命令处理（在 cmd_queue 消费侧，可能在 main loop 或专用 handler）
    - 找到现有 cmd dispatcher（`main.c` 或 `cmd_handler.c`）
    - 加 `case CMD_BIND_REQUEST`：调 `bind_service_handle_bind_request` → 取 result → 用 `protocol_format_bind_ack` 格式化 → `ble_service_notify_str` 回 ACK
    - result=0 时切 UI: `ui_manager_set_ui(1)` + 解冻外设
    - result=2 时调用 `ble_service_disconnect()` (如不存在则按需新增)
    - 加 `case CMD_UNBIND`：仅当连接的客户端是当前 phone_id（这一层信息从 BLE 层取得；如果实现复杂度大，简化为：BOUND 状态收到 UNBIND 即认为是当前手机，因为其他手机的 BIND 早被 gate 拦下）→ 调 `bind_service_handle_unbind` → 回 `UNBIND_ACK\n` → 断开
    - _Requirements: 3.2-3.6, 5.6_

  - [ ] 7.3 BLE 广播名 UNBOUND 后缀
    - 在 `ble_service.c` 启动广播前根据 `bind_service_is_bound()` 决定 device_name：BOUND 用现有名（如 `RideWind`），UNBOUND 用 `RideWind [BIND]`
    - 当状态切换时（绑定成功/解绑），调 `esp_ble_gap_set_device_name` 重设
    - _Requirements: 9.3_

- [ ] 8. Phase 2 验证 + commit
  - [ ] 8.1 用 `nRF Connect` 或 `LightBlue` 工具实机测试
    - 设备 UNBOUND 状态，App 工具连上：发 `GET:VERSION\n` → 应回 `ERR:NOT_BOUND`
    - 发 `BIND:<合法 uuid>:<错 token>:<随机 nonce>\n` → 应回 `BIND_ACK:1:`
    - 发正确 BIND → 应回 `BIND_ACK:0:RideWind-XXXX` → 断开重连后任何命令都能用了
    - 设备 BOUND 状态，用第二个手机连：任何命令应回 `ERR:NOT_BOUND` + 5s 内被踢
    - 已绑手机发 `UNBIND\n` → 回 `UNBIND_ACK` → 断开 → 设备屏幕回 QR
  - [ ] 8.2 `idf.py build` — 0 error
  - [ ] 8.3 提交 commit：`feat: BLE 协议绑定命令与准入控制（Phase 2）`
  - _Requirements: 8.1, 8.2, 10.1_

### Phase 3 — App 端扫码绑定

- [ ] 9. 引入 App 端依赖
  - [ ] 9.1 修改 `RideWind/pubspec.yaml`
    - 添加 `mobile_scanner: ^5.0.0`、`flutter_secure_storage: ^9.0.0`、`uuid: ^4.0.0`
    - 运行 `flutter pub get`
    - 注：`mobile_scanner` 是 native plugin，加完必须**冷重启**（按 q 退 flutter run 再启）— 这是项目规律
    - _Requirements: 4.2, 4.5, 4.8_

  - [ ] 9.2 iOS / Android 摄像头权限配置
    - `ios/Runner/Info.plist` 加 `NSCameraUsageDescription`：`扫描设备二维码以完成绑定`
    - `android/app/src/main/AndroidManifest.xml` 加 `<uses-permission android:name="android.permission.CAMERA"/>`
    - _Requirements: 4.2_

- [ ] 10. 创建 secure_storage_service
  - [ ] 10.1 创建 `RideWind/lib/services/secure_storage_service.dart`
    - 封装 `flutter_secure_storage` 的 `getOrCreatePhoneId() → Future<String>`、`saveBoundDevice({mac, phoneId, deviceName})`、`getBoundDevice() → Future<BoundDevice?>`、`clearBound()`
    - iOS 配置 `KeychainAccessibility.first_unlock_this_device`
    - Android 配置 `encryptedSharedPreferences: true`
    - 注册到 service_locator（如项目用 get_it）
    - _Requirements: 4.5, 4.8_

- [ ] 11. 扩展 BluetoothProvider
  - [ ] 11.1 修改 `RideWind/lib/providers/bluetooth_provider.dart`
    - 新增私有字段 `bool _isBound` `String? _boundMac`，启动时从 secure_storage 加载
    - 新增公开 getter `bool get isBound`、`String? get boundMac`
    - 新增方法 `void sendBindRequest(String phoneId, String token, String nonce)` → `_bleService.sendCommand('BIND:$phoneId:$token:$nonce')`
    - 新增方法 `void sendUnbind()` → `_bleService.sendCommand('UNBIND')`
    - 新增 `Stream<BindAck> bindAckStream`：在 ResponseRouter 接 `BIND_ACK:` 前缀，解析 result + device_name
    - 新增 `Stream<void> unbindAckStream`
    - 新增 `Future<void> markBound(String mac, String deviceName)` 内部 set + persist + notifyListeners
    - 新增 `Future<void> markUnbound()` 同理
    - 严格不破坏现有 public API（公开方法仅追加，不改签名）— Requirement 8.5
    - _Requirements: 4.5, 8.5_

  - [ ] 11.2 修改 ResponseRouter（位置预计在 `RideWind/lib/services/ble_service.dart` 或独立文件）
    - 添加 `BIND_ACK:` 路由 → 解析 `BIND_ACK:<result>:<device_name>` → push 到 `_bindAckController`
    - 添加 `UNBIND_ACK` 路由 → push 到 `_unbindAckController`
    - 添加 `ERR:NOT_BOUND` 路由 → 触发 `notBoundEvent`（让 BindFlowController 知道要走绑定流程）
    - 不破坏现有 SpeedReport / PRESET / VOLUME 等 51 测试覆盖的解析路径
    - _Requirements: 8.2, 10.5_

- [ ] 12. 创建 bind_flow_controller
  - [ ] 12.1 创建 `RideWind/lib/core/bind_flow_controller.dart`
    - 实现 `Future<BindResult> startBind({required String mac, required String token})` 按 design.md 描述：取 phone_id → 连 BLE（15s 超时）→ 发 BIND（10s ACK 超时）→ 解析 ACK → 成功调 markBound + return ok / 失败 return 对应错误码
    - 实现 `Future<bool> unbind({required bool deviceConnected})`：connected 时发 UNBIND 等 5s ACK，无论结果都清本地；未连接时仅清本地
    - 定义 `enum BindResult { ok, connectFail, timeout, tokenMismatch, alreadyBoundOther, phoneIdInvalid, nonceReplay, unknown }`
    - 注册到 service_locator
    - _Requirements: 4.4-4.7, 5.3-5.5_

- [ ] 13. 创建 scan_bind_screen
  - [ ] 13.1 创建 `RideWind/lib/screens/scan_bind_screen.dart`
    - StatefulWidget，使用 `MobileScanner` 显示相机预览
    - `onDetect` 回调：拿到 first barcode → 解析 URI（`Uri.parse`）→ 校验 scheme=ridewind, host=bind, query 含 mac/token/v=1（mac 12 hex, token 32 hex）→ 不匹配显示 Toast「二维码无效」并继续扫
    - 解析成功：暂停扫描 → 调 `BindFlowController.startBind` → 显示 LoadingOverlay
    - 成功：Toast「绑定成功」1.5s → 跳 main UI
    - 失败：Dialog 显示原因 + Retry/Back 按钮；Retry 重置回扫描
    - _Requirements: 4.2, 4.3, 4.6, 4.7_

  - [ ] 13.2 修改 `RideWind/lib/screens/no_device_screen.dart`
    - 加「扫码绑定」按钮 → 跳 ScanBindScreen
    - 按钮仅在 `!btProvider.isBound` 时显示
    - _Requirements: 4.1_

- [ ] 14. Phase 3 验证 + commit
  - [ ] 14.1 `flutter analyze` — 0 error
  - [ ] 14.2 `flutter test test/protocol/` — 51 个旧测全过
  - [ ] 14.3 实机测试：扫码绑定整流程
    - 全新设备 + 全新 App：扫 QR → 连接 → 绑定成功 → 进主 UI → 数据交互正常
    - 同一手机重启 App：自动连原设备，跳过扫码
    - 第二台手机扫同一 QR：因为第一台已绑，应被设备拒绝（ACK result=2）
  - [ ] 14.4 提交 commit：`feat: App 扫码绑定流程（Phase 3）`
  - _Requirements: 10.2, 10.5_

### Phase 4 — 解绑 + 保底重置 + 测试文档

- [ ] 15. App 解绑 UI
  - [ ] 15.1 修改 `RideWind/lib/screens/settings_screen.dart`
    - 加「解绑设备」入口（红色文字 + 警告图标），仅 `btProvider.isBound` 时显示
    - 点击 → 弹 Dialog「确认解绑？」「解绑后该设备需要重新扫码绑定，且其他手机才能连接它」「取消 / 确认解绑」
    - 确认 → 检查 `btProvider.isConnected`：是 → 调 `BindFlowController.unbind(deviceConnected: true)`；否 → 弹二级 Dialog「设备未连接，仅清除手机端绑定…」「取消 / 仍然解绑」→ 调 `unbind(deviceConnected: false)`
    - 解绑完成：跳 NoDeviceScreen
    - _Requirements: 5.1-5.5_

- [ ] 16. 编写测试与文档
  - [ ] 16.1 创建 `RideWind/test/protocol/bind_protocol_test.dart`
    - encode `CMD_BIND_REQUEST` 字符串 → 校验各字段位置正确
    - decode `BIND_ACK:0:RideWind-A1B2` → result=0 + device_name 正确
    - decode `BIND_ACK:1:` / `2:` / `3:` / `4:` → 四种错误分支
    - decode 畸形输入 → 返回 null/error
    - decode `UNBIND_ACK` → 正确识别
    - _Requirements: 10.4_

  - [ ] 16.2 创建 `RideWind/docs/BINDING_TEST_CHECKLIST.md`
    - 6 类场景：① 首次绑定 happy ② 第二台手机被拒 ③ App 主动解绑 ④ 5 次冷启保底 ⑤ token 10 分钟轮换 ⑥ App 卸载重装边缘
    - 每场景四列表格：前置 / 步骤 / 预期 / 实际
    - _Requirements: 10.3_

- [ ] 17. Phase 4 验证 + commit
  - [ ] 17.1 走通 BINDING_TEST_CHECKLIST 全部 6 场景实机
  - [ ] 17.2 `flutter analyze` 0 error；`flutter test` 全过；`idf.py build` 0 error
  - [ ] 17.3 提交 commit：`feat: 解绑流程与保底重置（Phase 4）`
  - [ ] 17.4 在 CHANGELOG.md 加一段 Unreleased / device-binding-qrcode 说明
  - _Requirements: 10.1, 10.2, 10.5_

## Notes

- 每个 Phase 都能独立运行：Phase 1 完了即使没 Phase 2，设备也能开机出 QR（虽然 App 还连不上）；Phase 2 完了用蓝牙调试 App 也能完成绑定
- Phase 3 之前 App 端不需要任何改动，所以 Phase 1+2 烧录到测试机不影响线上 App
- ESP-IDF qrcode 组件版本号 `^0.1.0` 是占位，task 1.1 实际拉取时 confirm 最新可用版
- 中文显示如不支持，task 3.1 退化为英文 + 后续叠加图片资源
- 整个 spec **不动 ridewind-esp/drivers/**，drivers 层完全保持
- 整个 spec **不引入新状态管理框架**，仍用 Provider + get_it（符合 engineering-refactor 约束）
- BLE protocol UUID（0xFFE0/0xFFE1）和现有命令格式**不动**

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["2.1"] },
    { "id": 3, "tasks": ["2.2"] },
    { "id": 4, "tasks": ["3.1", "3.2"] },
    { "id": 5, "tasks": ["4.1", "4.2"] },
    { "id": 6, "tasks": ["5.1", "5.2", "5.3"] },
    { "id": 7, "tasks": ["6.1"] },
    { "id": 8, "tasks": ["6.2"] },
    { "id": 9, "tasks": ["7.1", "7.2", "7.3"] },
    { "id": 10, "tasks": ["8.1", "8.2", "8.3"] },
    { "id": 11, "tasks": ["9.1", "9.2"] },
    { "id": 12, "tasks": ["10.1"] },
    { "id": 13, "tasks": ["11.1", "11.2"] },
    { "id": 14, "tasks": ["12.1"] },
    { "id": 15, "tasks": ["13.1", "13.2"] },
    { "id": 16, "tasks": ["14.1", "14.2", "14.3", "14.4"] },
    { "id": 17, "tasks": ["15.1"] },
    { "id": 18, "tasks": ["16.1", "16.2"] },
    { "id": 19, "tasks": ["17.1", "17.2", "17.3", "17.4"] }
  ]
}
```
