# 🚗 车库（Garage）大更新 — 系统设计文档

> 版本: v1.0 | 日期: 2026-05-22
> 目标: 将车库从"只读浏览器"升级为"选车即沉浸"的核心体验系统

---

## 一、系统总览

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter App (Garage)                       │
├─────────────────────────────────────────────────────────────┤
│  车辆选择 UI  →  参数映射引擎  →  联动指令发送               │
│  (品牌/搜索/   (CarProfile →    (WebSocket 批量             │
│   收藏/最近)    风/光/声/Logo)    命令序列)                   │
└──────────────────────────┬──────────────────────────────────┘
                           │ WiFi WebSocket (port 81)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    ESP32 (Critical T1)                        │
├─────────────────────────────────────────────────────────────┤
│  protocol.c → cmd_queue → dispatch:                          │
│    • drv_pwm (风扇)                                          │
│    • led_effects (灯效)                                      │
│    • audio_engine (音效)                                     │
│    • ui_logo (LCD Logo)                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、子系统设计

### 2.1 车辆选择 UI

**当前状态**: 已有品牌筛选 + 搜索 + 2列网格 + CarDetailScreen

**升级内容**:

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 收藏系统 | 长按卡片收藏，顶部 ★ 标签快速筛选 | P1 |
| 最近使用 | 记录最近 10 辆"激活"过的车，顶部横向滚动条 | P1 |
| 车型分类标签 | 跑车/SUV/经典车/电动车/赛车 — 基于 engine+class 自动分类 | P2 |
| 选车确认弹窗 | 点击 "SELECT THIS CAR" 后弹出联动预览面板 | P1 |
| 沉浸模式入口 | 选车后进入全屏"驾驶仪表盘"界面 | P2 |

**数据持久化**: SharedPreferences
- `garage_favorites`: List<String> (filename 列表)
- `garage_recent`: List<String> (最近 10 辆，FIFO)
- `garage_active_car`: String? (当前激活车辆 filename)

**车型自动分类算法**:
```dart
enum CarCategory {
  supercar,    // HP >= 600 或 class 含 "S1/S2/X"
  sports,      // HP >= 300 且 weight < 1800kg
  muscle,      // engine == "V8" 且 origin == "United States" 且 year < 1990
  suv,         // layout 含 "AWD" 且 weight > 2000kg
  classic,     // year < 1980
  electric,    // engine == "Electric"
  rally,       // class 含 "Rally" 或 drivetrain == "AWD" 且 aspiration 含 "Turbo"
  general,     // 其他
}
```

---

### 2.2 车辆参数映射系统 (CarProfile)

**核心思想**: 每辆车的 specs 数据 → 映射为一组设备控制参数

```dart
/// 车辆沉浸配置 — 由映射算法从 CarSpecs 生成
class CarImmersionProfile {
  // 风扇
  final int fanSpeed;           // 0-100
  final int suggestedMaxSpeed;  // km/h (用于 RunningMode 上限)
  
  // 灯光
  final int ledPreset;          // 1-14 (推荐预设)
  final Color primaryColor;     // 主色调 (品牌色)
  final int throttleFxMode;     // 1-8 (推荐油门灯效)
  final int brightness;         // 50-100
  
  // 音效
  final EngineProfile engineProfile;  // 引擎音效参数
  final int suggestedVolume;    // 0-100
  
  // Logo
  final String brandLogoAsset;  // 品牌 Logo 资源路径 (如果有)
  final bool autoUploadLogo;    // 是否自动推送 Logo
}

/// 引擎音效配置
class EngineProfile {
  final double idleRpm;         // 怠速转速感 (影响 idle 音高)
  final double revResponse;     // 油门响应灵敏度
  final double exhaustTone;     // 排气音色 (0=低沉, 1=高亢)
  final bool turboWhine;        // 是否有涡轮声
  final bool electricWhine;     // 电动车电机声
}
```

**映射算法**:

