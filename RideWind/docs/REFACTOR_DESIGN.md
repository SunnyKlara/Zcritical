# DeviceConnectScreen 重构设计方案

## 现状分析

**文件**: `lib/screens/device_connect_screen.dart` — 2072 行

### 当前职责（过多）

| 职责 | 行数估算 | 说明 |
|------|----------|------|
| BLE 连接生命周期 | ~150 行 | 连接监听、断开去抖、重连、后台释放 |
| 应用生命周期 | ~50 行 | 前后台切换、后台断开计时器 |
| Running Mode 逻辑 | ~100 行 | 速度控制、油门模式、紧急停止 |
| Colorize Mode 逻辑 | ~80 行 | 预设切换、PageView 控制、硬件同步 |
| 硬件 UI 同步 | ~60 行 | UI 模式切换命令发送 |
| 用户偏好存储/恢复 | ~100 行 | 设备特定设置、全局偏好、自定义 RGB |
| 功能引导系统 | ~200 行 | Running/Colorize 引导、GlobalKey 管理 |
| 菜单/对话框 | ~300 行 | 设备菜单、WiFi 配网、Logo、OTA 入口 |
| 雾化器控制 | ~30 行 | 开关状态、指示器 |
| UI 构建 | ~400 行 | build、背景图、模式切换 PageView |
| WiFi 配网对话框 | ~350 行 | 完整的 StatefulWidget（已内联） |
| 断开/重连对话框 | ~150 行 | 两个对话框 |

### 状态变量清单（28 个）

```
_currentModeIndex, _modePageController          → 模式切换
_isAirflowStarted, _airflowController           → 雾化器
_currentSpeed, _maxSpeed, _lastCommandTime       → Running
_lastSentHardwareUI                              → 硬件同步
_colorPageController, _colorPageViewKey          → Colorize PageView
_featureGuideService, _guideOverlayEntry         → 引导
_hasCheckedRunningModeGuide/Colorize             → 引导
_carImageKey, _lowerHalfKey, ... (8个 GlobalKey) → 引导
_runningModeKeys, _runningModeStateKey           → Running Widget
_preferenceService                               → 偏好
_colorize (ColorizeController)                   → Colorize 状态
_connectionSub, _presetReportSub, _streamlightReportSub → BLE 订阅
_navigatedOnDisconnect, _disconnectedByBackground → 断开状态
_disconnectDebounceTimer                         → 去抖
```

### 已经做过的提取

- `RunningModeWidget` — 速度滚轮 UI（但回调仍在 Screen 里处理）
- `ColorizeController` — Colorize 状态管理（通过 get_it 注入）
- `ColorizePresetView` — 预设面板 UI
- `ColorizeRGBDetailView` — RGB 调色面板 UI
- `AirflowIndicatorController` — 雾化器指示器

---

## 重构目标

1. **Screen 只做 UI 编排**（< 300 行）：组合子 Widget，不持有业务逻辑
2. **每个模式独立可测试**：改 Running 不碰 Colorize
3. **BLE 连接管理独立**：不散落在 Screen 的 initState/dispose 里
4. **新功能有明确的放置位置**：不用在 2000 行里找插入点

---

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│  DeviceConnectScreen (< 300 行)                          │
│  - 纯 UI 编排：Stack + PageView                          │
│  - 监听 DeviceSessionController 状态变化                  │
│  - 不直接操作 BLE/偏好/引导                               │
└────────────────────────┬────────────────────────────────┘
                         │ 依赖注入 (get_it)
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
┌─────────────┐  ┌──────────────┐  ┌──────────────┐
│ DeviceSession│  │ ColorizeCtrl │  │ GuideService │
│ Controller   │  │ (已有)       │  │ (已有)       │
│              │  └──────────────┘  └──────────────┘
│ - BLE 连接   │
│ - 模式切换   │
│ - 速度/雾化  │
│ - 偏好存储   │
│ - 硬件UI同步 │
└─────────────┘
```

### 核心：DeviceSessionController

一个 `ChangeNotifier`，持有所有与当前设备会话相关的状态：

```dart
class DeviceSessionController extends ChangeNotifier {
  // 注入
  final BluetoothProvider _bt;
  final PreferenceService _prefs;
  final DeviceModel device;

  // 连接状态
  bool isConnected = true;
  bool disconnectedByBackground = false;
  ConnectionEvent? lastEvent; // connected / disconnected / reconnecting

  // Running Mode
  int currentSpeed = 0;
  int maxSpeed = 340;

  // 模式
  ControlMode currentMode = ControlMode.running;

  // 雾化器
  bool isAirflowOn = false;

  // 硬件 UI 同步
  int lastSentHardwareUI = -1;

