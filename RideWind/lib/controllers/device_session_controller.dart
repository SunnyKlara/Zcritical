// DeviceSessionController - Phase 2 of DeviceConnectScreen refactor.
//
// Manages all business logic for the current device session:
//   - BLE connection lifecycle (listen, debounce disconnect, reconnect, background release)
//   - App lifecycle (foreground/background transitions)
//   - Running Mode (speed control, throttle mode, emergency stop)
//   - Atomizer toggle
//   - Hardware UI sync
//   - User preference storage/restore
//
// Screen only listens to notifyListeners() to refresh UI.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../services/preference_service.dart';
import '../controllers/colorize_controller.dart';
import '../data/led_presets.dart';

/// Connection event type
enum ConnectionEvent {
  connected,
  disconnected,
  reconnecting,
  backgroundDisconnected,
}

/// Control mode (mirrors ControlMode in Screen)
enum SessionControlMode {
  running,
  colorize,
  rgb,
}

class DeviceSessionController extends ChangeNotifier {
  // ==================================================================
  //  Dependencies
  // ==================================================================
  final BluetoothProvider _bt;
  final PreferenceService _prefs;
  final ColorizeController colorize;
  final DeviceModel device;

  DeviceSessionController({
    required BluetoothProvider bluetoothProvider,
    required PreferenceService preferenceService,
    required this.colorize,
    required this.device,
  })  : _bt = bluetoothProvider,
        _prefs = preferenceService;

  // ==================================================================
  //  State fields
  // ==================================================================

  // -- Connection --
  bool _navigatedOnDisconnect = false;
  bool get navigatedOnDisconnect => _navigatedOnDisconnect;

  bool _disconnectedByBackground = false;
  bool get disconnectedByBackground => _disconnectedByBackground;

  ConnectionEvent? _lastConnectionEvent;
  ConnectionEvent? get lastConnectionEvent => _lastConnectionEvent;

  final StreamController<void> _disconnectConfirmed =
      StreamController<void>.broadcast();
  Stream<void> get onDisconnectConfirmed => _disconnectConfirmed.stream;

  final StreamController<void> _reconnectFailed =
      StreamController<void>.broadcast();
  Stream<void> get onReconnectFailed => _reconnectFailed.stream;

  // -- Running Mode --
  int _currentSpeed = 0;
  int get currentSpeed => _currentSpeed;

  int _maxSpeed = 340;
  int get maxSpeed => _maxSpeed;

  DateTime _lastCommandTime = DateTime.now();

  // -- Atomizer --
  bool _isAirflowOn = false;
  bool get isAirflowOn => _isAirflowOn;

  // -- Mode --
  int _currentModeIndex = 0;
  int get currentModeIndex => _currentModeIndex;

  SessionControlMode get currentMode {
    switch (_currentModeIndex) {
      case 0:
        return SessionControlMode.running;
      case 1:
        return SessionControlMode.colorize;
      case 2:
        return SessionControlMode.rgb;
      default:
        return SessionControlMode.running;
    }
  }

  // -- Hardware UI sync --
  int lastSentHardwareUI = -1;

  // -- BLE subscriptions --
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<int>? _presetReportSub;
  StreamSubscription<bool>? _streamlightReportSub;

  // -- Timers --
  Timer? _disconnectDebounceTimer;
  Timer? _backgroundDisconnectTimer;
  static const Duration _backgroundGracePeriod = Duration(seconds: 10);

  // ==================================================================
  //  Init & Dispose
  // ==================================================================

  Future<void> init() async {
    colorize.resetToDefaults();
    _setupConnectionListener();
    _setupPresetReportListener();
    _setupStreamlightReportListener();
    await _syncHardwareUIOnInit();
  }

  /// Restore user preferences. Returns the restored selectedColorIndex
  /// so Screen can rebuild its PageController.
  Future<int> restorePreferences() async {
    try {
      await colorize.loadCustomPresets();
      final int selectableMax =
          (colorize.presetCount + colorize.customPresets.length - 1)
              .clamp(0, 1 << 30);

      final deviceSettings = await _prefs.getDeviceSettings(device.id);

      if (deviceSettings != null) {
        colorize.setSelectedColorIndex(
            (deviceSettings['colorPreset'] as int? ?? 0)
                .clamp(0, selectableMax));
        _currentSpeed =
            (deviceSettings['speed'] as int? ?? 0).clamp(0, _maxSpeed);
        _isAirflowOn = deviceSettings['atomizer'] as bool? ?? false;
        colorize.setBrightnessValue(
            (deviceSettings['brightness'] as double? ?? 1.0)
                .clamp(0.0, 1.0));
      } else {
        final colorPreset = await _prefs.getColorPreset();
        final speedValue = await _prefs.getSpeedValue();
        final atomizerState = await _prefs.getAtomizerState();

        colorize.setSelectedColorIndex(colorPreset.clamp(0, selectableMax));
        _currentSpeed = speedValue.clamp(0, _maxSpeed);
        _isAirflowOn = atomizerState;
      }

      final hasCustom = await _prefs.getHasCustomColors();
      if (hasCustom) {
        final savedColors = await _prefs.getCustomRGBColors();
        if (savedColors != null) {
          for (final zone in ['L', 'M', 'R', 'B']) {
            if (savedColors.containsKey(zone)) {
              colorize.setRedValue(zone, savedColors[zone]!['r']!);
              colorize.setGreenValue(zone, savedColors[zone]!['g']!);
              colorize.setBlueValue(zone, savedColors[zone]!['b']!);
            }
          }
          colorize.markCustomColors();
        }
      }

      notifyListeners();
      return colorize.selectedColorIndex;
    } catch (e) {
      debugPrint('restorePreferences failed: $e');
      return 0;
    }
  }

