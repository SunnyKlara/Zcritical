RideWind APP 项目架构分析文档

📅 更新日期: 2025-12-25
📱 项目类型: Flutter 智能 LED 风扇蓝牙控制应用


---

1. 项目概述

RideWind 是一款智能 LED 风扇蓝牙控制应用，通过蓝牙连接 JDY-08 模块控制硬件设备。当前处于"UI 花瓶"向"真实硬件连接"过渡阶段。

1.1 技术栈

类别
技术
框架
Flutter 3.9.2 + Dart 3.0+
状态管理
Provider
蓝牙通信
flutter_blue_plus
权限管理
permission_handler
UI 组件
flutter_svg, google_fonts
音频
audioplayers


---

2. 页面导航流程图

┌─────────────────────────────────────────────────────────────────────────────┐
│                           RideWind APP 页面流程                              │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────────┐
                              │   SplashScreen   │
                              │    (启动页面)     │
                              │  Logo + 用户协议  │
                              └────────┬─────────┘
                                       │ 点击"开始使用"
                                       ▼
                         ┌─────────────────────────────┐
                         │   OnboardingFlowScreen      │
                         │      (引导流程页面)          │
                         │  3页 PageView 滑动引导       │
                         │  1. 通知权限说明             │
                         │  2. 蓝牙权限说明             │
                         │  3. 全部就绪                 │
                         └─────────────┬───────────────┘
                                       │ 点击"开始探索"
                                       ▼
                         ┌─────────────────────────────┐
                         │     DeviceScanScreen        │
                         │      (设备扫描页面)          │
                         │  声波动画 + 自动扫描蓝牙     │
                         │  [DEV] 开发者模式入口        │
                         └─────────────┬───────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │ 未找到设备              │ 找到设备并连接成功       │ 开发者模式
              ▼                        ▼                        ▼
┌─────────────────────┐  ┌─────────────────────────┐  ┌─────────────────────┐
│   NoDeviceScreen    │  │  设备发现弹窗 (底部滑入) │  │  直接跳转到控制页面  │
│    (未连接页面)      │  │  显示设备名称+信号强度   │  │  (模拟设备)          │
│  背景图 + 添加按钮   │  │  "进入控制界面" 按钮     │  └──────────┬──────────┘
└─────────┬───────────┘  └───────────┬─────────────┘             │
          │                          │                           │
          │ 点击添加                  │ 点击进入                   │
          ▼                          ▼                           │
┌─────────────────────┐  ┌─────────────────────────────────────────────────────┐
│  DeviceScanScreen   │  │              DeviceConnectScreen                    │
│    (重新扫描)        │  │               (核心控制页面)                         │
└─────────────────────┘  │  ┌─────────────────────────────────────────────────┐│
                         │  │           模式选择页面 (默认状态)                 ││
                         │  │  PageView 左右滑动选择模式，点击文字进入          ││
                         │  │  • Cleaning Mode                                ││
                         │  │  • Running Mode                                 ││
                         │  │  • Colorize Mode                                ││
                         │  │  • Bluetooth Test                               ││
                         │  └─────────────────────────────────────────────────┘│
                         │                        │ 点击模式文字                │
                         │                        ▼                            │
                         │  ┌─────────────────────────────────────────────────┐│
                         │  │              进入具体模式                        ││
                         │  │                                                 ││
                         │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐││
                         │  │  │Cleaning │ │Running  │ │Colorize │ │BT Test │││
                         │  │  │ Mode    │ │ Mode    │ │ Mode    │ │        │││
                         │  │  │         │ │         │ │         │ │        │││
                         │  │  │气流开关  │ │速度滚轮  │ │颜色选择  │ │蓝牙测试│││
                         │  │  │控制     │ │0-340    │ │9种预设   │ │命令发送│││
                         │  │  │         │ │油门加速  │ │RGB调节   │ │        │││
                         │  │  │         │ │紧急停止  │ │         │ │        │││
                         │  │  └─────────┘ └─────────┘ └─────────┘ └────────┘││
                         │  └─────────────────────────────────────────────────┘│
                         └─────────────────────────────────────────────────────┘
                                       │ 返回按钮
                                       ▼
                         ┌─────────────────────────────┐
                         │     DeviceListScreen        │
                         │      (设备列表页面)          │
                         │  已连接设备卡片              │
                         │  点击进入控制 / 长按断开     │
                         └─────────────────────────────┘


