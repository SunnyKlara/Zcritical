# 实施计划：Flutter APP 适配 ESP32 硬件

## 概述

本计划将设计文档中的架构变更分解为可执行的编码任务，按依赖关系排序。基础层（BLE 服务、协议服务）优先，然后是功能模块（Logo 上传、OTA、音频投射），最后是 UI 适配和清理工作。每个任务都引用具体的需求条款和设计组件。

## 任务

- [x] 1. BLEService 设备类型检测与基础增强
  - [x] 1.1 在 `ble_service.dart` 中添加 `DeviceType` 枚举（esp32, f4, unknown）和 `deviceType` getter
    - 在 `_connectInternal` 中根据设备名自动判断：T1 → esp32，JDY/BT05/HC → f4
    - 连接断开时重置 `_deviceType` 为 unknown
    - _需求: 1.1, 1.4_

  - [x] 1.2 在 `_connectInternal` 中添加重连时重置接收缓冲区的逻辑
    - 确保每次连接/重连前清空 ProtocolService 和 BluetoothProvider 的数据缓冲区
    - _需求: 1.3_

  - [ ]* 1.3 编写 BLE 扫描过滤器属性测试
    - **Property 1: BLE 扫描过滤器正确性**
    - 在 `test/services/ble_scan_filter_test.dart` 中使用 `glados` 生成随机设备名和 UUID 组合
    - 验证 T1、FFE0、JDY/BT05/HC 设备被包含，其他设备被排除
    - **验证: 需求 1.1, 1.4**

- [x] 2. ProtocolService 核心增强 — 命令重试与缓冲区保护
  - [x] 2.1 在 `protocol_service.dart` 中实现 `sendCommandWithRetry` 方法
    - 发送命令后等待指定前缀的响应，3 秒超时自动重发，最多重试 2 次
    - 使用现有的 `_pendingRequests` 机制扩展，支持通用的响应匹配
    - _需求: 1.5, 6.1_

  - [x] 2.2 增强 `_handleReceivedData` 中的接收缓冲区保护
    - 缓冲区超过 512 字节未收到 `\n` 时清空并记录警告日志（当前已实现）
    - 确认 BluetoothProvider 层的 1024 字节缓冲区保护也已就位
    - 验证 `\r\n` 和 `\n` 两种行终止符均能正确分割和解析
    - _需求: 6.4, 6.5, 2.7_

  - [ ]* 2.3 编写命令超时重试属性测试
    - **Property 2: 命令超时重试机制**
    - 在 `test/services/command_retry_test.dart` 中模拟超时和响应场景
    - 验证最多发送 3 次（1 原始 + 2 重试），每次间隔不少于 3 秒
    - **验证: 需求 1.5, 6.1**

  - [ ]* 2.4 编写行终止符等价性属性测试
    - **Property 5: 行终止符等价性**
    - 在 `test/services/line_terminator_test.dart` 中生成随机命令字符串
    - 验证 `\r\n` 和 `\n` 结尾的解析结果完全相同
    - **验证: 需求 2.7**

  - [ ]* 2.5 编写 MTU 分片重组属性测试
    - **Property 10: MTU 分片重组正确性**
    - 在 `test/services/mtu_reassembly_test.dart` 中将命令拆分为随机大小片段
    - 验证依次送入缓冲区后能正确重组并解析
    - **验证: 需求 6.4**

- [x] 3. 检查点 — 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 4. ProtocolService ESP32 新响应格式解析
  - [x] 4.1 在 `protocol_service.dart` 中添加 ESP32 新响应解析方法
    - `parseLogoSlots(String)` — 解析 "LOGO_SLOTS:v0:v1:v2:active\r\n"
    - `parseStreamlightOkResponse(String)` — 解析 "OK:STREAMLIGHT:x\r\n"
    - `parseWifiIp(String)` — 解析 "WIFI_IP:x.x.x.x\r\n"
    - `parseAudioReady(String)` — 解析 "AUDIO_READY:ip:port\r\n"
    - `parseWifiError(String)` — 解析 "WIFI_ERR:reason\r\n"
    - `parseVolumeResponse(String)` — 解析 "VOL:xx\r\n"
    - `parseWifiScanResponse(String)` — 解析 "WIFI_SCAN:USE_PHONE\r\n"
    - 在 `_matchPendingRequest` 和 `_parseProactiveReport` 中集成新解析方法
    - 对未知格式的响应记录警告日志但不影响正常功能
    - _需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

  - [x] 4.2 添加 `LogoSlotStatus` 数据模型
    - 在 `lib/models/` 下创建 `logo_slot_status.dart`
    - 包含 `slot0Valid`, `slot1Valid`, `slot2Valid`, `activeSlot` 字段
    - 实现 `factory LogoSlotStatus.fromProtocol(String response)` 工厂方法
    - _需求: 2.1, 10.3_

  - [ ]* 4.3 编写协议响应解析往返一致性属性测试
    - **Property 3: 协议响应解析往返一致性**
    - 在 `test/services/protocol_parse_roundtrip_test.dart` 中生成随机参数
    - 验证 LOGO_SLOTS、WIFI_IP、VOL 等格式化后再解析得到相同值
    - **验证: 需求 2.1, 2.3, 2.5**

  - [ ]* 4.4 编写未知响应鲁棒性属性测试
    - **Property 4: 未知响应鲁棒性**
    - 在 `test/services/protocol_robustness_test.dart` 中生成随机字符串
    - 验证不抛异常、不损坏状态、后续正常响应仍可解析
    - **验证: 需求 2.6**

