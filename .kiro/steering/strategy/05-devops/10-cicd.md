# 10. CI/CD 流水线

## 是什么
持续集成/持续部署。代码推送后自动触发：编译→测试→构建→部署。消除手动操作，保证每次发布质量一致。

## 为什么需要
- 手动编译/部署容易出错（忘记步骤、环境不一致）
- 多人协作时需要自动化验证（PR 合并前必须通过测试）
- 快速反馈：提交后几分钟知道是否破坏了什么
- 发布频率提升：从"一周一次手动发布"到"每天多次自动发布"
- ESP32 固件 + Flutter App + 后端三条流水线

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              CI/CD 流水线                             │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [触发] git push / PR / tag                         │
│       │                                              │
│       ▼                                              │
│  [CI 阶段]                                           │
│   ├─ ESP32: idf.py build → 固件 bin                 │
│   ├─ Flutter: flutter analyze → flutter test        │
│   ├─ 后端: npm test / go test                       │
│   └─ 代码质量: lint / 覆盖率 / 安全扫描            │
│       │                                              │
│       ▼                                              │
│  [CD 阶段]                                           │
│   ├─ 固件: 签名 → 上传 OSS → 通知 OTA 服务        │
│   ├─ App: 构建 APK/IPA → 上传应用商店/TestFlight   │
│   └─ 后端: Docker build → push → K8s 滚动更新     │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 理由 |
|------|------|------|
| CI 平台 | GitHub Actions | 免费额度够用，生态好 |
| 备选 | GitLab CI / Jenkins | 自托管，更灵活 |
| ESP32 构建 | espressif/idf Docker 镜像 | 官方镜像，环境一致 |
| Flutter 构建 | subosito/flutter-action | GitHub Action 插件 |
| 制品存储 | GitHub Releases / OSS | 固件 bin、APK 归档 |
| 通知 | 飞书/钉钉 Webhook | 构建结果实时通知 |

## 实现步骤

### Phase 1：ESP32 固件 CI（2h）
1. `.github/workflows/firmware.yml`
2. 触发条件：push to main, PR to main, paths: `ridewind-esp/**`
3. 步骤：checkout → setup IDF → idf.py build → 上传 bin artifact
4. 可选：固件大小检查（超过阈值报警）

### Phase 2：Flutter App CI（2h）
5. `.github/workflows/flutter.yml`
6. flutter analyze + flutter test + build apk
7. PR 时只跑 analyze+test，merge 后才 build
8. 覆盖率报告上传（Codecov）

### Phase 3：后端 CI（1-2h）
9. lint + unit test + integration test
10. Docker build 验证（确保 Dockerfile 没问题）

### Phase 4：CD 自动部署（2-3h）
11. 固件 CD：tag v*.*.* → 签名 → 上传 OSS → 更新 OTA 版本 API
12. App CD：tag → build release → 上传蒲公英/TestFlight
13. 后端 CD：merge to main → Docker push → K8s 滚动更新

### Phase 5：质量门禁（1h）
14. PR 必须通过 CI 才能合并（Branch Protection）
15. 代码覆盖率不能下降
16. 固件大小不能超过分区限制

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| 构建环境不一致 | 本地能编译 CI 不行 | Docker 镜像固定版本 |
| 密钥泄露 | 签名密钥在日志中暴露 | GitHub Secrets + 不打印 |
| 构建太慢 | 每次 CI 等 20 分钟 | 缓存依赖 + 并行任务 |
| Flaky Test | 测试偶尔失败 | 重试机制 + 修复不稳定测试 |
| CD 回滚 | 部署了有 bug 的版本 | 蓝绿部署 + 一键回滚 |

## 与 RideWind 的关系
- 当前状态：手动 `idf.py build`，无自动化
- 优先级：P4（多人协作或频繁发布时）
- 快速收益：PR 自动跑 `idf.py build` 验证编译（防止合入编译不过的代码）

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| ESP32 CI | 2h | ⭐⭐ |
| Flutter CI | 2h | ⭐⭐ |
| 后端 CI | 1-2h | ⭐⭐ |
| CD 自动部署 | 2-3h | ⭐⭐⭐ |
| 质量门禁 | 1h | ⭐ |
| **总计** | **~2 天** | |

## 学到什么
- CI/CD 概念和最佳实践
- GitHub Actions YAML 语法
- Docker 在 CI 中的应用
- 自动化测试策略
- 制品管理和版本发布流程
- DevOps 文化和工程效率
