import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'screens/no_device_screen.dart';
import 'screens/device_list_screen.dart';
import 'providers/bluetooth_provider.dart';
import 'core/service_locator.dart';
import 'services/first_launch_manager.dart';

/// Sentry DSN — 注册 https://sentry.io 后替换为你的项目 DSN
/// 免费版每月 5000 事件，足够小规模用户使用
const String _sentryDsn = 'https://1e3ffad26e1049487f7453f026da401e@o4511444403355648.ingest.us.sentry.io/4511444408270848';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 锁定竖屏模式
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 设置系统UI样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Sentry 初始化（包裹整个 APP，自动捕获未处理异常）
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.environment = const String.fromEnvironment(
        'SENTRY_ENV',
        defaultValue: 'production',
      );
      options.tracesSampleRate = 0.2; // 20% 性能追踪采样
      options.attachScreenshot = true;
      options.sendDefaultPii = false; // 不发送用户隐私信息
    },
    appRunner: () async {
      // 🔧 初始化依赖注入
      setupServiceLocator();

      // 检查是否为首次启动
      final firstLaunchManager = FirstLaunchManager();
      final isFirstLaunch = await firstLaunchManager.isFirstLaunch();

      // 检查是否有已保存的设备（决定启动路由）
      bool hasSavedDevices = false;
      if (!isFirstLaunch) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final jsonStr = prefs.getString('saved_devices_list');
          if (jsonStr != null && jsonStr.isNotEmpty) {
            final list = jsonDecode(jsonStr) as List;
            hasSavedDevices = list.isNotEmpty;
          }
        } catch (_) {}
      }

      runApp(ZcriticalApp(
        isFirstLaunch: isFirstLaunch,
        hasSavedDevices: hasSavedDevices,
      ));
    },
  );
}

class ZcriticalApp extends StatefulWidget {
  final bool isFirstLaunch;
  final bool hasSavedDevices;

  const ZcriticalApp({
    super.key,
    required this.isFirstLaunch,
    required this.hasSavedDevices,
  });

  @override
  State<ZcriticalApp> createState() => _ZcriticalAppState();
}

class _ZcriticalAppState extends State<ZcriticalApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sl<BluetoothProvider>()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Zcritical T1',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          primaryColor: Colors.white,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            secondary: Color(0xFF00FF94),
            surface: Color(0xFF1A1A1A),
          ),
          useMaterial3: true,
        ),
        home: widget.isFirstLaunch
            ? const SplashScreen()
            : widget.hasSavedDevices
                ? const DeviceListScreen()
                : const NoDeviceScreen(),
      ),
    );
  }
}
