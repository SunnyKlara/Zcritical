# Requirements Document

## Introduction

RideWind 设备一对一绑定（QR Code Pairing）特性。核心目的：**防止多手机连接冲突**。一台 ESP32 设备只能与单一手机配对；任何未授权的手机即使发现 BLE 信号也会被设备拒绝连接。

绑定流程：设备未绑定时，开机后 LCD 显示二维码 → 用户用 RideWind App 扫码 → App 通过 BLE 连接并发起绑定握手 → 设备记录授权手机标识到 NVS → 进入正常工作界面。绑定建立后跨重启保持；只有用户在 App 中**主动解绑**或触发**保底重置**才能让设备回到未绑定态、重新出二维码。

实施范围：ESP32 固件（`ridewind-esp/`）+ Flutter App（`RideWind/`）。**不涉及**云端、不涉及账号体系。

## Glossary

- **Pairing_Authority**：设备端绑定状态机及其授权决策逻辑
- **Bound_Phone_Id**：当前授权手机的唯一标识，UUIDv4 字符串，存于设备 NVS（namespace `bind`，key `phone_id`）
- **Pair_Token**：开机时设备随机生成的一次性配对令牌（128-bit），写入二维码 payload，用于校验扫码请求来自当前广播的二维码
- **Pair_Nonce**：每次绑定握手 App 提交的随机数，与 Pair_Token 一同校验，防重放
- **Bind_State**：设备端两种工作模态之一——`UNBOUND`（显示二维码、等待绑定）或 `BOUND`（正常 UI 工作流）
- **QR_Payload**：编码进二维码的 URI，格式 `ridewind://bind?mac=<MAC>&token=<TOKEN>&v=1`
- **Bind_NVS_Namespace**：NVS 中绑定相关数据的命名空间，固定为 `bind`
- **Cold_Boot_Counter**：NVS 计数器，每次冷启动 +1，正常绑定运行 ≥10s 后清零；用于保底解绑
- **Unbind_Reset_Threshold**：触发保底解绑所需的连续未稳定冷启动次数，固定为 5
- **CMD_BIND_REQUEST / CMD_BIND_ACK / CMD_UNBIND**：BLE 协议层新增的三条命令
- **App_Phone_Id**：手机端首次启动生成的 UUIDv4，存于平台安全存储（Android: EncryptedSharedPreferences；iOS: Keychain）
- **Bond_Reject_Event**：当 BOUND 状态下非 Bound_Phone_Id 的客户端尝试绑定握手时设备产生的拒绝事件

## Requirements

### Requirement 1: 设备端绑定状态机

**User Story:** As a device, I want to track whether I am bound to a phone and behave differently in each state, so that I never serve multiple phones simultaneously.

#### Acceptance Criteria

1. WHEN the device boots, THE Pairing_Authority SHALL read `bind/phone_id` from NVS, set Bind_State to `BOUND` if the value exists and is a 36-character UUIDv4 string, otherwise set Bind_State to `UNBOUND`
2. WHEN Bind_State is `UNBOUND`, THE device SHALL display the QR code screen on LCD and SHALL NOT enter any normal UI screen (UI1..UI8)
3. WHEN Bind_State is `BOUND`, THE device SHALL skip the QR screen at boot and proceed directly to the previously active UI screen exactly as the current behavior
4. WHEN Bind_State transitions from `UNBOUND` to `BOUND` after a successful bind handshake, THE device SHALL switch the LCD from QR screen to the default UI (UI1) within 500 ms
5. WHEN Bind_State transitions from `BOUND` to `UNBOUND` (after CMD_UNBIND or fallback reset), THE device SHALL clear `bind/phone_id` from NVS, regenerate a new Pair_Token, and switch the LCD to the QR screen within 500 ms
6. THE Pairing_Authority SHALL persist Bind_State only via the existence of `bind/phone_id` in NVS — there SHALL be no separate "is_bound" boolean key

### Requirement 2: 二维码生成与渲染

**User Story:** As a user, I want to see a clear, scannable QR code on the device LCD when the device is unbound, so that I can pair with my phone using the RideWind App.

#### Acceptance Criteria

