# 实施计划：RideWind APP 用户体验优化

## 概述

按照三阶段优化方案，将设计文档中的变更转化为可执行的编码任务。任务按依赖关系排序：先修复导航流程，再替换废弃 API，最后清理冗余代码。

## 任务

- [x] 1. 修复导航流程
  - [x] 1.1 修复 SplashScreen 导航方式
    - 在 `lib/screens/splash_screen.dart` 的 `_navigateToOnboarding()` 方法中，将 `Navigator.of(context).push()` 替换为 `Navigator.of(context).pushReplacement()`
    - _Requirements: 1.1, 1.2, 1.3, 4.1, 4.3_

  - [x] 1.2 修复 NoDeviceScreen 安全返回导航
    - 在 `lib/screens/no_device_screen.dart` 的 `_handleBackNavigation()` 方法中，添加 `canPop()` 检查
    - 当 `canPop()` 为 false 时，使用 `pushReplacement` 跳转到 `DeviceScanScreen`
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 1.3 实现蓝牙断开连接提示对话框
    - 在 `lib/screens/device_connect_screen.dart` 中：
    - 修改 `_connectionSub` 监听器，断开时调用 `_showDisconnectDialog()` 而非直接跳转
    - 新增 `_showDisconnectDialog()` 方法，显示包含"重新连接"和"返回扫描"按钮的对话框
    - 新增 `_attemptReconnect()` 方法，尝试重连并处理失败情况
    - 新增 `_showReconnectFailedDialog()` 方法，显示重连失败提示
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ]* 1.4 编写导航流程单元测试
    - 测试 SplashScreen 使用 pushReplacement 跳转
    - 测试 NoDeviceScreen 返回时的 canPop 检查逻辑
    - 测试蓝牙断开时显示对话框
    - _Requirements: 1.1, 2.1, 2.2, 3.1_

- [x] 2. 检查点 - 确认导航修复
  - 确保所有测试通过，如有问题请告知。

- [x] 3. 替换 WillPopScope 为 PopScope
  - [x] 3.1 替换 no_device_screen.dart 和 splash_screen.dart 中的 WillPopScope
    - 将 `WillPopScope` 替换为 `PopScope`，使用 `canPop: false` 和 `onPopInvokedWithResult` 参数
    - 移除不再需要的 `_onWillPop` 包装方法
    - _Requirements: 5.1, 5.2, 5.4_

  - [x] 3.2 替换 welcome_screen.dart、register_screen.dart、onboarding_screen.dart 中的 WillPopScope
    - 同上替换模式
    - _Requirements: 5.1, 5.2, 5.4_

  - [x] 3.3 替换 rgb_color_screen.dart、cleaning_mode_screen.dart、audio_test_screen.dart 中的 WillPopScope
    - 注意 audio_test_screen 和 rgb_color_screen 的 `_onWillPop` 直接返回 bool，需提取逻辑
    - 注意 cleaning_mode_screen 使用 SafeArea 而非 Scaffold 作为子组件
    - _Requirements: 5.1, 5.2, 5.4_

  - [x] 3.4 替换 device_list_screen.dart 和 permission_screen.dart 中的 WillPopScope
    - 同上替换模式
    - _Requirements: 5.1, 5.2, 5.4_

- [x] 4. 替换 withOpacity() 为 withAlpha()
  - [x] 4.1 替换 widgets 目录下文件中的 withOpacity()
    - 涉及文件：running_mode_widget.dart、guide_overlay.dart、user_info_drawer.dart、triangle_indicator_painter.dart、toast_notification.dart、mode_text_widget.dart、mode_text_svg_package.dart、mode_text_svg.dart、mode_text_image.dart、mode_button.dart、colorize_start_button.dart、colorize_mode_rgb_settings.dart、colorize_mode_color_picker.dart
    - 使用转换公式：`withOpacity(x)` → `withAlpha((x * 255).round())`
    - _Requirements: 6.1, 6.2, 6.4_

  - [x] 4.2 替换 screens 目录下文件中的 withOpacity()
    - 涉及文件：device_scan_screen.dart、onboarding_flow_screen.dart、no_device_screen.dart 及其他包含 withOpacity 的 screen 文件
    - 使用相同转换公式
    - _Requirements: 6.1, 6.2, 6.4_

  - [ ]* 4.3 编写 withOpacity 转换公式属性基测试
    - **Property 1: withOpacity 到 withAlpha 转换公式正确性**
    - **Validates: Requirements 6.2**
    - 使用 glados 生成随机 Color 和透明度值，验证转换公式正确性

- [x] 5. 检查点 - 确认 API 替换
  - 确保所有测试通过，运行 `dart analyze` 确认无废弃 API 警告，如有问题请告知。

- [x] 6. 清理冗余代码
  - [x] 6.1 清理 welcome_screen.dart 中对废弃文件的引用
    - `welcome_screen.dart` 引用了 `onboarding_screen.dart`，需移除该 import 并修复相关代码
    - _Requirements: 7.2_

  - [x] 6.2 删除废弃页面文件
    - 删除以下 7 个文件：onboarding_screen.dart、onboarding_screen_new.dart、permission_screen.dart、permission_screen_new.dart、ready_screen.dart、ready_screen_new.dart、main_control_screen.dart
    - _Requirements: 7.1, 7.2, 7.3_

  - [x] 6.3 删除冗余服务文件
    - 删除以下 3 个文件：bluetooth_service.dart、jdy08_bluetooth_service.dart、device_control_service.dart
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

  - [ ]* 6.4 编写代码完整性属性基测试
    - **Property 2: 废弃 API 零残留**
    - **Validates: Requirements 5.1, 5.3, 6.1, 6.3**
    - **Property 3: 已删除文件零引用**
    - **Validates: Requirements 7.2, 8.2**
    - 遍历所有 Dart 源文件，验证无废弃 API 引用和无已删除文件的 import

- [x] 7. 最终检查点 - 确认所有优化完成
  - 确保所有测试通过，运行 `dart analyze` 确认零警告，如有问题请告知。

## 备注

- 标记 `*` 的任务为可选任务，可跳过以加快 MVP 进度
- 每个任务引用了具体的需求编号以确保可追溯性
- 检查点确保增量验证
- 属性基测试验证通用正确性属性
- 单元测试验证具体示例和边界情况
