# 发布基础设施演进路线图

> 本文档定义 Critical T1 从当前状态到行业标准的演进路径。
> 不是立刻要做的 TODO，而是一份参照系——确保每一步不走偏。
> 最后更新：2026-05-24

---

## 一、现状评估

### 已经做对的事情

| 领域 | 现状 | 行业对标 |
|------|------|----------|
| CI/CD（Android） | GitHub Actions 全自动：analyze → build → release → deploy → notify | ✅ 达到中小团队标准 |
| 版本号体系 | 双轨独立（APP/固件）+ 协议版本 | ✅ 正确的架构决策 |
| 自动升级 | app_version.json + 国内 CDN + fallback | ✅ 超过多数独立开发者 |
| Git 规范 | 清晰的 commit 规范 + tag 触发 + 分支策略 | ✅ 合理 |
| 文档体系 | steering + hooks + handoff | ✅ 远超同阶段项目 |

### 存在的差距

| 领域 | 现状 | 行业标准 | 差距等级 |
|------|------|----------|----------|
| 软硬件兼容性管理 | 有协议版本概念，但无强制执行 | 兼容性矩阵 + 连接时协商 + 降级策略 | 🟡 中等 |
| iOS 发布 | CI 能编译（no-codesign），无签名/分发 | TestFlight 自动分发 + App Store 审核流 | 🟡 中等 |
| 固件 OTA 安全性 | 有 OTA 功能，无签名验证/回滚 | 签名固件 + A/B 分区 + 回滚 | 🔴 重要 |
| 灰度发布 | 有 rolloutPercentage 字段，未实现逻辑 | 分阶段推送 + 监控 + 自动回滚 | 🟢 低优先 |
| 端到端测试 | 无自动化硬件测试 | HIL（Hardware-in-Loop）测试 | 🟢 远期 |

---

## 二、行业标准参照

### 2.1 软硬件版本兼容性（核心问题）

**行业做法（DJI / Tesla / 小米 IoT / Sonos）：**

```
┌─────────────────────────────────────────────────────┐
│  连接握手流程（行业标准）                              │
├─────────────────────────────────────────────────────┤
│  1. APP 连接设备                                     │
│  2. APP 发送 GET:VERSION                             │
│  3. 固件回复 fw_version + protocol_version           │
│  4. APP 查询本地兼容性表：                            │
│     - proto 匹配 → 正常使用                          │
│     - proto 可降级 → 隐藏新功能，正常使用旧功能        │
│     - proto 不兼容 → 提示用户升级固件/APP             │
│  5. 记录设备固件版本，用于后续功能开关                  │
└─────────────────────────────────────────────────────┘
```

**关键概念：兼容性矩阵**

```
APP v1.2 ←→ 固件 v1.0 (proto=1)  ✅ 完全兼容
APP v1.3 ←→ 固件 v1.0 (proto=1)  ⚠️ 新功能不可用，旧功能正常
APP v1.3 ←→ 固件 v1.1 (proto=2)  ✅ 完全兼容
APP v1.2 ←→ 固件 v1.1 (proto=2)  ⚠️ 固件新功能 APP 不展示
APP v2.0 ←→ 固件 v1.0 (proto=1)  ❌ 不兼容，强制升级固件
```

**你现在的差距**：已有 `GET:VERSION` 握手和 `PROTOCOL_VERSION`，但 APP 端没有完整的兼容性判断逻辑和功能降级机制。这不是"缺了什么"，而是"已有骨架，缺肌肉"。

---

### 2.2 固件 OTA 安全性

**行业做法（ESP-IDF 原生支持）：**

| 机制 | 说明 | ESP-IDF 支持 |
|------|------|-------------|
| 签名验证 | 固件 .bin 用私钥签名，设备用公钥验证 | ✅ Secure Boot v2 |
| A/B 分区 | 两个 OTA 分区交替写入，失败回滚到上一个 | ✅ esp_ota_ops |
| 版本防回滚 | 不允许刷入比当前更旧的固件 | ✅ anti-rollback |
| 断点续传 | OTA 中断后从断点继续 | 需自行实现 |
| 完整性校验 | SHA256 校验下载的 bin | ✅ 内置 |

**你现在的差距**：有 OTA 功能但没有签名验证和 A/B 回滚。用户 OTA 过程中断电 = 变砖。这是**产品上线前必须解决的**。

