# 48. 订阅/会员体系

## 是什么
用户按月或按年付费解锁高级功能，形成持续性收入（MRR - Monthly Recurring Revenue）。包括会员等级设计、权益差异化、试用期、续费管理、收入确认。是 SaaS/App 最健康的商业模式。

## 为什么需要
- 持续收入比一次性销售更稳定、更可预测
- 提高用户 LTV（Life Time Value）：一个用户持续付费 12 个月 > 一次性购买
- 增加用户粘性：付费用户不容易流失（沉没成本效应）
- 产品迭代有保障：持续收入 = 持续投入研发的底气
- 差异化竞争：免费基础版获客 + 付费高级版变现

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              订阅/会员体系架构                        │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [会员等级]                                          │
│   免费版 → 基础版 (¥9.9/月) → 高级版 (¥19.9/月)  │
│       │                                              │
│       ▼                                              │
│  [权益管理]                                          │
│   ┌─────────────────────────────────────────┐       │
│   │  免费版：基础音效(3个) + 基础灯效(5个)  │       │
│   │  基础版：全部音效 + 全部灯效 + 云同步   │       │
│   │  高级版：自定义音效上传 + 远程控制       │       │
│   │         + 数据分析 + 优先客服            │       │
│   └─────────────────────────────────────────┘       │
│       │                                              │
│       ▼                                              │
│  [订阅管理]                                          │
│   Apple IAP / Google Play / 微信支付                │
│   自动续费 → 到期提醒 → 续费失败处理              │
│       │                                              │
│       ▼                                              │
│  [权益校验]                                          │
│   App/设备 请求功能 → 检查会员等级 → 允许/拒绝    │
│   过期 → 降级到免费版（保留数据，锁定功能）       │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 说明 |
|------|------|------|
| iOS 订阅 | StoreKit 2 + App Store Server API | Apple 强制虚拟商品走 IAP |
| Android 订阅 | Google Play Billing Library | Google 强制 |
| 国内 Android | 微信支付 + 自建续费 | 国内无 Google Play |
| 会员状态 | PostgreSQL + Redis 缓存 | 持久化 + 快速校验 |
| 权益配置 | JSON 配置 + 后端 API | 灵活调整不发版 |
| 收据验证 | Apple/Google 服务端 API | 防伪造 |
| 数据分析 | MRR/Churn/LTV 计算 | 订阅业务核心指标 |

## 实现步骤

### Phase 1：会员等级与权益设计（2h）
1. 等级定义：
   ```json
   {
     "tiers": [
       {
         "id": "free",
         "name": "免费版",
         "price": 0,
         "features": ["basic_sounds_3", "basic_effects_5", "ble_control"]
       },
       {
         "id": "basic",
         "name": "基础会员",
         "price_monthly": 9.9,
         "price_yearly": 99,
         "features": ["all_sounds", "all_effects", "cloud_sync", "custom_logo"]
       },
       {
         "id": "premium",
         "name": "高级会员",
         "price_monthly": 19.9,
         "price_yearly": 199,
         "features": ["custom_sound_upload", "remote_control", "data_analytics", "priority_support"]
       }
     ]
   }
   ```
2. 权益校验 API：
   ```
   GET /api/subscription/check-feature?feature=custom_sound_upload
   → {"allowed": true, "tier": "premium", "expires_at": "2026-12-31"}
   ```
3. App 端权益门控：功能入口检查会员等级，未解锁显示升级提示

### Phase 2：Apple IAP 订阅（3-4h）
4. App Store Connect 配置：
   - 自动续期订阅组
   - 月度/年度两个 SKU
   - 免费试用期（7 天）
   - 推介促销价（首月 ¥1）
5. StoreKit 2 集成：
   - 展示订阅选项 → 用户购买 → 验证交易
   - 监听订阅状态变化（续费/取消/过期/退款）
6. 服务端验证：
   - App Store Server Notifications V2
   - 订阅状态变更实时通知后端
   - 更新用户会员状态

