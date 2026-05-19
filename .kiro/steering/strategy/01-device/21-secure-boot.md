# 21. 固件安全启动（Secure Boot）

## 是什么

从芯片上电到应用代码执行，每一级都验证下一级的签名，形成信任链。未经签名的代码无法在设备上运行。

## 为什么需要

- 防止竞争对手/黑客提取固件逆向
- 防止用户刷入非官方固件绕过付费功能
- 防止供应链攻击（工厂偷换固件）
- 合规要求（CE/FCC 对无线设备固件完整性有要求）
- OTA 的安全基础——没有 Secure Boot，OTA 签名验证形同虚设

## 技术架构

```
┌─────────────────────────────────────────────┐
│              ESP32-S3 启动链                  │
├─────────────────────────────────────────────┤
│  ROM Bootloader (芯片内置，不可改)            │
│       │ 验证签名                             │
│       ▼                                      │
│  2nd Stage Bootloader (flash, 签名)          │
│       │ 验证签名                             │
│       ▼                                      │
│  Application (ota_0 或 ota_1, 签名)          │
└─────────────────────────────────────────────┘

eFuse 区域（一次性烧写，不可逆）：
  - KEY_BLOCK: 存储公钥摘要 (SHA-256)
  - SECURE_BOOT_EN: 使能位
  - JTAG_DISABLE: 关闭调试口
```

## 技术栈选型

| 组件 | 技术 | 说明 |
|------|------|------|
| Secure Boot 版本 | V2 (RSA-PSS 3072) | ESP32-S3 推荐，支持多密钥 |
| Flash 加密 | AES-256-XTS | 防止直接读取 flash 内容 |
| 密钥生成 | `espsecure.py generate_signing_key` | RSA-3072 密钥对 |
| 签名工具 | `espsecure.py sign_data` | 构建时自动签名 |
| eFuse 烧写 | `espefuse.py` | 生产环境一次性操作 |
| 密钥存储 | AWS KMS / 阿里云密钥管理 | 私钥永不落地 |

## 实现步骤

### Phase 1：开发环境准备（1h）

1. **生成密钥对**
   ```bash
   espsecure.py generate_signing_key --version 2 secure_boot_signing_key.pem
   # 备份私钥到安全位置（U盘锁柜 / KMS）
   # 提取公钥
   espsecure.py extract_public_key --keyfile secure_boot_signing_key.pem pub_key.pem
   ```

2. **sdkconfig 配置**
   ```
   CONFIG_SECURE_BOOT=y
   CONFIG_SECURE_BOOT_V2_ENABLED=y
   CONFIG_SECURE_BOOT_SIGNING_KEY="secure_boot_signing_key.pem"
   CONFIG_SECURE_FLASH_ENC_ENABLED=y
   CONFIG_SECURE_FLASH_ENCRYPTION_MODE_DEVELOPMENT=y  # 开发阶段
   ```

3. **开发模式 vs 生产模式**
   - 开发模式：允许重新烧写（eFuse 不锁死）
   - 生产模式：eFuse 永久锁定，不可逆

### Phase 2：Flash 加密（1-2h）

4. **加密配置**
   - 首次启动时芯片自动生成 AES 密钥并烧入 eFuse
   - 后续所有 flash 读写自动加解密（对应用透明）
   - NVS 分区需要单独处理（`nvs_flash_secure_init`）

5. **加密对 OTA 的影响**
   - OTA 写入的数据会被自动加密存储
   - 固件 bin 文件本身不需要预加密（硬件透明处理）
   - 但 `esptool.py` 烧录时需要加密模式：`--encrypt`

### Phase 3：生产烧录流程（1h）

6. **产线流程设计**
   ```
   1. 首次烧录（开发固件，Secure Boot 开发模式）
   2. 功能验证通过
   3. 切换到生产模式 sdkconfig
   4. 烧录生产固件（自动烧写 eFuse）
   5. 验证 Secure Boot 生效（尝试烧录未签名固件，应失败）
   6. 出厂
   ```

7. **多密钥支持**
   - Secure Boot V2 支持最多 3 个密钥槽
   - 用途：主密钥 + 备份密钥 + 紧急恢复密钥
   - 可以吊销单个密钥（烧 eFuse 位）

### Phase 4：CI/CD 集成（1h）

8. **自动签名流水线**
   ```yaml
   # GitHub Actions 示例
   - name: Sign firmware
     env:
       SIGNING_KEY: ${{ secrets.SECURE_BOOT_KEY }}
     run: |
       echo "$SIGNING_KEY" > /tmp/key.pem
       espsecure.py sign_data --version 2 --keyfile /tmp/key.pem build/app.bin
       rm /tmp/key.pem
   ```

## 关键坑点

| 坑 | 后果 | 解法 |
|----|------|------|
| eFuse 烧错 | 设备变砖，不可逆 | 先在开发模式验证，生产前三重确认 |
| 私钥丢失 | 永远无法更新固件 | 多备份 + KMS + 多密钥槽 |
| Flash 加密 + OTA | 加密模式下 OTA 写入需要特殊处理 | ESP-IDF 5.x 已自动处理 |
| NVS 加密 | 普通 NVS API 读不出数据 | 用 `nvs_flash_secure_init` |
| 开发效率下降 | 每次烧录都要签名 | 开发阶段用开发模式，CI 才用生产模式 |
| JTAG 关闭 | 无法硬件调试 | 生产前确保固件稳定，保留串口日志 |
| 降级攻击 | 刷回有漏洞的旧版本 | 固件版本号写入 eFuse（anti-rollback） |

## 与 RideWind 的关系

- 当前状态：未启用任何安全特性，flash 可被任意读取
- 优先级：上架前 P3（OTA 做完后紧接着做）
- 依赖：必须先完成 OTA 分区改造（#1），Secure Boot 需要 ota 分区布局
- 风险：启用后开发流程变复杂，建议产品稳定后再锁死

## 预计工作量

| 模块 | 时间 | 难度 |
|------|------|------|
| 密钥生成 + sdkconfig | 1h | ⭐ |
| 开发模式验证 | 1h | ⭐⭐ |
| Flash 加密集成 | 1-2h | ⭐⭐⭐ |
| 生产烧录流程文档 | 1h | ⭐ |
| CI/CD 签名集成 | 1h | ⭐⭐ |
| **总计** | **~1 天** | |

## 学到什么

- 硬件信任根（Root of Trust）概念
- eFuse 一次性可编程存储器
- 非对称加密在嵌入式中的应用
- 密钥生命周期管理
- 安全与开发效率的平衡
- 产线安全烧录流程设计
