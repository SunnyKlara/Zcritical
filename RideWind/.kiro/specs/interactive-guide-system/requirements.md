# 需求文档：交互式引导系统重构

## 简介

RideWind 应用当前的引导覆盖层系统（`EnhancedGuideOverlay`）存在根本性的架构缺陷：手指动画固定在屏幕中心而非指向实际目标元素，点击任意位置即可推进步骤而非等待用户执行正确操作，所有引导步骤使用占位 `GlobalKey()` 而未绑定到真实 UI 组件。本次重构将构建一个真正的交互式引导系统，使手指动画精确指向目标元素，水波纹从目标元素发出，提示框动态定位于目标附近，并且系统等待用户执行正确手势后才推进到下一步。

## 术语表

- **Guide_System**：交互式引导系统，负责管理引导流程的核心组件
- **Guide_Step**：引导步骤数据模型，包含目标元素、提示文本、手势类型等信息
- **Guide_Overlay**：引导覆盖层，渲染在应用界面之上的半透明遮罩及交互元素
- **Finger_Pointer**：手指指针动画组件，根据手势类型展示不同动画效果
- **Ripple_Effect**：水波纹效果组件，从目标元素中心向外扩散的视觉反馈
- **Tooltip**：提示框组件，显示引导文本，支持毛玻璃（glassmorphism）和呼吸光边框（glowBorder）两种样式
- **Gesture_Detector**：手势检测器，负责识别用户在目标区域执行的手势并判断是否匹配当前步骤要求
- **Target_Element**：目标元素，引导步骤指向的实际 UI 组件
- **GestureType**：手势类型枚举，定义引导步骤所需的用户操作类型（tap、longPress、swipeLeft、swipeRight、swipeUp、swipeDown、dragHorizontal、dragVertical）
- **Running_Mode_Guide**：行驶模式引导流程，包含 8 个步骤，使用毛玻璃提示框样式
- **Colorize_Mode_Guide**：颜色模式引导流程，包含 7 个步骤，使用呼吸光边框提示框样式
- **GlobalKey**：Flutter 框架中用于唯一标识和定位 UI 组件的键对象

## 需求

### 需求 1：引导步骤数据模型扩展

**用户故事：** 作为开发者，我希望引导步骤模型包含手势类型信息，以便系统能够根据不同步骤要求不同的用户交互方式。

#### 验收标准

1. THE Guide_Step 模型 SHALL 包含一个 GestureType 字段，用于定义该步骤所需的用户手势类型
2. THE GestureType 枚举 SHALL 包含以下值：tap、longPress、swipeLeft、swipeRight、swipeUp、swipeDown、dragHorizontal、dragVertical
3. WHEN Guide_Step 未指定 GestureType 时，THE Guide_System SHALL 使用 tap 作为默认手势类型
4. THE Guide_Step 模型 SHALL 保留现有的 targetKey、title、description、position、icon 字段，确保向后兼容

### 需求 2：目标元素精确定位

**用户故事：** 作为用户，我希望引导手指动画精确指向实际的 UI 元素，以便我能清楚地知道应该操作哪个控件。

#### 验收标准

1. WHEN 引导步骤激活时，THE Guide_Overlay SHALL 通过 Target_Element 的 GlobalKey 获取该元素在屏幕上的精确位置和尺寸
2. THE Finger_Pointer SHALL 定位于 Target_Element 的中心位置上方，指尖指向目标中心
3. THE Ripple_Effect SHALL 以 Target_Element 的中心为圆心向外扩散
4. IF Target_Element 的 GlobalKey 无法获取到 RenderBox（元素未渲染或不可见），THEN THE Guide_System SHALL 跳过该步骤并自动推进到下一步
5. WHEN 引导步骤切换时，THE Guide_Overlay SHALL 以淡入淡出动画过渡到新目标位置

### 需求 3：提示框动态定位

**用户故事：** 作为用户，我希望引导提示框显示在目标元素附近且不遮挡目标，以便我能同时看到提示文本和需要操作的控件。

#### 验收标准

1. THE Tooltip SHALL 根据 Target_Element 在屏幕中的位置自动选择显示在目标上方或下方
2. WHEN Target_Element 位于屏幕上半部分时，THE Tooltip SHALL 显示在 Target_Element 下方
3. WHEN Target_Element 位于屏幕下半部分时，THE Tooltip SHALL 显示在 Target_Element 上方
4. THE Tooltip SHALL 水平居中对齐于 Target_Element，并在超出屏幕边界时自动调整位置使其完全可见
5. THE Tooltip SHALL 与 Target_Element 之间保持足够间距，避免与 Finger_Pointer 动画重叠