```
马力 → 风速档位:
  0-150 HP    → fan 20-35  (微风，经典老爷车)
  150-300 HP  → fan 35-55  (中等，普通跑车)
  300-600 HP  → fan 55-75  (强风，高性能)
  600+ HP     → fan 75-100 (飓风，超跑)

扭矩 → 引擎音色:
  < 200 lb·ft  → exhaustTone 0.8 (高转轻快)
  200-400      → exhaustTone 0.5 (均衡)
  400-600      → exhaustTone 0.3 (低沉浑厚)
  600+         → exhaustTone 0.1 (深沉咆哮)

排量 → 怠速转速感:
  < 2.0L       → idleRpm 900  (高转小排量)
  2.0-4.0L     → idleRpm 750  (标准)
  4.0-6.0L     → idleRpm 650  (大排量低转)
  6.0L+        → idleRpm 550  (超大排量)

进气方式 → 涡轮声:
  "Turbocharged"     → turboWhine = true
  "Supercharged"     → turboWhine = true (不同音色)
  "Naturally Aspirated" → turboWhine = false
  "Electric"         → electricWhine = true

车型类别 → 灯效推荐:
  supercar  → THROTTLE_FX_TACHOMETER (转速条) + 红色系预设
  sports    → THROTTLE_FX_PULSE (脉冲) + 蓝色系预设
  muscle    → THROTTLE_FX_ALTERNATE (交替闪) + 橙色系预设
  classic   → THROTTLE_FX_WAVE (波浪) + 暖白预设
  electric  → THROTTLE_FX_WIND_WAVE (风浪联动) + 蓝绿预设
  suv       → THROTTLE_FX_CHASE (追逐) + 白色预设
  rally     → THROTTLE_FX_LIGHTNING (闪电) + 黄色预设

品牌 → 主色调:
  Ferrari     → #DC0000 (法拉利红)
  Lamborghini → #DAA520 (兰博基尼金)
  BMW         → #0066B1 (宝马蓝)
  Mercedes    → #333333 (奔驰银灰)
  Porsche     → #B12B28 (保时捷红)
  Ford        → #003478 (福特蓝)
  ...
```

**音量联动**:
```
车型类别 → 建议音量:
  supercar  → 80  (声浪是卖点)
  sports    → 70
  muscle    → 85  (V8 咆哮)
  classic   → 50  (温和)
  electric  → 30  (电机声不宜太大)
  suv       → 55
  rally     → 75
```

---

### 2.3 风扇联动界面

**选车后自动设定**:
1. 用户在 CarDetailScreen 点击 "SELECT THIS CAR"
2. 弹出 `ImmersionPreviewSheet` 底部弹窗:
   - 显示推荐风速 (带滑块可微调)
   - 显示推荐灯效 (可切换)
   - 显示推荐音量 (可调)
   - "ACTIVATE" 按钮一键应用全部
3. 激活后发送命令序列:
   ```
   FAN:{mapped_speed}
   PRESET:{preset_index}
   LED_GRADIENT:1:{r}:{g}:{b}:1
   VOL:{volume}
   THROTTLE_FX:{mode}
   ```

**手动微调**: 激活后在 RunningMode 界面，风速滚轮仍可手动调整

---

### 2.4 长按紧急停止 → 调速弹窗

**当前行为**: 长按编码器 → 紧急停止 (fan=0, throttle off)

**升级交互设计**:

```
用户长按紧急停止按钮 (App 端)
  ↓
立即: FAN:0 + THROTTLE:0 (安全第一)
  ↓
0.5s 后: 弹出 SpeedControlSheet
  ├── 当前车辆信息 (缩略图 + 名称)
  ├── 风速滑块 (0-100, 当前=0)
  ├── 快捷按钮: [微风 25%] [中风 50%] [强风 75%] [飓风 100%]
  ├── 恢复按钮: "恢复到车辆推荐值" (回到 CarProfile 的 fanSpeed)
  └── 完全停止确认: "保持停止"
```

**硬件端长按** (编码器):
- 保持现有紧急停止逻辑不变
- App 通过 `speedReportStream` 检测到速度突变为 0 时，自动弹出调速弹窗

---

### 2.5 引擎声联动

**当前状态**: audio_player 有 idle/rev/knock/start 四轨，但参数固定

**升级方案**:

不同车型类别对应不同音效参数组合（通过现有 `audio_engine` 接口控制）:

| 车型 | idle 音量 | rev 响应 | 排气音色 | 特殊音效 |
|------|-----------|----------|----------|----------|
| 超跑 | 高 (80%) | 极快 | 高亢尖锐 | 回火声 |
| 跑车 | 中 (60%) | 快 | 均衡 | — |
| 肌肉车 | 高 (85%) | 中 | 低沉浑厚 | 怠速抖动 |
| 经典车 | 低 (40%) | 慢 | 温和 | — |
| 电动车 | 极低 (20%) | 极快 | 电机声 | 加速嗡鸣 |
| SUV | 中 (50%) | 中 | 中低 | — |
| 拉力 | 高 (70%) | 快 | 中高 | 涡轮泄压 |

**实现路径**:
- Phase 1: App 端通过 `VOL` 命令调整音量 + 现有引擎音效
- Phase 2: 扩展协议，新增 `ENGINE_PROFILE:idle_vol:rev_speed:tone` 命令
- Phase 3: ESP32 端 audio_player 支持参数化音效合成

