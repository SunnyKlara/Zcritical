---
inclusion: manual
---

# 11. 容器化部署

## 是什么
用 Docker 将应用及其依赖打包成标准化容器，用 Docker Compose/K8s 编排多个容器协同工作。"在我机器上能跑"→"在任何机器上都能跑"。

## 为什么需要
- 环境一致性：开发/测试/生产用同一个镜像
- 快速部署：秒级启动，不用装依赖
- 隔离性：不同服务互不干扰
- 可扩展：需要更多实例？复制容器即可
- 回滚简单：切换到上一个镜像版本

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              容器化架构                               │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [开发环境] docker-compose.yml                      │
│   ├─ api-server (Node/Go)                           │
│   ├─ postgres:15                                    │
│   ├─ redis:7                                        │
│   ├─ nginx (反向代理)                               │
│   └─ emqx (MQTT Broker)                            │
│                                                      │
│  [生产环境] K8s / Docker Swarm / 单机 Compose       │
│   ├─ Deployment (多副本)                            │
│   ├─ Service (负载均衡)                             │
│   ├─ Ingress (域名路由)                             │
│   ├─ ConfigMap/Secret (配置/密钥)                   │
│   └─ PVC (持久化存储)                               │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 说明 |
|------|------|------|
| 容器运行时 | Docker | 行业标准 |
| 本地编排 | Docker Compose | 开发环境一键启动 |
| 生产编排 | K8s (阿里云 ACK) / 单机 Compose | 按规模选择 |
| 镜像仓库 | 阿里云 ACR / Docker Hub | 私有镜像存储 |
| 基础镜像 | node:20-alpine / golang:1.22-alpine | 最小化镜像 |
| 健康检查 | HEALTHCHECK / K8s Probe | 自动重启不健康容器 |

## 实现步骤

### Phase 1：Dockerfile 编写（2h）
1. 多阶段构建（Multi-stage）：编译阶段 + 运行阶段
2. 最小化镜像：alpine 基础，只包含运行时依赖
3. 非 root 用户运行（安全）
4. .dockerignore 排除不需要的文件

### Phase 2：Docker Compose 开发环境（2h）
5. 一键启动所有服务：`docker compose up`
6. 数据持久化：volumes 挂载 PostgreSQL 数据
7. 热重载：代码目录挂载到容器内
8. 环境变量：.env 文件管理

### Phase 3：生产部署（2-3h）
9. 镜像推送到私有仓库
10. 服务器拉取镜像 + 启动
11. Nginx 反向代理 + SSL
12. 日志收集：容器日志 → 文件/ELK

### Phase 4：K8s 进阶（3-4h，可选）
13. Deployment + Service + Ingress
14. 滚动更新策略（零停机）
15. HPA 自动扩缩容
16. ConfigMap/Secret 管理配置

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| 镜像太大 | 拉取慢，部署慢 | 多阶段构建 + alpine |
| 数据丢失 | 容器重启后数据没了 | Volume 持久化 |
| 端口冲突 | 多服务端口撞车 | Compose 网络隔离 |
| 时区问题 | 日志时间不对 | 设置 TZ 环境变量 |
| DNS 解析 | 容器间通信用服务名 | Compose 自动 DNS |
| 资源限制 | 容器吃光内存 | 设置 memory limit |

## 与 RideWind 的关系
- 当前状态：无后端，无容器化需求
- 优先级：P4（后端开发时同步做）
- 起步：Docker Compose 本地开发环境（一键启动 PG+Redis+API）
- 生产：初期单机 Compose 够用，千级用户后考虑 K8s

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| Dockerfile | 2h | ⭐⭐ |
| Docker Compose | 2h | ⭐⭐ |
| 生产部署 | 2-3h | ⭐⭐⭐ |
| K8s（可选） | 3-4h | ⭐⭐⭐⭐ |
| **总计** | **~2 天** | |

## 学到什么
- Docker 核心概念（镜像/容器/网络/卷）
- Dockerfile 最佳实践
- 容器编排（Compose/K8s）
- 微服务部署模式
- 生产环境运维基础
- 云原生思维
