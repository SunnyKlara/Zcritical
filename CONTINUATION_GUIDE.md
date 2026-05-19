# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-18 -->

> 新对话先读 `.kiro/steering/START-HERE.md`，再读本文件。

## 当前阶段：体验打磨期

软硬件功能全部跑通，逻辑正确，能用。用户实测后判断："产品没经过精雕细作，玩起来很多细节别扭"——
进入打磨阶段，跟 bug 修复是两条并行工作流，不要混。

DeviceConnectScreen 瘦身（~3500 行）暂缓，优先解决体验感受问题。

## 已完成

| 阶段 | 内容 | 验证 |
|------|------|------|
| 1. 固件迁移 | STM32→ESP32-S3 完全重写 | idf.py build 零错误 |
| 2. 菜单 UI | LCD 轮盘菜单 + 滑动动画 | idf.py build 零错误 |
| 3. APP 协议适配 | 14 项需求，17 个任务 | flutter analyze 通过 |
| 4. APP 重构（部分） | 协议层拆分、Provider 重写、DI 引入 | 51 个协议测试通过 |
| 4.5 引擎音效 | 4 层可变采样率合成 | idf.py build 零错误 |
| 5. 自定义音频上传 | BLE 二进制传输 + LittleFS 存储 | idf.py build 零错误 |
| 6. 真实引擎音频素材 | 用户 MP3 → 22050Hz 8-bit PCM 头文件 | idf.py build 零错误 (2.75MB/3MB) |
| 7. 引擎音频重构 | Forza 方案：5 层 44100Hz 16-bit LittleFS+PSRAM | idf.py build 零错误 (22% free) |

## 当前阻塞

- **✅ 音频 Forza 方案已实现** — 5 层 LittleFS+PSRAM，编译通过，待烧录验证
  - PCM 文件随 `idf.py flash` 自动写入 storage 分区（`storage.bin` at 0x620000）
  - smooth_rpm 惯性降到 8-25/tick（~2-4s 从怠速到红线），涡轮迟滞感
  - ⚠️ 首次烧录会覆盖 storage 分区（logo 文件需重新上传）
- **油门模式音频逻辑已改** — 速度=0 静音，0→1 启动，减到 0 停声
- **✅ 油门模式 UI 完成** — commit `2e88004`，彩色数字+色条显示完美
- **待用户烧录验证** — 预设色条修复（draw_color_bar 顺序对齐 preset_colors.h）
- **⚠️ 风扇无法调速（硬件问题确认）** — GPIO 40 PWM 对风扇转速无影响。风扇只受 GPIO 10 开关控制
- **DeviceConnectScreen 仍 ~3500 行** — 暂缓

## 下一步

1. **P0 体验打磨**（新方向）
   - Round A：用户实玩，记 30-50 条体验问题（产出 `POLISH_PLAN.md` 或类似文件）
   - Round B：AI 分类（硬件/APP/同步/视听），标位置和改动量
   - Round C：按"高频 × 低成本"批量改，每批 3-5 条，烧录验证
2. **P1 修真机 bug**（如果 Round A 中混进了 bug 类问题，导出到 DEBUG_PLAN）
3. **P2 DeviceConnectScreen 拆分**
4. **P3 OTA 实现**（main.c 当前返回 NOT_IMPL，上架前必修）
5. **P4 go_router 声明式路由 + 国际化 + CI/CD**

## 本次对话决策

- 2026-05-15（音频素材集成）：
  - 用户提供 4 段真实引擎 MP3 素材（启动加速/刹车/中加速/长加速）
  - 转换工具：`ridewind-esp/tools/convert_engine_audio.py`（miniaudio 解码 + numpy 处理）
  - 素材源文件：`ridewind-esp/main/resources/audio_raw/`（MP3 原始文件）
  - 层映射（待烧录验证后可能调整）：
    - 启动加速.mp3 → engine_idle (800 RPM, 4.48s, 95KB)
    - 刹车.mp3 → engine_low (2000 RPM, 4.48s, 95KB)
    - 中加速.mp3 → engine_mid (4000 RPM, 2.90s, 61KB)
    - 长加速.mp3 → engine_high (7000 RPM, 8.85s, 189KB)
  - 总 flash 占用 442KB（固件 2.75MB/3MB 分区，余 256KB）
  - 编译通过，待烧录验证音效效果
  - 潜在问题：素材是"动态过程"录音而非"稳态循环"，循环播放可能不够自然，烧录后听效果再调

