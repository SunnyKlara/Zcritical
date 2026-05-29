# Design Document: Device Binding via QR Code

## Overview

本设计文档描述如何在现有 RideWind 系统上实现一对一绑定。整体策略是**在协议层和 BLE 入口处插入"准入控制"门**，外加一个独立的 `bind_service` 模块管理状态机和 NVS 持久化；其他模块基本不动。

设计目标：
- 设备端：不破坏现有 UI / 协议 / OTA / Audio 流程，**只新增 1 个 service + 1 个 UI 屏 + 协议层 3 条命令**
- App 端：扫码界面 + 解绑入口接到 `BluetoothProvider`，复用 `BLEService` 现有机制，**不引入新状态管理框架**
- 文本协议风格：保持现有"行分隔 ASCII 命令"约定，与 `CMD_PING` / `CMD_HELLO` 同级

## 架构与模块边界

### 设备端模块图

```
┌──────────────────────────────────────────────────────────┐
│                       main.c (boot)                       │
│  nvs_flash_init → app_state_init → bind_service_init →   │
│  根据 Bind_State 分流：                                    │
│    BOUND   → boot_logo → ui_manager_set_ui(1)            │
│    UNBOUND → ui_manager_set_ui(QR)  (跳过 logo)          │
└──────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌──────────────┐   ┌──────────────────┐   ┌──────────────┐
│ ble_service  │   │   bind_service   │   │  ui_manager  │
│  (existing)  │   │     (NEW)        │   │   (touched)  │
│              │   │                  │   │              │
│ process_rx → │←─→│ pre-dispatch gate│   │ + ui_qr.c    │
│ cmd_queue    │   │ + state machine  │   │ (NEW screen) │
│              │   │ + NVS persist    │   │              │
└──────┬───────┘   └─────────┬────────┘   └──────┬───────┘
       │                     │                   │
       ▼                     ▼                   ▼
┌──────────────┐   ┌──────────────────┐   ┌──────────────┐
│   protocol   │   │       NVS        │   │   drv_lcd    │
│  (touched)   │   │  ns="bind"       │   │  (existing)  │
│ + 3 cmd enum │   │  phone_id /      │   │              │
│ + parse      │   │  cold_boot_count │   │              │
└──────────────┘   └──────────────────┘   └──────────────┘
                             │
                             ▼
                   ┌──────────────────┐
                   │ qrcode component │
                   │  (espressif/     │
                   │   qrcode)        │
                   └──────────────────┘
```

**职责划分**：
- `bind_service`：唯一拥有 `bind/*` NVS key 写权的模块；维护 `Bind_State` 与 `Pair_Token`；提供 "准入决策" API 给 `ble_service` 和 `protocol` 调用
- `ble_service`：在连接事件和 RX 路由时，调用 `bind_service` 的 gate 函数判断该客户端能否继续；不做绑定逻辑
- `protocol`：扩展 3 条 cmd 解析 + 1 个 ack 响应格式化函数；不持久化任何状态
- `ui_qr`：纯渲染，依赖 `bind_service_get_qr_payload()` 拿 token，依赖 `qrcode` 组件生成模块矩阵
- `ui_manager`：原 UI 路由表新增 QR 屏 ID（值 9），boot 时根据 `bind_state` 决定首屏

**层级合规性**（对照 engineering-standards 的 drivers / services / ui 分层）：
- `bind_service.c` 在 `services/`，**不**直接调用 GPIO/PWM 等外设 API
- `ui_qr.c` 在 `ui/`，调用 `drv_lcd` + `qrcode` 库 + `bind_service` getter，不直接碰 SPI

### App 端模块图

