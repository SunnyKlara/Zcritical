---
inclusion: auto
---

# 品牌规则 — Zcritical（不可违反）

## 核心规则

**RideWind 品牌已退出，项目全面切换到 Zcritical 品牌。**

任何面向用户的地方（APP UI、包名、文件名、下载链接、文档标题、BLE 广播名等）
**不得出现 "ridewind" / "RideWind" / "ride wind" 字样**。

## 品牌映射

| 旧 | 新 | 备注 |
|----|-----|------|
| RideWind | Zcritical T1 | 产品全名 |
| ridewind | zcritical | 代码/包名/URL 中的小写标识 |
| com.example.ridewind | com.zcritical.t1 | Android 包名 |
| Critical（APP 内 title） | Zcritical T1 | APP 显示名 |
| ridewind-vX.X.X.apk | zcritical-t1-vX.X.X.apk | APK 文件名 |
| BLE 广播名 "Critical_T1" | 保持 "Critical_T1" | 硬件端暂不改（需烧录） |

## 替换范围

需要替换的位置（按优先级）：
1. `android/app/build.gradle.kts` — applicationId
2. `android/app/src/main/kotlin/com/example/ridewind/` — 包目录路径
3. `pubspec.yaml` — name 字段
4. `app_version.json` — download_url
5. APP 内所有用户可见文字
6. GitHub Release 文件名
7. 服务器上的 APK 文件名和路径
8. iOS Bundle Identifier（后续）

## 例外

- `.kiro/` 内部文档可以用 ridewind 指代历史（如 "原 RideWind 品牌"）
- `ridewind-esp/` 目录名暂时保留（纯内部开发目录，不面向用户）
- Git 历史中的旧 commit message 不需要修改

## AI 行为

- 写新代码/文档时，默认使用 zcritical / Zcritical T1
- 遇到旧的 ridewind 引用时，主动提醒并修正
- 不要反复询问品牌名称，直接按本文件执行
