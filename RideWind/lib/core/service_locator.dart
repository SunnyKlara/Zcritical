import 'package:get_it/get_it.dart';
import '../services/ble_service.dart';
import '../protocol/command_sender.dart';
import '../protocol/response_router.dart';
import '../providers/bluetooth_provider.dart';
import '../controllers/colorize_controller.dart';
import '../controllers/device_session_controller.dart';
import '../services/preference_service.dart';
import '../services/ble_connection_manager.dart';
import '../models/device_model.dart';

/// 全局服务定位器
final sl = GetIt.instance;

/// 初始化依赖注入
///
/// 调用顺序：main() → setupServiceLocator() → runApp()
///
/// 注册链：
///   BLEService（单例）
///     → CommandSender（单例，依赖 BLEService）
///     → ResponseRouter（单例，依赖 CommandSender）
///     → BluetoothProvider（单例，依赖以上三者）
void setupServiceLocator() {
  // 底层 BLE 服务
  sl.registerLazySingleton<BLEService>(() => BLEService());

  // 协议层
  sl.registerLazySingleton<CommandSender>(() => CommandSender(sl<BLEService>()));
  sl.registerLazySingleton<ResponseRouter>(() => ResponseRouter(sl<CommandSender>()));

  // 状态管理层
  sl.registerLazySingleton<BluetoothProvider>(
    () => BluetoothProvider.withDependencies(
      bleService: sl<BLEService>(),
      commandSender: sl<CommandSender>(),
      responseRouter: sl<ResponseRouter>(),
    ),
  );

  // 控制器层
  sl.registerLazySingleton<ColorizeController>(
    () => ColorizeController(sl<BluetoothProvider>()),
  );

  // 偏好服务
  sl.registerLazySingleton<PreferenceService>(() => PreferenceService());

  // BLE 连接状态机
  sl.registerLazySingleton<BleConnectionManager>(
    () => BleConnectionManager(
      bluetoothProvider: sl<BluetoothProvider>(),
      preferenceService: sl<PreferenceService>(),
    )..initialize(),
  );
}

/// 创建 DeviceSessionController 实例（每次连接设备时调用）
DeviceSessionController createDeviceSessionController(DeviceModel device) {
  return DeviceSessionController(
    bluetoothProvider: sl<BluetoothProvider>(),
    preferenceService: sl<PreferenceService>(),
    colorize: sl<ColorizeController>(),
    device: device,
  );
}