```
┌────────────────────────────────────────────────────────┐
│                no_device_screen.dart                   │
│  + 「扫码绑定」按钮 → 跳 ScanBindScreen                │
└────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────┐
│              scan_bind_screen.dart (NEW)               │
│  mobile_scanner → 解析 ridewind:// URI →               │
│  BindFlowController.startBind(mac, token)              │
└────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────┐
│         bind_flow_controller.dart (NEW, in core/)      │
│  - load/create App_Phone_Id (UUIDv4)                   │
│  - 通过 BluetoothProvider 连指定 MAC                   │
│  - send CMD_BIND_REQUEST                               │
│  - 解析 CMD_BIND_ACK                                   │
│  - 持久化绑定状态 → 跳主 UI                            │
└────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────┐
│              BluetoothProvider (touched)               │
│  + sendBindRequest(phoneId, token, nonce)              │
│  + sendUnbind()                                        │
│  + Stream<BindAck> bindAckStream                       │
│  + bool isBound (loaded from prefs at boot)            │
└────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────┐
│                BLEService (existing)                   │
│  无需扩展：bind 命令复用现有 sendCommand()              │
│  ack 通过现有 ResponseRouter 路由                       │
└────────────────────────────────────────────────────────┘
```

## 设备端状态机

```
                        cold boot
                            │
                            ▼
                ┌───────────────────────┐
                │  read NVS bind/*      │
                │  cold_boot_count++    │
                └────────┬──────────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
  count >= 5 AND BOUND          其他情况
            │                         │
            ▼                         ▼
  ┌─────────────────┐       ┌─────────────────┐
  │ erase phone_id  │       │ phone_id exists?│
  │ count = 0       │       └────┬──────┬─────┘
  └────────┬────────┘            │      │
           │                  yes│      │no
           │                     ▼      ▼
           │           ┌──────────┐  ┌──────────┐
           ▼           │  BOUND   │  │ UNBOUND  │
   ┌────────────┐      └────┬─────┘  └────┬─────┘
   │  UNBOUND   │           │             │
   └────────────┘           │             │
        │                   │             │
        │  ┌────────────────┘             │
        │  │ run for 10s? → reset counter │
        │  ▼                              │
        │ normal UI flow                  │
        │  │                              │
        │  │  CMD_UNBIND from bound phone │
        │  ▼                              │
        └──┐                              │
           │                              │
           │       gen Pair_Token         │
           │       render QR screen       │
           │       freeze peripherals     │
           │       BLE adv [BIND]         │
           │              │               │
           │              ▼               │
           │   wait CMD_BIND_REQUEST      │
           │              │               │
           │              ▼               │
           │     token match? phone_id    │
           │     valid uuidv4?            │
           │       │           │          │
           │     yes           no         │
           │       │           │          │
           │       ▼           ▼          │
           │  write phone_id  ack err     │
           │  ack ok                      │
           │  switch UI(1) ◄──────────────┘
           │
           └─→ BOUND
```

**关键状态变量**（`bind_service.c` 模块级）：
```c
typedef struct {
    bool        is_bound;
    char        phone_id[37];      // 36 chars + NUL
    uint8_t     pair_token[16];    // 128-bit
    uint8_t     last_bind_nonce[16];
    bool        last_bind_nonce_valid;
    uint64_t    token_generated_us;
    uint8_t     cold_boot_count;
} bind_state_t;
```

## 协议扩展

### 文本协议格式（与现有 `CMD_PING` 等同风格）

#### CMD_BIND_REQUEST（App → Device）
```
BIND:<phone_id>:<token>:<nonce>\n
```
- `phone_id`：36 字符 UUIDv4 标准形式
- `token`：32 hex chars（小写）
- `nonce`：32 hex chars（16 字节 hex 编码）

示例：
```
BIND:550e8400-e29b-41d4-a716-446655440000:a1b2c3d4e5f60718293a4b5c6d7e8f90:0123456789abcdef0123456789abcdef
```

#### CMD_BIND_ACK（Device → App）
```
BIND_ACK:<result>:<device_name>\n
```
- `result`：0=ok, 1=token_mismatch, 2=already_bound_other, 3=phone_id_invalid, 4=nonce_replay
- `device_name`：仅 result=0 时携带，否则空字符串

