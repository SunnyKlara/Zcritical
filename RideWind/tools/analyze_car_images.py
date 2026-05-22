"""
分析 car_thumbnails 中所有 PNG 图片的实际车身占比。
输出 car_scale_map.json：每张图的 scale 系数（让所有车视觉大小统一）。

原理：
1. 读取每张 PNG，找到非透明像素的边界框 (bounding box)
2. 计算车身宽度占图片总宽度的比例 (content_ratio)
3. content_ratio 高的图（车身大）需要缩小，低的（车身小）需要放大
4. 归一化到目标范围：所有车最终显示宽度趋于一致
"""

import os
import json
from PIL import Image

THUMBNAILS_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'car_thumbnails')
OUTPUT_FILE = os.path.join(THUMBNAILS_DIR, 'car_scale_map.json')

def get_content_bounds(img):
    """获取非透明像素的边界框"""
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # 获取 alpha 通道
    alpha = img.split()[3]
    bbox = alpha.getbbox()  # (left, top, right, bottom) 或 None
    return bbox

def analyze_images():
    scale_map = {}
    ratios = []
    
    files = [f for f in os.listdir(THUMBNAILS_DIR) if f.lower().endswith('.png')]
    print(f"分析 {len(files)} 张图片...")
    
    for filename in files:
        filepath = os.path.join(THUMBNAILS_DIR, filename)
        try:
            img = Image.open(filepath)
            bbox = get_content_bounds(img)
            
            if bbox is None:
                # 完全透明的图片
                scale_map[filename] = 1.0
                continue
            
            left, top, right, bottom = bbox
            content_width = right - left
            content_height = bottom - top
            img_width, img_height = img.size
            
            # 车身宽度占图片宽度的比例
            width_ratio = content_width / img_width
            # 车身高度占图片高度的比例  
            height_ratio = content_height / img_height
            
            # 综合比例（取宽度为主，因为车是横向的）
            content_ratio = width_ratio
            ratios.append((filename, content_ratio, width_ratio, height_ratio))
            
        except Exception as e:
            print(f"  ❌ {filename}: {e}")
            scale_map[filename] = 1.0
    
    if not ratios:
        print("没有有效图片")
        return
    
    # 计算中位数作为基准
    sorted_ratios = sorted(ratios, key=lambda x: x[1])
    median_ratio = sorted_ratios[len(sorted_ratios) // 2][1]
    
    print(f"\n统计:")
    print(f"  图片数: {len(ratios)}")
    print(f"  最小占比: {sorted_ratios[0][1]:.3f} ({sorted_ratios[0][0]})")
    print(f"  最大占比: {sorted_ratios[-1][1]:.3f} ({sorted_ratios[-1][0]})")
    print(f"  中位数: {median_ratio:.3f}")
    
    # 计算 scale：让所有车的显示宽度趋于一致
    # scale = median_ratio / content_ratio
    # 但限制范围在 0.7 ~ 1.4，避免极端缩放
    for filename, content_ratio, w_ratio, h_ratio in ratios:
        scale = median_ratio / content_ratio
        scale = max(0.7, min(1.4, scale))
        scale_map[filename] = round(scale, 3)
    
    # 写入 JSON
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        json.dump(scale_map, f, indent=2, ensure_ascii=False)
    
    print(f"\n✅ 已生成: {OUTPUT_FILE}")
    print(f"   共 {len(scale_map)} 条记录")
    
    # 打印一些示例
    print("\n示例 (scale < 1.0 = 车身大需缩小, > 1.0 = 车身小需放大):")
    samples = sorted(scale_map.items(), key=lambda x: x[1])
    for name, scale in samples[:5]:
        print(f"  {scale:.3f}  {name}")
    print("  ...")
    for name, scale in samples[-5:]:
        print(f"  {scale:.3f}  {name}")

if __name__ == '__main__':
    analyze_images()