- 2026-05-16：预设颜色 LCD 色条 vs LED 灯珠不匹配修复
  - 根因：`preset_colors.h` 的预设排列顺序和 `draw_color_bar()` 的 case 顺序不一致
  - `draw_color_bar()` 是设计意图（LCD 色条为准），`preset_colors.h` 是旧排列
  - 修复：重排 `preset_colors.h` 对齐 `draw_color_bar()` 的 case 1-14 顺序
  - 同步更新 `RideWind/lib/data/led_presets.dart` 保持 APP 端一致
  - 修改文件：`preset_colors.h`、`led_presets.dart`、`ui_preset.c`（draw_color_bar 恢复原始）
  - 编译通过：idf.py build 零错误

- 2026-05-16：油门模式 LED 灯效系统实现（6 种速度响应效果）
  - 硬件布局确认：Main 6 颗 + Tail 3 颗（Left/Right 4 颗已去掉降成本）
  - 设计决策：效果选择通过 APP 弹窗，硬件端只执行
  - 实现 6 种效果：转速条填充 / 脉冲波 / 追逐流光 / Main↔Tail交替 / 波浪呼吸 / 闪电
  - 所有效果共用速度→颜色映射：蓝(0%) → 黄(50%) → 红(100%)
  - 进入油门模式自动激活，退出自动恢复静态色
  - 默认效果：交替闪烁(mode=4)
  - 协议预留：`THROTTLE_EFFECT:mode` (1-6)，尚未加入 protocol.c
  - 修改文件：`led_effects.h`、`led_effects.c`、`app_state.h`、`app_state.c`、`ui_speed.c`
  - 编译通过：idf.py build 零错误
  - 下一步：1) 烧录验证效果 2) 加入 BLE 协议命令 3) APP 端弹窗 UI

- 2026-05-17：油门灯效 BLE 协议 + APP 弹窗 UI 完成
  - ESP32: `protocol.h` 加 `CMD_THROTTLE_FX`，`protocol.c` 加解析 `THROTTLE_FX:1-6`，`main.c` 加命令处理
  - Flutter: `command_sender.dart` 加 `setThrottleEffect()`，`bluetooth_provider.dart` 暴露方法
  - 新建 `widgets/throttle_effect_selector.dart` — 底部弹窗 6 选项 UI
  - 使用方式：`ThrottleEffectSelector.show(context, currentMode: 4)` 接入任意按钮
  - 编译通过：idf.py build 零错误
  - 待接入：需要把弹窗调用接入到 Color 界面的"涂色"按钮
  - 待验证：flutter analyze（本次未运行）

- 2026-05-17（第二轮）：弹窗接入 Color 界面 + 删除转盘动画
  - `colorize_preset_view.dart`：删除"开始涂色"转盘逻辑，改为点击弹出 `ThrottleEffectSelector`
  - 删除 `_startSpinAnimation()` 方法、`dart:math` import、所有 `isSpinning`/`bounceOffset`/`indicatorOffset` 引用
  - 按钮现在点击直接弹出 6 效果选择底部弹窗
  - ESP32 编译通过：idf.py build 零错误
  - Flutter 待验证：flutter analyze 未运行（需要用户本地验证）

- 2026-05-17（第三轮）：波浪呼吸效果应用到 Speed 界面
  - 设计决策变更：
    - 油门模式下的速度响应灯效暂不使用，只用波浪呼吸
    - 波浪呼吸在整个 Speed 界面（普通+油门模式）持续运行
    - 颜色使用用户在 Color 界面选定的预设色（不随速度变色）
    - 固定 1.5 秒波浪周期（不随速度加快）
  - 修改：
    - `ui_speed.c`：`ui_speed_enter()` 启动波浪，双击退出时停止；油门进入/退出不再单独控制灯效
    - `led_effects.c`：波浪效果改用 `led_colors[]` 预设色，固定周期
    - `app_state.c`：默认模式改为 WAVE(5)
  - 编译通过：idf.py build 零错误
  - 后续方向：优化波浪效果的节奏、幅度、过渡曲线

