---
inclusion: auto
---

# 专业开发方法论 — Zcritical T1 项目适配版

> 本文档定义了本项目的开发思维框架和工作方法。
> 不是理论教材，是基于项目实际代码和痛点总结的实操指南。

## 核心原则：每一层只回答一个问题

```
┌─────────────────────────────────────────────────────────────┐
│                        用户的手                              │
└─────────────────────┬───────────────────────────────────────┘
                      │ 触摸/滑动
┌─────────────────────▼───────────────────────────────────────┐
│                    Flutter APP                               │
│                                                             │
│  Screen (看到什么)                                           │
│     ↓ 调用                                                  │
│  Provider (记住什么、通知谁)                                  │
│     ↓ 调用                                                  │
│  Protocol Layer (怎么编码命令、怎么解析响应)                   │
│     ↓ 调用                                                  │
│  BLE Service (怎么收发字节)                                   │
└─────────────────────┬───────────────────────────────────────┘
                      │ BLE 字节流
┌─────────────────────▼───────────────────────────────────────┐
│                    ESP32 固件                                │
│                                                             │
│  Protocol (听懂命令)                                         │
│     ↓                                                       │
│  App Logic (做什么决定)                                       │
│     ↓                                                       │
│  Drivers (怎么动硬件)                                        │
└─────────────────────────────────────────────────────────────┘
```

| 层 | 回答的问题 | 不该知道的事 |
|----|-----------|-------------|
| Screen | 用户看到什么？能做什么操作？ | BLE 命令格式、字节编码 |
| Provider | 当前状态是什么？变了通知谁？ | UI 长什么样、用了什么 Widget |
| Protocol | 这串字节什么意思？命令怎么编码？ | 业务逻辑、为什么要发这个命令 |
| BLE Service | 怎么和设备收发数据？ | 数据内容代表什么 |
| 固件 Protocol | 收到的字符串是什么命令？ | 为什么要执行这个命令 |
| 固件 App Logic | 收到命令后做什么决定？ | 硬件寄存器地址 |
| 固件 Drivers | 怎么控制这个外设？ | 为什么要输出这个 PWM |

**判断标准：如果你在某一层的代码里看到了"不该知道的事"，那就是架构违规。**

## 开发节奏：写代码前的 10 分钟

### 拿到需求后的思考清单

每次要加功能或修 bug，先在脑子里（或纸上）回答这 5 个问题：

```
1. 这个改动涉及哪些层？
   □ 只有 UI（换个颜色、调个布局）
   □ UI + 业务逻辑（新功能需要新状态）
   □ 全栈（需要新协议命令 + 固件支持）

2. 每一层要改什么？（一句话描述）
   - Screen: ___
   - Provider: ___
   - Protocol: ___
   - 固件: ___

3. 改完之后，怎么验证是对的？
   - 能写测试吗？写什么测试？
   - 不能写测试的话，怎么手动验证？

4. 如果以后要改这个功能，需要动几个文件？
   - 答案应该是 1-3 个。如果超过 5 个，说明耦合太紧。

5. 这个改动会不会破坏已有功能？
   - 协议格式变了吗？（如果变了，旧固件还能用吗？）
   - 公开 API 签名变了吗？（如果变了，其他 screen 要改吗？）
```

### 实际例子：加一个"风力区间控制"功能

**错误做法（你以前的方式）：**
1. 想到要加风力控制
2. 打开 garage_control_sheet.dart
3. 加一个 RangeSlider
4. 在 onChanged 里直接发 BLE 命令
5. 发现需要新协议命令，去固件加
6. 发现 UI 要显示当前值，加个 setState
7. 发现要持久化，加个 SharedPreferences 调用
8. 文件从 600 行变成 900 行

**正确做法：**
1. 回答 5 个问题：
   - 涉及：UI + Protocol + 固件
   - Screen: 加 RangeSlider 显示风力区间
   - Provider: 暴露 fanMin/fanMax getter + setFanRange() 方法
   - Protocol: 新命令 `FAN_RANGE:min,max`
   - 固件: 解析命令 → 存 NVS → 映射到 PWM
