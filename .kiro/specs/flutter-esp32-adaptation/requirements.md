# 需求文档：Flutter APP 适配 ESP32 硬件

## 简介

RideWind 智能风洞模拟器的硬件已从 STM32F405 + JDY-08 BLE 模块迁移到 ESP32-S3（使用 ESP-IDF v5.3.5）。本文档定义了 Flutter APP（RideWind/）适配 ESP32 硬件所需的全部修改。

核心原则：**ESP 端必须兼容 APP 的现有协议，而非反过来**。但由于硬件架构差异（片上 BLE vs 外部模块、WiFi 音频 vs A2DP、预设数量变化等），APP 端仍需进行针对性适配。

## 术语表

- **APP**: Flutter RideWind 移动应用程序
- **ESP32**: 新的 ESP32-S3 硬件平台（ridewind-esp/）
- **F4**: 旧的 STM32F405 硬件平台（f4_26_1.1/）
- **BLE_Service**: APP 端的 BLE 底层通信服务（ble_service.dart）
- **Protocol_Service**: APP 端的协议解析与命令封装服务（protocol_service.dart）
- **Logo_Uploader**: APP 端的 Logo 图片上传模块（当前有 SimpleLogoUploader、ReliableLogoUploader、LogoTransmissionManager 三个实现）
- **Audio_Stream_Service**: APP 端的 WiFi 音频投射服务（audio_stream_service.dart）
- **OTA_Upload_Service**: APP 端的固件升级服务（ota_upload_service.dart）
- **Bluetooth_Provider**: APP 端的蓝牙状态管理 Provider
- **Notify**: BLE 通知，ESP32 向 APP 发送数据的方式
- **CRC32**: 循环冗余校验算法，用于数据完整性验证
- **PSRAM**: ESP32-S3 的外部 SPI RAM，用于大数据缓冲
- **SoftAP**: ESP32 的 WiFi 软接入点模式
- **PCM**: 脉冲编码调制，原始音频数据格式

## 需求

### 需求 1：BLE 连接与设备发现适配

**用户故事：** 作为用户，我希望 APP 能可靠地发现并连接 ESP32 设备，以便通过手机控制风洞模拟器。

#### 验收标准

1. WHEN APP 执行 BLE 扫描时，THE BLE_Service SHALL 同时支持通过设备名称 "T1" 和 Service UUID 0xFFE0 两种方式发现 ESP32 设备。
2. THE BLE_Service SHALL 在连接后请求 MTU 为 247 字节，并将有效载荷（MTU - 3）用于后续数据分包。
3. WHEN BLE 连接断开时，THE BLE_Service SHALL 使用指数退避策略（最多 5 次）自动重连，每次重连前重置接收缓冲区。
4. THE BLE_Service SHALL 在扫描过滤中保留对旧设备名（JDY、BT05、HC）的兼容，以支持同时存在新旧硬件的场景。
5. WHEN ESP32 的 BLE Notify 发送失败（拥塞）时，THE APP SHALL 对关键响应（如 LOGO_ACK、OTA_ACK）实现超时重试机制，超时时间不少于 3 秒。

### 需求 2：BLE 协议响应格式兼容

**用户故事：** 作为用户，我希望 APP 能正确解析 ESP32 返回的所有响应，以便界面状态与硬件保持同步。

#### 验收标准

1. THE Protocol_Service SHALL 解析 ESP32 的 GET:LOGO_SLOTS 响应格式 "LOGO_SLOTS:v0:v1:v2:active\r\n"，其中 v0/v1/v2 为各槽位是否有效（0/1），active 为当前活跃槽位索引。
2. THE Protocol_Service SHALL 解析 ESP32 的 OK:STREAMLIGHT 响应格式 "OK:STREAMLIGHT:x\r\n"，其中 x 为流水灯状态（0/1）。
3. THE Protocol_Service SHALL 解析 ESP32 的 WIFI_IP 通知格式 "WIFI_IP:x.x.x.x\r\n" 和 AUDIO_READY 通知格式 "AUDIO_READY:ip:port\r\n"。
4. THE Protocol_Service SHALL 解析 ESP32 的 WIFI_ERR 错误通知格式 "WIFI_ERR:reason\r\n"。
5. THE Protocol_Service SHALL 解析 ESP32 的 VOL 响应格式 "VOL:xx\r\n"，用于音量查询。
6. WHEN Protocol_Service 收到未知格式的响应时，THE Protocol_Service SHALL 记录警告日志但不影响正常功能。
7. THE Protocol_Service SHALL 正确处理 ESP32 响应中的 \r\n 行终止符（命令确认）和 \n 行终止符（事件报告），两种格式均能正确分割和解析。

