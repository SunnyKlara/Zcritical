import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../utils/responsive_utils.dart';
import 'color_ring_screen.dart';

class RGBColorScreen extends StatefulWidget {
  const RGBColorScreen({super.key});

  @override
  State<RGBColorScreen> createState() => _RGBColorScreenState();
}

class _RGBColorScreenState extends State<RGBColorScreen> {
  // 四个灯光区域的RGB值
  final List<List<double>> _rgbValues = [
    [255, 255, 255], // L - 左侧
    [255, 255, 255], // M - 中间
    [255, 255, 255], // R - 右侧
    [255, 0, 0],     // B - 后部（默认红色）
  ];
  
  int _selectedZone = 3; // 默认选择后部(B)
  double _loopSpeed = 0.5; // 循环速度

  // RGB 数值手动输入状态
  int? _editingChannel; // null=无编辑, 0=R, 1=G, 2=B
  final TextEditingController _valueController = TextEditingController();
  final FocusNode _valueFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _valueFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _valueFocusNode.removeListener(_onFocusChanged);
    _valueController.dispose();
    _valueFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_valueFocusNode.hasFocus && _editingChannel != null) {
      _commitEdit();
    }
  }

  void _startEditing(int channelIndex, double currentValue) {
    setState(() {
      _editingChannel = channelIndex;
      _valueController.text = currentValue.toInt().toString();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _valueFocusNode.requestFocus();
      _valueController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _valueController.text.length,
      );
    });
  }

  void _commitEdit() {
    if (_editingChannel == null) return;
    final channel = _editingChannel!;
    final text = _valueController.text;
    if (text.isNotEmpty) {
      final parsed = int.tryParse(text) ?? _rgbValues[_selectedZone][channel].toInt();
      final clamped = parsed.clamp(0, 255);
      setState(() {
        _rgbValues[_selectedZone][channel] = clamped.toDouble();
        _editingChannel = null;
      });
    } else {
      // 空输入保持原值
      setState(() {
        _editingChannel = null;
      });
    }
  }

  Future<void> _handleBackNavigation() async {
    Navigator.of(context).pop();
  }

  void _openColorWheel() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ColorRingScreen(
          onColorSelected: _onColorSelected,
        ),
      ),
    );
  }

  void _onColorSelected(int r, int g, int b) {
    setState(() {
      _rgbValues[_selectedZone][0] = r.toDouble();
      _rgbValues[_selectedZone][1] = g.toDouble();
      _rgbValues[_selectedZone][2] = b.toDouble();
    });
  }

  Widget _buildEntryButton(BuildContext context) {
    final size = ResponsiveUtils.scaledSize(context, 40.0).clamp(36.0, 46.0);
    return GestureDetector(
      onTap: _openColorWheel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 2.0),
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF4500), // 朱砂红
              Color(0xFFE2C100), // 藤黄
              Color(0xFF2BAE66), // 竹绿
              Color(0xFF1661AB), // 石青
              Color(0xFF8B2671), // 紫棠
              Color(0xFFFF4500), // 回到起点
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.palette_outlined,
            color: Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
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
        body: SafeArea(
          child: LayoutBuilder(
          builder: (context, constraints) {
            // 根据可用空间动态计算各部分高度
            final isSmallScreen = ResponsiveUtils.isSmallScreen(context);
            final availableHeight = constraints.maxHeight;
            
            // 动态高度分配
            final topBarHeight = ResponsiveUtils.scaledHeight(context, 80.0).clamp(70.0, 90.0);
            final deviceDisplayHeight = isSmallScreen 
                ? availableHeight * 0.18  // 小屏幕：18%
                : availableHeight * 0.22; // 大屏幕：22%
            final spacing1 = isSmallScreen ? 24.0 : 40.0;
            
            return SingleChildScrollView(  // ✅ 添加滚动支持，防止overflow
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: availableHeight,
                ),
                child: Column(
                  children: [
                    // 顶部栏
                    SizedBox(
                      height: topBarHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveUtils.horizontalPadding(context),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  iconSize: ResponsiveUtils.scaledSize(context, 24.0).clamp(20.0, 28.0),
                                  onPressed: _handleBackNavigation,
                                ),
                                _buildEntryButton(context),
                              ],
                            ),
                            Text(
                              '色彩设置',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: ResponsiveUtils.scaledFontSize(
                                  context, 
                                  18.0,
                                  minSize: 16.0,
                                  maxSize: 20.0,
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert, color: Colors.white),
                              iconSize: ResponsiveUtils.scaledSize(context, 24.0).clamp(20.0, 28.0),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // 设备展示
                    Container(
                      height: deviceDisplayHeight.clamp(140.0, 200.0),
                      margin: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.horizontalPadding(context) * 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[900]?.withAlpha(77),
                        borderRadius: BorderRadius.circular(
                          ResponsiveUtils.scaledSize(context, 20.0).clamp(16.0, 24.0),
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: ResponsiveUtils.width(context, 70).clamp(240.0, 320.0),
                          height: ResponsiveUtils.scaledSize(context, 70.0).clamp(60.0, 80.0),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.directions_car, 
                              color: Colors.white, 
                              size: ResponsiveUtils.scaledSize(context, 40.0).clamp(32.0, 48.0),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: spacing1),
            
                    // 区域选择按钮
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.horizontalPadding(context),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildZoneButton(context, 'L', 0),
                          SizedBox(width: ResponsiveUtils.scaledSize(context, 12.0).clamp(8.0, 16.0)),
                          _buildZoneButton(context, 'M', 1),
                          SizedBox(width: ResponsiveUtils.scaledSize(context, 12.0).clamp(8.0, 16.0)),
                          _buildZoneButton(context, 'R', 2),
                          SizedBox(width: ResponsiveUtils.scaledSize(context, 12.0).clamp(8.0, 16.0)),
                          _buildZoneButton(context, 'B', 3),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: isSmallScreen ? 40.0 : 60.0),
            
                    // RGB滑块（移除Expanded，使用固定高度）
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.horizontalPadding(context) * 2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildColorSlider(
                            context,
                            'R',
                            Colors.red,
                            _rgbValues[_selectedZone][0],
                            (value) {
                              setState(() {
                                _rgbValues[_selectedZone][0] = value;
                              });
                            },
                            0,
                          ),
                          
                          SizedBox(height: isSmallScreen ? 16.0 : 24.0),
                          
                          _buildColorSlider(
                            context,
                            'G',
                            Colors.green,
                            _rgbValues[_selectedZone][1],
                            (value) {
                              setState(() {
                                _rgbValues[_selectedZone][1] = value;
                              });
                            },
                            1,
                          ),
                          
                          SizedBox(height: isSmallScreen ? 16.0 : 24.0),
                          
                          _buildColorSlider(
                            context,
                            'B',
                            Colors.blue,
                            _rgbValues[_selectedZone][2],
                            (value) {
                              setState(() {
                                _rgbValues[_selectedZone][2] = value;
                              });
                            },
                            2,
                          ),
                        ],
                      ),
                    ),
            
                    
                    SizedBox(height: isSmallScreen ? 30.0 : 40.0),
                    
                    // 循环速度控制
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.horizontalPadding(context) * 2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '循环速度',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: ResponsiveUtils.scaledFontSize(
                                    context, 
                                    18.0,
                                    minSize: 16.0,
                                    maxSize: 20.0,
                                  ),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          
                          SizedBox(height: isSmallScreen ? 12.0 : 16.0),
                  
                  Row(
                    children: [
                      const Text('慢', style: TextStyle(color: Colors.white70)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                          ),
                          child: Slider(
                            value: _loopSpeed,
                            min: 0,
                            max: 1,
                            divisions: 4,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white30,
                            onChanged: (value) {
                              setState(() {
                                _loopSpeed = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const Text('快', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            
                    SizedBox(height: isSmallScreen ? 30.0 : 40.0),
                    
                    // 应用按钮
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveUtils.horizontalPadding(context),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: ResponsiveUtils.buttonHeight(context),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF6366F1),
                        Color(0xFFEC4899),
                        Colors.red,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      final deviceProvider = Provider.of<DeviceProvider>(
                        context,
                        listen: false,
                      );
                      
                      // 应用选中区域的颜色
                      deviceProvider.setRGBColor(
                        _rgbValues[_selectedZone].map((e) => e.toInt()).toList(),
                      );
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已应用颜色: RGB(${_rgbValues[_selectedZone][0].toInt()}, '
                            '${_rgbValues[_selectedZone][1].toInt()}, '
                            '${_rgbValues[_selectedZone][2].toInt()})',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      '应用设置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: isSmallScreen ? 30.0 : 40.0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

  Widget _buildZoneButton(BuildContext context, String label, int index) {
    final isSelected = _selectedZone == index;
    final rgb = _rgbValues[index];
    final color = Color.fromRGBO(
      rgb[0].toInt(),
      rgb[1].toInt(),
      rgb[2].toInt(),
      1,
    );
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedZone = index;
        });
      },
      child: Container(
        width: ResponsiveUtils.scaledSize(context, 70.0).clamp(60.0, 80.0),
        height: ResponsiveUtils.scaledSize(context, 110.0).clamp(90.0, 120.0),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(ResponsiveUtils.scaledSize(context, 35.0).clamp(30.0, 40.0)),
          border: isSelected ? Border.all(
            color: Colors.white, 
            width: ResponsiveUtils.scaledSize(context, 3.0).clamp(2.0, 4.0),
          ) : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: ResponsiveUtils.scaledFontSize(context, 32.0, minSize: 28.0, maxSize: 36.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorSlider(
    BuildContext context,
    String label,
    Color color,
    double value,
    ValueChanged<double> onChanged,
    int channelIndex,
  ) {
    final isSmallScreen = ResponsiveUtils.isSmallScreen(context);
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: ResponsiveUtils.scaledFontSize(context, 20.0, minSize: 18.0, maxSize: 22.0),
            fontWeight: FontWeight.bold,
          ),
        ),
        
        SizedBox(width: isSmallScreen ? 16.0 : 20.0),
        
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: ResponsiveUtils.scaledSize(context, 8.0).clamp(6.0, 10.0),
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: ResponsiveUtils.scaledSize(context, 12.0).clamp(10.0, 14.0),
              ),
              overlayShape: RoundSliderOverlayShape(
                overlayRadius: ResponsiveUtils.scaledSize(context, 20.0).clamp(16.0, 24.0),
              ),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              activeColor: color,
              inactiveColor: Colors.white30,
              onChanged: onChanged,
            ),
          ),
        ),
        
        SizedBox(width: isSmallScreen ? 8.0 : 12.0),
        
        SizedBox(
          width: ResponsiveUtils.scaledSize(context, 50.0).clamp(45.0, 55.0),
          child: _editingChannel == channelIndex
              ? TextField(
                  controller: _valueController,
                  focusNode: _valueFocusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ResponsiveUtils.scaledFontSize(context, 16.0, minSize: 14.0, maxSize: 18.0),
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  onSubmitted: (_) => _commitEdit(),
                )
              : GestureDetector(
                  onTap: () => _startEditing(channelIndex, value),
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: ResponsiveUtils.scaledFontSize(context, 16.0, minSize: 14.0, maxSize: 18.0),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
        ),
      ],
    );
  }
}

