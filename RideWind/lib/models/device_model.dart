import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class DeviceModel {
  final String id;
  final String name;
  final int rssi;
  bool isConnected;
  final fbp.BluetoothDevice? bluetoothDevice;  // 真实的蓝牙设备引用

  DeviceModel({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnected = false,
    this.bluetoothDevice,  // 可选的蓝牙设备引用
  });
}

class DeviceState {
  final String deviceId;
  final String deviceName;
  final int speed;
  final DeviceMode mode;
  final List<int> rgbColors;
  
  DeviceState({
    required this.deviceId,
    required this.deviceName,
    this.speed = 0,
    this.mode = DeviceMode.running,
    this.rgbColors = const [255, 255, 255],
  });
  
  DeviceState copyWith({
    String? deviceId,
    String? deviceName,
    int? speed,
    DeviceMode? mode,
    List<int>? rgbColors,
  }) {
    return DeviceState(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      speed: speed ?? this.speed,
      mode: mode ?? this.mode,
      rgbColors: rgbColors ?? this.rgbColors,
    );
  }
}

enum DeviceMode {
  cleaning,
  running,
  colorize,
}