---

### 2.6 Logo 联动

**当前状态**: LogoManagementScreen 已支持 `initialImageBytes` 参数

**升级方案**:

1. **品牌 Logo 资源库**: 在 `assets/brand_logos/` 预置常见品牌 Logo (240×240 PNG)
2. **选车自动推送流程**:
   ```
   用户选车 → CarImmersionProfile.autoUploadLogo == true
     → 检查 ESP32 当前 Logo 是否已是该品牌
       → 是: 跳过
       → 否: 后台自动上传 (WiFi WebSocket, ~3s)
   ```
3. **Logo 缓存策略**:
   - ESP32 有 3 个 Logo 槽位
   - 槽位 0: 用户自定义 Logo (不自动覆盖)
   - 槽位 1-2: 车库自动推送 (LRU 替换)
   - App 记录 `Map<String, int> brandLogoSlotCache` (品牌→槽位映射)

4. **无品牌 Logo 时**: 使用车辆缩略图作为 Logo (已有 `_setAsLogo` 逻辑)

---

### 2.7 音量联动

**设计原则**: 自动建议，不强制覆盖

```dart
/// 选车时的音量建议逻辑
void suggestVolume(CarImmersionProfile profile) {
  final currentVol = btProvider.currentVolume;
  final suggested = profile.suggestedVolume;
  
  // 如果用户已手动设置了音量，只在差异 > 30% 时提示
  if ((currentVol - suggested).abs() > 30) {
    showVolumeHint("建议音量: $suggested% (${profile.category.name} 风格)");
  }
  
  // 如果当前静音且选了超跑，温和提示
  if (currentVol == 0 && suggested > 50) {
    showVolumeHint("开启声浪体验？推荐 $suggested%");
  }
}
```

---

### 2.8 硬件适配 — 风扇调速

**当前硬件限制**:
- GPIO 40 (PIN_FAN) 的 LEDC PWM 已实现，代码完整
- `drv_pwm.c` 使用 LEDC 10-bit 分辨率，1kHz，非线性曲线
- 实际测试中 GPIO 40 对某些风扇型号无效，仅 GPIO 10 开关控制有效

**解决方案评估**:

| 方案 | 可行性 | 成本 | 推荐 |
|------|--------|------|------|
| A. 换风扇 (支持 PWM 的 4pin 风扇) | ★★★★★ | $5-15 | ✅ 首选 |
| B. 外接 MOSFET 模块 (GPIO→MOSFET→风扇) | ★★★★ | $2-5 | ✅ 备选 |
| C. 换 GPIO (测试其他引脚) | ★★★ | $0 | 先试 |
| D. 软件模拟 (快速开关 GPIO 10) | ★★ | $0 | ❌ 噪音大 |

**推荐路径**:
1. 先测试 GPIO 10 是否支持 LEDC PWM (修改 `pin_config.h` 中 `PIN_FAN`)
2. 如果不行，购买 4-pin PWM 风扇 (Noctua NF-A4x10 PWM 推荐)
3. 如果要保留现有风扇，加 IRLZ44N MOSFET 模块

**软件层面**: `drv_pwm.c` 代码已完整支持 0-100% 调速，无需修改。只需确认硬件连接正确。

---

## 三、协议扩展

### 新增命令 (Phase 2)

```
# 车库激活命令 — 批量设置多个参数
GARAGE_ACTIVATE:fan:preset:volume:throttle_fx
  例: GARAGE_ACTIVATE:65:3:70:1

# 引擎音效配置 (Phase 3)
ENGINE_PROFILE:idle_vol:rev_speed:tone:turbo
  例: ENGINE_PROFILE:80:2:5:1

# 查询当前车库状态
GET:GARAGE
  响应: GARAGE:fan:preset:volume:throttle_fx:logo_slot
```

**Phase 1 (无需协议扩展)**: 使用现有命令序列实现:
```
FAN:65\n
PRESET:3\n
VOL:70\n
THROTTLE_FX:1\n
LOGO_START_BIN:...  (如需推送 Logo)
```

---

## 四、实现优先级

### Phase 1 — 核心联动 (1-2 周)
- [x] 车辆选择 UI 已有 (品牌筛选 + 搜索 + 网格)
- [ ] CarImmersionProfile 映射算法
- [ ] ImmersionPreviewSheet (选车确认弹窗)
- [ ] 联动命令序列发送 (FAN + PRESET + VOL + THROTTLE_FX)
- [ ] 收藏 + 最近使用
- [ ] 长按紧急停止 → 调速弹窗

