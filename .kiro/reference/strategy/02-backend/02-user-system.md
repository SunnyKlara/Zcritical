---
inclusion: manual
---

# 2. 后端用户系统

## 是什么

用户注册、登录、身份认证、权限管理的完整后端服务。让 App 用户有账号体系，数据跟着账号走（换手机不丢设置），同时支撑后续所有需要"知道你是谁"的功能。

## 为什么需要

- 没有账号 = 数据只存本地，换手机/卸载重装全丢
- 设备绑定需要知道"这台设备属于谁"
- OTA 灰度需要按用户分组
- 数据分析需要用户维度（留存、活跃、付费）
- 社区/分享/客服都依赖用户身份
- 付费功能（订阅/会员）的前提

## 技术架构

```
┌──────────────────────────────────────────────────────┐
│                   用户系统架构                         │
├──────────────────────────────────────────────────────┤
│                                                       │
│  [客户端]                                             │
│   App (Flutter) → HTTP/HTTPS → API Gateway           │
│                                                       │
│  [认证层]                                             │
│   注册：手机号/邮箱/微信/Apple ID                    │
│   登录：密码/验证码/OAuth/生物识别                   │
│   令牌：JWT (Access Token + Refresh Token)           │
│       │                                               │
│       ▼                                               │
│  [业务层]                                             │
│   用户 CRUD / 个人资料 / 设备绑定 / 偏好设置        │
│       │                                               │
│       ▼                                               │
│  [存储层]                                             │
│   PostgreSQL (用户表) + Redis (Session/Token 缓存)   │
│                                                       │
│  [安全层]                                             │
│   密码 bcrypt 哈希 / Rate Limiting / CORS / HTTPS    │
│                                                       │
└──────────────────────────────────────────────────────┘
```

## 技术栈选型

| 组件 | 技术 | 理由 |
|------|------|------|
| 语言/框架 | Node.js + Express 或 Go + Gin | JS 生态丰富 / Go 性能好 |
| 数据库 | PostgreSQL | 关系型，成熟，免费 |
| 缓存 | Redis | Token 黑名单、Session、限流 |
| 认证 | JWT (RS256) | 无状态，可分布式验证 |
| 第三方登录 | 微信 OAuth / Apple Sign In | 国内必须微信，iOS 必须 Apple |
| 短信验证码 | 阿里云 SMS / Twilio | 注册+登录验证 |
| 密码存储 | bcrypt (cost=12) | 业界标准，抗彩虹表 |
| API 文档 | OpenAPI 3.0 (Swagger) | 前后端协作契约 |

## 实现步骤

### Phase 1：基础注册登录（3-4h）

1. **数据模型**
   ```sql
   CREATE TABLE users (
       id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       phone       VARCHAR(20) UNIQUE,
       email       VARCHAR(255) UNIQUE,
       password_hash VARCHAR(255),
       nickname    VARCHAR(50),
       avatar_url  VARCHAR(500),
       created_at  TIMESTAMPTZ DEFAULT NOW(),
       updated_at  TIMESTAMPTZ DEFAULT NOW(),
       last_login  TIMESTAMPTZ,
       status      SMALLINT DEFAULT 1  -- 1=active, 0=disabled
   );
   ```

2. **注册流程**
   - 验证短信验证码（Redis 中比对）
   - 检查手机号是否已注册
   - bcrypt 哈希密码
   - 插入 users 表
   - 生成 JWT 返回

3. **登录流程**
   - 查询用户 → 验证密码/验证码
   - 生成 Access Token (15min) + Refresh Token (30d)
   - 记录 last_login → 返回 tokens

### Phase 2：JWT 令牌管理（2h）

4. **Token 设计**
   - Access Token：短过期（15min），携带 user_id + role
   - Refresh Token：长过期（30d），存 Redis 支持主动吊销
   - 签名算法：RS256（非对称，公钥可分发给微服务验证）

5. **刷新机制**
   - 验证 refresh_token 签名 → 检查黑名单 → 生成新 access_token
   - 可选：Refresh Token Rotation（每次刷新换新 RT）

6. **登出**
   - 将 refresh_token 加入 Redis 黑名单（TTL = 剩余有效期）
   - 客户端清除本地 token

### Phase 3：第三方登录（2-3h）

7. **微信登录**
   - App 调用微信 SDK 获取 code
   - 后端用 code 换 access_token → 获取 openid/unionid
   - 查找或创建用户 → 返回 JWT

8. **Apple Sign In**
   - iOS 14+ 强制要求
   - 验证 Apple 返回的 identity_token (JWT)
   - 首次登录创建用户，后续直接关联

### Phase 4：用户资料与设备绑定（2h）

9. **个人资料 API**
   - GET/PUT /api/user/profile
   - DELETE /api/user/account（注销，GDPR 要求）

10. **设备绑定**
    - 一个用户可绑定多台设备
    - 一台设备只能绑定一个用户（转让需解绑）
    - 绑定时验证设备 SN 合法性

### Phase 5：安全加固（1-2h）

11. **Rate Limiting**
    - 登录：同一 IP 5 次/分钟
    - 短信验证码：同一手机号 1 次/60 秒
    - 注册：同一 IP 3 次/小时

12. **安全措施**
    - HTTPS 强制（HSTS）
    - 密码强度校验
    - 参数化查询防 SQL 注入
    - 输入过滤防 XSS
    - CORS 白名单

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| JWT 无法主动失效 | 改密码后旧 token 仍有效 | 短过期 + Refresh Token + Redis 黑名单 |
| 手机号换绑 | 用户换号后无法登录 | 支持多种登录方式绑定 |
| 微信 UnionID | 不同应用 openid 不同 | 用 unionid 统一标识 |
| 密码明文传输 | 中间人截获 | HTTPS 强制 |
| 注销后数据 | 个保法要求删除 | 软删除 + 30 天后硬删除 |
| Token 存储 | App 端 token 被提取 | Secure Storage（Keychain/Keystore） |
| 并发注册 | 同一手机号重复注册 | DB UNIQUE 约束 + 应用层幂等 |

## 与 RideWind 的关系

- 当前状态：无后端，App 数据纯本地存储
- 优先级：P3（OTA 之后，上架前）
- 最小可行版：手机号 + 验证码登录 → 设备绑定 → 云端同步设置
- 依赖：需要先有服务器（阿里云 ECS / Serverless）

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| 数据库设计 + 基础 CRUD | 2h | ⭐⭐ |
| 注册/登录/JWT | 3-4h | ⭐⭐⭐ |
| 短信验证码集成 | 1-2h | ⭐⭐ |
| 微信/Apple 登录 | 2-3h | ⭐⭐⭐ |
| 设备绑定 | 1h | ⭐⭐ |
| 安全加固 | 1-2h | ⭐⭐ |
| **总计** | **~2 天** | |

## 学到什么

- RESTful API 设计规范
- JWT 认证机制和安全考量
- OAuth 2.0 协议流程
- 密码学基础（哈希、盐、bcrypt）
- 数据库设计（范式、索引、约束）
- 安全编码实践（注入防护、限流、CORS）
- 用户隐私合规（GDPR、个保法）