2. 先写协议（protocol.h 加枚举，protocol.c 加解析）
3. 再写 Provider 方法（组装命令，调用 CommandSender）
4. 最后写 UI（RangeSlider 调用 Provider 方法）
5. 每一步独立可验证

## 文件管理：300 行规则

### 为什么是 300 行

- 一屏能看完的代码量大约 40-50 行
- 一个人能同时记住的上下文大约 200-300 行
- 超过 300 行，你开始需要上下滚动来理解代码
- 超过 500 行，你开始忘记文件开头写了什么

### 什么时候拆

写完一个功能后问自己：
- 这个文件里有几个"主题"？（如果超过 2 个，拆）
- 有没有一段代码可以独立理解、独立测试？（如果有，拆出去）
- 如果我要改其中一个功能，需要读完整个文件吗？（如果是，拆）

### 怎么拆

```
拆之前：running_mode_widget.dart (1560 行)
  - 布局配置 (120行)
  - 油门加速逻辑 (200行)
  - 外部流订阅 (150行)
  - 滚轮 UI (100行)
  - 刻度渲染 (120行)
  - 调试面板 (80行)
  - 引导演示 (80行)

拆之后：
  running_mode/
  ├── running_mode_widget.dart    (主组件，组装各部分，~200行)
  ├── running_mode_config.dart    (布局配置类，~120行)
  ├── throttle_controller.dart    (加速/减速逻辑，~200行)
  ├── speed_wheel.dart            (滚轮+刻度 UI，~220行)
  └── debug_panel.dart            (调试面板，~80行)
```

**拆分的黄金法则：拆完之后，每个文件的文件名就能告诉你它做什么。**

## 命名即文档

### 好命名 vs 坏命名

| 坏 | 好 | 为什么 |
|----|-----|--------|
| `_accelerate()` | `_incrementSpeedByStep()` | 说清楚做了什么操作 |
| `_isAccelerating` | `_isThrottleActive` | 说清楚是什么状态 |
| `_handleData()` | `_parseSpeedReport()` | 说清楚处理的是什么数据 |
| `_update()` | `_syncWheelToCurrentSpeed()` | 说清楚更新的是什么 |
| `config` | `layoutConfig` 或 `bleConfig` | 说清楚是哪种配置 |
| `data` | `firmwareBytes` 或 `colorPreset` | 说清楚是什么数据 |

### 命名的检验标准

> 如果你需要写注释来解释一个变量/方法的用途，说明名字取得不够好。

```dart
// ❌ 需要注释才能理解
int _count = 0; // 加速次数计数器（用于震动节奏）

// ✅ 名字自解释
int _accelerationStepCount = 0;
```

## 提交纪律

### 一个 commit 只做一件事

```
❌ 错误：
  "修复BLE连接 + 加了车库功能 + 调了UI颜色"

✅ 正确：
  commit 1: "fix: BLE reconnection after background resume"
  commit 2: "feat: garage speed/fan range control"  
  commit 3: "style: adjust color scheme on device list"
```

### Commit Message 格式

```
<type>: <一句话描述改了什么>

type 选项：
  feat:     新功能
  fix:      修 bug
  refactor: 重构（不改功能）
  style:    UI/样式调整
  chore:    构建/配置/工具
  docs:     文档
  test:     测试
```

### 提交前检查清单

```
□ flutter analyze 零 error
□ 改动只涉及一个功能/一个 bug
□ 没有不小心改了不相关的文件
□ 没有提交调试代码（debugPrint、临时 Container 背景色）
□ commit message 三个月后还能看懂
```

## 状态管理的唯一规则

**Widget 不持有来自设备的状态。**

```dart
// ❌ 错误：Widget 自己记住连接状态
class _MyScreenState extends State<MyScreen> {
  bool _isConnected = false;  // 这是从 BLE 来的状态，不该在这里
  
  void _onConnectionChanged(bool connected) {
    setState(() => _isConnected = connected);  // 手动同步 = bug 温床
  }
}

// ✅ 正确：从 Provider 读取
class _MyScreenState extends State<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final bt = context.watch<BluetoothProvider>();
    // bt.isConnected 是唯一真值源
    return Text(bt.isConnected ? '已连接' : '未连接');
  }
}
```

