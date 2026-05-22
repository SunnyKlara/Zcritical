---
inclusion: auto
---

<!-- last-verified: 2026-05-12 | source: code comments + FIX records + architecture analysis -->

# 已知坑位清单

> 每个坑位都是真实踩过的。新 AI 在相关领域工作前必须读对应条目。

---

## 硬件/驱动层

### 坑 1：编码器小幅旋转丢失
**现象：** 用户轻转旋钮（1-2 个 PCNT count），UI 无反应
**根因：** PCNT 四倍频给出 4 counts/detent，除以 2 取整步时，不足 2 的余数被丢弃
**解决方案：** `s_last_count += steps * 2`——只消耗映射到整步的 count，保留余数
**验收标准：** 轻转 1 个 detent 必须产生 delta=±1
**代码位置：** `drv_encoder.c` line ~120

### 坑 2：I2S DMA 帧对齐
**现象：** WiFi 音频播放时出现爆音/咔嗒声，左右声道互换
**根因：** TCP recv 返回任意字节数，不是 4 的倍数时 L/R 错位
**解决方案：** TCP 端 `aligned = len & ~3; carry = len - aligned;` 保留尾部字节到下次；Ring buffer 端 `item_size &= ~3u;`
**验收标准：** 连续播放 5 分钟无爆音
**代码位置：** `wifi_audio_service.c` TCP recv loop, `audio_engine.c` ringbuf read

### 坑 3：LCD DMA 缓冲区与 WiFi 争内部 SRAM
**现象：** 启用 WiFi 后 heap 不足，LCD 全屏刷新失败
**根因：** LCD DMA buffer 115KB + WiFi static RX buffers 都需要内部 DMA 内存
**解决方案：** WiFi `static_rx_buf_num = 4`（最小值）；动态缓冲走 PSRAM
**验收标准：** WiFi + BLE + LCD 同时工作，min free heap > 20KB
**代码位置：** `wifi_audio_service.c` wifi_init_config, `drv_lcd.c` s_dma_buf

### 坑 4：引擎声启动爆音
**现象：** 调用 start_engine() 时扬声器"啪"一声
**根因：** I2S DMA buffer 残留上次数据
**解决方案：** 启动前写 4 个静音 buffer 清空 DMA pipeline
**验收标准：** 进入 Speed UI 时无爆音
**代码位置：** `audio_player.c` audio_player_start_engine()

---

## BLE 通信层

### 坑 5：MTU 分片截断命令
**现象：** Logo 上传随机失败，协议解析器报 UNKNOWN_CMD
**根因：** BLE 按 MTU 分片，ESP32 收到不完整片段就解析
**解决方案：** 缓冲到 `\n` 才调用 protocol_parse()
**验收标准：** 任何长度的命令都能正确解析
**代码位置：** `ble_service.c` process_rx_data()

### 坑 6：广播数据不含 Service UUID
**现象：** APP 按 UUID 扫描找不到设备
**根因：** 广播数据只有设备名，没有 UUID
**解决方案：** 广播数据加入 0xFFE0
**验收标准：** UUID 和设备名两种方式都能发现
**代码位置：** `ble_service.c` advertising data

### 坑 7：BLE Notify 拥塞丢包
**现象：** 高频 notify 时 APP 丢包
**根因：** ESP32 notify 队列有限
**解决方案：** 高频上报做节流；关键响应 APP 端超时重试
**验收标准：** 快速操作时 APP 跟随，Logo 上传不卡死
**代码位置：** `ui_speed.c` SPEED_REPORT

---

## 协议层

### 坑 8：APP parseVolume 误匹配 OK:VOL
**现象：** 收到 "OK:VOL:50\r\n" 被错误解析为音量查询响应
**根因：** startsWith("VOL:") 也匹配 "OK:VOL:"
**解决方案：** 排除 "OK:VOL:" 前缀
**代码位置：** `protocol_parser.dart`

### 坑 9：LED_UPDATE 事件无解析器
**现象：** 硬件调 RGB 后 APP 不同步
**根因：** ESP32 发 LED_UPDATE，APP 无对应解析器
**解决方案：** 新增 parseLedUpdate + ledUpdateStream
**代码位置：** `protocol_parser.dart`

---

## 音频系统

### 坑 10：引擎声与 WiFi 音频 I2S 冲突
**现象：** 同时启动两个音频源，输出噪音
**根因：** 两个任务同时写同一个 I2S 通道
**解决方案：** 互斥——start_engine() 先 pause audio_engine
**代码位置：** `audio_player.c`, `audio_engine.c`

### 坑 11：Ring buffer 满时 TCP 阻塞
**现象：** WiFi 音频播放一段时间后卡顿
**根因：** ringbuf 满 → TCP recv 阻塞 → APP send 阻塞
**解决方案：** xRingbufferSend 超时 50ms，超时丢弃
**代码位置：** `audio_engine.c` feed_a2dp_pcm()

### 坑 12：自定义音频必须 4 层齐全
**现象：** 上传 1-3 层后引擎声不变
**根因：** 设计决策——部分层混合音色不连贯
**解决方案：** APP 提示必须上传全部 4 层
**代码位置：** `audio_player.c` load_audio_layers()

---

## UI 层

### 坑 13：UI 切换时编码器 delta 残留
**现象：** 进入子 UI 时第一帧跳格
**根因：** 菜单旋转的 delta 带入新 UI
**解决方案：** set_ui() 中清零 encoder_delta
**代码位置：** `ui_manager.c`

### 坑 14：LCD 局部刷新闪烁
**现象：** 速度数字变化时闪烁
**根因：** fill_rect 清黑 + 画数字之间有一帧全黑
**解决方案：** 只清数字区域，精确匹配 F4 清除范围
**代码位置：** `ui_speed.c` draw_speed_screen()

---

## WiFi/网络

### 坑 15：WiFi 不能开机自动连接
**现象：** 开机自动连 WiFi 后 BLE 不稳定
**根因：** WiFi 扫描/握手占用 RF 时间
**解决方案：** 等 APP BLE 命令触发才连 WiFi
**代码位置：** `wifi_audio_service.c` init 注释

### 坑 16：WiFi Power Save 导致音频断续
**现象：** 播放时周期性断续（~100ms）
**根因：** WiFi 默认 Power Save 周期性休眠
**解决方案：** `esp_wifi_set_ps(WIFI_PS_NONE)` 在 STA_START 后
**代码位置：** `wifi_audio_service.c` event handler

---

## AI 工具使用层（元坑位）

### 坑 17：一次性生成多文件导致接口不一致
**现象：** AI 写 5+ 文件，编译时函数签名不匹配
**根因：** AI 写第 3 个文件时"忘了"第 1 个文件的接口
**解决方案：** 每次最多改 3 个文件，改完编译验证
**验收标准：** 每次提交 `idf.py build` 零错误

### 坑 18：AI 顺从"先这样后面再整理"
**现象：** 临时方案变永久方案
**根因：** AI 默认顺从
**解决方案：** 争议义务——必须指出风险，建议当场做对
**验收标准：** 每次"先这样"都有记录 + 回头整理的时间点

### 坑 19：文档与代码不同步
**现象：** 新 AI 读过时文档，产出冲突代码
**根因：** 改代码没同步文档
**解决方案：** hook 自动提醒
**验收标准：** protocol-contract.md 与代码始终一致