  @override
  void dispose() {
    _disconnectDebounceTimer?.cancel();
    _backgroundDisconnectTimer?.cancel();
    _connectionSub?.cancel();
    _presetReportSub?.cancel();
    _streamlightReportSub?.cancel();
    _disconnectConfirmed.close();
    _reconnectFailed.close();
    _presetPageChanged.close();
    colorize.stopCycleAnimation(sendCommand: false);
    saveSettings();
    super.dispose();
  }

  // ==================================================================
  //  BLE Connection Listener
  // ==================================================================

  void _setupConnectionListener() {
    _connectionSub = _bt.connectionStream.listen((connected) {
      if (!connected) {
        _handleDisconnected();
      } else {
        _handleConnected();
      }
    });
  }

  void _handleDisconnected() {
    // Connection lifecycle is now managed by BleConnectionManager.
    // DeviceSessionController does NOT show popups or manage reconnection.
    // It only updates its internal state for UI rendering purposes.
    _lastConnectionEvent = ConnectionEvent.disconnected;
    notifyListeners();
  }

  void _handleConnected() {
    _disconnectDebounceTimer?.cancel();
    _disconnectDebounceTimer = null;
    _lastConnectionEvent = ConnectionEvent.connected;

    // Save this device for auto-reconnect on next app launch
    _prefs.saveLastConnectedDevice(device.id, device.name);

    lastSentHardwareUI = -1;
    colorize.lastSentHardwareUI = -1;

    if (currentMode == SessionControlMode.colorize ||
        currentMode == SessionControlMode.rgb) {
      Future.delayed(const Duration(milliseconds: 250), () {
        colorize.syncCapsuleToHardware(colorize.selectedColorIndex);
      });
    }

    notifyListeners();
  }

  void _setupPresetReportListener() {
    _presetReportSub = _bt.presetReportStream.listen((preset) {
      final appIndex = preset - 1;
      if (appIndex < 0 || appIndex >= ledPresetMaps.length) return;

      final wasCustom =
          colorize.selectedColorIndex >= colorize.presetCount &&
              colorize.selectedColorIndex <
                  colorize.presetCount + colorize.customPresets.length;

      colorize.onPresetReport(preset);

      if (!wasCustom) {
        _presetPageChanged.add(appIndex);
      }
    });
  }

  /// Notifies Screen to scroll the color PageView to [appIndex].
  final StreamController<int> _presetPageChanged =
      StreamController<int>.broadcast();
  Stream<int> get onPresetPageChanged => _presetPageChanged.stream;

  void _setupStreamlightReportListener() {
    _streamlightReportSub =
        _bt.streamlightReportStream.listen((isEnabled) {
      colorize.onStreamlightReport(isEnabled);
    });
  }

  // ==================================================================
  //  Hardware UI Sync
  // ==================================================================

  Future<void> _syncHardwareUIOnInit() async {
    if (_bt.isConnected) {
      await _bt.setHardwareUI(1);
      lastSentHardwareUI = 1;
    }
  }

  Future<void> syncHardwareUIOnModeChange(int modeIndex) async {
    if (!_bt.isConnected) return;

    switch (modeIndex) {
      case 0:
        if (lastSentHardwareUI != 1) {
          await _bt.setHardwareUI(1);
          lastSentHardwareUI = 1;
        }
        break;
      case 1:
        if (lastSentHardwareUI != 2) {
          await _bt.setHardwareUI(2);
          lastSentHardwareUI = 2;
        }
        colorize.syncCapsuleToHardware(colorize.selectedColorIndex);
        break;
      case 2:
        if (lastSentHardwareUI != 3) {
          await _bt.setHardwareUI(3);
          lastSentHardwareUI = 3;
          colorize.lastSentHardwareUI = 3;
        }
        break;
    }
  }

  // ==================================================================
  //  Mode Switching
  // ==================================================================

  void setModeIndex(int index) {
    if (_currentModeIndex == index) return;
    _currentModeIndex = index;
    notifyListeners();
  }

  // ==================================================================
  //  Running Mode - Speed Control
  // ==================================================================

  Future<void> setSpeed(int speed) async {
    _currentSpeed = speed;

    if (speed == 0 || speed == _maxSpeed) {
      _prefs.saveSpeedValue(speed);
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastCommandTime).inMilliseconds;

    bool shouldSend = (speed == 0 || speed == _maxSpeed) || elapsed >= 100;

    if (shouldSend) {
      _lastCommandTime = now;
      await _bt.setRunningSpeed(speed);
    }

    notifyListeners();
  }

