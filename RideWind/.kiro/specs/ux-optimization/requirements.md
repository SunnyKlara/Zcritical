# 需求文档：RideWind APP 用户体验优化

## 简介

本文档定义了 RideWind 智能 LED 风扇蓝牙控制应用的用户体验优化需求。优化范围涵盖三个核心领域：导航流程修复、废弃 API 替换、冗余代码清理。目标是提升应用稳定性、消除编译警告、减少维护成本。

## 术语表

- **App**: RideWind Flutter 蓝牙控制应用
- **Navigator**: Flutter 的页面导航管理器，管理页面栈的 push/pop 操作
- **SplashScreen**: 应用启动页面，展示 Logo 和用户协议
- **OnboardingFlowScreen**: 引导流程页面，包含 3 页权限说明
- **DeviceScanScreen**: 设备扫描页面，执行蓝牙扫描并发现设备
- **NoDeviceScreen**: 未连接设备页面，扫描未找到设备时显示
- **DeviceConnectScreen**: 核心设备控制页面，包含所有模式控制功能
- **DeviceListScreen**: 设备列表页面，管理已连接设备
- **BluetoothProvider**: 蓝牙状态管理器，管理扫描、连接、断开等蓝牙操作
- **WillPopScope**: Flutter 已废弃的返回键拦截组件
- **PopScope**: Flutter 推荐的返回键拦截组件，替代 WillPopScope
- **withOpacity()**: Color 类已废弃的透明度设置方法
- **withAlpha()**: Color 类推荐的透明度设置方法，替代 withOpacity()
- **pushReplacement**: Navigator 方法，替换当前页面（不保留在栈中）
- **push**: Navigator 方法，将新页面压入栈顶（保留当前页面）
- **导航栈**: Navigator 维护的页面历史记录栈

## 需求

### 需求 1：SplashScreen 导航修复

**用户故事：** 作为用户，我希望从启动页进入引导页或扫描页后无法回退到启动页，以获得流畅的单向启动流程。

#### 验收标准

1. WHEN SplashScreen 完成加载并跳转到目标页面, THE Navigator SHALL 使用 pushReplacement 替代 push 执行页面跳转
2. WHEN 用户在 OnboardingFlowScreen 或 DeviceScanScreen 按下系统返回键, THE App SHALL 阻止回退到 SplashScreen
3. WHEN SplashScreen 跳转完成后, THE Navigator 的页面栈 SHALL 不再包含 SplashScreen 实例

### 需求 2：NoDeviceScreen 安全返回导航

**用户故事：** 作为用户，我希望在未连接设备页面点击返回按钮时始终能正常导航，而不会遇到黑屏或应用崩溃。

#### 验收标准

1. WHEN 用户在 NoDeviceScreen 点击返回按钮且导航栈中存在上一页面, THE Navigator SHALL 执行 pop 操作返回上一页面
2. WHEN 用户在 NoDeviceScreen 点击返回按钮且导航栈中不存在上一页面, THE Navigator SHALL 使用 pushReplacement 跳转到 DeviceScanScreen
3. WHEN NoDeviceScreen 处理返回操作前, THE App SHALL 调用 canPop() 检查导航栈状态

### 需求 3：蓝牙断开连接用户提示

**用户故事：** 作为用户，我希望在蓝牙设备意外断开时收到明确提示并获得重连选项，而不是被静默跳转到扫描页面。

#### 验收标准

1. WHEN 蓝牙设备在 DeviceConnectScreen 意外断开连接, THE App SHALL 显示一个包含断开提示信息的对话框
2. WHEN 断开提示对话框显示时, THE App SHALL 提供"重新连接"和"返回扫描"两个操作选项
3. WHEN 用户选择"重新连接"选项, THE BluetoothProvider SHALL 尝试重新连接到最近断开的设备
4. WHEN 用户选择"返回扫描"选项, THE Navigator SHALL 使用 pushReplacement 跳转到 DeviceScanScreen
5. WHEN 重新连接尝试失败, THE App SHALL 显示连接失败提示并保留"返回扫描"选项

### 需求 4：导航策略统一

**用户故事：** 作为开发者，我希望所有单向流程页面使用一致的导航策略，以避免导航栈管理混乱。

#### 验收标准

1. THE App 中所有单向流程页面（SplashScreen → OnboardingFlowScreen → DeviceScanScreen）SHALL 统一使用 pushReplacement 进行页面跳转
2. WHEN OnboardingFlowScreen 跳转到 DeviceScanScreen, THE Navigator SHALL 使用 pushReplacement 执行跳转
3. WHEN SplashScreen 跳转到 OnboardingFlowScreen 或 DeviceScanScreen, THE Navigator SHALL 使用 pushReplacement 执行跳转


