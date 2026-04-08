import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// 🎵 音频测试页面
/// 
/// 用于快速测试引擎声是否正常播放
class AudioTestScreen extends StatefulWidget {
  const AudioTestScreen({super.key});

  @override
  State<AudioTestScreen> createState() => _AudioTestScreenState();
}

class _AudioTestScreenState extends State<AudioTestScreen> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  String _status = '准备就绪';

  Future<void> _handleBackNavigation() async {
    if (_isPlaying) {
      await _testStop();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _testPlay() async {
    try {
      setState(() => _status = '正在加载音频...');
      debugPrint('🎵 测试播放音频...');
      
      await _player.setSource(AssetSource('sound/engine_loop.mp3'));
      
      setState(() => _status = '音频已加载，开始播放...');
      debugPrint('✅ 音频文件已加载');
      
      await _player.seek(const Duration(seconds: 16));
      await _player.setVolume(0.8); // 80% 音量
      await _player.resume();
      
      setState(() {
        _isPlaying = true;
        _status = '✅ 正在播放引擎声！';
      });
      
      debugPrint('✅ 音频播放成功！');
    } catch (e) {
      setState(() => _status = '❌ 播放失败: $e');
      debugPrint('❌ 音频播放失败: $e');
    }
  }

  Future<void> _testStop() async {
    await _player.pause();
    setState(() {
      _isPlaying = false;
      _status = '⏸️ 已停止播放';
    });
    debugPrint('⏸️ 音频已暂停');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _handleBackNavigation();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('🎵 引擎声测试', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBackNavigation,
          ),
        ),
        body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 状态指示器
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isPlaying ? Colors.green.withAlpha(51) : Colors.grey.withAlpha(51),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isPlaying ? Colors.green : Colors.grey,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isPlaying ? Icons.volume_up : Icons.volume_off,
                      size: 64,
                      color: _isPlaying ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isPlaying ? Colors.green : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 播放按钮
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: _isPlaying ? null : _testPlay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    '播放引擎声',
                    style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 停止按钮
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: _isPlaying ? _testStop : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    '停止播放',
                    style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              // 说明文字
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(51),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue, width: 1),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 测试说明：',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. 确保设备音量已打开\n'
                      '2. 点击"播放引擎声"按钮\n'
                      '3. 应该听到引擎加速声\n'
                      '4. 查看控制台日志了解详情',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

