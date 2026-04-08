import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/no_device_screen.dart';
import 'providers/bluetooth_provider.dart';
import 'providers/device_provider.dart';
import 'services/engine_audio_manager.dart';
import 'services/first_launch_manager.dart';
import 'widgets/app_update_dialog.dart';

void main() async {
  // 🔧 全局错误处理（捕获Release模式下的未处理异常）
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('❌ Flutter错误: ${details.exception}');
    debugPrint('📍 堆栈: ${details.stack}');
  };
  
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 锁定竖屏模式（禁止横屏）
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
    
    // 🚗 初始化引擎音效管理器（添加错误处理，防止Release模式崩溃）
    try {
      await EngineAudioManager().initialize();
    } catch (e) {
      debugPrint('⚠️ 引擎音效初始化失败（非致命）: $e');
    }
    
    // 检查是否为首次启动，决定入口页面
    final firstLaunchManager = FirstLaunchManager();
    final isFirstLaunch = await firstLaunchManager.isFirstLaunch();
    
    runApp(RideWindApp(isFirstLaunch: isFirstLaunch));
  }, (error, stackTrace) {
    debugPrint('❌ 未捕获异常: $error');
    debugPrint('📍 堆栈: $stackTrace');
  });
}

class RideWindApp extends StatefulWidget {
  final bool isFirstLaunch;
  
  const RideWindApp({super.key, required this.isFirstLaunch});

  @override
  State<RideWindApp> createState() => _RideWindAppState();
}

class _RideWindAppState extends State<RideWindApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // 延迟3秒检查更新，等页面加载完
    Future.delayed(const Duration(seconds: 3), _checkUpdate);
  }

  Future<void> _checkUpdate() async {
    final ctx = _navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      AppUpdateDialog.checkAndShow(ctx);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'RideWind',
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
        home: widget.isFirstLaunch ? const SplashScreen() : const NoDeviceScreen(),
      ),
    );
  }
}