示例（成功）：
```
BIND_ACK:0:RideWind-A1B2
```
示例（失败）：
```
BIND_ACK:2:
```

#### CMD_UNBIND（App → Device）
```
UNBIND\n
```
设备回 `UNBIND_ACK\n` 后断开 BLE。

### 准入控制（gate）规则

`bind_service_can_dispatch(cmd_type_t cmd)` 在 `protocol_parse` 后、`cmd_queue` 入队前调用：

| Bind_State | cmd            | 处理            |
|------------|----------------|----------------|
| UNBOUND    | CMD_BIND_REQUEST | 入队，由 bind_service 处理 |
| UNBOUND    | 其他任意 cmd     | 拒绝，回 `ERR:NOT_BOUND\n` |
| BOUND      | CMD_BIND_REQUEST | 检查 phone_id：是当前→刷新；不是→回 `BIND_ACK:2:` 后断开 |
| BOUND      | CMD_UNBIND       | 入队由 bind_service 处理 |
| BOUND      | 其他 cmd         | 入队（与现行行为一致） |

注意：`gate` 只看协议命令类型，**不**看 BLE 链路层 ID（同时只有一个 GATT 连接，复用现状）。

## NVS 数据布局

| Namespace | Key             | Type    | 描述 |
|-----------|-----------------|---------|------|
| `bind`    | `phone_id`      | string  | 36 chars UUIDv4，存在即代表 BOUND |
| `bind`    | `cold_boot_count` | u8    | 累计未稳定冷启次数，0~255 |
| `bind`    | `schema_version`| u8      | 当前固定 1 |

`bind_service_init()` 启动时：
1. `nvs_open("bind", NVS_READWRITE, &h)`
2. 读 `schema_version`：缺失则写 1 + cold_boot_count=0
3. 读 `cold_boot_count`，+1，写回
4. 读 `phone_id`：成功则 `is_bound = true`
5. 检查保底：`cold_boot_count >= 5 && is_bound` → `nvs_erase_key("phone_id")` + `is_bound = false` + count=0 + LOGW
6. 启动 10s 软件定时器：到点若 `is_bound` 未变，写回 `cold_boot_count = 0`

## 二维码渲染

### 依赖
- ESP-IDF 组件：`espressif/qrcode`（管理器加 `idf_component.yml`）
- 输出：`uint8_t modules[N][N]`（N 由版本决定，本协议 payload 长约 80~90 字符 → version 5, ECC M, N=37）

### 渲染流程（`ui_qr.c`）
```c
void ui_qr_render(void)
{
    char payload[128];
    bind_service_get_qr_payload(payload, sizeof(payload));   // ridewind://bind?...

    esp_qrcode_handle_t qr;
    esp_qrcode_config_t cfg = {
        .display_func = qr_pixel_callback,
        .max_qrcode_version = 6,
        .qrcode_ecc_level = ESP_QRCODE_ECC_MED,
    };
    esp_qrcode_generate(&cfg, payload);

    // qr_pixel_callback 已经把 modules 收集到全局 buffer
    // 居中绘制：240x240 / 37 modules ≈ 6 px/module
    drv_lcd_clear(COLOR_WHITE);
    int module_size = 6;
    int total = 37 * module_size;            // 222 px
    int offset = (240 - total) / 2;          // 9 px

    for (int y = 0; y < 37; y++)
        for (int x = 0; x < 37; x++)
            if (qr_modules[y][x])
                drv_lcd_fill_rect(offset + x*module_size, offset + y*module_size,
                                  module_size, module_size, COLOR_BLACK);

    drv_lcd_draw_text_8x16(20, 230 - 16, "请用 RideWind App 扫码绑定", COLOR_BLACK);
}
```

注：`drv_lcd_draw_text_8x16` 当前若不支持 UTF-8 中文，备选用图片资源（同 boot_logo 风格存为 RGB565 PSRAM 图）渲染那一行文字——具体在 task 阶段确认。