  // 方法
  Future<void> setSpeed(int speed) { ... }
  Future<void> toggleAirflow() { ... }
  Future<void> switchMode(ControlMode mode) { ... }
  Future<void> emergencyStop() { ... }
  Future<void> saveSettings() { ... }
  Future<void> restoreSettings() { ... }

  // 生命周期
  void onAppPaused() { ... }
  void onAppResumed() { ... }
  void dispose() { ... }
}
```

### 文件结构（重构后）

```
lib/
├── controllers/
│   ├── device_session_controller.dart   ← 新建（~300 行）
│   ├── colorize_controller.dart         ← 已有
│   └── airflow_indicator_controller.dart ← 已有
├── screens/
│   ├── device_connect_screen.dart       ← 瘦身到 ~250 行
│   └── dialogs/
│       ├── disconnect_dialog.dart       ← 提取（~80 行）
│       ├── device_menu_sheet.dart       ← 提取（~150 行）
│       └── wifi_provisioning_dialog.dart ← 提取（~350 行，已内联）
├── widgets/
│   ├── running_mode_widget.dart         ← 已有
│   ├── colorize_preset_view.dart        ← 已有
│   ├── colorize_rgb_detail_view.dart    ← 已有
│   └── mode_page_view.dart             ← 新建（PageView 编排）
```

---

## 执行计划（分 4 步，每步可独立验证）

### Phase 1：提取对话框（低风险，纯搬运）

**改动**：把 `_WifiProvisioningDialog`、`_showDisconnectDialog`、`_showReconnectFailedDialog`、`_showDeviceMenu` 提取到独立文件。

**验证**：功能不变，只是代码位置变了。flutter analyze 通过 + 手动测试菜单/断开流程。

**预计减少**：~500 行

### Phase 2：提取 DeviceSessionController（中风险，核心重构）

**改动**：
1. 创建 `DeviceSessionController`，把 BLE 监听、速度控制、雾化器、偏好存储、硬件 UI 同步全部迁入
2. Screen 的 `initState` 简化为：创建 controller → 调用 `controller.init()`
3. Screen 的 `dispose` 简化为：`controller.dispose()`
4. 所有 `setState` 改为监听 controller 的 `notifyListeners`

**验证**：
- flutter analyze 通过
- 连接/断开/重连流程正常
- 速度控制正常
- 模式切换正常
- 偏好保存/恢复正常

**预计减少**：~400 行（Screen 减少，controller 新增 ~300 行）

### Phase 3：提取功能引导（低风险）

**改动**：把引导相关的 8 个 GlobalKey、2 个 check 方法、2 个 show 方法提取到 `GuideCoordinator`。

**验证**：首次使用引导正常显示。

**预计减少**：~200 行

### Phase 4：清理 Screen（收尾）

**改动**：
- Screen 只保留 `build` 方法 + 少量 UI 辅助方法
- 所有回调改为调用 controller 方法
- 移除所有 `Provider.of<BluetoothProvider>(context, listen: false)` 直接调用

**最终 Screen 大小**：~250 行

---

## 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| BLE 连接状态丢失 | 中 | 高 | Phase 2 后立即实机测试连接/断开/重连 |
| 偏好恢复顺序错误 | 中 | 中 | 保持 `restoreSettings` 内部顺序不变 |
| Colorize 同步时序变化 | 低 | 中 | ColorizeController 已独立，改动最小 |
| 引导 GlobalKey 失效 | 低 | 低 | Phase 3 单独做，出问题可回退 |
| PageView 状态丢失 | 低 | 中 | 保持 PageController 生命周期不变 |

---

## 前置条件

1. ✅ 当前 main 分支干净，编译通过
2. ⚠️ 需要在新分支上做（`feat/screen-refactor`），完成后合并
3. ⚠️ 每个 Phase 完成后需要实机验证（BLE 连接是模拟器测不了的）
4. ⚠️ 建议在做之前先 push 当前产品化改动，确保有回退点

---

## 时间估算

| Phase | 工作量 | 风险 |
|-------|--------|------|
| Phase 1（对话框提取） | 2-3h | 低 |
| Phase 2（Controller 提取） | 4-6h | 中 |
| Phase 3（引导提取） | 1-2h | 低 |
| Phase 4（清理收尾） | 1-2h | 低 |
| **总计** | **8-13h** | |

---

## 决策建议

**现在做还是以后做？**

建议：先 push 产品化改动 → 发版给用户 → 收集反馈 → 下一个开发周期再做重构。

原因：
- 重构不产生用户可见价值
- 当前代码虽然大但功能稳定
- 重构后需要全量实机验证（BLE 相关改动无法自动化测试）
- 如果近期不加新功能到这个页面，重构的收益很低

**如果决定做**：
- 必须在独立分支上操作
- 每个 Phase 完成后 commit + 实机验证
- Phase 2 是关键节点，如果验证不通过可以回退到 Phase 1 的状态