---

3. 目录结构

lib/
├── main.dart                          # 应用入口
│
├── screens/                           # 📱 页面层 (18个文件)
│   ├── splash_screen.dart             # 启动页 - Logo、协议勾选
│   ├── onboarding_flow_screen.dart    # 引导流程 - 3页权限说明
│   ├── onboarding_screen.dart         # (旧版引导，已弃用)
│   ├── onboarding_screen_new.dart     # (新版引导，已弃用)
│   ├── permission_screen.dart         # (权限页，已整合)
│   ├── permission_screen_new.dart     # (新权限页，已整合)
│   ├── ready_screen.dart              # (就绪页，已整合)
│   ├── ready_screen_new.dart          # (新就绪页，已整合)
│   ├── device_scan_screen.dart        # 设备扫描 - 声波动画、蓝牙扫描
│   ├── no_device_screen.dart          # 未连接 - 空状态页面
│   ├── device_list_screen.dart        # 设备列表 - 已连接设备管理
│   ├── device_connect_screen.dart     # ⭐ 核心控制页 - 模式切换、设备控制
│   ├── main_control_screen.dart       # (旧版控制页，已弃用)
│   ├── cleaning_mode_screen.dart      # Cleaning Mode 独立页面
│   ├── rgb_color_screen.dart          # RGB 颜色设置页面
│   ├── bluetooth_test_screen.dart     # 蓝牙测试页面
│   ├── audio_test_screen.dart         # 音频测试页面
│   ├── register_screen.dart           # 注册页面
│   └── welcome_screen.dart            # 欢迎页面
│
├── widgets/                           # 🧩 组件层 (13个文件)
│   ├── airflow_button.dart            # 气流控制按钮 (绿/红渐变)
│   ├── running_mode_widget.dart       # ⭐ Running Mode 完整组件
│   ├── colorize_mode_color_picker.dart # 颜色选择器 (9色条)
│   ├── colorize_mode_rgb_settings.dart # RGB 设置界面
│   ├── colorize_start_button.dart     # 开始涂色按钮
│   ├── triangle_indicator_painter.dart # 倒三角指示器
│   ├── mode_button.dart               # 模式按钮
│   ├── mode_text_widget.dart          # 模式文字组件
│   ├── mode_text_image.dart           # 模式文字图片
│   ├── mode_text_svg.dart             # 模式文字 SVG
│   ├── mode_text_svg_package.dart     # SVG 包装组件
│   ├── adjustable_svg_component.dart  # 可调节 SVG 组件
│   ├── device_found_bottom_sheet.dart # 设备发现底部弹窗
│   └── user_info_drawer.dart          # 用户信息抽屉
│
├── providers/                         # 📊 状态管理层 (2个文件)
│   ├── bluetooth_provider.dart        # 蓝牙状态管理
│   └── device_provider.dart           # 设备状态管理
│
├── services/                          # ⚙️ 服务层 (6个文件)
│   ├── ble_service.dart               # ⭐ 蓝牙通信服务 (JDY-08)
│   ├── protocol_service.dart          # ⭐ 通信协议服务
│   ├── bluetooth_service.dart         # (冗余，待删除)
│   ├── jdy08_bluetooth_service.dart   # (冗余，待删除)
│   ├── device_control_service.dart    # (编译错误，待重构)
│   └── engine_audio_controller.dart   # 引擎音效控制
│
├── models/                            # 📦 数据模型层 (2个文件)
│   ├── device_model.dart              # 设备模型 + 设备状态
│   └── sound_wave_scanner.dart        # 声波扫描动画组件
│
└── utils/                             # 🔧 工具层 (1个文件)
    └── responsive_utils.dart          # 响应式布局工具类


---

4. 核心页面详解

4.1 SplashScreen (启动页)

文件: lib/screens/splash_screen.dart

功能:
- 显示 RideWind Logo (几何设计: 正方形+对角线+相切圆)
- 用户协议勾选框
- "开始使用" 按钮
- 协议弹窗确认
导航: → OnboardingFlowScreen


---

4.2 OnboardingFlowScreen (引导流程)