- 2026-05-17（第四轮）：波浪呼吸效果优化
  - 亮度曲线：三角波 → 余弦二次逼近（丝滑无折角）
  - Gamma 2.0 校正：暗部细节更丰富，符合人眼感知
  - 最低亮度：0% → 15%（灯永远不全灭，保持连续感）
  - 相位间距：42 → 60（波浪有方向感，跑出灯带边缘）
  - 周期：1500ms → 2000ms（更优雅从容）
  - 尾灯：独立呼吸 → 跟随 Main 延迟 300ms（波传播感）
  - 编译通过：idf.py build 零错误
  - 待烧录验证效果

- 2026-05-17（第五轮）：波浪效果对比度修复
  - 问题：gamma 双重压缩 + 最低亮度 15% 导致波浪不明显
  - 修复：最低亮度 38→12 (5%)，去掉 gamma 压缩，余弦直接映射
  - 编译通过：idf.py build 零错误

- 2026-05-17（第六轮）：LED 偶发闪烁修复（RMT DMA）
  - 问题：波浪呼吸过程中偶尔某颗灯珠闪其他颜色
  - 根因：RMT 传输被 BLE/音频中断打断，导致 WS2812 收到错误数据
  - 修复：`drv_led.c` 两个 RMT 配置 `.flags.with_dma = false` → `true`
  - DMA 模式下硬件自动发送，CPU 不参与，不受中断影响
  - 编译通过：idf.py build 零错误
  - 待烧录验证闪烁是否消失

- 2026-05-17（第七轮）：波浪效果完全重写（海浪风格）
  - 核心分歧解决：用户要的是"所有灯同时明暗起伏"，不是"每颗灯不同相位的空间波"
  - 新设计：
    - 所有 Main+Tail 灯同步变化
    - 3500ms 周期（从容）
    - 波谷 3%（极暗但不灭），波峰 100%
    - 波峰停留 700ms，波谷停留 600ms（像浪打到顶悬停再退）
    - ease-in 上升（慢→快），ease-out 下降（快→慢）
  - 编译通过：idf.py build 零错误

- 2026-05-17（第八轮）：DMA 回退 + 闪烁问题待解
  - DMA 模式导致 RMT 通道不足（ESP32-S3 RMT TX 通道有限，两个灯带用 DMA 超出）
  - 回退：`.flags.with_dma = false`（恢复正常启动）
  - LED 偶发闪烁问题暂搁，后续用降低刷新率或提升任务优先级解决
  - 编译通过：idf.py build 零错误

- 2026-05-18：Git 分支整合
  - 问题：10 个分支互不同步，引脚修复在 `fw/treadmill-panel` 但当前在 `fw/wave-wind-sync` 导致丢失
  - 决策：合并所有修改到 main，删除所有旧分支，以后只在 main 上工作
  - 操作：stash → checkout main → pop → commit `3aa72af` → tag `v0.3-unified-main`
  - 删除分支：fw/treadmill-panel, fw/treadmill-ui, fw/wave-effect, fw/wave-experiment, fw/wave-wind-sync, app/colorize-custom-presets, app/reconnect-restore, app/sync-throttle, app/ui-refactor
  - 新工作流：只在 main 上开发，用 tag 标记好的版本点，改坏了用 tag 回退

- 2026-05-17（第十轮）：波浪效果重写 — Pacifica 多层叠加
  - 参考 FastLED Pacifica（Mark Kriegsman 2019）的多层正弦波叠加原理
  - 新实现：2 层正弦波以不同速度/方向移动，叠加后波峰=亮，波谷=暗
  - 层1：左→右 4s 周期，层2：右→左 2.7s 周期
  - 对比度：二次方增强，波谷 3%，波峰 100%
  - 6 颗灯每颗有不同空间相位，形成移动的亮区
  - 尾灯跟随但有时间偏移
  - 分支：`feature/wave-effect-tuning`
  - 编译通过：idf.py build 零错误
  - 待烧录验证