### 需求 3：预设颜色数量扩展

**用户故事：** 作为用户，我希望 APP 支持 ESP32 的 14 种颜色预设（F4 仅 12 种），以便使用全部可用配色方案。

#### 验收标准

1. THE APP SHALL 支持 1-14 范围的预设索引，包括新增的预设 13（Ocean Blue）和预设 14（Warm Amber）。
2. THE Protocol_Service SHALL 在 setLEDPreset 方法中将参数校验范围从 1-12 扩展为 1-14。
3. THE Protocol_Service SHALL 在 parsePresetReport 方法中将有效预设范围从 1-12 扩展为 1-14。
4. THE APP 的颜色预设 UI（color_ring_screen.dart）SHALL 显示全部 14 种预设选项，包含名称和预览色。

### 需求 4：Logo 上传模块统一

**用户故事：** 作为开发者，我希望将多个 Logo 上传实现统一为一个可靠的模块，以便降低维护成本并提高上传成功率。

#### 验收标准

1. THE APP SHALL 使用单一的 Logo 上传模块替代当前的 SimpleLogoUploader、ReliableLogoUploader 和 LogoTransmissionManager 三个实现。
2. THE 统一 Logo_Uploader SHALL 实现滑动窗口协议，窗口大小可配置（默认 40），支持累积 ACK（LOGO_ACK:seq）和选择性 ACK（LOGO_SACK:base:bitmap）。
3. THE 统一 Logo_Uploader SHALL 支持 ESP32 的 LOGO_START 协议：发送 "LOGO_START:size:crc32\n"（自动分配槽位）或 "LOGO_START:slot:size:crc32\n"（指定槽位），等待 "LOGO_READY:slot\r\n" 响应。
4. THE 统一 Logo_Uploader SHALL 使用与 ESP32 和 F4 相同的 CRC32 查找表算法（标准 CRC32/ISO 3309），确保校验值一致。
5. WHEN Logo 上传过程中 BLE Notify 丢失导致 ACK 超时时，THE 统一 Logo_Uploader SHALL 重传超时窗口内的数据包，最多重试 10 次。
6. THE 统一 Logo_Uploader SHALL 在传输完成后发送 "LOGO_END\n"，并等待 "LOGO_OK:slot\r\n" 或 "LOGO_FAIL:reason\r\n" 响应，超时时间不少于 10 秒。
7. THE 统一 Logo_Uploader SHALL 提供进度回调（0.0-1.0）、状态回调和错误回调接口。

### 需求 5：WiFi 音频投射功能

**用户故事：** 作为用户，我希望通过 WiFi 将手机音频投射到 ESP32 设备的扬声器，以便在骑行时听音乐（ESP32-S3 不支持经典蓝牙 A2DP）。

#### 验收标准

1. THE Audio_Stream_Service SHALL 通过 BLE 发送 "WIFI:ssid:password\n" 命令，将 WiFi 凭据传递给 ESP32。
2. WHEN ESP32 成功连接 WiFi 并返回 "WIFI_IP:x.x.x.x\r\n" 时，THE APP SHALL 记录 ESP32 的 IP 地址并启用音频投射按钮。
3. THE Audio_Stream_Service SHALL 使用 Android AudioPlaybackCapture API 捕获系统音频，通过 TCP 连接到 ESP32 的 8080 端口，以 44100Hz 16-bit 立体声 PCM 格式流式传输。
4. IF ESP32 返回 "WIFI_ERR:reason\r\n" 时，THEN THE APP SHALL 显示 WiFi 连接失败提示并允许用户重新输入凭据。
5. THE APP SHALL 在音频投射界面提供 WiFi 扫描功能（使用 Android WifiManager），让用户选择网络并输入密码。
6. WHEN 音频投射正在进行时，THE APP SHALL 显示投射状态指示器，并提供停止投射的按钮。
7. THE APP SHALL 仅在 Android 10（API 29）及以上版本启用音频投射功能，低版本显示不支持提示。

### 需求 6：BLE Notify 可靠性增强

