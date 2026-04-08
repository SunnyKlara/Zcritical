import 'package:flutter/material.dart';
import 'no_device_screen.dart';
import '../services/first_launch_manager.dart';

/// 引导流程页面 - 使用 PageView 实现丝滑滑动
/// 统一设计规范：字体、样式、布局、组件大小
class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final PageController _pageController = PageController();
  final FirstLaunchManager _firstLaunchManager = FirstLaunchManager();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      // 最后一页，标记引导完成并跳转到蓝牙扫描页面
      _completeOnboardingAndNavigate();
    }
  }

  /// 完成引导流程并跳转到添加设备页面（NoDeviceScreen）
  /// 先调用 markOnboardingComplete() 持久化完成状态，然后导航
  /// 使用 pushAndRemoveUntil 清空栈，确保 NoDeviceScreen 成为栈底，返回即退出APP
  Future<void> _completeOnboardingAndNavigate() async {
    // 标记引导流程已完成
    await _firstLaunchManager.markOnboardingComplete();
    
    // 清空导航栈，将 NoDeviceScreen 设为根页面
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const NoDeviceScreen()),
        (route) => false, // 移除所有旧路由
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // PageView 内容区域
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildPage(
                    title: '允许通知权限',
                    description: '"驭风"需要获取通知权限，以及时报告您的设备状态，并在设备发生故障时发出警报。',
                    imagePath: 'assets/images/notification_bubble.png',
                  ),
                  _buildPage(
                    title: '允许"附近设备"权限',
                    description: '驭风需要获取蓝牙与WIFI权限，以便查找、连接附近的设备。',
                    imagePath: 'assets/images/bluetooth_connection.png',
                  ),
                  _buildPage(
                    title: '全部就绪！',
                    description: '使用 驭风App 控制驭风系列产品，探索自然科学。',
                    imagePath: null, // 第三页没有组件图
                  ),
                ],
              ),
            ),

            // 底部固定区域：指示器 + 按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  // 页面指示器
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: _buildIndicator(index == _currentPage),
                      );
                    }),
                  ),

                  const SizedBox(height: 32),

                  // 下一步按钮
                  SizedBox(
                    width: 320,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(29),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage == 2 ? '开始探索' : '下一步',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 统一的页面布局
  Widget _buildPage({
    required String title,
    required String description,
    String? imagePath, // 可选图片路径
  }) {
    // 获取屏幕尺寸，用于响应式计算
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = screenHeight * 0.08; // 顶部留白为屏幕高度的8%

    return Padding(
      padding: EdgeInsets.fromLTRB(32.0, topPadding, 32.0, 0), // 增加水平内边距
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 - 统一样式，往上移动，字体更大
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 48, // 增大标题字体大小
              fontWeight: FontWeight.w800, // 增加字重，使其更加突出
              height: 1.1, // 减小行高，使文字更紧凑
              letterSpacing: -0.5, // 调整字间距，使大标题更紧凑
            ),
            maxLines: 2, // 限制最大行数
            overflow: TextOverflow.ellipsis, // 文字过长时显示省略号
          ),

          const SizedBox(height: 32), // 增加间距
          // 描述文字 - 统一样式，字体更大
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withAlpha(204), // 增加不透明度，提高可读性
              fontSize: 20, // 增大副标题字体大小
              height: 1.5, // 调整行高
              fontWeight: FontWeight.w400, // 增加字重
              letterSpacing: 0.2, // 调整字间距
            ),
            maxLines: 4, // 限制最大行数，防止文字过多影响布局
          ),

          // 组件图片 - 统一大小，浮动在中间（如果有图片）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0), // 增加与文字的间距
              child: Center(
                child: imagePath != null
                    ? Image.asset(
                        imagePath,
                        width:
                            MediaQuery.of(context).size.width * 0.8, // 增大图片宽度
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              '图片加载失败\n$imagePath',
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(), // 没有图片时留空
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 页面指示器横条 - 带丝滑动画
  /// 选中: 短条 20px，更亮的白色
  /// 未选中: 长条 40px，白色
  Widget _buildIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      width: isActive ? 20 : 40,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(isActive ? 255 : 153),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