文件: lib/screens/onboarding_flow_screen.dart

功能:
- 3页 PageView 滑动引导
- 页面1: 通知权限说明
- 页面2: 蓝牙权限说明
- 页面3: 全部就绪
- 底部指示器动画
导航: → DeviceScanScreen


---

4.3 DeviceScanScreen (设备扫描)

文件: lib/screens/device_scan_screen.dart

功能:
- 声波扫描动画 (SoundWaveScanner)
- 自动蓝牙扫描 (4秒超时)
- 过滤 JDY-08/RideWind 设备
- 自动连接第一个设备
- 设备发现弹窗 (底部滑入动画)
- [DEV] 开发者模式入口 (右下角长按)
导航:
- 找到设备 → DeviceConnectScreen
- 未找到 → NoDeviceScreen
- 开发者模式 → DeviceConnectScreen (模拟设备)

---

4.4 DeviceConnectScreen (核心控制页) ⭐

文件: lib/screens/device_connect_screen.dart

这是整个 APP 最核心的页面，包含所有控制功能。

状态机:
┌─────────────────────────────────────────────────────────────┐
│                    DeviceConnectScreen                       │
├─────────────────────────────────────────────────────────────┤
│  _modeActivated = false (默认状态)                           │
│  ├─ 显示模式选择 PageView                                    │
│  ├─ 可左右滑动选择: Cleaning/Running/Colorize/BT Test       │
│  └─ 点击文字 → _modeActivated = true                        │
├─────────────────────────────────────────────────────────────┤
│  _modeActivated = true (进入模式)                            │
│  ├─ _currentModeIndex = 0 → Cleaning Mode                   │
│  │   └─ 气流开关按钮 (AirflowButton)                         │
│  ├─ _currentModeIndex = 1 → Running Mode                    │
│  │   └─ RunningModeWidget (速度滚轮+油门+紧急停止)           │
│  ├─ _currentModeIndex = 2 → Colorize Mode                   │
│  │   ├─ _showColorPicker = false → 默认界面                 │
│  │   ├─ _showColorPicker = true → 颜色选择器                │
│  │   └─ _showRGBSettings = true → RGB 设置界面              │
│  └─ _currentModeIndex = 3 → Bluetooth Test                  │
│      └─ BluetoothTestScreen (嵌入)                          │
└─────────────────────────────────────────────────────────────┘

背景图切换逻辑:
String _getBackgroundImage() {
  if (!_modeActivated) return 'connected_interface.png';
  
  switch (_currentMode) {
    case cleaning: return 'connected_interface.png';
    case running:
      return _showSpeedControl 
        ? 'running_mode_no_text.png' 
        : 'running_mode.png';
    case colorize:
      if (_showRGBSettings) return 'rgb_settings_clean.png';
      if (_showColorPicker) return 'colorize_mode_no_text.png';
      if (_hasSelectedColor) return 'colorize_mode_no_button.png';
      return 'colorize_mode.png';
    case bluetoothTest: return 'connected_interface.png';
  }
}


---

4.5 NoDeviceScreen (未连接页面)

文件: lib/screens/no_device_screen.dart

功能:
- 背景图 (no_device.png)
- 透明点击区域设计
- 中央添加设备按钮 → DeviceScanScreen
- 用户信息抽屉入口

---

4.6 DeviceListScreen (设备列表)

文件: lib/screens/device_list_screen.dart

功能:
- 已连接设备卡片
- 点击 → DeviceConnectScreen
- 长按 → 断开连接对话框
- 响应式布局 (ResponsiveUtils)

---

5. 核心组件详解

5.1 RunningModeWidget (速度控制)

文件: lib/widgets/running_mode_widget.dart

功能:
- ListWheelScrollView 速度滚轮 (0-340 km/h)
- 油门加速按钮 (长按持续加速)
- 紧急停止按钮
- 赛车引擎体验 (高速摇摆效果)
- 单位切换 (km/h ↔ mph)
- 震动反馈
关键参数:

int _currentSpeed = 170;        // 当前速度
int _maxSpeed = 340;            // 最大速度
int _accelerationInterval = 120; // 加速间隔(ms)
int _baseAccelerationStep = 3;  // 基础加速步长

---