1. WHEN entering `UNBOUND` state, THE device SHALL generate a fresh Pair_Token using `esp_random()` to produce 128 bits encoded as 32 lowercase hex characters
2. THE QR_Payload SHALL be the URI `ridewind://bind?mac=<MAC>&token=<TOKEN>&v=1` where `<MAC>` is the device BLE MAC address as 12 uppercase hex characters without separators and `<TOKEN>` is the Pair_Token
3. THE device SHALL render the QR code using ECC level M (medium error correction)
4. THE rendered QR code SHALL occupy a centered square region on the 240×240 LCD with a minimum module size of 6 pixels and a quiet zone of at least 4 modules on every side
5. THE QR screen SHALL display below the QR code a single line of fixed Chinese text "请用 RideWind App 扫码绑定" rendered with the existing 8×16 font
6. WHEN the same Pair_Token has been displayed for more than 10 minutes without a successful bind, THE device SHALL regenerate a new Pair_Token and re-render the QR code
7. THE QR code SHALL remain visible continuously while Bind_State is `UNBOUND` — no animation, no idle blanking, no boot logo overlay

### Requirement 3: BLE 绑定握手协议

**User Story:** As an App, I want a deterministic BLE handshake to register myself as the bound phone, so that the device records my identity atomically and rejects all other phones afterwards.

#### Acceptance Criteria

1. THE protocol layer SHALL define three new commands: `CMD_BIND_REQUEST`, `CMD_BIND_ACK`, `CMD_UNBIND`, integrated into the existing `protocol.c` / `protocol.h` command dispatcher and following the existing command frame format
2. WHEN the device is in `UNBOUND` state and receives `CMD_BIND_REQUEST` carrying `{phone_id, token, nonce}`, THE Pairing_Authority SHALL verify that the received `token` matches the current Pair_Token byte-for-byte
3. IF the token matches, THEN THE Pairing_Authority SHALL atomically write `phone_id` to `bind/phone_id` in NVS, commit the NVS transaction, set Bind_State to `BOUND`, and reply with `CMD_BIND_ACK` carrying `{result=0, device_name}`
4. IF the token does not match, THEN THE Pairing_Authority SHALL reply with `CMD_BIND_ACK` carrying `{result=1}` (token mismatch) and SHALL NOT modify NVS
5. WHEN the device is in `BOUND` state and receives `CMD_BIND_REQUEST` from a phone whose `phone_id` does not equal Bound_Phone_Id, THE Pairing_Authority SHALL reply with `CMD_BIND_ACK` carrying `{result=2}` (already bound to another phone) and SHALL disconnect the BLE link within 200 ms
6. WHEN the device is in `BOUND` state and the connecting phone (identified during connection or on first command) does not present a `phone_id` matching Bound_Phone_Id within 5 seconds of GATT connection, THE Pairing_Authority SHALL disconnect the BLE link
7. THE `phone_id` field in CMD_BIND_REQUEST SHALL be a UTF-8 string of exactly 36 characters in canonical UUIDv4 form (e.g., `550e8400-e29b-41d4-a716-446655440000`); requests with malformed `phone_id` SHALL be rejected with `result=3`
8. THE Pair_Nonce field SHALL be 16 bytes of random data; the device SHALL reject any CMD_BIND_REQUEST whose `nonce` was used by a previous successful bind for the current Pair_Token (in-memory single-slot cache, cleared on token regeneration)

### Requirement 4: App 端扫码与绑定流程

**User Story:** As a user, I want to scan the device QR code with the RideWind App and complete pairing without any manual data entry, so that the binding feels seamless.

#### Acceptance Criteria