**用户故事：** 作为用户，我希望 APP 与 ESP32 之间的通信稳定可靠，不会因为 BLE 通知丢失而导致功能异常。

#### 验收标准

1. WHEN APP 发送命令后未在 3 秒内收到预期响应时，THE Protocol_Service SHALL 自动重发该命令，最多重试 2 次。
2. THE BLE_Service SHALL 在发送数据时使用 write-without-response 模式，并在连续发送多个包时保持最小 2ms 间隔以避免 ESP32 BLE 协议栈拥塞。
3. WHEN BLE 连接参数协商成功后，THE BLE_Service SHALL 请求 High Priority 连接参数（11.25ms interval）以降低延迟。
4. THE Protocol_Service SHALL 维护一个接收缓冲区，正确处理 BLE MTU 分片导致的不完整命令，在收到 '\n' 后才解析完整命令。
5. IF 接收缓冲区超过 512 字节仍未收到完整命令，THEN THE Protocol_Service SHALL 清空缓冲区并记录警告日志。

### 需求 7：OTA 固件升级适配

**用户故事：** 作为用户，我希望通过 APP 升级 ESP32 的固件，以便获取新功能和修复。

#### 验收标准

1. THE OTA_Upload_Service SHALL 发送 "OTA_START:size:crc32\n" 命令启动 ESP32 的 OTA 升级会话，其中 size 为固件大小，crc32 为固件 CRC32 校验值。
2. THE OTA_Upload_Service SHALL 将固件数据以 "OTA_DATA:seq:hex\n" 格式分包发送，每包 16 字节数据（32 字符十六进制），每 16 包等待一次 ACK。
3. WHEN OTA 传输完成后，THE OTA_Upload_Service SHALL 发送 "OTA_END\n" 并等待 "OTA_OK\r\n"（成功）或 "OTA_FAIL:reason\r\n"（失败）响应。
4. THE OTA_Upload_Service SHALL 将最大固件大小限制从 960KB 调整为 2.5MB（ESP32 OTA 分区大小）。
5. IF OTA 升级过程中 BLE 连接断开，THEN THE OTA_Upload_Service SHALL 中止升级并通知用户，ESP32 将自动回滚到上一个有效固件。
6. THE OTA_Upload_Service SHALL 支持从 GitHub 下载固件和本地文件选择两种固件来源。

### 需求 8：音频控制命令适配

**用户故事：** 作为用户，我希望通过 APP 控制 ESP32 的音量，以便调节扬声器音量。

#### 验收标准

1. THE Protocol_Service SHALL 使用 "VOL:xx\n" 命令格式设置 ESP32 音量（0-100），替代旧的 "AUDIO:VOL:xx\n" 格式。
2. THE Protocol_Service SHALL 使用 "GET:VOL\n" 查询当前音量，解析 "VOL:xx\r\n" 响应。
3. THE APP SHALL 移除 F4 特有的音频命令（AUDIO:PLAY、AUDIO:STOP、AUDIO:PAUSE、AUDIO:RESUME、AUDIO:NEXT、AUDIO:PREV、GET:AUDIO），因为 ESP32 不使用 VS1003 MP3 解码器和 W25Q128 Flash 存储音频文件。
4. THE APP SHALL 保留音量控制功能，并在 WiFi 音频投射模式下实时调节 ESP32 端的混音音量。

### 需求 9：旧协议代码清理

**用户故事：** 作为开发者，我希望清理 APP 中不再使用的旧协议代码，以便降低代码复杂度和维护成本。

#### 验收标准

1. THE APP SHALL 移除 JDY08BluetoothService（jdy08_bluetooth_service.dart）中的二进制协议实现（0xAA...0x55 帧格式），因为 ESP32 仅使用文本协议。
2. THE APP SHALL 移除 BluetoothService（bluetooth_service.dart）中使用占位符 UUID（0xFFF0/0xFFF1/0xFFF2）的旧实现，统一使用 BLE_Service（ble_service.dart）中的 0xFFE0/0xFFE1。
3. THE APP SHALL 移除 PROTOCOL_SPECIFICATION.md 中描述的二进制协议文档，更新为当前文本协议规范。
4. THE APP SHALL 保留 Protocol_Service 中所有当前正在使用的文本协议命令和解析逻辑。

### 需求 10：设备状态同步增强

**用户故事：** 作为用户，我希望 APP 连接设备后能立即获取设备的完整状态，以便界面显示与硬件一致。