### 需求 4：手势类型感知的手指动画

**用户故事：** 作为用户，我希望手指动画能直观地展示我需要执行的操作类型，以便我无需阅读文字就能理解应该如何操作。

#### 验收标准

1. WHEN GestureType 为 tap 时，THE Finger_Pointer SHALL 播放上下弹跳动画，模拟点击动作
2. WHEN GestureType 为 longPress 时，THE Finger_Pointer SHALL 播放按下并保持的动画，手指下压后停顿再抬起
3. WHEN GestureType 为 swipeLeft 时，THE Finger_Pointer SHALL 播放从右向左的水平滑动动画
4. WHEN GestureType 为 swipeRight 时，THE Finger_Pointer SHALL 播放从左向右的水平滑动动画
5. WHEN GestureType 为 swipeUp 或 swipeDown 时，THE Finger_Pointer SHALL 播放垂直方向的滑动动画
6. WHEN GestureType 为 dragHorizontal 时，THE Finger_Pointer SHALL 播放水平来回拖动动画
7. WHEN GestureType 为 dragVertical 时，THE Finger_Pointer SHALL 播放垂直来回拖动动画

### 需求 5：手势验证与步骤推进

**用户故事：** 作为用户，我希望系统在我正确执行了引导要求的操作后才推进到下一步，以便我能真正学会如何使用每个功能。

#### 验收标准

1. WHEN 用户在 Target_Element 区域执行了与当前步骤 GestureType 匹配的手势时，THE Guide_System SHALL 自动推进到下一步
2. WHEN 用户在 Target_Element 区域执行了不匹配的手势时，THE Guide_System SHALL 保持当前步骤不变
3. WHEN GestureType 为 tap 时，THE Gesture_Detector SHALL 在用户点击 Target_Element 区域后判定为匹配
4. WHEN GestureType 为 longPress 时，THE Gesture_Detector SHALL 在用户长按 Target_Element 区域超过 500 毫秒后判定为匹配
5. WHEN GestureType 为 swipeLeft 或 swipeRight 时，THE Gesture_Detector SHALL 在用户在 Target_Element 区域执行水平滑动且方向正确后判定为匹配
6. WHEN GestureType 为 swipeUp 或 swipeDown 时，THE Gesture_Detector SHALL 在用户在 Target_Element 区域执行垂直滑动且方向正确后判定为匹配
7. WHEN GestureType 为 dragHorizontal 或 dragVertical 时，THE Gesture_Detector SHALL 在用户在 Target_Element 区域执行对应方向的拖动操作后判定为匹配
8. THE Gesture_Detector SHALL 将匹配的手势事件传递给底层 UI 组件，使实际功能同时生效

### 需求 6：GlobalKey 暴露与绑定

**用户故事：** 作为开发者，我希望目标 UI 组件暴露 GlobalKey，以便引导系统能够定位到实际的控件位置。

#### 验收标准

1. THE RunningModeWidget SHALL 通过公开属性或回调暴露以下元素的 GlobalKey：速度滚轮、单位标签、油门按钮、紧急停止按钮
2. THE DeviceConnectScreen SHALL 暴露以下元素的 GlobalKey：汽车图片区域、下半部分点击区域、颜色胶囊条、开始涂色按钮、调色盘按钮、LMRB 胶囊区域、RGB 滑条区域、亮度调节条
3. WHEN 引导步骤定义时，THE Guide_System SHALL 使用从实际 UI 组件获取的 GlobalKey 而非占位 GlobalKey

### 需求 7：Running Mode 引导流程

**用户故事：** 作为用户，我希望在首次进入行驶模式时获得完整的交互式引导，以便我能学会所有控制操作。

#### 验收标准

