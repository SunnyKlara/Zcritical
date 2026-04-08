# Logo上传调试指南

## 🎯 目的

这个调试界面可以帮助你查看Logo上传过程中的每一个步骤,找出失败的原因。

## 📱 如何使用

### 1. 导入调试界面

在你的主界面(如 `device_connect_screen.dart`)中添加导入:

```dart
import 'logo_upload_debug_screen.dart';
```

### 2. 添加菜单入口

在菜单中添加一个"Logo上传调试"选项:

```dart
ListTile(
  leading: const Icon(Icons.bug_report),
  title: const Text('Logo上传调试'),
  onTap: () {
    Navigator.pop(context); // 关闭抽屉
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LogoUploadDebugScreen(),
      ),
    );
  },
),
```

### 3. 使用调试界面

1. **选择图片**: 点击"选择图片"按钮
   - 界面会自动进行预处理和压缩
   - 日志区域会显示每个步骤的详细信息

2. **查看日志**: 
   - ✅ 绿色 = 成功
   - ❌ 红色 = 错误
   - 🚀 黄色 = 重要事件
   - 📊 蓝色 = 进度信息

3. **上传**: 点击"上传"按钮
   - 实时查看上传进度
   - 查看每个数据包的发送情况
   - 查看硬件端的响应

4. **复制日志**: 点击右上角的复制按钮
   - 可以将完整日志复制到剪贴板
   - 粘贴给我分析问题

## 📋 日志说明

### APP端日志

```
[时间] 📷 开始选择图片...
[时间] ✅ 图片已选择: /path/to/image.jpg
[时间] 📊 原始文件大小: 245.3 KB
[时间] 🔄 开始预处理图片...
[时间]    目标尺寸: 240x240
[时间]    目标格式: RGB565
[时间] ✅ 预处理完成
[时间]    数据大小: 112.5 KB
[时间] 🗜️ 开始RLE压缩...
[时间] ✅ 压缩完成
[时间]    压缩后: 54.5 KB
[时间]    压缩率: 48.4%
[时间]    CRC32: 0x12345678
[时间] 🚀 开始上传Logo
[时间] 📊 上传进度: 10.0%
[时间] 📊 上传进度: 20.0%
...
[时间] ✅ 上传成功!
```

### 硬件端日志(通过串口查看)

```
[LOGO] COMPRESSED START orig=115200 comp=55800 crc=305419896
[LOGO] Ready (compressed mode, 3488 packets)
[LOGO] Packet 100: 16 bytes decoded
[LOGO] Progress: 2% (seq=100/3488)
[LOGO] Packet 200: 16 bytes decoded
...
[LOGO] ═══════════════════════════════════
[LOGO] END received, starting verification
[LOGO] ═══════════════════════════════════
[LOGO] Size check: received=55800, expected=55800
[LOGO] ✓ Size check passed
[LOGO] Decompression check: decompressed=115200, expected=115200
[LOGO] ✓ Decompression size check passed
[LOGO] Starting CRC32 calculation...
[LOGO]   Address: 0x00000010
[LOGO]   Size: 115200 bytes
[LOGO] CRC32 verification:
[LOGO]   Expected:   0x12345678 (305419896)
[LOGO]   Calculated: 0x12345678 (305419896)
[LOGO] ✓ CRC32 check passed
[LOGO] ✅ Upload complete!
[LOGO] ═══════════════════════════════════
```

## 🔍 常见问题诊断

### 问题1: 上传失败,没有任何日志

**可能原因**: 蓝牙未连接
**解决方法**: 
1. 检查蓝牙是否已连接
2. 查看APP顶部是否显示"已连接"

### 问题2: 日志显示"LOGO_ERROR:NOT_READY"

**可能原因**: 硬件端未准备好接收
**解决方法**:
1. 检查硬件端串口日志
2. 确认收到"LOGO_READY"消息
3. 重新发送LOGO_START_COMPRESSED命令

### 问题3: 日志显示"LOGO_FAIL:SIZE"

**可能原因**: 数据包丢失
**解决方法**:
1. 检查蓝牙信号强度
2. 减慢发送速度
3. 查看哪些数据包没有收到ACK

### 问题4: 日志显示"LOGO_FAIL:CRC"

**可能原因**: 数据传输错误或解压缩错误
**解决方法**:
1. 对比APP端和硬件端的CRC32值
2. 检查解压缩是否正确
3. 查看硬件端的详细日志

### 问题5: 卡在某个进度不动

**可能原因**: 
- 蓝牙缓冲区满
- 硬件端处理慢
- 数据包重传失败

**解决方法**:
1. 查看最后一条日志的时间
2. 检查是否收到"LOGO_BUSY"消息
3. 等待或重新上传

## 📝 如何报告问题

当上传失败时,请提供以下信息:

1. **APP端日志**: 点击复制按钮,粘贴完整日志
2. **硬件端日志**: 通过串口工具复制完整日志
3. **图片信息**: 
   - 原始文件大小
   - 预处理后大小
   - 压缩后大小
   - 压缩率
4. **失败位置**: 在哪个步骤失败的
5. **错误信息**: 具体的错误消息

## 🛠️ 硬件端调试

### 查看串口日志

使用串口工具(如PuTTY, SecureCRT)连接到硬件:
- 波特率: 115200
- 数据位: 8
- 停止位: 1
- 校验: 无

### 关键日志点

1. **接收开始**: `[LOGO] COMPRESSED START`
2. **数据接收**: `[LOGO] Packet XXX`
3. **进度更新**: `[LOGO] Progress: XX%`
4. **接收完成**: `[LOGO] END received`
5. **校验过程**: `[LOGO] CRC32 verification`
6. **最终结果**: `[LOGO] ✅ Upload complete!`

## 💡 优化建议

如果上传经常失败,可以尝试:

1. **减小图片**: 使用更简单的图片,压缩率会更高
2. **靠近设备**: 减少蓝牙传输距离
3. **关闭其他蓝牙设备**: 减少干扰
4. **重启设备**: 清空缓冲区
5. **更新固件**: 确保使用最新版本

## 📞 技术支持

如果问题仍然无法解决,请联系技术支持并提供:
- 完整的APP端日志
- 完整的硬件端日志
- 测试图片
- 设备型号和固件版本