- 2026-05-17（第十一轮）：波浪效果第四版 — 潮汐呼吸+微延迟
  - 放弃多层叠加（6颗灯空间效果不成立）
  - 新方案：整体明暗起伏(3.5s) + 200ms微扫过延迟 + S曲线
  - 编译通过：idf.py build 零错误

- 2026-05-15：方向转向「体验打磨期」
  - 用户实测后判断：功能跑通但"没经过精雕细作"，玩起来很多细节别扭
  - 协作模式确立：用户以产品经理身份提需求，AI 深入理解后从专业角度设计实现。用户说了就是确认，不等二次确认
  - 编译通过，烧录卡在 esptool 连接（用户需按 BOOT 键）
  - 产品结构梳理：
    - 软件 4 面板：跑步机(pace mode) / 风扇(running mode) / 主灯(color mode) / RGB调色(RGB)
    - 硬件 6 界面：Speed / Color / RGB / Bright / Logo / Speed(跑步机)
  - **Speed 界面设计探讨（待确认）**：
    - 开机默认雾化器**开**（之前误改为关，需改回）
    - 按键映射：单击=toggle 普通/油门模式，长按=toggle 雾化器
    - 油门模式：按住加速，松开怠速（像驾驶）
    - ✅ 已确认：油门模式下按住只做加速，长按不切雾化器（油门模式忽略所有事件，用原始 GPIO）
    - ✅ 已确认：油门退出方式 → 旋转编码器退出
  - **按键模式识别重构**（ui_speed.c）：
    - 普通模式：CLICK（短按 <250ms）→ 进入油门模式
    - 普通模式：LONG_PRESS（≥600ms）→ 开/关雾化器（toggle）
    - 普通模式：DOUBLE_CLICK → 切换到菜单界面
    - 油门模式：按住（GPIO 直读）→ 加速；松开 → 减速
    - 油门模式：旋转编码器 → 退出油门模式
    - 油门模式：双击 → 退出油门 + 切换到菜单界面
    - 油门模式：速度降到 0 不退出，保持待命（只有旋转/双击退出）
    - 关键：编码器驱动已有完善的状态机区分 click/long_press，UI 层只需正确响应事件
  - **油门模式视觉区分**（ui_speed.c + ui_common.c）：
    - 预渲染彩色数字贴图（538KB，11 档 × 10 数字），和 Tixing 完全相同的方式
    - 颜色：蓝(0%) → 黄(50%) → 红(100%)，带 gamma 校正保留抗锯齿层次
    - 生成脚本：`tools/gen_colored_digits.py`
    - 色条：140px 宽 × 3px 高，只在油门模式显示，退出时清除
    - 模式切换时强制重绘数字（`s_last_throttle_draw` 脏检测）
    - 新增文件：`resources/colored_digits.c`、`resources/colored_digits.h`、`tools/gen_colored_digits.py`
    - 修改文件：`ui_common.c`、`ui_common.h`、`ui_speed.c`、`CMakeLists.txt`
  - **油门模式双击退出**：油门模式下双击 → 停止一切 → 切换到菜单界面
  - **Git 管理约定**：不自动 commit，只有用户确认"保留这版"时才 commit
  - 两个已改 bug：
    - BUG-A 风扇上电自转：drv_pwm.c 加 GPIO 预拉低（已编译通过）
    - BUG-B 油门长按失效：ui_speed.c 油门 poll 循环只响应 ROTATE（已编译通过）
    - ⚠️ 雾化器默认值需改回 1（用户确认默认开）

