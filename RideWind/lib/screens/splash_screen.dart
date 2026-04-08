import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'onboarding_flow_screen.dart';
import 'device_scan_screen.dart';
import 'no_device_screen.dart';
import '../services/first_launch_manager.dart';

/// 启动页面 - APP打开后的第一个页面
/// 展示Logo、品牌名称、开始使用按钮和用户协议
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _agreedToTerms = false; // 默认未勾选用户协议
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  /// 首次启动管理器
  final FirstLaunchManager _firstLaunchManager = FirstLaunchManager();

  @override
  void initState() {
    super.initState();

    // 创建淡入动画
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // 启动动画
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  /// 开始使用 - 进入引导页面
  Future<void> _startApp() async {
    // 如果未同意协议，先显示确认对话框
    if (!_agreedToTerms) {
      await _showAgreementDialog();
      return;
    }

    // 已同意协议，继续跳转
    await _navigateToOnboarding();
  }

  /// 跳转到引导页面或设备扫描页面
  /// 根据首次启动状态决定跳转目标：
  /// - 首次启动：显示 OnboardingFlowScreen
  /// - 非首次启动：直接显示 DeviceScanScreen
  Future<void> _navigateToOnboarding() async {
    setState(() {
      _isLoading = true;
    });

    // 检查是否为首次启动
    final isFirstLaunch = await _firstLaunchManager.isFirstLaunch();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      // 根据首次启动状态决定跳转目标
      // 首次启动：显示引导流程
      // 非首次启动：直接进入添加设备页面（NoDeviceScreen）
      final Widget targetScreen = isFirstLaunch
          ? const OnboardingFlowScreen()
          : const NoDeviceScreen();

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  /// 显示用户协议确认对话框
  Future<void> _showAgreementDialog() async {
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 点击外部不关闭
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '用户协议与隐私政策',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '欢迎使用 RideWind！',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: '在使用我们的服务前，请您仔细阅读并同意'),
                    TextSpan(
                      text: '《用户协议》',
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          _showAgreementPage('用户协议');
                        },
                    ),
                    const TextSpan(text: '和'),
                    TextSpan(
                      text: '《隐私政策》',
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          _showAgreementPage('隐私政策');
                        },
                    ),
                    const TextSpan(text: '。\n\n我们将严格保护您的个人信息安全。'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false); // 返回 false（拒绝）
            },
            child: const Text(
              '拒绝',
              style: TextStyle(color: Colors.white60, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true); // 返回 true（同意）
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              '同意',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    // 如果用户同意
    if (agreed == true) {
      setState(() {
        _agreedToTerms = true; // 自动勾选协议复选框
      });
      // 继续跳转
      await _navigateToOnboarding();
    }
  }

  /// 显示协议详情页面
  void _showAgreementPage(String title) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => _AgreementPage(title: title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              children: [
                const Spacer(flex: 4),

                // Logo和品牌名称
                _buildLogoSection(),

                const Spacer(flex: 3),

                // 开始使用按钮
                _buildStartButton(),

                const SizedBox(height: 16),

                // 用户协议勾选
                _buildAgreementCheckbox(),

                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Logo和品牌名称区域
  Widget _buildLogoSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Logo图标
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 8),
            borderRadius: BorderRadius.circular(0), // 纯正方形，无圆角
          ),
          child: CustomPaint(painter: _RideWindLogoPainter()),
        ),

        const SizedBox(width: 20),

        // 品牌名称
        const Text(
          'RideWind',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            height: 1,
          ),
        ),
      ],
    );
  }

  /// 开始使用按钮
  Widget _buildStartButton() {
    return Center(
      child: SizedBox(
        width: 320,
        height: 58,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _startApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            disabledBackgroundColor: Colors.white.withAlpha(128),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(29),
            ),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : const Text(
                  '开始使用',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  /// 用户协议勾选框
  Widget _buildAgreementCheckbox() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 圆形勾选框
          GestureDetector(
            onTap: () {
              setState(() {
                _agreedToTerms = !_agreedToTerms;
              });
            },
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: _agreedToTerms
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                      ),
                    )
                  : null,
            ),
          ),

          const SizedBox(width: 8),

          // 协议文本（可点击链接）
          Flexible(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: '我已阅读并同意 '),
                  TextSpan(
                    text: '用户协议',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        _showAgreementPage('用户协议');
                      },
                  ),
                  const TextSpan(text: ' 和 '),
                  TextSpan(
                    text: '隐私声明',
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        _showAgreementPage('隐私政策');
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// RideWind Logo绘制器
/// 几何设计：正方形 + 对角线（左下到右上）+ 与对角线、下边框、右边框同时相切的圆形
class _RideWindLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    // 对角线直接连接到正方形的角（无间隙）
    final L = size.width; // 使用完整尺寸

    // 1. 绘制对角线（从左下到右上，完全连接到角）
    canvas.drawLine(
      Offset(0, size.height), // 左下角
      Offset(size.width, 0), // 右上角
      paint,
    );

    // 2. 计算圆形位置和半径
    // 对角线方程：从(0, L)到(L, 0)，即 y = -x + L 或 x + y = L
    // 圆心设为(cx, cy)，半径为r
    //
    // 条件1：与右边框相切 → cx = L - r
    // 条件2：与下边框相切 → cy = L - r
    // 条件3：与对角线 x + y = L 相切
    //        点到直线距离 = |cx + cy - L| / sqrt(2) = r
    //        因为圆在对角线下方（右下角），cx + cy > L
    //        所以 (cx + cy - L) / sqrt(2) = r
    //
    // 将 cx = L - r, cy = L - r 代入条件3：
    // ((L - r) + (L - r) - L) / sqrt(2) = r
    // (L - 2r) / sqrt(2) = r
    // L - 2r = r * sqrt(2)
    // L = 2r + r * sqrt(2)
    // L = r * (2 + sqrt(2))
    // r = L / (2 + sqrt(2))
    // r ≈ L / 3.414
    // r ≈ 0.293 * L

    final double radius = L / (2 + math.sqrt(2));
    final double circleCenterX = L - radius;
    final double circleCenterY = L - radius;

    // 3. 绘制圆形
    canvas.drawCircle(Offset(circleCenterX, circleCenterY), radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 协议详情页面
class _AgreementPage extends StatelessWidget {
  final String title;

  const _AgreementPage({required this.title});

  Future<void> _handleBackNavigation(BuildContext context) async {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackNavigation(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => _handleBackNavigation(context),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '更新日期：2025年1月1日',
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildContent(title),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String type) {
    if (type == '用户协议') {
      return const Text(
        '''欢迎使用 RideWind！

一、服务条款的接受
感谢您使用 RideWind 产品和服务。请您仔细阅读以下条款，如果您使用 RideWind 服务，即表示您同意遵守下述全部条款。

二、服务说明
RideWind 是一款智能设备控制应用，为用户提供设备连接、控制和管理等功能。

三、用户账号
1. 用户应当提供真实、准确、完整的个人信息。
2. 用户有责任保管好自己的账号和密码，因用户保管不善造成的损失由用户自行承担。
3. 用户不得将账号转让、出租或出借给他人使用。

四、用户行为规范
用户在使用 RideWind 服务时，必须遵守以下规定：
1. 不得利用本服务从事违法违规活动。
2. 不得干扰或破坏本服务的正常运行。
3. 不得侵犯他人的合法权益。

五、隐私保护
我们重视用户的隐私保护，详见《隐私政策》。

六、知识产权
RideWind 的所有内容，包括但不限于软件、界面设计、文字、图片等，均受相关知识产权法律保护。

七、免责声明
1. 对于因不可抗力或非本公司原因造成的服务中断，本公司不承担责任。
2. 用户使用本服务造成的任何直接或间接损失，本公司不承担责任。

八、服务变更、中断或终止
本公司可能会对服务内容进行变更，也可能会中断、中止或终止服务。

九、法律适用与争议解决
本协议适用中华人民共和国法律。如发生争议，双方应友好协商解决；协商不成的，可向本公司所在地人民法院提起诉讼。

十、其他
本协议的最终解释权归 RideWind 所有。''',
        style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.8),
      );
    } else {
      return const Text(
        '''RideWind 隐私政策

引言
RideWind（以下简称"我们"）非常重视用户的隐私和个人信息保护。本隐私政策将帮助您了解我们如何收集、使用、存储和保护您的个人信息。

一、我们收集的信息
1. 设备信息：包括设备型号、操作系统版本、设备标识符等。
2. 蓝牙信息：用于连接和控制您的 RideWind 设备。
3. 位置信息：用于蓝牙设备扫描（Android 系统要求）。
4. 使用数据：包括应用使用情况、功能偏好等。

二、信息的使用
我们收集的信息将用于：
1. 提供、维护和改进我们的服务。
2. 与您的设备进行连接和通信。
3. 分析应用使用情况，优化用户体验。
4. 向您发送服务通知（如果您允许）。

三、信息的存储
1. 您的个人信息将存储在您的设备本地。
2. 我们采用行业标准的安全措施保护您的信息。
3. 未经您的同意，我们不会将您的信息传输至第三方服务器。

四、信息的分享
我们不会向第三方出售、出租或分享您的个人信息，除非：
1. 获得您的明确同意。
2. 法律法规要求或政府部门要求。
3. 为维护我们的合法权益所必需。

五、您的权利
您有权：
1. 访问、更正或删除您的个人信息。
2. 撤回您对个人信息处理的同意。
3. 要求我们限制或停止处理您的个人信息。

六、儿童隐私
我们不会故意收集 14 岁以下儿童的个人信息。如果您是儿童的父母或监护人，请监督儿童使用我们的服务。

七、第三方服务
我们的应用可能包含第三方服务（如蓝牙、定位服务），这些服务有各自的隐私政策。

八、隐私政策的更新
我们可能会不时更新本隐私政策。更新后的政策将在应用中发布，请您定期查阅。

九、联系我们
如果您对本隐私政策有任何疑问，请通过应用内反馈功能联系我们。

最后更新日期：2025年1月1日''',
        style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.8),
      );
    }
  }
}
