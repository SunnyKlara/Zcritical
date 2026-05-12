# 需求文档

## 简介

本需求涵盖 RideWind 应用的两项改进：（1）将现有的简单文字弹窗式功能引导升级为带有手指指针动画、水波纹效果和文字提示框的分步交互式引导系统；（2）修复 RGB 调色页面自定义颜色在返回预设页面时被覆盖的 Bug。

## 术语表

- **Guide_Overlay（引导覆盖层）**: 覆盖在应用界面之上的半透明遮罩层，用于高亮目标 UI 元素并展示引导提示
- **Finger_Pointer（手指指针）**: 引导过程中指向目标 UI 元素的手指图标动画，带有上下浮动效果
- **Ripple_Effect（水波纹效果）**: 从目标 UI 元素中心向外扩散的圆形波纹动画，用于吸引用户注意力
- **Tooltip（提示框）**: 显示在目标元素附近的文字说明框，包含步骤标题和描述
- **GuideStep（引导步骤）**: 引导流程中的单个步骤，包含目标元素定位、提示内容和动画配置
- **FeatureGuideService（功能引导服务）**: 管理各功能模块引导完成状态的服务，使用 SharedPreferences 持久化
- **ColorizeState（调色状态）**: 调色模式的子状态枚举，包含 preset（预设）和 rgbDetail（RGB 详细调节）
- **Preset_Color（预设颜色）**: 应用内置的 LED 配色方案，用户可从预设列表中选择
- **Custom_RGB_Color（自定义 RGB 颜色）**: 用户通过 RGB 滑块手动调节的 LED 颜色值
- **Zone（区域）**: LED 灯的物理分区，包括 L（左）、M（中）、R（右）、B（底部）

## 需求

### 需求 1：交互式引导动画系统

**用户故事：** 作为新用户，我希望在首次使用各功能时看到带有手指指针动画和水波纹效果的分步交互式引导，以便我能直观地理解每个 UI 元素的操作方式。

#### 验收标准

1. WHEN 用户首次进入某功能模块时，THE Guide_Overlay SHALL 显示分步交互式引导，依次高亮目标 UI 元素并展示 Finger_Pointer 动画、Ripple_Effect 动画和 Tooltip 提示框
2. WHEN 引导步骤切换时，THE Guide_Overlay SHALL 播放 Finger_Pointer 从当前目标元素移动到下一个目标元素的过渡动画
3. WHEN 某个引导步骤激活时，THE Finger_Pointer SHALL 在目标元素附近持续播放上下浮动的循环动画
4. WHEN 某个引导步骤激活时，THE Ripple_Effect SHALL 从目标元素的高亮区域中心向外扩散，播放至少两圈循环水波纹动画
5. WHEN 某个引导步骤激活时，THE Tooltip SHALL 根据目标元素在屏幕中的位置自动选择显示方向（上、下、左、右），确保提示框完整显示在屏幕可见区域内
6. WHEN 用户点击"下一步"按钮或点击高亮区域时，THE Guide_Overlay SHALL 前进到下一个引导步骤
7. WHEN 用户完成所有引导步骤时，THE FeatureGuideService SHALL 将该功能的引导完成状态持久化存储，后续进入该功能时不再显示引导
8. WHEN 用户点击"跳过"按钮时，THE Guide_Overlay SHALL 立即关闭引导覆盖层，并将该功能的引导标记为已完成
9. IF 目标 UI 元素在当前屏幕中不可见或无法定位，THEN THE Guide_Overlay SHALL 跳过该步骤并自动前进到下一个可定位的步骤

### 需求 2：引导动画视觉效果

**用户故事：** 作为用户，我希望引导动画流畅且视觉效果精美，以便引导过程不会打断我的使用体验。

#### 验收标准

1. THE Finger_Pointer SHALL 使用手指图标（如 Icons.touch_app），并以 0.8 秒为周期播放上下浮动动画，浮动幅度为 8 像素
2. THE Ripple_Effect SHALL 以半透明主题色（0xFF25C485）绘制，从不透明度 0.4 渐变到 0.0，扩散半径从高亮区域边缘扩展至额外 30 像素
3. WHEN 引导步骤之间切换时，THE Guide_Overlay SHALL 在 300 毫秒内完成淡出旧步骤和淡入新步骤的过渡动画
4. THE Guide_Overlay SHALL 在高亮区域周围绘制主题色（0xFF25C485）边框，边框宽度为 2 像素，圆角半径为 8 像素

### 需求 3：自定义 RGB 颜色状态保持

**用户故事：** 作为用户，我希望在 RGB 调色页面自定义颜色后返回预设页面时，自定义的 RGB 颜色值不会被预设颜色覆盖，以便我能在预设和自定义颜色之间自由切换而不丢失调节结果。

#### 验收标准

1. WHEN 用户在 rgbDetail 状态下调节了自定义 RGB 颜色值并返回 preset 状态时，THE 设备控制页面 SHALL 保留用户自定义的 RGB 颜色值，不调用预设颜色覆盖逻辑
2. WHEN 用户从 rgbDetail 返回 preset 后再次进入 rgbDetail 时，THE 设备控制页面 SHALL 显示用户上次自定义的 RGB 颜色值
3. WHEN 用户在 preset 状态下主动选择一个预设颜色时，THE 设备控制页面 SHALL 将该预设颜色应用到本地 RGB 值（_redValues、_greenValues、_blueValues）
4. WHEN 用户自定义了 RGB 颜色值时，THE 设备控制页面 SHALL 使用标志位区分当前颜色来源是预设还是自定义，以决定返回 preset 时是否执行预设覆盖

### 需求 4：自定义 RGB 颜色持久化

**用户故事：** 作为用户，我希望自定义的 RGB 颜色值在应用重启后仍然保留，以便我不需要每次重新调节颜色。

#### 验收标准

1. WHEN 用户调节自定义 RGB 颜色值时，THE PreferenceService SHALL 将各区域（L、M、R、B）的 R、G、B 值持久化存储到 SharedPreferences
2. WHEN 应用启动并加载设备控制页面时，THE 设备控制页面 SHALL 从 SharedPreferences 读取已保存的自定义 RGB 颜色值并恢复到本地状态
3. WHEN 用户选择预设颜色时，THE PreferenceService SHALL 清除已保存的自定义 RGB 颜色值，表示当前使用预设颜色
4. FOR ALL 有效的自定义 RGB 颜色值，保存后再读取 SHALL 得到与保存时相同的颜色值（往返一致性）
