# Logo传输卡在ACK:9的问题分析与修复

## 问题现象

从截图可以看到：
```
LOGO_DATA:7:00210021...
LOGO_DATA:8:00210021...
LOGO_DATA:9:01890147
硬件响应: LOGO_ACK:9
LOGO_DATA:0:00000000  ← 错误！应该发送包10，却发送了包0
```

## 根本原因

**滑动窗口逻辑错误**：当收到`LOGO_ACK:9`后，`slideWindow(9)`被调用，将`sendBase`设置为10，但是`nextSeqNum`没有正确更新，导致重新发送已经发送过的包。

### 代码分析

```dart
// 当前的传输循环
Future<void> _transmitWithSlidingWindow() async {
  while (window.sendBase < window.totalPackets) {
    // 1. 发送新包 (nextSeqNum从0开始)
    while (!window.isFull && window.nextSeqNum < window.totalPackets) {
      await _sendPacket(window.nextSeqNum);
      window.nextSeqNum++;  // 0→1→2→...→10
      await rateController.waitBeforeSend();
    }

    // 2. 等待ACK
    final response = await _waitForResponse(...);

    // 3. 处理ACK:9
    if (response != 'TIMEOUT') {
      _handleAckResponse(response);  // 调用slideWindow(9)
      // slideWindow(9)将sendBase设置为10
      // 但nextSeqNum仍然是10
    }

    // 4. 下一轮循环
    // sendBase=10, nextSeqNum=10
    // 窗口不满，继续发送
    // 但是！如果nextSeqNum被错误重置，就会重新发送包0
  }
}
```

### 问题定位

查看`slideWindow`方法：
```dart
void slideWindow(int ackedSeq) {
  for (int seq = sendBase; seq <= ackedSeq; seq++) {
    ackedPackets.add(seq);
    inFlightPackets.remove(seq);
    lostPackets.remove(seq);
  }
  sendBase = ackedSeq + 1;  // sendBase = 10
  // ❌ 没有更新nextSeqNum！
}
```

**问题**：`slideWindow`只更新了`sendBase`，但没有确保`nextSeqNum`至少等于`sendBase`。

## 修复方案

### 方案1：在slideWindow中同步nextSeqNum（推荐）

```dart
void slideWindow(int ackedSeq) {
  for (int seq = sendBase; seq <= ackedSeq; seq++) {
    ackedPackets.add(seq);
    inFlightPackets.remove(seq);
    lostPackets.remove(seq);
  }
  sendBase = ackedSeq + 1;
  
  // ✅ 确保nextSeqNum不会回退
  if (nextSeqNum < sendBase) {
    nextSeqNum = sendBase;
  }
}
```

### 方案2：在传输循环中检查

```dart
Future<void> _transmitWithSlidingWindow() async {
  while (window.sendBase < window.totalPackets) {
    // ✅ 确保nextSeqNum不会小于sendBase
    if (window.nextSeqNum < window.sendBase) {
      window.nextSeqNum = window.sendBase;
    }
    
    // 发送窗口内的新包
    while (!window.isFull && window.nextSeqNum < window.totalPackets) {
      await _sendPacket(window.nextSeqNum);
      window.nextSeqNum++;
      await rateController.waitBeforeSend();
    }
    
    // ... 其余逻辑
  }
}
```

### 方案3：组合方案（最安全）

同时应用方案1和方案2，双重保护。

## 为什么会出现这个问题？

可能的原因：
1. **初始化问题**：`nextSeqNum`在某个地方被错误重置为0
2. **重传逻辑**：重传丢失包时可能影响了`nextSeqNum`
3. **窗口滑动**：`slideWindow`没有正确维护`nextSeqNum`的不变性

## 测试验证

修复后，应该看到：
```
LOGO_DATA:7:...
LOGO_DATA:8:...
LOGO_DATA:9:...
硬件响应: LOGO_ACK:9
LOGO_DATA:10:...  ← 正确！
LOGO_DATA:11:...
LOGO_DATA:12:...
```

## 实施步骤

1. 修改`SlidingWindow.slideWindow`方法
2. 在`_transmitWithSlidingWindow`开头添加检查
3. 添加调试日志验证修复
4. 测试完整传输流程

## 额外建议

### 添加断言保护

```dart
void slideWindow(int ackedSeq) {
  assert(ackedSeq >= sendBase, 'ACK序号不能小于sendBase');
  assert(ackedSeq < totalPackets, 'ACK序号超出范围');
  
  for (int seq = sendBase; seq <= ackedSeq; seq++) {
    ackedPackets.add(seq);
    inFlightPackets.remove(seq);
    lostPackets.remove(seq);
  }
  sendBase = ackedSeq + 1;
  
  // 确保nextSeqNum不会回退
  if (nextSeqNum < sendBase) {
    nextSeqNum = sendBase;
  }
}
```

### 添加调试日志

```dart
void slideWindow(int ackedSeq) {
  print('[WINDOW] slideWindow: ackedSeq=$ackedSeq, sendBase=$sendBase→${ackedSeq + 1}, nextSeqNum=$nextSeqNum');
  
  for (int seq = sendBase; seq <= ackedSeq; seq++) {
    ackedPackets.add(seq);
    inFlightPackets.remove(seq);
    lostPackets.remove(seq);
  }
  sendBase = ackedSeq + 1;
  
  if (nextSeqNum < sendBase) {
    print('[WINDOW] ⚠️ nextSeqNum回退: $nextSeqNum→$sendBase');
    nextSeqNum = sendBase;
  }
  
  print('[WINDOW] slideWindow完成: sendBase=$sendBase, nextSeqNum=$nextSeqNum');
}
```

## 总结

这是一个经典的滑动窗口协议实现bug：**窗口滑动时没有正确维护发送序号的单调性**。修复方法很简单，但影响很大——这个bug会导致传输完全卡住。