### Token 轮换
`ui_qr_render` 之外，`bind_service` 维护 `token_generated_us`，在主循环每 1s 检查一次；若 `now - generated > 600s` 则 regen + LCD 重绘事件入 `ui_qr` 队列。

## App 端设计

### 新增文件
```
RideWind/lib/
├── core/
│   └── bind_flow_controller.dart    (NEW, ~150 lines)
├── services/
│   └── secure_storage_service.dart  (NEW, ~50 lines)  ← 封装 flutter_secure_storage
└── screens/
    └── scan_bind_screen.dart        (NEW, ~200 lines)
```

### `bind_flow_controller.dart` 关键 API
```dart
class BindFlowController {
  final BluetoothProvider ble;
  final SecureStorageService storage;

  /// 扫码后调用，返回成功 / 失败原因
  Future<BindResult> startBind({
    required String mac,
    required String token,
  }) async {
    // 1. 取/造 phone_id
    final phoneId = await storage.getOrCreatePhoneId();
    // 2. 连 BLE
    final connected = await ble.connectByMac(mac, timeout: Duration(seconds: 15));
    if (!connected) return BindResult.connectFail;
    // 3. 发 BIND
    final nonce = _genNonce();
    ble.sendCommand('BIND:$phoneId:$token:$nonce');
    // 4. 等 ACK
    final ack = await ble.bindAckStream
        .firstWhere((_) => true)
        .timeout(Duration(seconds: 10), onTimeout: () => BindAck.timeout());
    if (ack.result == 0) {
      await storage.saveBoundDevice(mac: mac, phoneId: phoneId, deviceName: ack.deviceName);
      return BindResult.ok;
    }
    return BindResult.fromCode(ack.result);
  }

  Future<void> unbind() async { ... }
}
```

### 状态融合（接入 BluetoothProvider）

`BluetoothProvider` 增加：
- `bool _isBound` 私有字段，启动时从 `secure_storage` 加载
- `String? _boundDeviceMac`
- `Stream<BindAck> bindAckStream` （from ResponseRouter 解析 `BIND_ACK:xx:yy`）
- 公开方法：`getBoundDeviceMac()`, `clearLocalBindState()`

**遵守 engineering-refactor 规则**：不破坏 `BluetoothProvider` 现有 public API；新方法属于扩展。

### 解绑流程
```
[Settings] 「解绑设备」按钮 (仅 isBound 时可见)
     │
     ▼
[Dialog] 「确认解绑？」
     │
     ▼
   isConnected?
     │
   ┌─┴─┐
   │   │
  yes  no
   │   │
   │   └─→ [Dialog] 「设备未连接，仅清手机端…」 → clearLocalBindState
   │
   ▼
sendUnbind() → wait UNBIND_ACK (5s)
   │
   ▼
clearLocalBindState() → navigate to NoDeviceScreen
```

## 启动顺序固化（设备端）

`main.c` 现有顺序：
```c
nvs_flash_init();
app_state_init();
ui_manager_init();
drv_lcd_init();
boot_logo_show();          // ← 现有
ble_service_init();
ui_manager_set_ui(1);      // ← 现有默认进 UI1
```

新顺序：
```c
nvs_flash_init();
app_state_init();
bind_service_init();       // NEW: 读 NVS, 累加 cold_boot_count, 检查保底
drv_lcd_init();
ui_manager_init();
ble_service_init();        // 此时 advertising 已带 [BIND] 后缀（如 UNBOUND）

if (bind_service_is_bound()) {
    boot_logo_show();
    ui_manager_set_ui(1);
} else {
    ui_manager_set_ui(UI_QR);   // NEW screen ID = 9
}

// 后续主循环 + 10s soft timer 回调清 cold_boot_count
```

外设冻结：`bind_service_apply_unbound_freeze()` 在进入 UNBOUND 时调用，置位标志被各 service 在 tick 函数开头检查跳过输出。

## 错误处理

