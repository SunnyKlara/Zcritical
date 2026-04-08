/// 🎨 Colorize Mode 节流器
/// 
/// 用于限制RGB调色时LED命令的发送频率，避免硬件端LCD刷新卡顿。
/// 默认最小间隔为50ms。
class ColorizeThrottler {
  /// 最小发送间隔（毫秒）
  static const int _minIntervalMs = 50;
  
  /// 上次发送时间
  DateTime _lastSendTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  /// 待发送的最新值（用于确保最终值被发送）
  Map<String, dynamic>? _pendingValue;
  
  /// 检查是否可以发送命令
  /// 
  /// 返回 true 表示可以发送，同时更新上次发送时间
  /// 返回 false 表示需要等待
  bool canSend() {
    final now = DateTime.now();
    if (now.difference(_lastSendTime).inMilliseconds >= _minIntervalMs) {
      _lastSendTime = now;
      return true;
    }
    return false;
  }
  
  /// 检查是否可以发送，如果不能则存储待发送值
  /// 
  /// [value] 待发送的值（可选，用于存储最新值）
  /// 返回 true 表示可以发送
  bool canSendWithPending(Map<String, dynamic>? value) {
    if (canSend()) {
      _pendingValue = null;
      return true;
    } else {
      _pendingValue = value;
      return false;
    }
  }
  
  /// 获取待发送的值
  Map<String, dynamic>? get pendingValue => _pendingValue;
  
  /// 清除待发送的值
  void clearPending() {
    _pendingValue = null;
  }
  
  /// 重置节流器
  /// 
  /// 将上次发送时间重置为0，允许立即发送下一条命令
  void reset() {
    _lastSendTime = DateTime.fromMillisecondsSinceEpoch(0);
    _pendingValue = null;
  }
  
  /// 获取距离下次可发送的剩余时间（毫秒）
  int get remainingMs {
    final elapsed = DateTime.now().difference(_lastSendTime).inMilliseconds;
    final remaining = _minIntervalMs - elapsed;
    return remaining > 0 ? remaining : 0;
  }
  
  /// 是否有待发送的值
  bool get hasPending => _pendingValue != null;
}