- 2026-05-15（第二轮）：烧录实测反馈 — 风扇不转 + 按键模式识别问题
  - **BUG-C 风扇完全不转**：`drv_pwm.c` 中 `gpio_config()` 锁定了 GPIO matrix，LEDC 无法接管
    - 修复：改用 `gpio_reset_pin()` + `gpio_set_direction()` + `gpio_set_level(0)`，让 LEDC 干净接管
  - **BUG-D 油门模式速度降 0 自动退出**：CLICK 事件有 400ms 延迟，进入油门时按钮已松开，120ms 内速度从 10 降到 0 就退出了
    - 修复：`throttle_process()` 中速度降到 0 不再退出油门模式，只停风扇。退出只能通过旋转编码器
  - **按键时序优化**（board_config.h）：
    - `BUTTON_TIMEOUT_MS`：400ms → 250ms（单击确认更快）
    - `LONG_PRESS_MS`：800ms → 600ms（长按响应更快，和单击区分更明显）
  - 改动文件：`drv_pwm.c`、`ui_speed.c`、`board_config.h`
  - **BUG-E 风扇 GPIO 40 被 Octal PSRAM 占用**（发现根因）：
    - `sdkconfig` 中 `CONFIG_SPIRAM_MODE_OCT=y`，Octal PSRAM 占用 GPIO 33-37 + DQS(GPIO 40)
    - LEDC PWM 信号无法路由到 GPIO 40 → 风扇永远不转
    - 开雾化器/进油门时风扇转是因为 GPIO 10 拉高（可能 PCB 上有电气关联）
    - **已排除**：GPIO 40 不被 Octal PSRAM 占用（PSRAM 只用 33-37），GPIO 40 可用
    - **真正原因**：之前加的 `gpio_config()` / `gpio_reset_pin()` 预处理代码干扰了 LEDC 引脚路由
    - **修复**：去掉所有 GPIO 预配置，纯 LEDC 初始化（duty=0 即保证上电不转）
    - 加了 `drv_pwm_set_duty` 调试日志，烧录后可从串口确认 PWM 是否被调用

- 2026-05-12（第三轮）：文档审计 + Git 管理体系建立 + 历史补救提交
  - 审计发现：3400+ 未提交变更，仅 3 个 commit，无分支策略
  - 创建 `guides/git-workflow.md`（auto inclusion）— 分支策略、commit 规范、提交节奏、历史补救方案
  - 补全 .gitignore — 增加 Keil 产物、PlatformIO 产物、Python cache、.vs/
  - 清理文档残留 — 删除 ENGINE_SOUND_REDESIGN.md 空壳、PROTOCOL_SPECIFICATION.md 空壳
  - 修复 README.md 和 RideWind/README.md 中的过时链接 → 指向 steering
  - 执行历史补救：7 个结构化 commit + tag v0.1.0-baseline，工作区干净
  - 移除误提交的 .vs/ 二进制文件和 RideWind.zip
  - 推送状态：后台上传中（~110MB），用户需确认完成

- 2026-05-12（第二轮）：AI 协作操作系统 18 模式全部落地
  - 子系统二完成：协作模式 8-11（探索/手术/脚手架/重构）→ `guides/collaboration-modes.md`
  - 子系统三补完：模式 14（参考项目烂尾分析）→ `knowledge/why-reference-failed.md`
  - 子系统三补完：模式 15（命名统一表）→ `specs/naming-conventions.md`（auto inclusion）
  - 18 模式蓝图元文档 → `steering/AI-COLLAB-OS-BLUEPRINT.md`
  - START-HERE.md 更新索引，新增 4 个文件引用

- 2026-05-12（第一轮）：文档体系大清理，落地子系统一 + 四
  - 创建 `.kiro/steering/` 三层体系（specs/guides/knowledge）
  - 创建 5 个 hooks 把纸面规则变成自动执行机制
  - 删除 f4_26_1.1 两份副本、RideWind/docs/archive/（35文件）、过时规划文档
  - 协议唯一真值源迁移到 steering/specs/protocol-contract.md
  - 引脚唯一真值源确认为 pin_config.h（删除了冗余 .md）
  - CONTINUATION_GUIDE.md 从 400 行精简为纯 session handoff
  - architecture-boundary-guard hook 对所有 write 触发，prompt 中区分代码/非代码文件跳过
  - 深度文档产出：architecture.md（固件全景）、known-pitfalls.md（19 个坑位）

## 编译状态

```
ESP32 固件：idf.py build — ✅ 零错误（2026-05-18 验证，Forza 音频重构 + selftest.c 加入 CMake）
  固件 2.43MB/3MB (22% free)，storage.bin 含 5 层 PCM (2.38MB)
  待烧录验证
Flutter APP：flutter analyze — 待验证（led_presets.dart 顺序重排）
协议测试：flutter test test/protocol/ — ✅ 51/51 通过
```