1. WHEN the App detects no Bound_Phone_Id stored locally OR the stored device pairing is missing, THE App SHALL show a "Scan to Bind" entry button on the no-device screen
2. WHEN the user taps "Scan to Bind", THE App SHALL open a camera scanning screen using `mobile_scanner` package and read QR codes
3. WHEN a QR code is detected, THE App SHALL parse it as a URI and accept it only if scheme is `ridewind`, host is `bind`, query contains `mac` (12 hex chars), `token` (32 hex chars), and `v=1`; otherwise reject with a Toast "二维码无效"
4. WHEN a valid QR is parsed, THE App SHALL connect to the BLE peripheral whose MAC matches the parsed `mac` (use scan-then-connect pattern), with a 15-second connect timeout
5. WHEN BLE connection is established, THE App SHALL load App_Phone_Id (creating one via `Uuid().v4()` if not yet present and persisting to secure storage), generate a fresh 16-byte nonce via `Random.secure()`, and send CMD_BIND_REQUEST `{phone_id, token, nonce}`
6. WHEN the App receives CMD_BIND_ACK with `result=0`, THE App SHALL persist the device's MAC and a "bound" flag locally, navigate to the main UI, and show a 1.5s success toast "绑定成功"
7. WHEN the App receives CMD_BIND_ACK with `result≠0` OR connection times out OR command times out (10s), THE App SHALL show an error dialog with the failure reason and offer "Retry" / "Back" actions; THE App SHALL NOT persist any bound state
8. THE App_Phone_Id storage SHALL use `flutter_secure_storage` with `IOSOptions.first.copyWith(accessibility: KeychainAccessibility.first_unlock_this_device)` on iOS and `AndroidOptions(encryptedSharedPreferences: true)` on Android
9. THE App SHALL surface a single, current bound device — multi-device binding is out of scope for this spec

### Requirement 5: App 端解绑流程

**User Story:** As a user, I want to unbind my device from within the App settings, so that I can pair the device with a different phone.

#### Acceptance Criteria

1. THE App settings screen SHALL include an "解绑设备" entry that is visible only when a Bound_Phone_Id is stored AND a device is currently or recently connected
2. WHEN the user taps "解绑设备", THE App SHALL show a confirmation dialog with title "确认解绑？" and body "解绑后该设备需要重新扫码绑定，且其他手机才能连接它"
3. WHEN the user confirms unbinding AND the device is currently connected, THE App SHALL send CMD_UNBIND to the device, wait for ACK with 5-second timeout, then clear the local bound state regardless of ACK outcome
4. WHEN the user confirms unbinding AND the device is NOT currently connected, THE App SHALL show a secondary dialog "设备未连接，仅清除手机端绑定。设备需通过断电重置才能与其他手机配对。是否继续？" with "取消"/"仍然解绑"
5. WHEN unbinding is complete, THE App SHALL clear App_Phone_Id-to-device mapping from local storage and navigate to the no-device screen
6. WHEN the device receives CMD_UNBIND from the currently bound phone, THE Pairing_Authority SHALL clear `bind/phone_id` from NVS, transition to `UNBOUND`, regenerate Pair_Token, switch LCD to QR screen, and reply with ACK before disconnecting

### Requirement 6: 保底重置机制

**User Story:** As a user who lost my phone or uninstalled the App, I want a way to reset device binding without the App, so that I am not permanently locked out of my own device.

#### Acceptance Criteria

1. THE device SHALL maintain a `bind/cold_boot_count` counter in NVS, incremented by 1 on every cold boot before reading Bind_State
2. WHEN the device has been in `BOUND` state continuously for at least 10 seconds since boot AND the counter is non-zero, THE device SHALL reset `bind/cold_boot_count` to 0
3. WHEN the device boots AND finds `bind/cold_boot_count` ≥ Unbind_Reset_Threshold (5) AND Bind_State is `BOUND`, THE Pairing_Authority SHALL clear `bind/phone_id` from NVS, reset the counter to 0, and start in `UNBOUND` state with a fresh QR code
4. THE fallback reset SHALL be triggered only by cold boots (power-on / hardware reset) — soft reboots (`esp_restart()`) SHALL also count, but watchdog-triggered resets SHALL NOT count
5. THE device SHALL log every fallback reset event via ESP_LOGW with tag `bind` so that the trigger is visible in serial logs for support diagnostics
6. THE device SHALL NOT expose any other unbind path: no hardware button combo, no menu item, no UART command — App-driven unbind (Requirement 5) and fallback (this requirement) are the only two

### Requirement 7: NVS 数据布局与迁移

**User Story:** As a developer, I want a clearly defined NVS layout for binding data, so that the storage schema is forward-compatible and does not collide with existing keys.

