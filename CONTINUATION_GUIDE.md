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

## 当前阻塞

- **待用户烧录验证** — 已 commit `ea5e12f`，含风扇供电修复 + 颜色调整 + 色条移除
- **⚠️ 风扇/雾化器共用 GPIO 10 供电** — 普通模式调速时 GPIO 10 也会拉高，可能导致雾化器同时工作。待用户确认硬件行为
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
    - 彩色大数字：油门模式下数字颜色随速度渐变（蓝→黄→红），普通模式白色
    - 实现方式：`ui_draw_large_digit_tinted` — 遍历位图像素按亮度着色，~0.2ms/帧
    - 数字下方 4px 彩色进度条作为辅助指示（可能和风速表横线冲突，待实测调整）
    - 模式切换时强制重绘数字（`s_last_throttle_draw` 脏检测）
    - 新增文件改动：`ui_common.c`（tinted digit + tinted number 函数）、`ui_common.h`（声明）
  - **油门模式双击退出**：油门模式下双击 → 停止一切 → 切换到菜单界面
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
ESP32 固件：idf.py build — ✅ 零错误（2026-05-15 验证，3 文件改动后编译通过）
  待烧录验证（esptool 连接失败，用户需按 BOOT 键或检查 COM 口）
Flutter APP：flutter analyze — ✅ 通过（2026-04-30 最后验证，本次未改 APP）
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