## 关键文件速查

| 用途 | 文件 |
|------|------|
| 固件入口 | `ridewind-esp/main/main.c` |
| 固件状态 | `ridewind-esp/main/app/app_state.h` |
| 固件协议 | `ridewind-esp/main/services/protocol.c` |
| APP 入口 | `RideWind/lib/main.dart` |
| APP 核心页面 | `RideWind/lib/screens/device_connect_screen.dart` |
| APP 蓝牙状态 | `RideWind/lib/providers/bluetooth_provider.dart` |
| APP 协议解析 | `RideWind/lib/protocol/protocol_parser.dart` |
| APP BLE 底层 | `RideWind/lib/services/ble_service.dart` |

- 2026-05-18：波浪效果v4宽波版确认并合入main
  - 用户确认效果"非常好，非常满意"
  - tag: `wave-v4-wide-confirmed`
  - 已合入 main 主干
  - 最终参数：相位间距25，20fps，底亮15%+潮汐8s(15%↔30%)，峰值100%，周期2.5s
  - 炸灯频率明显降低
  - AI自主执行规则落地（steering/commit-convention.md）
  - 后续可优化：波速微变 / 双发防炸灯 / 全局brightness响应

- 2026-05-18：风速联动波浪效果实验
  - 分支：`fw/wave-wind-sync`（从 main 新建）
  - 4个参数随 current_speed_kmh(0-100) 动态变化：
    - wave_cycle: 2500→1200ms（风大浪快）
    - base_bright: 38→3（风大浪深）
    - phase_step: 25→40（风大波窄）
    - tidal_cycle: 8000→4000ms（潮汐加速）
  - 静止时效果与确认版v4完全一致
  - 提交：`6eb045f`
  - 编译通过(7% free)
  - 回退：`git checkout main` (tag: wave-v4-wide-confirmed)
  - 待烧录验证风速联动效果

- 2026-05-18：风速联动v2 — 加大变化幅度
  - 用户反馈v1联动不明显，参数变化范围太小
  - 加大：周期2500→800ms / 底亮38→0 / 相位25→55 / 潮汐8s→3s
  - 提交：`647f668` on main（amend覆盖了之前的commit）
  - ⚠️ 注意：直接提交到了main而非实验分支（git状态需确认）
  - 编译通过(7% free)
  - 待烧录验证联动效果是否明显

- 2026-05-18（产测自检固件）：
  - 新增产测自检模式：开机时按住编码器按钮（IO8）进入，正常不按则正常启动
  - 新增文件：`app/selftest.h`、`app/selftest.c`
  - 修改文件：`main.c`（app_main 开头加检测入口）、`CMakeLists.txt`（加源文件）
  - 测试 10 项：LCD / LED Main / LED Tail / 编码器旋转 / 编码器按键 / 喇叭 / 风扇 / 雾化器 / BLE(跳过) / PSRAM
  - LCD 显示逐项 PASS/FAIL + 最终 ALL PASS（绿）或 FAIL（红）
  - ALL PASS 后等 3 秒自动 esp_restart() 进入正常主程序；FAIL 则死循环等待排查
  - Speaker 测试后加 drv_audio_stop() 防止残留蜂鸣
  - UART 串口同步输出详细日志
  - 编译通过：`idf.py app` 零错误，分区剩余 22%
  - ⚠️ `idf.py build`（全量含 storage）会报 littlefs-python circular import 错误（Python 3.14 兼容性问题），用 `idf.py app` 或 `idf.py app-flash` 绕过
  - 产测锁（Production Test Lock）：ALL PASS 后写 NVS `selftest.passed=1`，后续开机即使按住按钮也不再进入自检
  - 售后重测：通过 BLE 命令或 nvs_flash_erase 清除标志
  - main.c 调整：NVS init 移到 selftest 检测之前（selftest 需要读 NVS）
  - 使用场景：组装 20 台产品做 QC 验证

