// BLE Connection State Machine
//
// Single source of truth for BLE connection lifecycle.
// Replaces scattered bool flags and timers with a formal state machine.
//
// States:
//   idle → scanning → connecting → verifying → connected
//                                                  ↓
//                                  reconnecting ← disconnected (transient)
//                                       ↓
//                                    failed (show UI)
//
// Rules:
//   - connected → reconnecting: ALWAYS silent (no popup)
//   - reconnecting → connected: silent recovery
//   - reconnecting → failed: only transition that triggers user-visible UI
//   - App background: connected → backgrounded → (resume) → reconnecting

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../models/device_model.dart';
import '../providers/bluetooth_provider.dart';
import '../services/preference_service.dart';

enum BleState {
  idle,          // No device known, waiting for user action
  connecting,    // Attempting to connect
  verifying,     // Physical link up, verifying hardware responds
  connected,     // Fully operational
  reconnecting,  // Lost connection, silently trying to restore
  failed,        // All reconnect attempts exhausted
}

class BleConnectionManager extends ChangeNotifier {
  final BluetoothProvider _bt;
  final PreferenceService _prefs;

  BleConnectionManager({
    required BluetoothProvider bluetoothProvider,
    required PreferenceService preferenceService,
  })  : _bt = bluetoothProvider,
        _prefs = preferenceService;

  // ==================================================================
  //  State
  // ==================================================================

  BleState _state = BleState.idle;
  BleState get state => _state;

  DeviceModel? _device;
  DeviceModel? get device => _device;

  String? _failureReason;
  String? get failureReason => _failureReason;

  // Reconnect config
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectBaseDelay = Duration(seconds: 3);
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  // Connection stream subscription
  StreamSubscription<bool>? _connectionSub;

  // ==================================================================
  //  Public API
  // ==================================================================

  /// Start listening to BLE connection events.
  /// Call once at app startup.
  void initialize() {
    _connectionSub = _bt.connectionStream.listen(_onConnectionChanged);
  }

  /// Connect to a specific device (user-initiated from scan).
  Future<bool> connectToDevice(DeviceModel device) async {
    _device = device;
    _failureReason = null;
    _reconnectAttempt = 0;
    _cancelReconnectTimer();

    _setState(BleState.connecting);

    final success = await _bt.connectToDevice(device);
    if (success) {
      _setState(BleState.connected);
      _prefs.saveLastConnectedDevice(device.id, device.name);
      return true;
    } else {
      _failureReason = _bt.lastConnectionError ?? 'Connection failed';
      _setState(BleState.failed);
      return false;
    }
  }

  /// Auto-connect to last known device (app startup).
  /// Returns true if connected, false if no saved device or failed.
  Future<bool> autoConnect() async {
    final lastDevice = await _prefs.getLastConnectedDevice();
    if (lastDevice == null) return false;

    final deviceId = lastDevice['id']!;
    final deviceName = lastDevice['name']!;

    final btDevice = fbp.BluetoothDevice.fromId(deviceId);
    final deviceModel = DeviceModel(
      id: deviceId,
      name: deviceName,
      rssi: -60,
      bluetoothDevice: btDevice,
    );

    _device = deviceModel;
    _setState(BleState.connecting);

    final success = await _bt.connectToDevice(deviceModel);
    if (success) {
      _setState(BleState.connected);
      return true;
    } else {
      // Auto-connect failure is not "failed" state — just go back to idle
      _setState(BleState.idle);
      return false;
    }
  }

  /// User-initiated disconnect (e.g. remove device).
  Future<void> disconnect() async {
    _cancelReconnectTimer();
    _reconnectAttempt = 0;
    await _bt.disconnect();
    _device = null;
    _setState(BleState.idle);
  }

  /// App went to background — prepare for possible disconnect.
  void onAppPaused() {
    // Nothing to do here — if BLE disconnects while backgrounded,
    // _onConnectionChanged will handle it via reconnecting state.
  }

  /// App returned to foreground.
  Future<void> onAppResumed() async {
    if (_state == BleState.connected && _bt.isConnected) return;
    if (_state == BleState.reconnecting) return; // already trying
    if (_device == null) return;

    // We were connected but lost it while backgrounded
    if (!_bt.isConnected && _state != BleState.idle) {
      _startReconnect();
    }
  }

  /// Forget the saved device (clear auto-connect).
  Future<void> forgetDevice() async {
    await _prefs.clearLastConnectedDevice();
    _device = null;
    _setState(BleState.idle);
  }

  // ==================================================================
  //  Internal State Machine
  // ==================================================================

  void _setState(BleState newState) {
    if (_state == newState) return;
    debugPrint('[BLE-SM] $_state → $newState');
    _state = newState;
    notifyListeners();
  }

  void _onConnectionChanged(bool connected) {
    if (connected) {
      _onBleConnected();
    } else {
      _onBleDisconnected();
    }
  }

  void _onBleConnected() {
    _cancelReconnectTimer();
    _reconnectAttempt = 0;
    _failureReason = null;

    if (_state == BleState.reconnecting || _state == BleState.connecting) {
      _setState(BleState.connected);
      // Save device for future auto-connect
      if (_device != null) {
        _prefs.saveLastConnectedDevice(_device!.id, _device!.name);
      }
    }
    // If already connected, ignore (duplicate event)
  }

  void _onBleDisconnected() {
    if (_state == BleState.idle || _state == BleState.failed) return;
    if (_device == null) return;

    // ANY disconnect from connected/verifying → go to reconnecting (silent)
    _startReconnect();
  }

  void _startReconnect() {
    if (_state == BleState.reconnecting) return; // already in progress
    _setState(BleState.reconnecting);
    _reconnectAttempt = 0;
    _scheduleNextReconnect();
  }

  void _scheduleNextReconnect() {
    _cancelReconnectTimer();

    if (_reconnectAttempt >= _maxReconnectAttempts) {
      // Exhausted all attempts — NOW transition to failed
      _failureReason = 'Device unreachable after $_maxReconnectAttempts attempts';
      _setState(BleState.failed);
      return;
    }

    // Exponential backoff: 3s, 6s, 12s, 24s, 48s
    final delay = _reconnectBaseDelay * (1 << _reconnectAttempt);
    _reconnectAttempt++;

    debugPrint('[BLE-SM] Reconnect attempt $_reconnectAttempt/$_maxReconnectAttempts '
        'in ${delay.inSeconds}s');

    _reconnectTimer = Timer(delay, () async {
      if (_state != BleState.reconnecting) return;
      if (_device == null) return;

      // Check if BLE service already reconnected on its own
      if (_bt.isConnected) {
        _onBleConnected();
        return;
      }

      // Try manual reconnect
      final success = await _bt.connectToDevice(_device!);
      if (success) {
        // _onBleConnected will be called via connectionStream
        return;
      }

      // Failed — schedule next attempt
      _scheduleNextReconnect();
    });
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ==================================================================
  //  Dispose
  // ==================================================================

  @override
  void dispose() {
    _cancelReconnectTimer();
    _connectionSub?.cancel();
    super.dispose();
  }
}