---

### 2.3 多平台发布协调

**行业做法：**

```
发布时间线（典型 IoT 产品）：

Day 0: 代码冻结，打 tag
Day 1: 内部测试（全平台）
Day 2: 提交 App Store 审核（iOS 需要 1-3 天）
Day 3: Android APK 准备就绪（不发布，等 iOS）
Day 5: iOS 审核通过
Day 5: 同时发布 Android + iOS + 固件 OTA
        （或者 Android 先发，iOS 审核通过后自动上架）
```

**关键原则**：
- Android 和 iOS 的 APP 版本号保持一致
- 固件版本独立，但通过协议版本与 APP 绑定
- 如果新 APP 需要新固件，先推固件 OTA，等大部分设备升级后再推 APP
- 如果新 APP 向后兼容旧固件，可以直接推 APP

**你现在的差距**：iOS CI 能编译但不能签名分发。没有 TestFlight 自动化。发布协调目前是手动的。

---

### 2.4 用户升级零报错

**行业做法（防止升级过程中用户看到错误）：**

| 环节 | 防护措施 |
|------|----------|
| APP 更新 | 应用商店处理，天然安全 |
| APK 侧载更新 | 下载完整性校验（文件大小 + MD5）→ 安装前验证 → 失败提示重试 |
| 固件 OTA | 下载校验 → 写入校验 → 重启验证 → 失败回滚 |
| 协议不匹配 | 连接后立刻检测 → 友好提示"请升级固件" → 不崩溃 |
| 网络中断 | 断点续传 / 重试机制 / 离线可用（降级模式） |

**核心原则**：任何升级失败都不应该让设备变砖或 APP 崩溃。最坏情况 = 回到上一个正常状态。

---

## 三、演进路线图

### Phase 0：当前（已完成）
- [x] Android CI/CD 全自动
- [x] 版本号双轨体系
- [x] 协议版本概念
- [x] APP 自动升级（Android）
- [x] 国内 CDN + fallback
- [x] Git 规范 + 文档体系

### Phase 1：软硬件兼容性加固（下一步，优先级最高）

**目标**：APP 连接任何版本的固件都不崩溃，功能优雅降级。

```
□ APP 端实现完整的协议版本协商逻辑
  - 连接后自动 GET:VERSION
  - 超时（旧固件不响应）→ 假设 proto=0，隐藏新功能
  - proto 不兼容 → 弹窗提示升级，不崩溃
□ 建立兼容性矩阵文档（哪个 APP 版本兼容哪个固件版本）
□ APP 中按固件版本动态显示/隐藏功能入口
□ firmware.json 增加 min_app_version 字段（反向约束）
```

**工作量**：约 2-3 天代码 + 1 天测试

### Phase 2：固件 OTA 安全化

**目标**：OTA 过程中断电不变砖，不接受篡改的固件。

```
□ 启用 ESP-IDF A/B OTA 分区方案
  - 修改 partition table：两个 OTA 分区
  - OTA 写入新分区 → 验证 → 切换启动分区
  - 启动失败自动回滚到旧分区
□ 固件签名（可选，Phase 2.5）
  - 生成签名密钥对
  - CI 构建时自动签名
  - 设备端验证签名后才写入
□ OTA 进度反馈优化
  - APP 显示百分比进度
  - 失败时显示具体原因（网络/校验/空间不足）
  - 不显示红色错误，用友好文案
```

**工作量**：约 3-5 天（分区改动需要重新烧录一次）

### Phase 3：iOS 发布流水线

**目标**：push tag 后 iOS 自动构建 + 上传 TestFlight。

```
□ Apple Developer Program 注册（¥688/年）
□ 配置 iOS 签名证书（存入 GitHub Secrets）
□ CI 增加 iOS 签名构建 job
□ 自动上传 TestFlight（使用 fastlane 或 xcrun altool）
□ app_version.json 增加 ios_app_store_url
□ APP 端 iOS 更新检测走 App Store API
```

**工作量**：约 2 天配置 + 后续每次发版自动

### Phase 4：发布协调与灰度

**目标**：多平台发布有序协调，新版本分阶段推送。