- 2026-05-18（软件战略文档）：
  - 新增 `.kiro/steering/SOFTWARE-STRATEGY.md`（manual inclusion）— 50 项总索引表
  - 内容：产品演进 12 维度 + 公司软件版图 16 维度 + 学习路径 + 50 项技术系统清单
  - 定位：练手项目，全方位学习技术栈
  - ✅ 50/50 项全部展开完成（`.kiro/steering/strategy/` 12 个子目录，50 个文件）
  - 目录：01-device(9) / 02-backend(7) / 03-iot-cloud(2) / 04-frontend(5) / 05-devops(7) / 06-data(4) / 07-marketing(3) / 08-content(1) / 09-operation(3) / 10-business(3) / 11-security(1) / 12-community(5)
  - 每项含：架构图、技术栈、实现步骤、坑点表、与 RideWind 关系、工作量估算
  - 总索引：`.kiro/steering/SOFTWARE-STRATEGY.md`

- 2026-05-18（引擎音频 Forza Horizon 重构）：
  - 方案执行：5 层按挡位切分 + LittleFS + PSRAM 运行时加载
  - 新建脚本：`tools/gen_engine_layers_forza.py`（PyAV 解码 AAC → 44100Hz 16-bit mono PCM × 5 层）
  - PCM 输出：Layer 0-4 共 2.38MB（169K/81K/169K/566K/257K samples）
  - `storage.h/c`：层数 4→5，大小上限 256KB→1.2MB，新增 `storage_audio_read_16bit()` API
  - `audio_player.c`：完全重写，去掉头文件数组依赖，开机从 LittleFS→PSRAM 加载
  - smooth_rpm 惯性：80-200/tick → 8-25/tick（~2-4s 加速递进，涡轮迟滞感）
  - `CMakeLists.txt`：加 `selftest.c`（修复预存链接错误），加 `littlefs_create_partition_image`
  - `storage_data/`：5 个 PCM 文件，构建时自动打包为 `storage.bin`
  - 烧录命令：`idf.py flash`（含 `0x620000 build\storage.bin`）
  - ⚠️ 首次烧录覆盖整个 storage 分区（logo 需重新上传）
  - 编译通过：idf.py build 零错误，固件 2.43MB/3MB (22% free)
  - 旧 `engine_layers_16bit.h`（~2MB 头文件数组）不再被引用，固件体积从接近满改善到 22% free
  - 待烧录验证音效
  - 后续调参：smooth_rpm 加速率从 8-25 再降到 4-12/tick（~5-7s 从怠速到红线），用户反馈"0→340太快声音跟不上"

- 2026-05-18（引擎音频架构重构 — RC Engine 方案）：
  - 用户反馈 5 层切片方案效果不理想，根因：从动态加速录音切片无法得到好的稳态循环
  - 决策：抛弃 5 层 RPM 分段架构，改用 TheDIYGuy999/Rc_Engine_Sound_ESP32 的已验证架构
  - 新架构核心：idle 循环 + rev 循环（变速率播放）+ knock 脉冲（固定音高）+ start 一次性音效
  - 素材：LaFerrari V12（TheDIYGuy999 项目 GPL-3.0 开源素材）
    - idle: 7344 samples (166ms loop, 14.3KB)
    - rev: 7324 samples (166ms loop, 14.3KB)
    - knock: 74 samples (1.7ms pulse, 0.1KB)
    - start: 111360 samples (2.5s one-shot, 217.5KB)
    - 总计 246KB，直接编译进固件（不再依赖 LittleFS）
  - 工具脚本：
    - `tools/extract_rc_sounds.py` — 从 TheDIYGuy999 .h 文件提取 8-bit → 16-bit 44100Hz PCM
    - `tools/gen_engine_header.py` — PCM → C 头文件 `resources/engine_sounds.h`
  - `audio_player.c` 完全重写：
    - 变速率播放（定点数步进，RPM 高→播放快→音高升高）
    - idle/rev 交叉淡入淡出（低 RPM 90% idle，高 RPM 100% rev）
    - V12 knock 脉冲（每引擎循环 12 次，固定音高，给"突突突"节奏感）
    - 状态机：OFF → STARTING → RUNNING → STOPPING
    - RPM 惯性：ACC_RATE=3, DEC_RATE=5（每 buffer tick ~5.8ms）
  - `CMakeLists.txt`：移除 `littlefs_create_partition_image`（Python 3.14 不兼容 littlefs-python）
  - 编译通过：idf.py build 零错误，固件 2.69MB/3MB (14% free)
  - 旧 `engine_layers_16bit.h` 和 5 层 PCM 文件不再使用
  - 待烧录验证效果
  - 音量修正（用户反馈"太炸了"）：降低所有增益 + 加输出衰减器 `*6/10`
    - FULL_THROTTLE_VOL 130→100, REV_VOLUME_PCT 120→80, KNOCK_VOLUME_PCT 600→150, START 150→80
    - 编译通过：idf.py build 零错误，固件 2.69MB/3MB (14% free)
  - ⚠️ 第二次烧录反馈"还是不行"——根因：我自己设计的混合逻辑有问题，不是原版
  - 下一步决策（开新对话执行）：
    - 完全照搬参考项目的 variablePlaybackTimer() 混合逻辑
    - 直接用原始 8-bit signed char 素材（已复制到 resources/LaFerrari*_raw.h）
    - 保持参考项目所有音量参数不变（针对 8-bit 范围调好的）
    - 输出时 `(value - 128) << 8` 转 16-bit I2S
    - 不要自己设计，直接复制粘贴参考代码适配 I2S 输出
  - 参考项目已 clone 到 `tools/rc_engine_ref/`（71MB，可删除节省空间）
  - 用户另有下载：`Rc_Engine_Sound_ESP32-9.14.0/`（桌面）