### Phase 3：自建订阅（国内 Android）（2-3h）
7. 微信支付签约代扣：
   - 用户授权 → 每月自动扣款
   - 扣款前 24h 通知用户
   - 扣款失败 → 重试 3 次 → 降级
8. 手动续费模式（备选）：
   - 到期前 7 天推送提醒
   - 到期后进入宽限期（3 天）
   - 宽限期后降级到免费版
9. 会员状态管理：
   ```sql
   CREATE TABLE subscriptions (
     id            UUID PRIMARY KEY,
     user_id       UUID REFERENCES users(id),
     tier          VARCHAR(20),
     platform      VARCHAR(20),  -- apple/google/wechat
     status        VARCHAR(20),  -- active/expired/cancelled/grace_period
     started_at    TIMESTAMPTZ,
     expires_at    TIMESTAMPTZ,
     auto_renew    BOOLEAN DEFAULT true,
     transaction_id VARCHAR(100),
     created_at    TIMESTAMPTZ DEFAULT NOW()
   );
   ```

### Phase 4：试用与转化（1-2h）
10. 免费试用：
    - 新用户 7 天高级会员体验
    - 试用期结束前 1 天提醒
    - 试用→付费转化率追踪
11. 降级体验优化：
    - 过期后保留数据，只锁定功能
    - 明确告知哪些功能被锁定
    - 一键恢复（重新订阅立即解锁）
12. 升级引导：
    - 使用免费版功能时展示高级版差异
    - "解锁更多音效"按钮 → 订阅页面

### Phase 5：数据分析与优化（1-2h）
13. 核心指标：
    - MRR（月度经常性收入）
    - Churn Rate（月流失率，目标 <5%）
    - LTV（用户生命周期价值）= ARPU / Churn Rate
    - 试用→付费转化率（目标 >10%）
14. 留存分析：付费用户 vs 免费用户的留存差异
15. 价格实验：不同价格点的转化率和收入对比

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| Apple 30% 抽成 | 利润大幅减少 | 年订阅第二年降到 15%，小企业计划 15% |
| 订阅状态不同步 | 用户付了费但功能没解锁 | 服务端通知 + 主动查询 + 本地缓存 |
| 退款滥用 | Apple 退款后仍在使用 | 监听退款通知 → 立即降级 |
| 跨平台同步 | iOS 买的 Android 用不了 | 统一账号体系 + 服务端权益管理 |
| 价格敏感 | 定价太高无人买 | A/B 测试价格 + 阶梯定价 |
| 功能划分不当 | 免费版太好没人付费 / 太差没人用 | 核心功能免费，增值功能付费 |

## 与 RideWind 的关系
- 当前状态：无订阅/会员体系，所有功能免费
- 优先级：P5（产品成熟 + 用户基数足够后）
- 可能的付费功能：
  - 高级音效包（跑车/摩托/飞机引擎音效）
  - 高级灯效包（复杂动画/音乐联动）
  - 云同步（设备配置/Logo 云端备份）
  - 远程控制（通过云端控制设备）
  - 数据分析（骑行数据统计/排行榜）
- 定价参考：同类 App ¥6-20/月

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| 等级 + 权益设计 | 2h | ⭐⭐ |
| Apple IAP 订阅 | 3-4h | ⭐⭐⭐⭐ |
| 自建订阅（国内） | 2-3h | ⭐⭐⭐ |
| 试用 + 转化 | 1-2h | ⭐⭐ |
| 数据分析 | 1-2h | ⭐⭐ |
| **总计** | **~2.5 天** | |

## 学到什么
- 订阅商业模式设计（Freemium、定价策略）
- Apple/Google 内购机制和审核规则
- 订阅生命周期管理（试用→付费→续费→流失→召回）
- SaaS 核心指标（MRR、Churn、LTV、CAC）
- 权益系统设计和功能门控
- 用户付费心理学和转化优化