#### Acceptance Criteria

1. THE binding-related NVS keys SHALL all reside in namespace `bind`, distinct from existing namespaces (`config`, `logo`, etc.)
2. THE namespace `bind` SHALL contain exactly these keys: `phone_id` (string, 36 chars), `cold_boot_count` (u8), `schema_version` (u8, current value 1)
3. WHEN the device boots and `bind/schema_version` is missing, THE device SHALL initialize the namespace by writing `schema_version=1` and `cold_boot_count=0` and SHALL NOT touch `phone_id` if it already exists
4. WHEN the device boots and `bind/schema_version` is greater than the firmware-supported version, THE device SHALL log an error and start in `UNBOUND` state without modifying any `bind/*` key
5. THE Pair_Token SHALL never be persisted to NVS — it is a session-only value held in RAM and regenerated on every boot or token rotation event

### Requirement 8: 已有 BLE 通信兼容性

**User Story:** As a developer, I want the binding feature to integrate cleanly with the existing BLE service, so that the binding handshake does not break current speed/LED/audio command flows.

#### Acceptance Criteria

1. THE binding feature SHALL NOT change existing BLE service UUID (0xFFE0) or characteristic UUID (0xFFE1)
2. THE binding feature SHALL NOT modify the frame format or any existing command opcode of the protocol layer
3. WHEN Bind_State is `UNBOUND`, the BLE GATT server SHALL still advertise and accept connections, but SHALL only accept CMD_BIND_REQUEST — every other command SHALL receive an error response with code "not_bound" and SHALL NOT mutate device state
4. WHEN Bind_State is `BOUND` AND the connected client is the Bound_Phone_Id, THE BLE service SHALL behave identically to the current pre-binding behavior — all existing commands continue to work without modification
5. THE App's existing BluetoothProvider SHALL be extended with the bind handshake state machine and SHALL NOT have its public API changed for unrelated callers (Requirement 6.2 of engineering-refactor spec — public API stability)

### Requirement 9: 启动顺序与初始化

**User Story:** As a developer, I want a deterministic startup sequence that integrates the binding check, so that the device never briefly flashes a normal UI before falling back to the QR screen or vice versa.

#### Acceptance Criteria

1. THE startup sequence SHALL execute in this fixed order: (a) `nvs_flash_init` → (b) `app_state_init` → (c) increment `cold_boot_count` and check fallback reset (Requirement 6.3) → (d) read Bind_State → (e) if `BOUND`: proceed to current pre-binding boot logo and UI flow; if `UNBOUND`: skip boot logo and render QR screen directly
2. THE LCD SHALL NOT display the boot logo while in `UNBOUND` state — the logo screen is reserved for normal-use boot only
3. THE BLE service SHALL start advertising in both `BOUND` and `UNBOUND` states, but the advertised local name SHALL include suffix " [BIND]" while in `UNBOUND` state to aid manual debugging
4. WHEN entering `UNBOUND` state, THE device SHALL freeze all peripheral outputs that are not part of the QR screen (LED strips off, motor PWM 0, audio output muted) until a successful bind transitions to `BOUND`

### Requirement 10: 验收与质量门禁

**User Story:** As a developer, I want automated checks that exercise the full bind/unbind/reset flow, so that regressions are caught before reaching real devices.

#### Acceptance Criteria

1. THE firmware SHALL build cleanly with `idf.py build` — zero warnings of severity error or higher
2. THE App SHALL pass `flutter analyze` with zero errors after this feature is merged
3. THE feature SHALL include a manual test checklist (markdown file at `RideWind/docs/BINDING_TEST_CHECKLIST.md`) covering at minimum: first-time bind happy path, second-phone reject path, App-initiated unbind, cold-boot-5x fallback reset, token rotation after 10 min, App reinstall edge case
4. THE protocol-layer changes (new commands) SHALL be covered by unit tests in `RideWind/test/protocol/` exercising frame encode/decode and ack-result branching, with all new tests passing in CI
5. THE existing 51 protocol tests in `RideWind/test/protocol/` SHALL continue to pass after this feature is merged
