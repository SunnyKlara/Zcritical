# 需求文档：中华传统色彩圆盘

## 简介

为 ridewind Flutter 应用的 RGB 色彩设置界面（`RGBColorScreen`）添加中华传统色彩圆盘功能。用户可通过左上角的圆形按钮单击打开全屏色彩圆盘覆盖层，浏览按色系分类的中国传统色（如朱砂、胭脂、藤黄、石青等），选中后将对应 RGB 值回填至主界面的 RGB 滑块，实现快速选色。圆盘采用类似 COPIC 色轮的径向扇形布局，支持旋转浏览。同时增加 RGB 滑块数值手动输入功能和可选的 RGB 圆弧调色设计。

## 术语表

- **Color_Wheel_Overlay**: 中华传统色彩圆盘覆盖层，全屏展示色彩圆盘的界面组件
- **Entry_Button**: 入口按钮，位于 RGBColorScreen 左上角（返回按钮旁）的圆形按钮，单击打开色彩圆盘
- **Color_Swatch**: 色块，圆盘上的单个颜色展示单元，包含颜色名称和 RGB 值
- **Color_Family**: 色系，按色相分类的颜色组（如红色系、黄色系、绿色系等）
- **Radial_Layout**: 径向扇形布局，颜色从圆心向外辐射排列的布局方式
- **RGBColorScreen**: 现有的 RGB 色彩设置界面，包含 R/G/B 滑块和区域选择（L/M/R/B）
- **Traditional_Color_Data**: 中华传统色数据集，包含颜色中文名称和对应 RGB 值的数据模型
- **Zone**: 灯光区域，设备的四个灯光控制区域（L 左侧 / M 中间 / R 右侧 / B 后部）
- **RGB_Value_Input**: RGB 数值输入框，允许用户手动输入 0-255 的精确数值
- **RGB_Arc_Picker**: RGB 圆弧调色器，以圆弧形式展示 R/G/B 三个通道的可选调色组件

## 需求

### 需求 1：入口按钮

**用户故事：** 作为用户，我希望在 RGB 色彩设置界面左上角看到一个圆形入口按钮，以便单击打开中华传统色彩圆盘。

#### 验收标准

1. THE Entry_Button SHALL 以简洁的圆形按钮形式显示在 RGBColorScreen 的左上角，位于返回按钮旁边
2. THE Entry_Button SHALL 使用与应用整体暗色主题一致的视觉风格，初始设计为简洁圆圈样式
3. WHEN 用户单击 Entry_Button，THE Color_Wheel_Overlay SHALL 以全屏覆盖层的形式弹出打开
4. WHEN Color_Wheel_Overlay 处于打开状态且用户单击关闭按钮或空白区域，THE Color_Wheel_Overlay SHALL 关闭并恢复显示 Entry_Button 圆圈
5. THE Entry_Button SHALL 具有不小于 44x44 逻辑像素的可触摸区域

### 需求 2：色彩圆盘布局

**用户故事：** 作为用户，我希望看到一个径向扇形布局的色彩圆盘，以便直观地浏览所有中华传统色。

#### 验收标准

1. THE Color_Wheel_Overlay SHALL 以全屏覆盖层的形式展示色彩圆盘
2. THE Radial_Layout SHALL 将 Color_Swatch 从圆心向外辐射排列，每个 Color_Family 占据一个扇形区域
3. THE Radial_Layout SHALL 在同一扇形区域内，将较深的颜色排列在靠近圆心的位置，较浅的颜色排列在外围
4. THE Color_Wheel_Overlay SHALL 在圆盘中心或顶部显示当前选中颜色的名称和 RGB 值预览
5. THE Color_Wheel_Overlay SHALL 提供关闭按钮或手势，允许用户返回 RGBColorScreen

### 需求 3：色块展示

**用户故事：** 作为用户，我希望每个色块都能展示中华传统色的名称和 RGB 值，以便了解每种颜色的文化含义和精确数值。

#### 验收标准

1. THE Color_Swatch SHALL 显示对应的中华传统色名称（中文），例如"朱砂"、"胭脂"、"藤黄"
2. THE Color_Swatch SHALL 以该颜色作为色块的填充色
3. WHEN 用户点击某个 Color_Swatch，THE Color_Wheel_Overlay SHALL 在预览区域显示该颜色的名称和 RGB 数值
4. THE Color_Swatch 上的文字颜色 SHALL 根据背景色的明暗自动选择黑色或白色，以确保可读性