1. THE Running_Mode_Guide SHALL 包含 8 个步骤，使用毛玻璃（glassmorphism）提示框样式
2. WHEN 步骤 1 激活时，THE Guide_System SHALL 指向下半部分区域，提示"点击进入调速界面"，等待用户执行 tap 手势
3. WHEN 步骤 1 完成且调速界面打开后，THE Guide_System SHALL 等待调速界面渲染完成，再激活步骤 2 指向速度滚轮
4. WHEN 步骤 2 激活时，THE Guide_System SHALL 指向速度滚轮，提示"上下滑动调节速度"，等待用户执行垂直滑动手势
5. WHEN 步骤 3 激活时，THE Guide_System SHALL 指向单位标签，提示"点击切换 km/h 和 mph"，等待用户执行 tap 手势
6. WHEN 步骤 4 激活时，THE Guide_System SHALL 指向油门按钮，提示"长按油门持续加速"，等待用户执行 longPress 手势
7. WHEN 步骤 5 激活时，THE Guide_System SHALL 指向紧急停止按钮，提示"点击紧急停止归零"，等待用户执行 tap 手势
8. WHEN 步骤 6 激活时，THE Guide_System SHALL 指向汽车图片区域，提示"点击开关雾化器"，等待用户执行 tap 手势
9. WHEN 步骤 7 激活时，THE Guide_System SHALL 指向汽车图片区域，提示"长按可关机或重启"，等待用户执行 tap 手势（仅展示信息）
10. WHEN 步骤 8 激活时，THE Guide_System SHALL 指向下半部分区域，提示"向左滑动进入颜色模式"，等待用户执行 swipeLeft 手势

### 需求 8：Colorize Mode 引导流程

**用户故事：** 作为用户，我希望在首次进入颜色模式时获得完整的交互式引导，以便我能学会所有颜色控制操作。

#### 验收标准

1. THE Colorize_Mode_Guide SHALL 包含 7 个步骤，使用呼吸光边框（glowBorder）提示框样式
2. WHEN 步骤 1 激活时，THE Guide_System SHALL 指向颜色胶囊条，提示"左右滑动选择预设颜色"，等待用户执行水平滑动手势
3. WHEN 步骤 2 激活时，THE Guide_System SHALL 指向开始涂色按钮，提示"点击开始颜色循环动画"，等待用户执行 tap 手势
4. WHEN 步骤 3 激活时，THE Guide_System SHALL 指向调色盘按钮，提示"点击进入 RGB 详细调色"，等待用户执行 tap 手势
5. WHEN 步骤 3 完成且 RGB 调色界面打开后，THE Guide_System SHALL 等待界面渲染完成，再激活步骤 4
6. WHEN 步骤 4 激活时，THE Guide_System SHALL 指向 LMRB 胶囊区域，提示"点击选择灯带区域"，等待用户执行 tap 手势
7. WHEN 步骤 5 激活时，THE Guide_System SHALL 指向 LMRB 胶囊区域，提示"长按打开详细调色面板"，等待用户执行 longPress 手势
8. WHEN 步骤 6 激活时，THE Guide_System SHALL 指向 RGB 滑条区域，提示"拖动调节颜色值"，等待用户执行 dragHorizontal 手势
9. WHEN 步骤 7 激活时，THE Guide_System SHALL 指向亮度调节条，提示"上下拖动调节亮度"，等待用户执行 dragVertical 手势

### 需求 9：步骤间 UI 状态等待

**用户故事：** 作为用户，我希望引导系统在需要界面切换的步骤之间能正确等待新界面渲染完成，以便手指动画能指向正确的目标。

#### 验收标准

1. WHEN 当前步骤的完成会触发 UI 状态变化（如打开调速界面、切换到 RGB 调色界面）时，THE Guide_System SHALL 在推进到下一步之前等待目标元素的 GlobalKey 对应的 RenderBox 可用
2. THE Guide_System SHALL 使用轮询机制检查目标元素是否已渲染，轮询间隔为 100 毫秒，最大等待时间为 2000 毫秒
3. IF 等待超时后目标元素仍未渲染，THEN THE Guide_System SHALL 跳过该步骤并继续后续引导

### 需求 10：引导流程控制

**用户故事：** 作为用户，我希望能够跳过引导流程，并且引导仅在首次使用时显示，以便不影响后续的正常使用体验。

#### 验收标准

1. THE Guide_Overlay SHALL 在右下角显示"跳过引导"按钮，允许用户随时退出引导流程
2. WHEN 用户完成所有引导步骤或点击跳过时，THE Guide_System SHALL 通过 FeatureGuideService 将该引导标记为已完成
3. WHEN 引导已标记为已完成时，THE Guide_System SHALL 在后续进入相同模式时不再显示引导
4. THE Guide_Overlay SHALL 显示当前步骤编号和总步骤数（如"3 / 8"），帮助用户了解引导进度
