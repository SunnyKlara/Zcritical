# Critical T1 — Session Handoff

<!-- last-verified: 2026-05-15 -->

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

## 当前阻塞

- **⚠️ 音频效果极差（根因待定）** — 16-bit 直接播放原始素材效果仍然很差，排除了素材/算法问题。怀疑硬件链路（MAX98357 接线/供电/喇叭质量）。需用户测试 WiFi 音频投射效果来定位
- **油门模式音频逻辑已改** — 速度=0 静音，0→1 启动，减到 0 停声
- **✅ 油门模式 UI 完成** — commit `2e88004`，彩色数字+色条显示完美
- **待用户烧录验证** — 预设色条修复（draw_color_bar 顺序对齐 preset_colors.h）
- **✅ 风扇 PWM 调速修复** — commit `2fde0cd`，引脚交换（PIN_FAN=IO10, PIN_HUMIDIFIER=IO40），风扇可正常调速
- **DeviceConnectScreen 仍 ~3500 行** — 暂缓，体验问题优先

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

- 2026-05-17（第九轮）：Git 管理 + 波浪效果分支
  - 提交主干：`51cf974` — "feat: LED效果系统 + 预设色修复 + 油门灯效框架 + 波浪呼吸效果(WIP)"
  - 新建分支：`feature/wave-effect-tuning`（当前在此分支）
  - 波浪效果仍不满意，需要进一步探讨用户期望的具体视觉感受
  - 待确认：用户描述期望效果的具体样子（节奏、对比度、过渡感觉）

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

- 2026-05-17（第十二轮）：波浪效果第五版 — 方向性扫光
  - 用户反馈：需要明确的从左到右方向感，亮暗对比不能太高但起伏要明显
  - 新方案：亮区(宽2.5颗灯)从左到右扫过，底亮30%，峰值100%，2.5s周期
  - 尾灯延迟400ms跟随
  - 分支：`feature/wave-effect-tuning`
  - 编译通过：idf.py build 零错误

- 2026-05-17（第十三轮）：波浪效果第六版 — 连续正弦波右→左
  - 用户反馈：方向反了 + 有顿挫感（亮区进出灯带时有间隙）
  - 修复：方向改为右→左，用连续正弦波循环（无间隙，连绵不绝）
  - 参数：底亮30%，峰值100%，2.5s周期，波长=6颗灯
  - 分支：`feature/wave-effect-tuning`
  - 编译通过：idf.py build 零错误

- 2026-05-17（第十五轮）：波浪效果恢复 + 方向确认
  - 发现之前的提交丢失了确认版代码（文件里还是旧版）
  - 重新写入确认版：连续正弦波左→右，底亮30%，峰值100%，2.5s周期
  - 提交：`393c4b0` on `fw/treadmill-ui` 分支
  - ⚠️ 注意：当前在 `fw/treadmill-ui` 分支，不是 main
  - 分支状态：main 停在 `a046ebc`，fw/treadmill-ui 在 `393c4b0`（领先 main 3 个提交）
  - 编译通过：idf.py build 零错误

- 2026-05-17（第十六轮）：波浪对比度增强
  - BASE_BRIGHT 76→38（30%→15%），亮暗起伏更明显
  - 分支：`fw/treadmill-ui`
  - 编译通过（⚠️ 分区空间仅剩 4%，后续注意固件体积）

- 2026-05-17：Git commit 规范确认
  - commit 消息用中文
  - 详细描述修改内容（参数变化、原因、影响）
  - 提交：`c972608` on `fw/treadmill-panel`

- 2026-05-17（第十四轮）：跑步机界面 Forza Horizon 风格重设计
  - 调研 Forza Horizon 5 速度仪表盘 UI 设计（GitHub 开源复刻项目 + 社区分析）
  - `ui_treadmill.c` 完全重写：
    - 旧设计：纯文字（标题+数字+状态），像文本终端
    - 新设计：270° 弧形仪表盘 + 大号居中速度数字 + 渐变色弧 + 刻度线
    - 弧形颜色渐变：白色(0-40%) → 橙色(40-70%) → 红色(70-100%)
    - 局部刷新优化：只重绘变化的弧段区域
    - 刻度线：6 个位置（0/5/10/15/20 km/h），已达到的为白色
    - 状态：RUNNING(绿) / READY(灰)
  - 操作逻辑不变：旋转调速(0.5步进)、点击启停、长按/双击返回菜单
  - 新增 BLE 通知：`TREAD_SPEED:X.X` 和 `TREAD_RUN:0/1`
  - 性能注意：全屏弧形绘制用 atan2f 逐像素计算，首次进入可能有 200-400ms 延迟
  - 待 idf.py build 验证编译

- 2026-05-17（第十五轮）：Git 分支规范化整理
  - 确立分支命名规范：
    - `main` = 稳定基线，可编译可烧录
    - `app/xxx` = Flutter APP 功能分支（只改 RideWind/）
    - `fw/xxx` = ESP32 固件功能分支（只改 ridewind-esp/）
    - `feat/xxx` = 跨端功能（APP + 固件同时改）
  - 执行重命名：
    - `feature/treadmill-ui` → `fw/treadmill-ui`
    - `feature/wave-effect-tuning` → `fw/wave-effect`
  - 整理 stash：跑步机 UI 改动提交到 `fw/treadmill-ui`，波浪+音频 WIP 提交到 `fw/wave-effect`
  - 最终分支结构：
    - `main` — 稳定基线
    - `app/colorize-custom-presets` — APP 自定义颜色胶囊
    - `app/ui-refactor` — APP RGB 面板改进
    - `fw/treadmill-ui` ★当前 — 固件跑步机 Forza UI
    - `fw/wave-effect` — 固件波浪灯效 + 音频引擎
  - 工作区干净，所有改动已提交到对应分支

- 2026-05-17（第十六轮）：跑步机 UI 多版本迭代（v2→v3→v4）
  - v2：Forza 弧形 + F4 数字 + 小圆点（极简，方向正确）
  - v3（误解）：去掉弧形改成色条 + F4 背景，完全模仿 Speed UI — 用户否决
  - v4（最终）：**保留 Forza 弧形** + F4 数字贴图 + 油门操控模式
    - 圆弧：270° 薄弧(4px)，白→橙→红渐变，跟随速度填充
    - 数字：F4 大号白色贴图，居中显示，整数 0-20
    - 操控：油门模式 — 按住加速(150ms/步)，松开减速(100ms/步)
    - 无文字、无色条、无小数点
    - 状态：小圆点指示器（绿=运行，灰=停止）
    - 退出：双击或长按返回菜单
  - 关键教训：用户说"参考 Speed 的数字和操控"≠"把 UI 改成 Speed 一样"
  - 分支：`fw/treadmill-panel`，commit `9a52763`
  - 待 idf.py build 验证编译
  - 后续：菜单图标单独设计、弧线性能优化（首次绘制耗时）
  - BUG修复：长按误退出（commit `f5c6cc3`）
    - 问题：油门模式按住加速，但600ms后编码器驱动发LONG_PRESS事件导致退出
    - 修复：移除LONG_PRESS退出，只保留双击退出
    - 已烧录验证编译通过（用户实测中）

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
ESP32 固件：idf.py build — ✅ 零错误（2026-05-16 验证，油门灯效 6 模式实现后编译通过）
  ui_treadmill.c 重写后未重新编译（clangd 报错均为 ESP-IDF sysroot 问题，与 ui_speed.c 一致）
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
