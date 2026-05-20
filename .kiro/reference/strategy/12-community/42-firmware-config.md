---
inclusion: manual
---

# 42. 固件配置系统

## 是什么
让用户通过 App 自定义固件行为参数（加速曲线、灵敏度、默认模式），无需重新编译固件。设备端通过 NVS 持久化存储参数，App 通过 BLE 协议读写配置，实现"一个固件，千人千面"的个性化体验。

## 为什么需要
- 不同用户有不同偏好：有人喜欢灵敏响应，有人喜欢平滑过渡
- 避免为每个用户编译不同固件：一套固件 + 参数化 = 无限可能
- 产品个性化：用户调出"自己的"设备感觉，增加情感连接
- 快速迭代：新增可调参数不需要 OTA，只需 App 更新
- 售后便利：远程调整参数解决"体验不好"类问题

## 技术架构
```
┌─────────────────────────────────────────────────────┐
│              固件配置系统架构                         │
├─────────────────────────────────────────────────────┤
│                                                      │
│  [App 端]                                            │
│   配置界面 → 参数调节（滑块/选择器/开关）         │
│   实时预览 → BLE 发送 → 设备即时生效              │
│       │                                              │
│       ▼                                              │
│  [BLE 配置协议]                                      │
│   CMD_CONFIG_READ:  读取当前配置                    │
│   CMD_CONFIG_WRITE: 写入新配置                      │
│   CMD_CONFIG_RESET: 恢复出厂默认                    │
│       │                                              │
│       ▼                                              │
│  [设备端]                                            │
│   ┌─────────────────────────────────────────┐       │
│   │  参数定义表 (config_defs[])              │       │
│   │  ├─ key: "led_speed"                    │       │
│   │  ├─ type: UINT8                         │       │
│   │  ├─ min: 1, max: 100, default: 50      │       │
│   │  └─ nvs_key: "cfg.led_spd"             │       │
│   └─────────────────────────────────────────┘       │
│       │                                              │
│       ▼                                              │
│  [NVS 存储]                                          │
│   持久化保存 → 重启后自动加载                      │
│   恢复出厂 → 清除所有自定义，回到默认值           │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## 技术栈选型
| 组件 | 技术 | 说明 |
|------|------|------|
| 参数存储 | ESP-IDF NVS (Non-Volatile Storage) | 掉电不丢失，KV 存储 |
| 配置协议 | 自定义 BLE 命令 | 复用已有协议框架 |
| 参数校验 | 设备端范围检查 | 防止非法值写入 |
| App UI | Flutter 滑块/选择器 | 直观的参数调节 |
| 配置同步 | 云端备份（可选） | 换手机不丢配置 |
| 参数定义 | C 结构体 + JSON 描述 | 设备端执行，App 端展示 |

## 实现步骤

### Phase 1：参数定义框架（2h）
1. 设备端参数定义：
   ```c
   typedef enum {
       CFG_TYPE_UINT8,
       CFG_TYPE_UINT16,
       CFG_TYPE_INT8,
       CFG_TYPE_BOOL,
       CFG_TYPE_ENUM,
   } config_type_t;

   typedef struct {
       const char *key;
       const char *nvs_key;
       config_type_t type;
       int32_t min_val;
       int32_t max_val;
       int32_t default_val;
       const char *name_zh;
       const char *category;
   } config_def_t;

   static const config_def_t config_defs[] = {
       {"led_speed",     "cfg.led_spd",  CFG_TYPE_UINT8,  1, 100, 50,
        "灯效速度", "led"},
       {"led_brightness","cfg.led_brt",  CFG_TYPE_UINT8,  0, 100, 80,
        "LED亮度", "led"},
       {"audio_volume",  "cfg.aud_vol",  CFG_TYPE_UINT8,  0, 100, 70,
        "音量", "audio"},
       {"accel_curve",   "cfg.acc_crv",  CFG_TYPE_ENUM,   0, 3,   1,
        "加速曲线", "motor"},
       {"auto_sleep_min","cfg.slp_min",  CFG_TYPE_UINT16, 0, 60,  5,
        "自动休眠(分钟)", "power"},
       {"boot_preset",   "cfg.boot_pre", CFG_TYPE_UINT8,  0, 9,   0,
        "开机预设", "general"},
   };
   ```
2. 参数读写 API：
   ```c
   int32_t config_get(const char *key);
   esp_err_t config_set(const char *key, int32_t value);
   esp_err_t config_reset_all(void);
   esp_err_t config_load_all(void);
   ```
3. 启动时加载：`app_main()` 中调用 `config_load_all()`

### Phase 2：BLE 配置协议（2h）
4. 协议命令设计：
   ```
   CMD_CONFIG_GET_ALL:   → 返回所有参数当前值
   CMD_CONFIG_GET:       {key} → 返回单个参数值
   CMD_CONFIG_SET:       {key, value} → 设置参数，立即生效
   CMD_CONFIG_RESET:     → 恢复所有参数为默认值
   CMD_CONFIG_GET_DEFS:  → 返回参数定义（类型/范围/默认值）
   ```
5. 参数校验：设备端收到 SET 命令 → 检查范围 → 合法则写入 NVS + 应用
6. 批量设置：一次命令设置多个参数（减少 BLE 往返）

### Phase 3：App 配置界面（2-3h）
7. 配置页面设计：
   - 分类 Tab：灯效 / 音频 / 电机 / 电源 / 通用
   - 每个参数：名称 + 当前值 + 滑块/选择器 + 默认值标记
   - 实时生效：滑动即发送 BLE 命令
8. 参数类型对应 UI：
   - UINT8/UINT16 → 滑块 (Slider)
   - BOOL → 开关 (Switch)
   - ENUM → 下拉选择 (Dropdown)
9. 恢复默认：长按参数 → "恢复默认" / 全局"恢复出厂设置"

### Phase 4：配置持久化与同步（1-2h）
10. NVS 存储策略：
    - 每次 SET 立即写入 NVS（掉电安全）
    - 启动时批量读取所有配置到 RAM
    - NVS 分区独立于 OTA 分区
11. 云端备份（可选）：
    - App 连接设备时读取全部配置 → 上传云端
    - 换手机/重装 App → 从云端恢复配置
12. 配置导出/导入：JSON 格式导出 → 分享给其他用户

### Phase 5：高级功能（1h）
13. 配置预设：保存多套配置方案，一键切换
14. 条件触发：特定条件自动切换配置
15. 参数联动：修改一个参数时建议关联参数调整

## 关键坑点
| 坑 | 后果 | 解法 |
|----|------|------|
| NVS 写入寿命 | Flash 擦写次数有限 | 防抖：滑块松手后才写入 |
| 参数冲突 | 两个参数组合导致异常 | 定义参数间约束规则 |
| OTA 后参数失效 | 新固件改了参数定义 | 版本兼容：新增用默认值，删除的忽略 |
| BLE 延迟 | 滑块拖动时设备响应慢 | 节流发送（100ms 间隔） |
| 恢复出厂误触 | 用户配置全丢 | 二次确认 + 恢复前自动备份 |
| 参数太多 | 用户不知道调什么 | 分级：基础可见，高级隐藏 |

## 与 RideWind 的关系
- 当前状态：部分参数可通过 BLE 设置（亮度/颜色/音量），但无统一配置框架
- 优先级：P3（扩展更多可配置参数，统一管理）
- 已有基础：`app_state.c` 中的状态管理 + NVS 读写
- 扩展方向：加速曲线/灵敏度/自动休眠/开机预设/灯效速度

## 预计工作量
| 模块 | 时间 | 难度 |
|------|------|------|
| 参数定义框架 | 2h | ⭐⭐ |
| BLE 配置协议 | 2h | ⭐⭐ |
| App 配置界面 | 2-3h | ⭐⭐ |
| NVS 持久化 | 1h | ⭐⭐ |
| 云端同步（可选） | 1-2h | ⭐⭐ |
| **总计** | **~1.5 天** | |

## 学到什么
- 嵌入式参数化设计（配置与代码分离）
- NVS 存储最佳实践（寿命/性能/安全）
- BLE 实时交互协议设计
- 用户个性化产品设计思维
- 配置版本兼容性管理
- 从"硬编码"到"可配置"的工程化思维