- [x] 5. 预设颜色范围扩展（1-12 → 1-14）
  - [x] 5.1 修改 `protocol_service.dart` 中的预设范围校验
    - `setLEDPreset` 方法：将 `index > 12` 改为 `index > 14`
    - `parsePresetReport` 方法：将 `preset <= 12` 改为 `preset <= 14`
    - 更新相关注释中的 "1-12" 为 "1-14"
    - _需求: 3.2, 3.3_

  - [x] 5.2 修改 `color_ring_screen.dart` 中的预设 UI
    - 添加预设 13（Ocean Blue, #0066CC）和预设 14（Warm Amber, #FFBF00）的颜色定义
    - 更新预设选择 UI 以显示全部 14 种预设选项
    - _需求: 3.1, 3.4_

  - [ ]* 5.3 编写预设索引范围验证属性测试
    - **Property 6: 预设索引范围验证**
    - 在 `test/services/preset_range_test.dart` 中生成随机整数
    - 验证 1-14 范围内接受，范围外拒绝
    - **验证: 需求 3.1, 3.2, 3.3**

- [x] 6. 音量命令格式适配
  - [x] 6.1 在 `protocol_service.dart` 中添加设备感知的音量控制方法
    - 添加 `setVolume(int volume)` 方法：ESP32 用 `VOL:xx\n`，F4 用 `AUDIO:VOL:xx\n`
    - 添加 `getVolume()` 方法：发送 `GET:VOL\n`
    - 在 `_matchPendingRequest` 中添加 VOL 响应匹配
    - 在 `_parseProactiveReport` 中添加 VOL 报告解析
    - 需要从 BLEService 获取 `deviceType` 来决定命令格式
    - _需求: 8.1, 8.2_

  - [x] 6.2 在 `bluetooth_provider.dart` 中适配音量控制
    - 添加 `setVolume(int volume)` 方法，委托给 ProtocolService
    - 标记 F4 特有的音频方法为 `@deprecated`：`audioPlay`, `audioStop`, `audioPause`, `audioResume`, `audioNext`, `audioPrev`, `getAudioStatus`
    - 添加音量状态流和 getter
    - _需求: 8.1, 8.3, 8.4_

  - [ ]* 6.3 编写音量命令格式设备适配属性测试
    - **Property 12: 音量命令格式设备适配**
    - 在 `test/services/volume_command_test.dart` 中生成随机音量值和设备类型
    - 验证 ESP32 生成 `VOL:xx\n`，F4 生成 `AUDIO:VOL:xx\n`，范围外拒绝
    - **验证: 需求 8.1**

