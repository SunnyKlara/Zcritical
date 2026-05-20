import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls the Android AudioPlaybackCapture → TCP → ESP32 pipeline.
///
/// Flow:
///   1. APP sends WiFi credentials to ESP32 via BLE: "WIFI:ssid:password\n"
///   2. ESP32 connects to same WiFi, reports IP: "WIFI_IP:x.x.x.x"
///   3. APP starts audio capture service with ESP32's IP
///   4. Service captures system audio and streams PCM via TCP
class AudioStreamService {
  static const _channel = MethodChannel('com.example.ridewind/audio_capture');

  // SharedPreferences keys for WiFi credentials
  static const _kWifiSsid = 'wifi_ssid';
  static const _kWifiPassword = 'wifi_password';

  /// Start audio capture and stream to the given IP.
  static Future<bool> startCapture({String ip = '192.168.4.1'}) async {
    try {
      final result = await _channel.invokeMethod<bool>('startCapture', {'ip': ip});
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'UNSUPPORTED') {
        throw UnsupportedError('音频投射需要 Android 10 或更高版本');
      }
      rethrow;
    }
  }

  /// Stop capturing and disconnect.
  static Future<void> stopCapture() async {
    await _channel.invokeMethod('stopCapture');
  }

  /// Check if audio capture is currently active.
  static Future<bool> isCapturing() async {
    final result = await _channel.invokeMethod<bool>('isCapturing');
    return result ?? false;
  }

  /// Get current status message.
  static Future<String> getStatus() async {
    final result = await _channel.invokeMethod<String>('getStatus');
    return result ?? '';
  }

  /// Scan WiFi networks using Android's native WiFi API.
  /// Returns list of {ssid: String, rssi: int, secure: bool}
  static Future<List<Map<String, dynamic>>> scanWifi() async {
    final result = await _channel.invokeMethod<List>('scanWifi');
    if (result == null) return [];
    return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Get the currently connected WiFi network info.
  /// Returns {ssid: String, frequency: int (MHz)} or null if not connected.
  /// frequency > 3000 means 5GHz band (ESP32 only supports 2.4GHz).
  static Future<Map<String, dynamic>?> getConnectedWifi() async {
    final result = await _channel.invokeMethod<Map>('getConnectedWifi');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  // ╔══════════════════════════════════════════════════════════════╗
  // ║          📶 WiFi 凭据管理 (需求 11.1, 11.2, 11.3)            ║
  // ╚══════════════════════════════════════════════════════════════╝

  /// 保存 WiFi 凭据到 SharedPreferences
  ///
  /// [ssid] WiFi 网络名称
  /// [password] WiFi 密码
  static Future<void> saveWifiCredentials(String ssid, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWifiSsid, ssid);
    await prefs.setString(_kWifiPassword, password);
  }

  /// 加载已保存的 WiFi 凭据
  ///
  /// 返回 {ssid: String, password: String}，如果没有保存的凭据则返回 null
  static Future<Map<String, String>?> loadWifiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final ssid = prefs.getString(_kWifiSsid);
    final password = prefs.getString(_kWifiPassword);
    if (ssid == null || password == null) return null;
    return {'ssid': ssid, 'password': password};
  }

  /// 清除已保存的 WiFi 凭据
  static Future<void> clearWifiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWifiSsid);
    await prefs.remove(_kWifiPassword);
  }
}
