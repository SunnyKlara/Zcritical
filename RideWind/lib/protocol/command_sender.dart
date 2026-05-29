import 'dart:async';
import '../services/ble_service.dart';

/// 命令发送器 — 封装 BLE 命令发送 + 重试逻辑
///
/// 职责：
/// - 构造协议命令字符串（每个命令一个方法）
/// - 通过 BLEService 发送（内部 _send 自动追加 \n）
/// - 带超时重试的可靠发送（sendWithRetry）
/// - 参数校验（范围检查）
///
/// 由 BluetoothProvider 持有，Screen 不直接访问。
/// 架构参考: CONTINUATION_GUIDE.md 第三节
class CommandSender {
  final BLEService _ble;

  /// 等待前缀匹配的请求队列（用于 sendWithRetry）
  final Map<String, Completer<String>> _pendingPrefixRequests = {};

  CommandSender(this._ble);

  // ═══════════════════════════════════════════════════════════════
  //  风扇控制
  // ═══════════════════════════════════════════════════════════════

  /// FAN:speed\n (0-100)
  Future<bool> setFanSpeed(int speed) async {
    if (speed < 0 || speed > 100) return false;
    return _send('FAN:$speed');
  }

  /// GET:FAN\n
  Future<bool> getFanSpeed() => _send('GET:FAN');

  /// SPEED:value\n (0-999, display value matching speed_max_display)
  Future<bool> setRunningSpeed(int speed) => _send('SPEED:$speed');

  /// UNIT:x\n (0=km/h, 1=mph)
  Future<bool> setSpeedUnit(int unit) => _send('UNIT:$unit');

  /// THROTTLE:x\n (0=关闭, 1=开启)
  Future<bool> setThrottleMode(bool enable) =>
      _send('THROTTLE:${enable ? 1 : 0}');

  // ═══════════════════════════════════════════════════════════════
  //  雾化器控制
  // ═══════════════════════════════════════════════════════════════

  /// WUHUA:x\n (0=关闭, 1=开启)
  Future<bool> setWuhuaqiStatus(bool enable) =>
      _send('WUHUA:${enable ? 1 : 0}');

  /// GET:WUHUA\n
  Future<bool> getWuhuaqiStatus() => _send('GET:WUHUA');

  // ═══════════════════════════════════════════════════════════════
  //  LED 控制
  // ═══════════════════════════════════════════════════════════════

  /// PRESET:index\n (1-14)
  Future<bool> setLEDPreset(int index) {
    if (index < 1 || index > 14) return Future.value(false);
    return _send('PRESET:$index');
  }

  /// GET:PRESET\n
  Future<bool> queryCurrentPreset() => _send('GET:PRESET');