- [x] 7. 检查点 — 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 8. 设备状态同步增强
  - [x] 8.1 修改 `bluetooth_provider.dart` 中的 `_syncHardwareStateOnReconnect` 方法
    - 连接成功后依次发送：`GET:ALL\n`, `GET:PRESET\n`, `GET:LOGO_SLOTS\n`, `GET:VOL\n`, `GET:STREAMLIGHT\n`
    - 解析各响应并更新对应的 UI 状态
    - 添加 `_logoSlotStatus` 字段和 getter，用于存储 Logo 槽位状态
    - _需求: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [x] 8.2 修改 `_verifyHardwareOnline` 方法
    - 在验证硬件在线后，额外发送 `GET:PRESET\n`, `GET:LOGO_SLOTS\n`, `GET:VOL\n`, `GET:STREAMLIGHT\n`
    - 确保首次连接时也能完成完整状态同步
    - _需求: 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 9. Logo 上传模块统一重构
  - [x] 9.1 重构 `logo_transmission_manager.dart` 为统一 Logo 上传器
    - 重命名类为 `UnifiedLogoUploader`（或保持 `LogoTransmissionManager` 名称但统一接口）
    - 添加 `slot` 参数支持：`LOGO_START:size:crc32\n`（自动分配）或 `LOGO_START:slot:size:crc32\n`（指定槽位）
    - 确保使用 `Crc32.calculate()` 而非内部 `_calculateCRC32` 方法（统一 CRC32 实现）
    - 添加 LOGO_SACK（选择性 ACK）处理：解析 `LOGO_SACK:base:bitmap\r\n`
    - 确保 ACK 超时重传最多 10 次（当前已实现）
    - 添加 LOGO_END 后等待 `LOGO_OK:slot\r\n` 或 `LOGO_FAIL:reason\r\n`，超时 10 秒
    - 确保进度回调、状态回调、错误回调接口完整
    - _需求: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7_

  - [x] 9.2 删除旧的 Logo 上传实现
    - 删除 `lib/services/simple_logo_uploader.dart`
    - 删除 `lib/services/reliable_logo_uploader.dart`
    - 更新所有引用这两个文件的代码，改为使用统一的 LogoTransmissionManager
    - _需求: 4.1_

  - [ ]* 9.3 编写滑动窗口不变量属性测试
    - **Property 7: 滑动窗口不变量**
    - 在 `test/services/sliding_window_invariant_test.dart` 中生成随机 ACK/超时事件序列
    - 验证 `sendBase ≤ nextSeqNum ≤ sendBase + windowSize` 且 `sendBase ≤ totalPackets`
    - **验证: 需求 4.2**

  - [ ]* 9.4 编写 CRC32 算法一致性属性测试
    - **Property 8: CRC32 算法一致性**
    - 在 `test/utils/crc32_consistency_test.dart` 中生成随机字节数组
    - 验证 `Crc32.calculate()` 与已知测试向量一致，且与 LogoTransmissionManager 内部实现一致
    - **验证: 需求 4.4**

  - [ ]* 9.5 编写上传进度单调性属性测试
    - **Property 9: 上传进度单调性**
    - 在 `test/services/progress_monotonicity_test.dart` 中生成随机 ACK 事件序列
    - 验证进度值在 [0.0, 1.0] 范围内、单调非递减、完成时为 1.0
    - **验证: 需求 4.7**

  - [ ]* 9.6 编写十六进制编码往返一致性属性测试
    - **Property 11: 十六进制编码往返一致性**
    - 在 `test/utils/hex_roundtrip_test.dart` 中生成随机字节数组（1-16 字节）
    - 验证编码为十六进制后再解码得到相同数据
    - **验证: 需求 7.2**

- [x] 10. 检查点 — 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 11. OTA 固件升级适配
  - [x] 11.1 修改 `ota_upload_service.dart` 中的固件大小限制和命令格式
    - 将 `maxFirmwareSize` 从 `960 * 1024` 改为 `2560 * 1024`（2.5MB）
    - 确保 `OTA_START` 命令格式为 `OTA_START:size:crc32\n`（当前已包含 CRC32）
    - 更新 `pickLocalFirmware` 中的错误提示为 "最大支持 2.5MB"
    - 添加 BLE 断连时中止升级并通知用户 ESP32 将自动回滚的逻辑
    - _需求: 7.1, 7.4, 7.5_

  - [x] 11.2 确保 OTA 支持 GitHub 下载和本地文件选择两种固件来源
    - 验证 `downloadRemoteFirmware` 和 `pickLocalFirmware` 两个方法均可用
    - 更新 `ota_upgrade_screen.dart` 中的固件大小提示
    - _需求: 7.6_

- [x] 12. WiFi 音频投射功能完善
  - [x] 12.1 在 `audio_stream_service.dart` 中添加 WiFi 凭据管理
    - 添加 `saveWifiCredentials(String ssid, String password)` — 保存到 SharedPreferences
    - 添加 `loadWifiCredentials()` — 加载已保存的凭据
    - 添加 `clearWifiCredentials()` — 清除已保存的凭据
    - _需求: 11.1, 11.2, 11.3_

  - [x] 12.2 在 `bluetooth_provider.dart` 中集成 WiFi 音频投射流程
    - 添加 `sendWifiCredentials(String ssid, String password)` 方法：发送 `WIFI:ssid:password\n`
    - 监听 `WIFI_IP:x.x.x.x` 响应，更新 ESP32 IP 地址状态
    - 监听 `WIFI_ERR:reason` 响应，触发错误回调
    - 监听 `AUDIO_READY:ip:port` 响应
    - 添加 `_esp32IpAddress` 字段和 getter
    - _需求: 5.1, 5.2, 5.4, 11.4_

  - [x] 12.3 修改 `audio_stream_screen.dart` 音频投射界面
    - 添加 WiFi 扫描功能（调用 `AudioStreamService.scanWifi()`）
    - 显示 WiFi 网络列表（SSID、信号强度、是否需要密码）
    - 添加密码输入框和连接按钮
    - 已保存的 WiFi 自动填充密码
    - 添加投射状态指示器和停止投射按钮
    - 仅在 Android 10+ 启用，低版本显示不支持提示
    - 处理 `WIFI_SCAN:USE_PHONE\r\n` 响应
    - _需求: 5.3, 5.5, 5.6, 5.7, 12.1, 12.2, 12.3_

  - [ ]* 12.4 编写 WiFi 凭据存储往返一致性属性测试
    - **Property 13: WiFi 凭据存储往返一致性**
    - 在 `test/services/wifi_credentials_test.dart` 中生成随机 SSID 和密码
    - 使用 `SharedPreferences.setMockInitialValues({})` mock 存储
    - 验证保存后加载得到相同值
    - **验证: 需求 11.1**