**什么状态可以放在 Widget 本地：**
- 动画控制器（AnimationController）
- 滚动位置（ScrollController）
- 表单输入（TextEditingController）
- 临时 UI 状态（弹窗是否显示、Tab 选中索引）

**什么状态必须放在 Provider：**
- 来自设备的数据（速度、温度、连接状态）
- 跨页面共享的数据（当前设备、用户偏好）
- 需要持久化的数据（上次连接的设备）

## 协议设计的铁律

### 向后兼容

```
已发布的命令格式永远不能改。只能加新命令。

❌ 错误：把 SPEED:120 改成 SPEED:120:kmh
✅ 正确：新增 SPEED_EX:120:kmh，旧命令保持不变
```

### 未知命令处理

```
固件收到不认识的命令 → 回复 ERR:UNKNOWN_CMD:原始命令
APP 收到不认识的响应 → 忽略，不崩溃
```

### 新功能的协议设计流程

```
1. 在 protocol.h 定义新枚举
2. 在 protocol.c 写解析逻辑
3. 在 board_config.h 加 capability bit
4. 在 main.c 加 handler
5. APP 端通过 capability 判断固件是否支持，不支持就不发
```

## 加新功能的完整流程（标准化）

```
第 1 步：想清楚（10 分钟）
  - 回答 5 个问题
  - 画出数据流向（哪里产生 → 哪里消费）

第 2 步：协议先行（如果需要新命令）
  - 固件：protocol.h 加枚举 + protocol.c 加解析 + main.c 加 handler
  - APP：CommandSender 加发送方法 + ResponseRouter 加解析

第 3 步：业务逻辑
  - Provider 加状态字段 + 方法
  - 或者 Controller 加逻辑

第 4 步：UI
  - Screen/Widget 调用 Provider 方法
  - 通过 Consumer/Selector 监听状态变化

第 5 步：验证
  - flutter analyze 零 error
  - 手动测试核心路径
  - 协议测试通过

第 6 步：提交
  - 一个功能一个 commit
  - 写清楚 commit message
```

## 修 Bug 的标准流程

```
第 1 步：复现
  - 明确复现步骤（哪个页面、什么操作、什么设备）
  - 如果不能稳定复现，加日志先观察

第 2 步：定位
  - 问题出在哪一层？
    - UI 显示错误 → Screen/Widget
    - 状态不对 → Provider
    - 命令没发出去 → Protocol/CommandSender
    - 设备没响应 → 固件
    - 连接断了 → BLE Service

第 3 步：修复
  - 只改出问题的那一层
  - 如果需要跨层改，每层单独验证

第 4 步：防回归
  - 能写测试就写测试
  - 不能写测试就在 commit message 里记录复现步骤

第 5 步：提交
  - fix: 一句话描述修了什么
  - 关联 issue（如果有）
```

## 什么时候该停下来重构

出现以下信号时，停下来花 30 分钟重构：

1. **改一个功能要动 5+ 个文件** → 耦合太紧，需要抽接口
2. **同一段逻辑出现在 3+ 个地方** → 需要提取公共方法
3. **文件超过 400 行** → 需要拆分
4. **加一个 if/else 来处理"特殊情况"** → 可能需要重新设计数据流
5. **写注释解释"为什么这样做"** → 代码结构可能有问题
6. **害怕改某个文件** → 说明它太复杂了，需要简化

## 本项目的具体约束

- **协议不可破坏**：已发布的命令格式是契约
- **一个版本一件事**：不在同一个版本里做多个不相关的改动
- **固件是真值源**：capability bitmap 由固件决定，APP 只是读取和适配
- **BluetoothProvider 是状态中枢**：所有设备数据通过它流向 UI
- **GetIt 是依赖容器**：service 的创建和组装在 service_locator.dart 里完成