### 需求 4：旋转浏览

**用户故事：** 作为用户，我希望能够旋转或滚动色彩圆盘，以便浏览所有色系的颜色。

#### 验收标准

1. WHEN 用户在 Color_Wheel_Overlay 上执行旋转手势（圆弧方向拖动），THE Radial_Layout SHALL 沿旋转方向转动以展示不同的 Color_Family
2. THE Radial_Layout SHALL 在旋转过程中保持流畅的动画效果
3. WHEN 用户释放旋转手势，THE Radial_Layout SHALL 自动对齐到最近的 Color_Family 扇形区域

### 需求 5：颜色选择与回填

**用户故事：** 作为用户，我希望在色彩圆盘上选中一个颜色后，该颜色的 RGB 值能自动回填到主界面的滑块上，以便快速应用传统色。

#### 验收标准

1. WHEN 用户在 Color_Wheel_Overlay 上点击某个 Color_Swatch，THE Color_Wheel_Overlay SHALL 将该颜色标记为选中状态并提供视觉反馈
2. WHEN 用户确认选择（点击确认按钮或双击色块），THE RGBColorScreen SHALL 将当前选中 Zone 的 R、G、B 滑块值更新为所选颜色的 RGB 值
3. WHEN 颜色回填完成，THE Color_Wheel_Overlay SHALL 自动关闭并返回 RGBColorScreen
4. THE RGBColorScreen SHALL 在滑块值更新后立即反映新的颜色值，区域选择按钮的颜色同步更新

### 需求 6：中华传统色数据

**用户故事：** 作为用户，我希望色彩圆盘包含真实的中华传统色数据，以便体验正宗的中国传统色彩文化。

#### 验收标准

1. THE Traditional_Color_Data SHALL 包含至少以下六个 Color_Family：红色系、黄色系、绿色系、蓝色系、紫色系、白灰黑系
2. THE Traditional_Color_Data SHALL 每个 Color_Family 包含至少 8 种颜色
3. THE Traditional_Color_Data SHALL 为每种颜色提供中文名称和精确的 RGB 值（0-255 范围内的整数）
4. THE Traditional_Color_Data SHALL 以独立的数据文件或常量类的形式组织，与 UI 组件解耦

### 需求 7：RGB 数值手动输入

**用户故事：** 作为用户，我希望能够单击 RGB 滑块旁的数值直接输入精确的 0-255 数值，以便精确控制颜色。

#### 验收标准

1. WHEN 用户单击 RGBColorScreen 上 R、G 或 B 滑块右侧的数值文本，THE RGB_Value_Input SHALL 切换为可编辑的文本输入框
2. THE RGB_Value_Input SHALL 仅接受 0 到 255 之间的整数输入
3. IF 用户输入超出 0-255 范围的数值，THEN THE RGB_Value_Input SHALL 自动将数值限制在有效范围内（小于 0 设为 0，大于 255 设为 255）
4. WHEN 用户完成输入（按下确认键或输入框失去焦点），THE RGBColorScreen SHALL 将对应滑块更新为输入的数值
5. THE RGB_Value_Input SHALL 使用数字键盘类型，方便用户输入数字

### 需求 8：RGB 圆弧调色器（可选）

**用户故事：** 作为用户，我希望有一个圆弧形式的 RGB 调色器，以便以更直观的方式调整颜色。

#### 验收标准

1. WHERE RGB_Arc_Picker 功能启用，THE RGBColorScreen SHALL 在色彩圆盘界面或主界面中展示以圆弧形式排列的 R、G、B 三个调色通道
2. WHERE RGB_Arc_Picker 功能启用，WHEN 用户沿圆弧拖动，THE RGB_Arc_Picker SHALL 调整对应通道的数值（0-255）
3. WHERE RGB_Arc_Picker 功能启用，THE RGB_Arc_Picker SHALL 与现有的线性滑块数值保持同步

### 需求 9：响应式适配

**用户故事：** 作为用户，我希望色彩圆盘在不同尺寸的设备上都能正常显示和操作。

#### 验收标准

1. THE Color_Wheel_Overlay SHALL 根据屏幕尺寸动态调整圆盘大小，使用 ResponsiveUtils 进行适配
2. THE Color_Swatch 上的文字大小 SHALL 根据屏幕尺寸和色块大小动态缩放
3. WHILE 设备处于小屏幕模式（屏幕高度 < 700px），THE Color_Wheel_Overlay SHALL 适当减小色块尺寸以确保所有内容可见
