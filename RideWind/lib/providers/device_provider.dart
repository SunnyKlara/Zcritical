import 'package:flutter/material.dart';
import '../models/device_model.dart';

class DeviceProvider with ChangeNotifier {
  DeviceState? _deviceState;
  
  DeviceState? get deviceState => _deviceState;
  int get speed => _deviceState?.speed ?? 0;
  DeviceMode get mode => _deviceState?.mode ?? DeviceMode.running;

  // 初始化设备状态
  void initializeDevice(String deviceId, String deviceName) {
    _deviceState = DeviceState(
      deviceId: deviceId,
      deviceName: deviceName,
    );
    notifyListeners();
  }

  // 设置速度
  void setSpeed(int speed) {
    if (_deviceState != null) {
      _deviceState = _deviceState!.copyWith(speed: speed);
      notifyListeners();
      
      // 这里会发送蓝牙命令到设备
      _sendSpeedCommand(speed);
    }
  }

  // 设置模式
  void setMode(DeviceMode mode) {
    if (_deviceState != null) {
      _deviceState = _deviceState!.copyWith(mode: mode);
      notifyListeners();
      
      // 这里会发送蓝牙命令到设备
      _sendModeCommand(mode);
    }
  }

  // 设置RGB颜色
  void setRGBColor(List<int> colors) {
    if (_deviceState != null) {
      _deviceState = _deviceState!.copyWith(rgbColors: colors);
      notifyListeners();
      
      // 这里会发送蓝牙命令到设备
      _sendColorCommand(colors);
    }
  }

  // 模拟发送速度命令
  void _sendSpeedCommand(int speed) {
    // 实际应用中，这里会通过蓝牙发送命令
    debugPrint('发送速度命令: $speed km/h');
  }

  // 模拟发送模式命令
  void _sendModeCommand(DeviceMode mode) {
    debugPrint('发送模式命令: ${mode.name}');
  }

  // 模拟发送颜色命令
  void _sendColorCommand(List<int> colors) {
    debugPrint('发送颜色命令: RGB(${colors[0]}, ${colors[1]}, ${colors[2]})');
  }

  // 重置设备状态
  void reset() {
    _deviceState = null;
    notifyListeners();
  }
}