  /// LED:strip:r:g:b\n (strip 1-4, rgb 0-255)
  Future<bool> setLEDColor(int strip, int r, int g, int b) {
    if (strip < 1 || strip > 4) return Future.value(false);
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      return Future.value(false);
    }
    return _send('LED:$strip:$r:$g:$b');
  }

  /// BRIGHT:value\n (0-100)
  Future<bool> setBrightness(int brightness) {
    if (brightness < 0 || brightness > 100) return Future.value(false);
    return _send('BRIGHT:$brightness');
  }

  /// TREAD:gear\n (0-20) — 跑步机档位
  Future<bool> setTreadSpeed(int gear) {
    if (gear < 0 || gear > 20) return Future.value(false);
    return _send('TREAD:$gear');
  }

  /// STREAMLIGHT:x\n (0=关闭, 1=开启)
  Future<bool> setStreamlightMode(bool enable) =>
      _send('STREAMLIGHT:${enable ? 1 : 0}');

  /// THROTTLE_FX:mode\n (0-8, 灯光模式)
  Future<bool> setThrottleEffect(int mode) {
    if (mode < 0 || mode > 8) return Future.value(false);
    return _send('THROTTLE_FX:$mode');
  }

  /// GET:STREAMLIGHT\n
  Future<bool> getStreamlightStatus() => _send('GET:STREAMLIGHT');

  // ═══════════════════════════════════════════════════════════════
  //  LCD / UI 控制
  // ═══════════════════════════════════════════════════════════════

  /// LCD:x\n (0=熄屏, 1=开屏)
  Future<bool> setLCDStatus(bool enable) =>
      _send('LCD:${enable ? 1 : 0}');

  /// UI:index\n (0=开机动画, 1=调速, 2=配色预设, 3=RGB调色, 4=亮度)
  Future<bool> setHardwareUI(int uiIndex) => _send('UI:$uiIndex');

  // ═══════════════════════════════════════════════════════════════
  //  音量控制（设备感知）
  // ═══════════════════════════════════════════════════════════════

  /// VOL:xx\n (ESP32) 或 AUDIO:VOL:xx\n (F4)
  Future<bool> setVolume(int volume) {
    if (volume < 0 || volume > 100) return Future.value(false);
    // ESP32 统一使用 VOL 命令
    return _send('VOL:$volume');
  }

  /// GET:VOL\n
  Future<bool> getVolume() => _send('GET:VOL');

  // ═══════════════════════════════════════════════════════════════
  //  WiFi 音频投射
  // ═══════════════════════════════════════════════════════════════

  /// WIFI:ssid:password\n
  Future<bool> sendWifiCredentials(String ssid, String password) =>
      _send('WIFI:$ssid:$password');

  // ═══════════════════════════════════════════════════════════════
  //  状态查询
  // ═══════════════════════════════════════════════════════════════

  /// GET:ALL\n
  Future<bool> getAllStatus() => _send('GET:ALL');

  /// GET:LOGO_SLOTS\n
  Future<bool> getLogoSlots() => _send('GET:LOGO_SLOTS');

  // ═══════════════════════════════════════════════════════════════
  //  通用发送
  // ═══════════════════════════════════════════════════════════════

  /// 发送原始命令（用于 Logo 上传等自定义协议）
  Future<bool> sendRawCommand(String command) {
    // _send 会自动追加 \n，所以先去掉输入中可能存在的尾部换行
    final cmd = command.endsWith('\n') ? command.substring(0, command.length - 1) : command;
    return _send(cmd);
  }

  /// 发送原始二进制数据（用于 Logo 二进制直传）
  Future<void> writeBytes(List<int> data) => _ble.sendData(data);

  // ═══════════════════════════════════════════════════════════════
  //  带重试的可靠发送
  // ═══════════════════════════════════════════════════════════════

  /// 发送命令并等待指定前缀的响应，超时自动重发
  ///
  /// 返回匹配的响应字符串，或 null（所有重试耗尽/连接断开）
  Future<String?> sendWithRetry(
    String command, {
    required String expectedPrefix,
    Duration timeout = const Duration(seconds: 3),
    int maxRetries = 2,
  }) async {
    final fullCommand = '$command\n';
    final totalAttempts = 1 + maxRetries;

    for (int attempt = 0; attempt < totalAttempts; attempt++) {
      if (!_ble.isConnected) return null;

      // 清除之前可能残留的同前缀请求
      final existing = _pendingPrefixRequests[expectedPrefix];
      if (existing != null && !existing.isCompleted) {
        existing.completeError(Exception('Superseded by retry'));
      }

      final completer = Completer<String>();
      _pendingPrefixRequests[expectedPrefix] = completer;

      try {
        await _ble.sendString(fullCommand);
      } catch (_) {
        _pendingPrefixRequests.remove(expectedPrefix);
        return null;
      }

      try {
        final response = await completer.future.timeout(timeout);
        return response;
      } on TimeoutException {
        _pendingPrefixRequests.remove(expectedPrefix);
        // 继续下一次重试
      } catch (_) {
        _pendingPrefixRequests.remove(expectedPrefix);
        return null;
      }
    }

    return null;
  }

  /// 由 ResponseRouter 调用：尝试匹配前缀等待请求
  void matchPrefixRequest(String response) {
    // Handle ERR:UNKNOWN_CMD — resolve the matching pending request as error
    if (response.startsWith('ERR:UNKNOWN_CMD:')) {
      final failedCmd = response.substring(16).trim();
      final keysToRemove = <String>[];
      for (final entry in _pendingPrefixRequests.entries) {
        // Match if the failed command starts with what we're waiting for
        // e.g. ERR:UNKNOWN_CMD:HELLO:1.2.1:1:android → resolves HELLO: waiter
        if (failedCmd.startsWith(entry.key.replaceAll(':', '')) ||
            entry.key.startsWith(failedCmd.split(':').first)) {
          if (!entry.value.isCompleted) {
            entry.value.completeError(Exception('ERR:UNKNOWN_CMD'));
          }
          keysToRemove.add(entry.key);
          break;
        }
      }
      for (final key in keysToRemove) {
        _pendingPrefixRequests.remove(key);
      }
      return;
    }

    final keysToRemove = <String>[];
    for (final entry in _pendingPrefixRequests.entries) {
      if (response.startsWith(entry.key) && !entry.value.isCompleted) {
        entry.value.complete(response);
        keysToRemove.add(entry.key);
        break;
      }
    }
    for (final key in keysToRemove) {
      _pendingPrefixRequests.remove(key);
    }
  }

  /// 重置所有等待中的请求（重连时调用）
  void resetPendingRequests() {
    for (final completer in _pendingPrefixRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Reset on reconnect'));
      }
    }
    _pendingPrefixRequests.clear();
  }

  // ═══════════════════════════════════════════════════════════════
  //  内部方法
  // ═══════════════════════════════════════════════════════════════

  Future<bool> _send(String command) async {
    try {
      await _ble.sendString('$command\n');
      return true;
    } catch (_) {
      return false;
    }
  }
}