- 2026-05-18：速度0静态 + 有风才起浪
  - 用户反馈：速度为0时不应该有波浪效果
  - 修复：wind==0时直接输出静态预设色，不执行波浪算法
  - 提交：`7b6bb2b` on main
  - 编译通过(22% free)

- 2026-05-18：audio_player.c 从零重写 — 完全照搬参考项目
  - 根因：之前自己设计的 16-bit 混合逻辑效果"太炸了"，不是原版的声音
  - 决策：抛弃所有自定义混合逻辑，100% 照搬 TheDIYGuy999 的 variablePlaybackTimer() + fixedPlaybackTimer()
  - 核心原则：**所有混合在 8-bit signed char 范围内完成**（和参考项目一模一样），最后才转 I2S
  - 搬过来的逻辑：
    - 8-bit 素材直接用（LaFerrariIdle_raw.h / Rev / Knock / Start）
    - idle/rev 交叉淡入（revSwitchPoint=50, idleEndPoint=300, proportion=100%）
    - throttleDependentVolume = map(rpm, 0, 500, 60, 130)
    - throttleDependentRevVolume = map(rpm, 0, 500, 60, 130)
    - throttleDependentKnockVolume = map(rpm, knockStartPoint, 500, 0, 100)
    - rpmDependentKnockVolume = map(rpm, 400, 500, 5, 100)
    - Diesel knock: 600% × throttleDepKnock × rpmDepKnock，V8 气缸模式
    - DAC 混合公式：`(a*8/10 + b7*2/10) * masterVolume/100 + dacOffset`
    - dacOffset 0→128 渐入防爆音
    - 状态机：OFF→STARTING→RUNNING→STOPPING（attenuator 渐弱）
    - RPM 惯性：ACC=2, DEC=1（LaFerrari.h 原值）
    - MAX_RPM_PERCENTAGE=400（音高最高 4 倍）
  - 输出转换：`(mixed_8bit - 128) << 8` → 16-bit signed I2S
  - 变速率实现：定点数 16.16 步进（数学等价于原版改定时器频率）
    - BASE_STEP = FP_ONE/2（22050→44100 上采样）
    - play_step = BASE_STEP * map(rpm, 0, 500, 100, 400) / 100
  - 编译通过：ninja 全量链接 [4/4] ✅ 零错误零警告
  - 待烧录验证效果
  - 如果效果还不对，可能需要检查：
    - dacOffset 渐入速度（当前每 buffer tick +1，约 1.5 秒到 128）
    - RPM 惯性是否太慢（ACC=2 per buffer = ~345 RPM/s）
    - knock 的 b7*2/10 衰减是否太大（原版 DAC2 单独输出，我们合并到一个通道）