```
□ 实现 rolloutPercentage 逻辑（APP 端按设备 ID hash 判断）
□ 发布顺序自动化：固件先推 → 等待 24h → APP 推送
□ 灰度监控：崩溃率/连接成功率异常时自动暂停推送
□ 发布 checklist 自动化（CI 检查所有前置条件）
```

**工作量**：约 3-5 天，但优先级低于 Phase 1-3

### Phase 5：远期（规模化后）

```
□ HIL 测试（硬件在环）— 自动化固件功能验证
□ 多硬件版本管理（T1 / T2 / T1 Pro 等）
□ 固件分渠道推送（按硬件版本推不同固件）
□ 崩溃监控集成（Sentry / Firebase Crashlytics）
□ 用户反馈闭环（APP 内反馈 → 自动创建 Issue）
```

---

## 四、软件与固件是否需要隔离？

### 行业答案：代码仓库可以在一起，但版本和发布必须独立。

**你现在的做法（monorepo）是正确的**，原因：
- 单人开发，跨仓库同步成本太高
- 协议变更需要同时改两端，放一起更容易保持一致
- CI 可以在一个 workflow 里同时验证两端

**但版本必须独立**（你已经做到了）：
- APP 版本：`pubspec.yaml` → `1.2.1+5`
- 固件版本：`board_config.h` → `1.1.1`
- 协议版本：`board_config.h` → `PROTOCOL_VERSION = 1`

**什么时候需要拆仓库？**
- 团队超过 3 人，且软硬件由不同人负责
- 需要给固件工程师开权限但不想暴露 APP 代码
- 目前不需要

---

## 五、版本不匹配的专业解决方案

### 问题本质

```
用户手里的设备 = 固件 v1.0
用户手机上的 APP = v1.3（刚从商店更新）
→ APP 发了一个 v1.3 才有的命令 → 固件不认识 → 静默失败或崩溃
```

### 行业标准解决方案：协议版本 + 能力协商

```dart
// APP 连接后的第一件事
Future<void> onConnected() async {
  final version = await getDeviceVersion(); // GET:VERSION
  
  if (version == null) {
    // 旧固件不支持版本查询
    _protocolVersion = 0;
    _capabilities = BaseCapabilities(); // 只开放基础功能
    return;
  }
  
  _protocolVersion = version.proto;
  
  if (_protocolVersion < MINIMUM_SUPPORTED_PROTO) {
    // 协议太旧，无法工作
    showFirmwareUpgradeDialog(); // 友好提示，不崩溃
    return;
  }
  
  // 按协议版本开放功能
  _capabilities = CapabilityMatrix.forProto(_protocolVersion);
}
```

### 能力矩阵示例

```dart
class CapabilityMatrix {
  static Capabilities forProto(int proto) {
    return Capabilities(
      hasColorize: proto >= 1,
      hasAudioCasting: proto >= 2,
      hasGarageMode: proto >= 2,
      hasTreadmill: proto >= 3,
      hasCustomLogo: proto >= 1,
    );
  }
}
```

**效果**：无论用户的固件是什么版本，APP 都能正常工作，只是功能多少不同。永远不崩溃。

---

## 六、决策原则（指导后续所有发布相关决策）

1. **向后兼容是默认要求** — 新 APP 必须能连旧固件（功能降级但不崩溃）
2. **向前兼容尽力而为** — 旧 APP 连新固件，新功能不展示即可
3. **强制升级是最后手段** — 只有安全漏洞或数据损坏风险时才用 `forceUpdate`
4. **用户永远不应该看到技术错误** — 所有异常都转化为友好提示 + 明确的下一步操作
5. **发布是可回滚的** — APP 可以回退版本号重新推送，固件有 A/B 分区
6. **自动化一切重复操作** — 人工步骤 = 出错机会
7. **先固件后 APP** — 新功能依赖新固件时，先推固件 OTA 让设备升级，再推 APP

---

## 七、当前推荐的下一步行动

按优先级排序：

1. **Phase 1**（兼容性加固）— 这是防止用户报错的根本解决方案，工作量小，收益大
2. **Phase 2**（OTA 安全化）— 产品正式销售前必须完成
3. **Phase 3**（iOS 流水线）— 等 iOS 功能开发到一定程度再投入

不建议现在就做 Phase 4/5，过早优化会拖慢功能开发。

---

*本文档随项目演进更新。每完成一个 Phase，标记为 done 并记录实际经验。*
