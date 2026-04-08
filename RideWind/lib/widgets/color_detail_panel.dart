import 'package:flutter/material.dart';
import '../data/traditional_chinese_colors.dart';

/// 选中颜色详情面板 — 显示在圆环中心区域（白色背景适配）
class ColorDetailPanel extends StatelessWidget {
  final ChineseColor? color;
  final VoidCallback? onConfirm;

  const ColorDetailPanel({
    super.key,
    this.color,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: color != null
          ? _buildColorContent(color!)
          : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return const SizedBox(
      key: ValueKey('placeholder'),
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, color: Colors.black26, size: 28),
          SizedBox(height: 6),
          Text(
            '点击色块选色',
            style: TextStyle(color: Colors.black38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildColorContent(ChineseColor c) {
    return Container(
      key: ValueKey('${c.family}_${c.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            c.name,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: c.toColor(),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: c.toColor().withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'R:${c.r}  G:${c.g}  B:${c.b}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 20,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '#${c.r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
            '${c.g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
            '${c.b.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 18,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              c.colorDescription,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 18,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: onConfirm,
              style: TextButton.styleFrom(
                backgroundColor: c.toColor(),
                foregroundColor: c.textColor,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('使用此色', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
