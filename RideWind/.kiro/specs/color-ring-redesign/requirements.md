# 需求文档：色彩圆环重新设计

## 简介

替换 ridewind Flutter 应用中现有的 COPIC 风格色彩圆盘（径向扇形梯形色块 + InteractiveViewer 缩放平移），改为参考 COPIC 色轮 app 的圆环设计。色系围成一个圆环，每个色系内的颜色从内圈到外圈按明度排列（深→浅），用户通过手指滑动使圆环旋转浏览。

入口保留现有的彩色渐变圆形图标（位于 `DeviceConnectScreen` 的 RGB 调色面板顶部，以及 colorize 模式界面顶部）。点击入口后进入一个专属的圆环界面（新的全屏页面），圆环在该页面中从左上角以缩放展开动画弹出，并支持拖动移动到屏幕任意位置。设计以色彩美感和交互流畅性为核心。

## 术语表

- **Color_Ring**：新的色彩圆环组件，使用 CustomPainter 绘制，由多段色系弧线围成一个完整圆环，每个色系内颜色从内圈（深色）到外圈（浅色）径向排列
- **Color_Band**：单个色系在圆环上占据的一段扇形区域，内部颜色沿径向方向按明度从深到浅排列为多层弧形色块
- **Color_Ring_Screen**：圆环专属界面，一个全屏页面（通过 Navigator.push 进入），深色背景，圆环在其中以动画弹出
- **Entry_Button**：现有的彩色渐变圆形入口按钮，位于 DeviceConnectScreen 的 RGB 调色面板顶部（`_buildHighQualityRGBPanel` 中）和 colorize 模式界面顶部，点击后进入 Color_Ring_Screen
- **RGB_Panel**：现有的 `DeviceConnectScreen` 中的 RGB 调色面板（`_buildHighQualityRGBPanel`），包含 R/G/B 滑块和灯带位置选择
- **Color_Family**：色系数据模型（`ColorFamily`），包含色系 ID、名称和颜色列表
- **Chinese_Color**：单个传统色数据模型（`ChineseColor`），包含名称和 RGB 值
- **Rotation_Angle**：圆环当前的旋转角度（弧度），由用户手势驱动
- **Color_Detail_Panel**：选中颜色后显示的详情区域，展示颜色名称、色块预览和 RGB 值

## 需求

### 需求 1：圆环绘制（参考 COPIC 色轮布局）

**用户故事：** 作为用户，我希望看到一个参考 COPIC 色轮布局的色彩圆环，色系围成圆，每个色系内的颜色从内到外按明度排列，以便直观地浏览中华传统色。

#### 验收标准

1. THE Color_Ring SHALL 使用 CustomPainter 将 6 个 Color_Family 绘制为一个完整圆环，每个 Color_Family 占据一段等角度的 Color_Band 扇形区域
2. THE Color_Band SHALL 在其扇形区域内，将该色系的颜色沿径向方向从内圈到外圈按明度从深到浅排列，每种颜色占据一层弧形色块（梯形/矩形），越靠外的色块弧长越大
3. THE Color_Ring SHALL 具有固定的内半径，外半径根据色系中最多颜色数量动态计算，确保所有颜色都能显示
4. THE Color_Ring SHALL 在相邻 Color_Band 之间绘制细微的分隔线（宽度不超过 1.5 像素），以区分不同色系
5. THE Color_Ring SHALL 在每个色块上显示该颜色的中文名称，文字颜色根据背景色明暗自动选择黑色或白色
6. THE Color_Ring 的内圈 SHALL 绘制为一条连续的窄色带弧线，展示每个色系的代表色（最深色），形成圆环的内边缘

### 需求 2：圆环界面与弹出动画

**用户故事：** 作为用户，我希望点击入口按钮后进入一个专属的圆环界面，圆环从左上角以缩放动画弹出展开，并且可以拖动移动到屏幕任意位置。

#### 验收标准

1. WHEN 用户点击 Entry_Button 时，THE 应用 SHALL 通过 Navigator.push 进入 Color_Ring_Screen（全屏深色背景页面）
2. WHEN Color_Ring_Screen 打开后，THE Color_Ring SHALL 从页面左上角位置以缩放展开动画弹出，从小尺寸放大到完整尺寸，动画持续 300 到 500 毫秒
3. THE Color_Ring SHALL 初始出现在左上角区域，不居中
4. THE Color_Ring SHALL 支持拖动手势，用户可以将圆环从左上角拖动到屏幕中心或任意位置
5. THE Color_Ring_Screen SHALL 提供关闭按钮或返回手势，关闭时圆环以反向缩放动画收回到左上角并消失，然后返回上一页面
6. THE 弹出动画 SHALL 包含缩放（从小到大）和透明度（从透明到不透明）的组合效果，使用弹性曲线（如 Curves.easeOutBack）

### 需求 3：旋转交互

**用户故事：** 作为用户，我希望通过手指滑动让圆环旋转，以便流畅地浏览不同色系。

#### 验收标准

