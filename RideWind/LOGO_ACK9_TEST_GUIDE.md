# Logo传输ACK:9问题修复测试指南

## 修复内容

已修复滑动窗口协议中的关键bug：
1. ✅ 在`slideWindow`方法中添加`nextSeqNum`回退保护
2. ✅ 在传输循环开头添加双重检查
3. ✅ 添加详细的调试日志

## 测试步骤

### 1. 重新编译APP

```bash
cd RideWind
flutter clean
flutter pub get
flutter run
```

### 2. 查看修复日志

修复后，你应该能在日志中看到：

**正常情况（无回退）**：
```
[LOGO_UPLOAD] 📤 发送包 0/2965
[LOGO_UPLOAD] 📤 发送包 1/2965
...
[LOGO_UPLOAD] 📤 发送包 9/2965
[LOGO_UPLOAD] ⏳ 等待ACK (seq=9)...
[LOGO_UPLOAD] 📥 收到: LOGO_ACK:9
[IMPORTANT] 收到ACK:9 (sendBase=0, nextSeqNum=10)
[IMPORTANT] 窗口滑动后: sendBase=10, nextSeqNum=10
[LOGO_UPLOAD] 📤 发送包 10/2965  ← 正确！
[LOGO_UPLOAD] 📤 发送包 11/2965
```

**如果检测到回退（已自动修正）**：
```
[WINDOW] ⚠️ nextSeqNum回退修正: 0→10
[IMPORTANT] ⚠️ 检测到nextSeqNum异常: 0 < 10，已修正
```

### 3. 验证传输流程

#### 预期行为：
1. 发送包 0-9（10个包）
2. 收到 `LOGO_ACK:9`
3. **立即发送包 10**（不是包0）
4. 继续发送包 11-19
5. 收到 `LOGO_ACK:19`
6. 继续...

#### 检查点：
- [ ] 包序号是否连续递增？
- [ ] 收到ACK后是否继续发送下一个包？
- [ ] 是否出现重复发送已确认的包？
- [ ] 进度条是否正常增长？

### 4. 完整测试场景

#### 场景A：正常传输
1. 选择一张图片
2. 点击"上传Logo"
3. 观察日志和进度条
4. 确认传输完成

**预期结果**：
- 传输时间：40-60秒
- 无包序号回退
- 进度条平滑增长
- 最终显示"上传成功"

#### 场景B：弱信号环境
1. 将手机移远一些（模拟弱信号）
2. 上传Logo
3. 观察是否有丢包和重传

**预期结果**：
- 可能出现超时和重传
- 但不应该出现包序号回退到0
- 最终仍能完成传输

#### 场景C：中断恢复
1. 开始传输
2. 传输到50%时关闭APP
3. 重新打开APP
4. 再次上传同一张图片

**预期结果**：
- 如果支持断点续传，应该从中断处继续
- 如果不支持，应该重新开始但不出错

## 调试日志过滤

### 查看所有Logo相关日志
```bash
adb logcat | grep -E "LOGO_UPLOAD|WINDOW|IMPORTANT"
```

### 只看关键事件
```bash
adb logcat | grep -E "收到ACK|窗口滑动|发送包"
```

### 检测异常
```bash
adb logcat | grep -E "回退|异常|错误|失败"
```

## 问题排查

### 如果仍然卡在ACK:9

**检查1：确认代码已更新**
```bash
# 查看slideWindow方法
grep -A 10 "void slideWindow" RideWind/lib/services/logo_transmission_manager.dart
```

应该看到：
```dart
if (nextSeqNum < sendBase) {
  print('[WINDOW] ⚠️ nextSeqNum回退修正: $nextSeqNum→$sendBase');
  nextSeqNum = sendBase;
}
```

**检查2：查看日志**
- 是否看到"收到ACK:9"？
- 是否看到"窗口滑动后"？
- nextSeqNum的值是多少？

**检查3：硬件端**
- 硬件是否正确发送了ACK:9？
- 硬件是否在处理缓冲区？
- 查看硬件串口输出

### 如果出现其他错误

**错误：LOGO_BUSY频繁出现**
- 原因：硬件缓冲区满
- 解决：增大`PACKET_BUFFER_SIZE`或加快`Logo_ProcessBuffer`处理

**错误：CRC校验失败**
- 原因：数据传输错误
- 解决：检查丢包率，可能需要降低发送速率

**错误：超时**
- 原因：蓝牙连接不稳定
- 解决：靠近设备，减少干扰

## 性能指标

### 修复前（有bug）
- ❌ 卡在ACK:9
- ❌ 包序号回退到0
- ❌ 传输无法完成

### 修复后（预期）
- ✅ 包序号连续递增
- ✅ 窗口正常滑动
- ✅ 传输顺利完成
- ✅ 传输时间：40-60秒
- ✅ 丢包率：<5%

## 报告问题

如果修复后仍有问题，请提供：

1. **完整日志**
```bash
adb logcat > logo_test.log
# 然后上传 logo_test.log
```

2. **APP截图**
- 显示进度条和状态
- 显示调试信息框

3. **硬件串口输出**
- 从Keil或串口助手复制

4. **测试环境**
- 手机型号
- Android版本
- 蓝牙距离
- 图片大小

## 下一步优化

修复完成后，可以考虑：
1. 移除调试日志（提高性能）
2. 优化窗口大小和发送速率
3. 添加更智能的拥塞控制
4. 实现完整的断点续传

## 总结

这个修复解决了滑动窗口协议中的一个关键bug：**窗口滑动时nextSeqNum没有正确更新，导致重新发送已确认的包**。

修复方法：
- 在`slideWindow`中确保`nextSeqNum >= sendBase`
- 在传输循环中添加双重检查
- 添加详细日志帮助调试

这是一个简单但关键的修复，应该能彻底解决ACK:9卡住的问题。