### Phase 2 — Logo + 灯光深度联动 (1 周)
- [ ] 品牌 Logo 资源库 (Top 30 品牌)
- [ ] 自动 Logo 推送 (槽位管理)
- [ ] 品牌主色调 → LED_GRADIENT 联动
- [ ] 车型分类标签 UI

### Phase 3 — 音效参数化 (2 周)
- [ ] ENGINE_PROFILE 协议扩展
- [ ] ESP32 audio_player 参数化
- [ ] App 端引擎音效预览
- [ ] 音量智能建议

### Phase 4 — 沉浸模式 (1 周)
- [ ] 全屏驾驶仪表盘 UI
- [ ] 实时参数可视化 (风速/转速/灯效状态)
- [ ] 一键切换车辆 (快速切换不退出沉浸模式)

---

## 五、数据流图

```
用户选车 (CarDetailScreen)
    │
    ▼
CarImmersionProfile.fromSpecs(car.specs)
    │
    ├─→ ImmersionPreviewSheet (用户确认/微调)
    │       │
    │       ▼ [ACTIVATE]
    │
    ▼
GarageActivationService.activate(profile)
    │
    ├─→ btProvider.setFanSpeed(profile.fanSpeed)
    ├─→ btProvider.setLEDPreset(profile.ledPreset)
    ├─→ btProvider.setVolume(profile.suggestedVolume)
    ├─→ btProvider.setThrottleEffect(profile.throttleFxMode)
    ├─→ btProvider.setLEDColor(1, r, g, b)  // 品牌色
    ├─→ LogoUploadService.pushBrandLogo(car.brand)  // 异步
    │
    ▼
SharedPreferences 更新:
    ├─→ garage_active_car = car.filename
    ├─→ garage_recent.insert(0, car.filename)
    └─→ 通知 UI 刷新
```

---

## 六、UI 线框图 (文字描述)

### ImmersionPreviewSheet (选车确认弹窗)

```
┌─────────────────────────────────────┐
│  ╭─────────╮                        │
│  │ 车辆图片 │  Ferrari 488 GTB      │
│  │  Hero    │  670 HP | V8 Twin-T   │
│  ╰─────────╯                        │
│                                      │
│  ─── 风速 ──────────────────────     │
│  [====●===========] 72%             │
│  推荐: 72% (超跑模式)               │
│                                      │
│  ─── 灯效 ──────────────────────     │
│  [转速条] [脉冲] [追逐] [●闪电]     │
│  主色调: ■ 法拉利红                  │
│                                      │
│  ─── 音量 ──────────────────────     │
│  [====●=====] 80%                   │
│                                      │
│  ─── Logo ──────────────────────     │
│  [✓] 自动推送 Ferrari Logo           │
│                                      │
│  ┌─────────────────────────────┐    │
│  │      ⚡ ACTIVATE             │    │
│  └─────────────────────────────┘    │
│                                      │
│  [跳过 Logo] [仅风扇] [取消]        │
└─────────────────────────────────────┘
```

### SpeedControlSheet (紧急停止后调速弹窗)

```
┌─────────────────────────────────────┐
│  ⚠️ 风扇已停止                       │
│                                      │
│  当前车辆: Ferrari 488 GTB           │
│  推荐风速: 72%                       │
│                                      │
│  [微风 25%] [中风 50%] [强风 75%]   │
│                                      │
│  [===========●===] 0%               │
│                                      │
│  [恢复推荐值]        [保持停止]      │
└─────────────────────────────────────┘
```

---

## 七、风险与约束

1. **car_specs.json 数据不完整**: ~900 辆车中部分 specs 为空 → 使用默认 "general" 配置
2. **Logo 上传耗时 ~3s**: 选车后 Logo 推送是异步的，不阻塞其他联动
3. **风扇硬件限制**: Phase 1 先用开关控制 (0 或 100%)，硬件修复后自动获得调速
4. **引擎音效参数化**: Phase 1 仅调音量，Phase 3 才做真正的音色变化
5. **ESP32 内存**: 批量命令间需 50ms 间隔，避免 cmd_queue 溢出 (深度 32)

---

## 八、与现有系统的兼容性

- **不修改** `protocol.h/c` (Phase 1 使用现有命令)
- **不修改** `drv_pwm.c` (软件层已完整)
- **不修改** `BluetoothProvider` 公开 API (只新增 service 层)
- **复用** `LogoManagementScreen.initialImageBytes` 接口
- **复用** `RunningModeWidget` 的所有外部流接口
- **新增** `GarageActivationService` (纯 Dart 层，不改硬件)
- **新增** `CarImmersionProfile` 模型
- **修改** `GarageScreen` + `CarDetailScreen` (增加联动入口)