1. WHEN 用户在圆环区域进行单指圆弧方向拖动手势时，THE Color_Ring_Screen SHALL 根据手指相对于圆环中心的角度变化量更新 Rotation_Angle，使圆环跟随手指旋转
2. WHEN 用户释放拖动手势时，THE Color_Ring_Screen SHALL 根据释放时的角速度施加惯性动画，使圆环继续旋转并逐渐减速停止
3. WHEN 惯性动画正在播放且用户再次触摸圆环时，THE Color_Ring_Screen SHALL 立即停止惯性动画，将控制权交还给用户手势
4. THE Color_Ring_Screen SHALL 区分旋转手势和拖动移动手势：在圆环弧线色块区域内的拖动为旋转，在圆环中心空白区域的拖动为移动整个圆环位置

### 需求 4：颜色选择

**用户故事：** 作为用户，我希望点击圆环上的颜色来选择它，以便将该颜色应用到灯光设置。

#### 验收标准

1. WHEN 用户点击圆环上的某个色块时，THE Color_Ring_Screen SHALL 根据点击坐标的角度和径向距离计算命中的 Chinese_Color，并将该颜色标记为选中状态
2. WHEN 一个 Chinese_Color 被选中时，THE Color_Ring_Screen SHALL 在选中色块上绘制高亮指示（白色描边）
3. WHEN 一个 Chinese_Color 被选中时，THE Color_Detail_Panel SHALL 在圆环中心或圆环附近显示该颜色的名称、色块预览和 RGB 数值
4. WHEN 用户双击某个色块或点击确认按钮时，THE Color_Ring_Screen SHALL 调用 onColorSelected 回调将选中颜色的 R、G、B 值传递给调用方，然后关闭圆环界面返回上一页
5. IF 用户点击的位置不在圆环的色块区域内，THEN THE Color_Ring_Screen SHALL 不改变当前选中状态

### 需求 5：入口集成

**用户故事：** 作为用户，我希望从现有的彩色入口按钮打开新的色彩圆环界面，以便保持操作习惯一致。

#### 验收标准

1. THE DeviceConnectScreen SHALL 保留 `_buildHighQualityRGBPanel` 中的彩色渐变圆形入口按钮（现有样式不变），点击后通过 Navigator.push 进入 Color_Ring_Screen 替代原有的 ChineseColorWheelOverlay
2. THE DeviceConnectScreen SHALL 同时更新 colorize preset 界面和 colorize rgbDetail 界面顶部的入口按钮，统一指向 Color_Ring_Screen
3. WHEN Color_Ring_Screen 通过 onColorSelected 回调返回颜色值时，THE DeviceConnectScreen SHALL 将返回的 R、G、B 值设置到当前选中灯带位置的 RGB 滑块上，并同步到硬件
4. THE DeviceConnectScreen 和 RGBColorScreen SHALL 移除对 ChineseColorWheelOverlay 的引用

### 需求 6：色系标识

**用户故事：** 作为用户，我希望在圆环上能辨识每个色系的名称，以便快速定位目标色系。

#### 验收标准

1. THE Color_Ring SHALL 在每段 Color_Band 的内圈弧线位置绘制该色系的名称标签
2. THE 色系名称标签 SHALL 沿弧线方向旋转排列，文字方向与弧线切线方向一致，保持可读性
3. THE 色系名称标签 SHALL 使用与色带形成对比的颜色（白色或半透明白色），字号根据圆环尺寸动态缩放

### 需求 7：动画与视觉体验

**用户故事：** 作为用户，我希望圆环的弹出、旋转和交互具有流畅的动画效果，以获得优雅的使用体验。

#### 验收标准

1. THE Color_Ring_Screen 的弹出动画 SHALL 在页面打开后从左上角开始，以缩放+淡入的组合效果展开到目标尺寸，持续 300 到 500 毫秒，使用弹性曲线（如 Curves.easeOutBack）
2. THE Color_Ring_Screen 的关闭动画 SHALL 以反向缩放+淡出效果收回到左上角，持续 200 到 300 毫秒
3. THE 惯性旋转动画 SHALL 使用减速曲线（如 Curves.decelerate），使旋转自然减速停止
4. WHEN 选中颜色发生变化时，THE Color_Detail_Panel SHALL 使用过渡动画更新显示内容，避免突兀切换
5. THE Color_Ring 在拖动移动时 SHALL 跟随手指实时移动，无延迟感

### 需求 8：响应式适配

**用户故事：** 作为用户，我希望色彩圆环在不同尺寸的设备上都能正常显示和操作。

#### 验收标准

1. THE Color_Ring_Screen SHALL 根据屏幕尺寸动态调整圆环大小，使用 ResponsiveUtils 进行适配
2. THE Color_Ring 上的色块文字大小 SHALL 根据圆环尺寸和色块大小动态缩放
3. WHILE 设备处于小屏幕模式（屏幕高度 < 700px），THE Color_Ring_Screen SHALL 适当减小圆环尺寸以确保不超出屏幕边界
4. THE Color_Ring 在拖动移动时 SHALL 不允许完全移出屏幕可视区域