  void setMaxSpeed(int newMax) {
    if (_maxSpeed == newMax) return;
    _maxSpeed = newMax;
    notifyListeners();
  }

  Future<void> setSpeedUnit(bool isMetric) async {
    await _bt.setSpeedUnit(isMetric);
  }

  Future<void> setThrottleMode(bool isThrottling) async {
    await _bt.setHardwareThrottleMode(isThrottling);
    await Future.delayed(const Duration(milliseconds: 30));
  }

  Future<void> emergencyStop() async {
    _currentSpeed = 0;
    await _bt.setHardwareThrottleMode(false);
    await Future.delayed(const Duration(milliseconds: 20));
    await _bt.setRunningSpeed(0);
    await _bt.setFanSpeed(0);
    notifyListeners();
  }

  // ==================================================================
  //  Atomizer
  // ==================================================================

  Future<bool> toggleAirflow() async {
    final newState = !_isAirflowOn;
    final success = await _bt.setWuhuaqiStatus(newState);
    if (success) {
      _isAirflowOn = newState;
      notifyListeners();
    }
    return success;
  }

  // ==================================================================
  //  Shutdown / Reboot
  // ==================================================================

  Future<void> performShutdown() async {
    await _bt.setWuhuaqiStatus(false);
    await Future.delayed(const Duration(milliseconds: 100));
    await _bt.setFanSpeed(0);
    await Future.delayed(const Duration(milliseconds: 100));
    for (int strip = 1; strip <= 4; strip++) {
      await _bt.setLEDColor(strip, 0, 0, 0);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await _bt.setLCDStatus(false);
    await Future.delayed(const Duration(milliseconds: 100));
    _isAirflowOn = false;
    notifyListeners();
  }

  Future<void> performReboot() async {
    await _bt.setWuhuaqiStatus(false);
    await _bt.setFanSpeed(0);
    for (int strip = 1; strip <= 4; strip++) {
      await _bt.setLEDColor(strip, 0, 0, 0);
    }
    await _bt.setLCDStatus(false);
    await Future.delayed(const Duration(milliseconds: 500));
    await _bt.setLCDStatus(true);
    for (int strip = 1; strip <= 4; strip++) {
      await _bt.setLEDColor(strip, 255, 255, 255);
    }
    _isAirflowOn = false;
    notifyListeners();
  }

  // ==================================================================
  //  App Lifecycle
  // ==================================================================

  void onAppPaused() {
    _scheduleBackgroundDisconnect();
  }

  Future<void> onAppResumed() async {
    _cancelBackgroundDisconnect();
    await _handleAppResumed();
  }

  void _scheduleBackgroundDisconnect() {
    _cancelBackgroundDisconnect();
    _backgroundDisconnectTimer = Timer(_backgroundGracePeriod, () {
      if (_bt.isConnected) {
        _disconnectedByBackground = true;
        _bt.disconnect();
      }
    });
  }

  void _cancelBackgroundDisconnect() {
    _backgroundDisconnectTimer?.cancel();
    _backgroundDisconnectTimer = null;
  }

  Future<void> _handleAppResumed() async {
    if (_bt.isConnected) {
      _disconnectedByBackground = false;
      return;
    }

    if (_navigatedOnDisconnect) {
      _disconnectedByBackground = false;
      return;
    }

    _disconnectedByBackground = false;
    _bt.resetBleReconnectState();

    final success = await _bt.connectToDevice(device);
    if (success) {
      _navigatedOnDisconnect = false;
      _lastConnectionEvent = ConnectionEvent.connected;
      notifyListeners();
    } else {
      _navigatedOnDisconnect = true;
      _lastConnectionEvent = ConnectionEvent.disconnected;
      notifyListeners();
      _disconnectConfirmed.add(null);
    }
  }

  // ==================================================================
  //  Reconnect
  // ==================================================================

  Future<bool> attemptReconnect() async {
    _lastConnectionEvent = ConnectionEvent.reconnecting;
    notifyListeners();

    final success = await _bt.connectToDevice(device);
    if (success) {
      _navigatedOnDisconnect = false;
      _lastConnectionEvent = ConnectionEvent.connected;
      notifyListeners();
      return true;
    } else {
      _lastConnectionEvent = ConnectionEvent.disconnected;
      notifyListeners();
      _reconnectFailed.add(null);
      return false;
    }
  }

  void resetDisconnectNavigation() {
    _navigatedOnDisconnect = false;
  }

  // ==================================================================
  //  Preference Storage
  // ==================================================================

  Future<void> saveSettings() async {
    try {
      final settings = {
        'colorPreset': colorize.selectedColorIndex,
        'speed': _currentSpeed,
        'atomizer': _isAirflowOn,
        'brightness': colorize.brightnessValue,
      };
      await _prefs.saveDeviceSettings(device.id, settings);
      _prefs.saveSpeedValue(_currentSpeed);
      _prefs.saveColorPreset(colorize.selectedColorIndex);
    } catch (e) {
      debugPrint('saveSettings failed: $e');
    }
  }
}