| 错误情形                          | 设备表现             | App 表现                  |
|----------------------------------|--------------------|--------------------------|
| QR 解析失败                      | -                  | Toast「二维码无效」       |
| BLE 连接超时（15s）              | -                  | Dialog 重试 / 返回         |
| BIND 命令超时（10s）             | -                  | Dialog 重试 / 返回         |
| token mismatch                  | log + ack 1        | Dialog「请重新扫码」       |
| already_bound_other             | log + ack 2 + 断开 | Dialog「该设备已被其他手机绑定」 |
| phone_id 格式错                 | log + ack 3        | Dialog「内部错误，重试」    |
| nonce replay                    | log + ack 4        | Dialog「重试」             |
| NVS 写失败                       | log E + 保留 UNBOUND| -                       |
| 设备 BOUND 状态、其他手机连入    | 5s 内未 BIND → 断开 | App 端自然连接失败          |

## 安全考虑

- **Token 一次性**：每次开机+每 10 分钟轮换，扫旧 token 必失败
- **Nonce 防重放**：单 token 周期内同一 nonce 不接受第二次（已绑成）
- **MitM 风险**：BLE 4.2+ 默认 LE Secure Connections 提供链路加密；本协议不再叠加加密。如未来需要，可在 `BIND_REQUEST` 加 HMAC，token 当 key
- **物理拆解攻击**：不是本设计的威胁模型——拆 flash 能拿到 phone_id 但拿不到 App，仍需扫码
- **首次绑定会被旁人偷扫吗？**：如果攻击者站旁边能看到屏幕，理论可行。规避：用户扫码时设备屏幕朝向用户、并且在配对用户操作下扫成功后 token 立即失效

## 测试策略

### 单元测试（设备端，host 编译可跑）
- `bind_service_token_rotation_test`：模拟时间推进 600s+1，断言 token 已变
- `bind_service_nvs_recovery_test`：模拟 schema_version 不存在 / 大于 1 / phone_id 格式错三种 NVS 状态

### 单元测试（App 端 `RideWind/test/protocol/`）
- `bind_protocol_test.dart`：encode/decode CMD_BIND_REQUEST 各字段、ACK 解析 4 种 result 分支
- 不破坏现有 51 个 protocol 测试

### 手动测试清单（`RideWind/docs/BINDING_TEST_CHECKLIST.md`）
覆盖 requirements §10.3 列出的 6 类场景，每类带"前置 / 步骤 / 预期 / 实际"四列。

### CI 集成
- 固件：现有 `idf.py build` 加上新 component 不变
- App：`flutter analyze` + `flutter test test/protocol/` 必须 0 错

## 关键决策记录

| 决策点                            | 选择                              | 备选 + 否决理由 |
|----------------------------------|----------------------------------|---------------|
| 二维码内容                        | URI 形式 mac+token              | 仅 mac（不安全）/ 公钥（工作量翻倍） |
| phone_id 来源                     | App UUIDv4 + secure_storage     | 系统硬件 ID（iOS/Android 都不稳定） |
| 解绑入口                          | App 按钮 + 5 次冷启保底          | 硬件长按（编码器键已占用）/ 菜单项（菜单已满） |
| Token 持久化                      | 不持久化，每次开机新生成         | 持久化（易被扫描泄漏；轮换无意义） |
| 协议帧格式                        | 复用文本协议风格                  | 二进制（违反现有约定，要改 parser） |
| 解绑后处理                        | 清 NVS + 立即出 QR + 断开 BLE   | 仅断开（用户困惑下次怎么连） |
| UNBOUND 状态外设                  | 全冻结                          | 部分允许（增加歧义；用户以为坏了） |

## 参考与依赖

- ESP-IDF 组件：[`espressif/qrcode`](https://components.espressif.com/components/espressif/qrcode)
- Flutter 包：[`mobile_scanner`](https://pub.dev/packages/mobile_scanner) / [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) / [`uuid`](https://pub.dev/packages/uuid)
- 工程规范：`engineering-standards.md`（drivers/services/ui 分层）
- 关联 spec：`engineering-refactor`（state management / public API stability）