#### 验收标准

1. WHEN BLE 连接成功后，THE APP SHALL 自动发送 "GET:ALL\n" 查询设备状态，并用返回的 "STATUS:FAN:x:WUHUA:x:BRIGHT:x\r\n" 更新界面。
2. WHEN BLE 连接成功后，THE APP SHALL 发送 "GET:PRESET\n" 查询当前预设，并用返回的 "PRESET_REPORT:x\r\n" 更新预设选择界面。
3. WHEN BLE 连接成功后，THE APP SHALL 发送 "GET:LOGO_SLOTS\n" 查询 Logo 槽位状态，并用返回的 "LOGO_SLOTS:v0:v1:v2:active\r\n" 更新 Logo 管理界面。
4. WHEN BLE 连接成功后，THE APP SHALL 发送 "GET:VOL\n" 查询当前音量，并用返回的 "VOL:xx\r\n" 更新音量控制界面。
5. WHEN BLE 连接成功后，THE APP SHALL 发送 "GET:STREAMLIGHT\n" 查询流水灯状态，并用返回的 "STREAMLIGHT:x\r\n" 更新流水灯开关状态。

### 需求 11：WiFi 凭据管理

**用户故事：** 作为用户，我希望 APP 能记住 WiFi 密码并在需要时自动发送给 ESP32，以便快速启动音频投射。

#### 验收标准

1. THE APP SHALL 在本地存储（SharedPreferences）中保存用户最近使用的 WiFi SSID 和密码。
2. WHEN 用户在音频投射界面选择已保存的 WiFi 网络时，THE APP SHALL 自动填充密码并发送 "WIFI:ssid:password\n" 给 ESP32。
3. THE APP SHALL 提供清除已保存 WiFi 凭据的选项。
4. WHEN ESP32 已连接 WiFi 并在 MTU 协商后发送 "WIFI_IP:x.x.x.x\r\n" 时，THE APP SHALL 自动更新音频投射界面的连接状态。

### 需求 12：WIFI_SCAN 命令处理

**用户故事：** 作为用户，我希望能扫描可用的 WiFi 网络，以便选择正确的网络进行音频投射。

#### 验收标准

1. WHEN 用户请求 WiFi 扫描时，THE APP SHALL 使用 Android 原生 WifiManager API 扫描附近的 WiFi 网络，而非通过 ESP32 扫描。
2. THE APP SHALL 显示扫描到的 WiFi 网络列表，包含 SSID、信号强度（RSSI）和是否需要密码。
3. WHEN ESP32 返回 "WIFI_SCAN:USE_PHONE\r\n" 时，THE APP SHALL 理解为 ESP32 不执行扫描，由手机端完成。

### 需求 13：错误处理与用户反馈

**用户故事：** 作为用户，我希望在操作失败时看到清晰的错误提示，以便了解问题并采取措施。

#### 验收标准

1. WHEN Logo 上传失败时，THE APP SHALL 根据错误类型显示具体原因：CRC 校验失败、内存不足（LOGO_ERROR:MEM）、槽位无效（LOGO_ERROR:INVALID_SLOT）、大小不匹配（LOGO_ERROR:SIZE_MISMATCH）、写入失败（LOGO_FAIL:WRITE）。
2. WHEN OTA 升级失败时，THE APP SHALL 显示失败原因并告知用户设备将自动回滚到上一版本。
3. WHEN WiFi 连接失败时，THE APP SHALL 显示 "WiFi 连接失败，请检查密码" 提示并允许重试。
4. WHEN BLE 命令超时时，THE APP SHALL 在重试耗尽后显示 "设备响应超时，请检查连接" 提示。
5. THE APP SHALL 在开发者模式下提供 BLE 通信日志查看功能，显示发送和接收的原始命令。

### 需求 14：Logo 上传 E2E 测试界面清理

**用户故事：** 作为开发者，我希望清理测试用的 Logo 上传界面，保留统一的上传入口。

#### 验收标准

1. THE APP SHALL 移除 logo_upload_e2e_test_screen.dart 测试界面，或将其标记为仅在开发者模式下可见。
2. THE APP SHALL 在正式的 Logo 管理界面中集成统一的 Logo 上传功能，提供图片选择、裁剪、预览和上传进度显示。
3. THE APP SHALL 在 Logo 上传前将图片转换为 240×240 RGB565 格式，大小为 115200 字节。