- [x] 13. 错误处理与用户反馈
  - [x] 13.1 在 `bluetooth_provider.dart` 和相关 UI 中添加错误消息映射
    - Logo 上传错误：`LOGO_ERROR:MEM` → "设备内存不足"，`LOGO_ERROR:INVALID_SLOT` → "Logo 槽位无效"，`LOGO_ERROR:SIZE_MISMATCH` → "图片大小不匹配"，`LOGO_FAIL:CRC` → "数据校验失败，请重试"，`LOGO_FAIL:WRITE` → "写入失败，请重试"
    - OTA 升级错误：显示失败原因并告知用户设备将自动回滚
    - WiFi 连接错误：显示 "WiFi 连接失败，请检查密码" 并允许重试
    - BLE 命令超时：重试耗尽后显示 "设备响应超时，请检查连接"
    - _需求: 13.1, 13.2, 13.3, 13.4_

  - [x] 13.2 在开发者模式下添加 BLE 通信日志查看功能
    - 在 `dev_test_screen.dart` 或新建调试界面中显示发送和接收的原始命令
    - 利用现有的 `rawDataStream` 实现
    - _需求: 13.5_

- [x] 14. 检查点 — 确保所有测试通过
  - 确保所有测试通过，如有问题请询问用户。

- [x] 15. 旧协议代码清理
  - [x] 15.1 删除旧的蓝牙服务实现文件
    - 如果存在 `jdy08_bluetooth_service.dart`，删除该文件
    - 如果存在 `bluetooth_service.dart`（使用 0xFFF0/0xFFF1/0xFFF2 UUID 的旧实现），删除该文件
    - 更新所有引用这些文件的 import 语句
    - _需求: 9.1, 9.2_

  - [x] 15.2 清理 ProtocolService 中的 F4 特有音频命令
    - 移除或标记为 `@deprecated`：`audioPlay`, `audioStop`, `audioPause`, `audioResume`, `audioNext`, `audioPrev`, `getAudioStatus`, `parseAudioStatus`
    - 保留所有当前正在使用的文本协议命令和解析逻辑
    - _需求: 8.3, 9.4_

  - [x] 15.3 更新或移除旧协议文档
    - 如果存在 `PROTOCOL_SPECIFICATION.md` 中的二进制协议描述，更新为当前文本协议规范
    - _需求: 9.3_

- [x] 16. Logo 上传界面整合与图片转换
  - [x] 16.1 清理 `logo_upload_e2e_test_screen.dart`
    - 将该测试界面标记为仅在开发者模式下可见（通过路由守卫或条件渲染）
    - _需求: 14.1_

  - [x] 16.2 在正式 Logo 管理界面中集成统一上传功能
    - 提供图片选择、裁剪预览功能
    - 上传前将图片转换为 240×240 RGB565 格式（115200 字节）
    - 显示上传进度条
    - 使用统一的 LogoTransmissionManager 执行上传
    - _需求: 14.2, 14.3_

  - [ ]* 16.3 编写 Logo 图片转换输出尺寸属性测试
    - **Property 14: Logo 图片转换输出尺寸**
    - 在 `test/services/image_conversion_test.dart` 中生成随机尺寸图片数据
    - 验证经过 240×240 裁剪/缩放和 RGB565 编码后输出恒等于 115200 字节
    - **验证: 需求 14.3**

- [x] 17. 最终检查点 — 全部测试通过
  - 确保所有测试通过，如有问题请询问用户。
  - 验证所有 14 项需求均已覆盖。

## 备注

- 标记 `*` 的任务为可选测试任务，可跳过以加快 MVP 进度
- 每个任务引用了具体的需求条款，确保可追溯性
- 检查点任务确保增量验证，避免问题累积
- 属性测试验证设计文档中定义的正确性属性
- 单元测试验证具体示例和边界条件
- 实施顺序：基础层（BLE/协议）→ 功能模块（Logo/OTA/音频）→ UI 适配 → 清理
