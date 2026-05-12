---
inclusion: auto
---

# AI 行为规范

## 争议义务

### 规则
1. 对用户方案有技术担忧时**必须说出来**，不藏着
2. 同一决策最多争论 2 轮。用户第二次坚持后，记录分歧到 `knowledge/lessons-learned.md` 并全力执行
3. 不用预设规则代替真正思考。每个建议都要基于当前上下文

### 必须触发争议的场景（不可跳过）
- 用户要求修改 BLEService 的队列/MTU/重连逻辑 → 提醒这是已稳定模块，改动风险高
- 用户要求一次性重写超过 3 个文件 → 提醒教训 1（接口不一致风险）
- 用户要求在 services/ 或 ui/ 中直接调用外设 API → 提醒架构分层约束
- 用户要求"先这样，后面再整理" → 提醒这等于永远不会整理，建议当场做对
- 用户要求改 Android 包名或 Dart 包名 → 提醒会破坏 MethodChannel 和构建
- 用户方案可能导致协议不兼容（APP 和 ESP32 两端不一致）→ 必须指出

### 不需要争议的场景（直接执行）
- 用户对 UI 布局/颜色/文案的偏好
- 用户选择的变量命名风格
- 用户决定的功能优先级排序

## 代码质量自检（防腐烂七道防线）

### 防线 1：职责信号
- 单文件超过 500 行 → 触发审视：是否承担了多个职责？
- 不是硬限制。500 行但职责单一 > 5 个 100 行碎片
- 当前已知大文件：`device_connect_screen.dart`(~3500行) — 正在拆分中

### 防线 2：架构边界（由 hook 自动检查）
- drivers/ → 只封装外设 API，不含业务逻辑
- services/ → 业务逻辑，通过 drivers/ 接口访问硬件
- ui/ → 状态机 + 渲染，通过 app_state 获取数据
- app/ → 全局状态 + 事件分发

### 防线 3：新功能三问（动手前必答）
1. 这个功能属于哪个层？（drivers/services/app/ui）
2. 应该放在哪个文件？（已有文件 or 新建？）
3. 现有文件能容纳吗？（会不会让它变成多职责？）

### 防线 4：协议一致性（由 hook 自动检查）
- 任何协议变更必须同时改 ESP32 端和 APP 端
- 改完必须更新 protocol-contract.md
- 新命令必须有：格式定义 + 响应格式 + 错误处理

### 防线 5：原子提交
- 一次提交只做一件事
- 不要把"修 bug"和"重构"混在一个提交里

### 防线 6：编译验证
- 改完 ESP32 代码 → `idf.py build` 必须零错误
- 改完 Flutter 代码 → `flutter analyze` 必须通过
- 改完协议解析 → `flutter test test/protocol/` 必须 51/51

### 防线 7：文档同步（由 hook 自动检查）
- 改了代码中的配置值 → 同步 spec 文档
- 改了文档中的规范 → 检查代码是否需要同步
- 新增/删除文件 → 更新 CONTINUATION_GUIDE.md

## 文档同步检查

每次对话结束前自检：
- [ ] 改了代码？→ 对应文档是否需要同步
- [ ] 改了协议？→ `steering/specs/protocol-contract.md` 是否更新
- [ ] 做了设计决策？→ 记录到 CONTINUATION_GUIDE.md 或 knowledge/
- [ ] CONTINUATION_GUIDE.md 是否反映当前状态

## 不要做的事

- 不要问"你有没有 ESP-IDF 环境"——能力表已经说了
- 不要一次性重写超过 3 个文件而不先确认方案
- 不要在 Flutter 代码中引入新的状态管理框架（保持 Provider + get_it）
- 不要修改 BLEService 的队列发送/MTU/重连逻辑（已稳定）
- 不要改 Android 包名 com.example.ridewind 或 Dart 包名（会破坏构建）

## 提交规范

- 一次提交只做一件事
- 提交信息格式：`[模块] 动作：简述`，如 `[esp/ui] fix: menu slide animation frame timing`
- 改完必须能编译通过再提交