### 需求 5：WillPopScope 废弃 API 替换

**用户故事：** 作为开发者，我希望将所有 WillPopScope 替换为 PopScope，以消除编译警告并使用 Flutter 推荐的 API。

#### 验收标准

1. THE App 中所有使用 WillPopScope 的文件 SHALL 替换为 PopScope 组件
2. WHEN 替换 WillPopScope 为 PopScope 时, THE PopScope SHALL 使用 canPop 和 onPopInvokedWithResult 参数实现等效的返回拦截逻辑
3. WHEN 替换完成后, THE App SHALL 不再包含任何 WillPopScope 引用
4. WHEN 替换完成后, THE App 的返回键拦截行为 SHALL 与替换前保持一致

涉及文件（10 个）：
- `lib/screens/no_device_screen.dart`
- `lib/screens/splash_screen.dart`（_AgreementPage）
- `lib/screens/welcome_screen.dart`
- `lib/screens/rgb_color_screen.dart`
- `lib/screens/register_screen.dart`
- `lib/screens/permission_screen.dart`
- `lib/screens/onboarding_screen.dart`
- `lib/screens/device_list_screen.dart`
- `lib/screens/cleaning_mode_screen.dart`
- `lib/screens/audio_test_screen.dart`

### 需求 6：withOpacity() 废弃 API 替换

**用户故事：** 作为开发者，我希望将所有 withOpacity() 调用替换为 withAlpha()，以消除编译警告并使用 Flutter 推荐的 API。

#### 验收标准

1. THE App 中所有使用 Color.withOpacity() 的代码 SHALL 替换为 Color.withAlpha() 调用
2. WHEN 替换 withOpacity(x) 为 withAlpha() 时, THE 转换公式 SHALL 为 withAlpha((x * 255).round())
3. WHEN 替换完成后, THE App SHALL 不再包含任何 withOpacity() 调用
4. WHEN 替换完成后, THE App 的视觉效果 SHALL 与替换前保持一致

涉及文件（12+ 个）：
- `lib/widgets/running_mode_widget.dart`
- `lib/widgets/guide_overlay.dart`
- `lib/widgets/user_info_drawer.dart`
- `lib/widgets/triangle_indicator_painter.dart`
- `lib/widgets/toast_notification.dart`
- `lib/widgets/mode_text_widget.dart`
- `lib/widgets/mode_text_svg_package.dart`
- `lib/widgets/mode_text_svg.dart`
- `lib/widgets/mode_text_image.dart`
- `lib/widgets/mode_button.dart`
- `lib/widgets/colorize_start_button.dart`
- `lib/widgets/colorize_mode_rgb_settings.dart`
- `lib/widgets/colorize_mode_color_picker.dart`
- `lib/screens/device_scan_screen.dart`
- `lib/screens/onboarding_flow_screen.dart`
- `lib/screens/no_device_screen.dart`

### 需求 7：废弃页面文件清理

**用户故事：** 作为开发者，我希望删除所有已废弃且不再使用的页面文件，以减少项目体积和维护成本。

#### 验收标准

1. THE App SHALL 删除以下已废弃的页面文件：
   - `lib/screens/onboarding_screen.dart`
   - `lib/screens/onboarding_screen_new.dart`
   - `lib/screens/permission_screen.dart`
   - `lib/screens/permission_screen_new.dart`
   - `lib/screens/ready_screen.dart`
   - `lib/screens/ready_screen_new.dart`
   - `lib/screens/main_control_screen.dart`
2. WHEN 废弃文件被删除后, THE App SHALL 不存在任何对已删除文件的 import 引用
3. WHEN 废弃文件被删除后, THE App SHALL 能正常编译且无缺失引用错误

### 需求 8：冗余服务文件清理

**用户故事：** 作为开发者，我希望删除与 ble_service.dart 功能重复的冗余蓝牙服务文件，以简化服务层架构。

#### 验收标准

1. THE App SHALL 删除以下冗余服务文件：
   - `lib/services/bluetooth_service.dart`
   - `lib/services/jdy08_bluetooth_service.dart`
   - `lib/services/device_control_service.dart`
2. WHEN 冗余文件被删除后, THE App SHALL 不存在任何对已删除文件的 import 引用
3. WHEN 冗余文件被删除后, THE App SHALL 能正常编译且无缺失引用错误
4. WHEN 冗余文件被删除后, THE App 的蓝牙通信功能 SHALL 通过 ble_service.dart 和 protocol_service.dart 正常运行