### 5.2 ColorizeModeColorPicker (颜色选择)

**文件**: `lib/widgets/colorize_mode_color_picker.dart`

**功能**:
- 9种预设颜色 (4纯色 + 5渐变)
- PageView 水平滑动选择
- 倒三角指示器 (动态颜色)
- 舞台灯光效果 (近亮远暗)

---

### 5.3 AirflowButton (气流按钮)

**文件**: `lib/widgets/airflow_button.dart`

**功能**:
- 渐变背景 (绿色启动/红色关闭)
- 震动反馈
- 外阴影效果

---

## 6. 状态管理

### 6.1 BluetoothProvider

**文件**: `lib/providers/bluetooth_provider.dart`

**职责**:
- 蓝牙扫描/连接/断开
- 设备列表管理
- 风扇速度控制
- LED 颜色控制

**关键方法**:
```dart
Future<void> startScan()                    // 开始扫描
Future<bool> connectToDevice(DeviceModel)   // 连接设备
Future<void> disconnect()                   // 断开连接
Future<bool> setFanSpeed(int speed)         // 设置风扇速度
Future<bool> setLEDColor(strip, r, g, b)    // 设置LED颜色

---

### 6.2 DeviceProvider

**文件**: `lib/providers/device_provider.dart`

**职责**:
- 设备状态管理
- 速度/模式/颜色状态
- 命令发送 (模拟)

---

## 7. 服务层

### 7.1 BLEService (蓝牙服务)

**文件**: `lib/services/ble_service.dart`

**职责**:
- 蓝牙扫描 (flutter_blue_plus)
- 设备连接/断开
- 数据收发 (JDY-08 透传模式)
- 连接状态监听

**JDY-08 配置**:
```dart
SERVICE_UUID = "0000FFE0-0000-1000-8000-00805F9B34FB"
CHAR_UUID = "0000FFE1-0000-1000-8000-00805F9B34FB"


---

7.2 ProtocolService (协议服务)

文件: lib/services/protocol_service.dart

职责:
- 命令编码 (FAN:speed, LED:strip:r:g:b)
- 响应解析
- 协议封装
命令格式:
FAN:50\n          # 设置风扇速度 50%
GET:FAN\n         # 查询风扇速度
LED:1:255:0:0\n   # 设置灯带1为红色


---

8. 资源文件

8.1 图片资源 (assets/images/)

文件名
用途
connected_interface.png
默认连接界面背景
running_mode.png
Running Mode 背景 (带文字)
running_mode_no_text.png
Running Mode 背景 (无文字)
colorize_mode.png
Colorize Mode 背景 (带按钮)
colorize_mode_no_text.png
Colorize Mode 背景 (无文字)
colorize_mode_no_button.png
Colorize Mode 背景 (无按钮)
rgb_settings_clean.png
RGB 设置界面背景
no_device.png
未连接页面背景
device_list_connected.png
设备列表背景 (未连接)
device_list_connected_active.png
设备列表背景 (已连接)
device_product.png
设备产品图


---

9. 已知问题

9.1 废弃 API
- WillPopScope → 应改为 PopScope
- withOpacity → 应改为 withValues
- Color.red/green/blue → 应使用新 API
9.2 冗余代码
- bluetooth_service.dart - 与 ble_service 重复
- jdy08_bluetooth_service.dart - 与 ble_service 重复
- device_control_service.dart - 编译错误
9.3 待完善功能
- 权限请求逻辑缺失
- 断线重连机制
- 生命周期管理

---

10. 开发者模式

在 DeviceScanScreen 右下角添加了开发者模式入口：

触发方式: 长按 "DEV" 标签

效果: 跳过蓝牙扫描，创建模拟设备，直接进入 DeviceConnectScreen

用途: 方便 UI 开发调试，无需真实蓝牙设备


---

11. 后续开发建议

1. 架构重构: 参考 .kiro/specs/architecture-redesign/ 中的设计文档
2. 修复废弃 API: 批量替换 WillPopScope、withOpacity 等
3. 合并冗余服务: 将 3 个蓝牙服务合并为 1 个
4. 添加权限请求: 在 OnboardingFlowScreen 中实现真实权限请求
5. 断线重连: 在 BluetoothProvider 中实现自动重连逻辑