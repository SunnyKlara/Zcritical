---
inclusion: auto
---

# 构建环境与编译指南

> AI 和用户共用的编译环境参考。每次需要编译固件时直接参考本文件。

## ESP-IDF 环境

| 项目 | 值 |
|------|-----|
| IDF 版本 | v5.3.5 |
| IDF 路径 | `C:\Espressif\frameworks\esp-idf-v5.3.5` |
| Export 脚本 | `C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1` |
| Python 环境 | `C:\Espressif\python_env\idf5.3_py3.14_env` |
| 工具链 | xtensa-esp-elf GCC 13.2.0 |
| 目标芯片 | ESP32（非 S3，注意！sdkconfig 里 IDF_TARGET=esp32） |

### 编译固件命令（PowerShell）

```powershell
# 一行搞定：加载环境 + 编译
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py build
```

### 增量编译（改了代码后）

```powershell
# 不需要 fullclean，直接 build 即可增量编译（只重编改动的 .c 文件）
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py build
```

### 全量编译（改了 sdkconfig.defaults 后）

```powershell
# 必须删除 sdkconfig + build 目录重新生成
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item sdkconfig -ErrorAction SilentlyContinue
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py build
```

### 烧录命令

```powershell
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py -p COM3 flash monitor
# COM 口号根据实际设备调整，用 idf.py -p COMx flash
```

## 编译时间优化

### 当前状况
- 全量编译（1338 个编译单元）：约 3-5 分钟
- 增量编译（改 1-2 个 .c 文件）：约 10-30 秒

### 优化策略

1. **永远用增量编译** — 改代码后直接 `idf.py build`，不要 clean
2. **ccache 已启用** — sdkconfig 里 `CCACHE_ENABLE=1`，重复编译会命中缓存
3. **只在改 sdkconfig.defaults 时才 fullclean** — 这是唯一需要全量重编的场景
4. **用 `idf.py app` 代替 `idf.py build`** — 跳过 bootloader 和 partition table 重编（节省 ~30s）
5. **并行编译** — ninja 默认已用所有 CPU 核心（16 线程）

### AI 编译策略

- 改了 .c/.h 文件 → 直接 `idf.py build`（增量）
- 改了 sdkconfig.defaults → 删 build + sdkconfig → `idf.py build`（全量）
- 只想验证编译通过 → `idf.py app`（跳过 bootloader）
- 需要看 flash 用量 → `idf.py size`
- 需要看 IRAM/DRAM 详情 → `idf.py size-components`

## 固件产物路径

| 文件 | 路径 | 用途 |
|------|------|------|
| 应用 bin | `ridewind-esp/build/ridewind-esp.bin` | OTA 升级用 |
| Bootloader | `ridewind-esp/build/bootloader/bootloader.bin` | 首次烧录用 |
| 分区表 | `ridewind-esp/build/partition_table/partition-table.bin` | 首次烧录用 |
| OTA 初始数据 | `ridewind-esp/build/ota_data_initial.bin` | 首次烧录用 |

### OTA 升级只需要 `ridewind-esp.bin`

APP 通过 BLE 传输这个文件即可，bootloader 和分区表不需要 OTA 更新。

## 固件发版命令序列

```powershell
# 1. 编译
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py build

# 2. 检查大小
C:\Espressif\frameworks\esp-idf-v5.3.5\export.ps1; idf.py size

# 3. 重命名 + 上传到 GitHub Release
copy ridewind-esp\build\ridewind-esp.bin ridewind-esp\build\ridewind-fw-vX.Y.Z.bin
gh release upload fw-vX.Y.Z "ridewind-esp\build\ridewind-fw-vX.Y.Z.bin" --clobber
```

## 网络问题解决方案

### GitHub 443 端口连接重置

**症状：** `git push` 或 `gh` 命令报 "Failed to connect to github.com port 443" 或 "Connection was reset"

**原因：** 国内网络环境对 GitHub 不稳定，DNS 污染或 GFW 干扰

**解决方案（按优先级）：**

1. **重试** — 等 10-30 秒再试，经常能通
2. **换 DNS** — 用 `8.8.8.8` 或 `223.5.5.5`
3. **Git 代理** — 如果有代理：
   ```powershell
   git config --global http.proxy http://127.0.0.1:7890
   git config --global https.proxy http://127.0.0.1:7890
   ```
4. **GitHub 镜像** — 用 `ghp.ci` 或 `hub.fastgit.xyz` 做 push mirror
5. **SSH 替代 HTTPS** — SSH 走 22 端口，有时比 443 稳定：
   ```powershell
   git remote set-url origin git@github.com:SunnyKlara/Zcritical.git
   ```

### AI 操作策略

- push 失败不阻塞工作流，先继续其他操作
- 所有 push 操作设置 timeout 45s
- 失败后等 30s 重试一次，再失败就跳过，告知用户手动 push
- 上传大文件（APK/bin）优先于 git push（gh release upload 走不同通道，有时更稳）

## IRAM 溢出问题

### 背景
ESP32 的 IRAM 只有 ~128KB，BT + WiFi + PSRAM 同时启用时很容易溢出。

### 当前配置（已解决溢出）
```
CONFIG_ESP_WIFI_IRAM_OPT=n          # WiFi 热路径移到 flash
CONFIG_ESP_WIFI_RX_IRAM_OPT=n       # WiFi RX 移到 flash
CONFIG_LWIP_IRAM_OPTIMIZATION=n     # LWIP 移到 flash
CONFIG_SPIRAM_CACHE_LIBTIME_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBENV_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBFILE_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBMISC_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBRAND_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBNUMPARSER_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBIO_IN_IRAM=n
CONFIG_SPIRAM_CACHE_LIBCHAR_IN_IRAM=n
```

### 如果未来再溢出
还可以关闭：`CONFIG_SPIRAM_CACHE_LIBMATH_IN_IRAM=n`、`CONFIG_SPIRAM_CACHE_LIBJMP_IN_IRAM=n`、`CONFIG_SPIRAM_CACHE_LIBSTR_IN_IRAM=n`、`CONFIG_SPIRAM_CACHE_LIBMEM_IN_IRAM=n`

### 影响评估
- WiFi 音频投射：从 IRAM 移到 flash 后理论延迟增加 ~1μs/次调用，实际不可感知
- BLE 通信：不受影响（BT controller 仍在 IRAM）
- 音频播放：不受影响（I2S DMA 不依赖这些函数）
