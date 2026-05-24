import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/preference_service.dart';
import 'device_management_screen.dart';

/// 设置 / 更多入口页（替代"个人中心"心智模型）
///
/// 职责：聚合所有不在主控制流的功能 + App 偏好 + 关于信息。
/// P0 MVP：版本号 + 反馈 + 关于 + 重置 四行最基础。
/// 后续 P1 迁入设备分组（LED/音效/Logo/清洁/OTA），
/// P2 加应用偏好（语言/深色/触感/提示音），
/// P3 通过版本号 ×5 解锁开发者选项。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  String _build = '';
  int _versionTapCount = 0; // P3 预留：连点 5 次解锁开发者选项

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _version = '1.0.0';
        _build = '0';
      });
    }
  }

  void _onVersionTap() {
    setState(() => _versionTapCount++);
    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('开发者选项即将上线'),
          duration: Duration(seconds: 1),
        ),
      );
      // TODO(P3): 切换 _devUnlocked = true，分组里多一段"开发者选项"
    }
  }

  Future<void> _onResetTap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重置所有设置？',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text(
          '将清除颜色预设、速度、雾化器状态、自定义 RGB 颜色等本地偏好。\n设备配对信息不受影响。',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认重置',
                style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await PreferenceService().reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已重置本地偏好'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _onFeedbackTap() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('反馈问题', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '遇到问题或有建议？通过以下方式联系我们：',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            _FeedbackContactRow(
              icon: Icons.email_outlined,
              label: '邮箱',
              value: 'support@zcritical.com',
            ),
            const SizedBox(height: 12),
            Text(
              '反馈时请附上：\n• APP 版本号（v$_version）\n• 手机型号和系统版本\n• 问题描述和复现步骤',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _onAboutTap() {
    showAboutDialog(
      context: context,
      applicationName: 'Zcritical T1',
      applicationVersion: 'v$_version (build $_build)',
      applicationLegalese: '智能风洞模拟器 · ESP32-S3 + Flutter',
      children: const [
        SizedBox(height: 12),
        Text('BLE 直连，无服务器、无账号体系，所有数据存在本地。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // 顶栏：返回 + 标题
            SliverToBoxAdapter(child: _buildTopBar(context)),

            // 品牌 + 版本号
            SliverToBoxAdapter(child: _buildBrandHeader()),

            // 关于分组（P0 仅这一组 + 重置）
            SliverToBoxAdapter(
              child: _SectionHeader(title: '设备'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _SettingsRow(
                    icon: Icons.devices_outlined,
                    title: '设备管理',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DeviceManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            SliverToBoxAdapter(
              child: _SectionHeader(title: '关于'),
            ),
            SliverToBoxAdapter(
              child: _SettingsGroup(
                children: [
                  _SettingsRow(
                    icon: Icons.feedback_outlined,
                    title: '反馈问题',
                    onTap: _onFeedbackTap,
                  ),
                  _SettingsRow(
                    icon: Icons.info_outline,
                    title: '关于 Zcritical T1',
                    onTap: _onAboutTap,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),

            // 危险操作：重置
            SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  onPressed: _onResetTap,
                  child: const Text(
                    '重置所有设置',
                    style: TextStyle(
                      color: Color(0xFFE74C3C),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回',
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zcritical T1',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onVersionTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _version.isEmpty ? '加载中...' : 'v$_version (build $_build)',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 视觉规范组件（按你的设计稿）
// 背景：#000，分组标题：白 40% 12sp，列表行：高 56 / 图标 24 白 80% / 标题 15sp 白
// ============================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withAlpha((255 * 0.4).round()),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// 一组设置项容器（自动给行间加 0.5px 分割线）
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i != children.length - 1) {
        divided.add(Divider(
          color: Colors.white.withAlpha(15),
          height: 0.5,
          thickness: 0.5,
          indent: 56,
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: divided);
  }
}

/// 单行设置项（图标 + 标题 + 可选尾值 + 箭头）
class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    // ignore: unused_element_parameter
    this.trailingText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon,
                  color: Colors.white.withAlpha((255 * 0.8).round()),
                  size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
              if (trailingText != null) ...[
                Text(
                  trailingText!,
                  style: TextStyle(
                    color: Colors.white.withAlpha((255 * 0.5).round()),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right,
                  color: Colors.white.withAlpha((255 * 0.4).round()),
                  size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 反馈联系方式行（图标 + 标签 + 可复制值）
class _FeedbackContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FeedbackContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制: $value'), duration: const Duration(seconds: 1)),
              );
            },
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF00FF94), fontSize: 14),
            ),
          ),
        ),
        const Icon(Icons.copy, color: Colors.white38, size: 16),
      ],
    );
  }
}
