#!/usr/bin/env python3
"""
Extract specific image arrays from F4 pic.h into separate C files for ESP32.
Generates ui_images.c and ui_images.h for the ridewind-esp project.
"""

import re
import os

PIC_H = os.path.join(os.path.dirname(__file__), 
    '../../f4_26_1.1/f4_26_1.1/f4_26_1.1/Core/Inc/pic.h')

OUTPUT_C = os.path.join(os.path.dirname(__file__), '../main/resources/ui_images.c')
OUTPUT_H = os.path.join(os.path.dirname(__file__), '../main/resources/ui_images.h')

# Arrays we need to extract (name -> True means needed)
NEEDED_ARRAYS = [
    # Background
    'gImage_beijing_240_240',
    # Speed UI1
    'gImage_fengshubiao_202_43',
    'gImage_speed_kmh_6225',
    'gImage_speed_mph_5225',
    # Status LEDs
    'gImage_h_deng_1221',
    'gImage_l_deng_1221', 
    'gImage_c_deng_1221',
    # Large digits 0-9 (for speed/brightness/volume)
    'gImage_speed_0_5153',
    'gImage_speed_1_1553',
    'gImage_speed_2_4853',
    'gImage_speed_3_4353',
    'gImage_speed_4_5153',
    'gImage_speed_5_4653',
    'gImage_speed_6_4953',
    'gImage_speed_7_4653',
    'gImage_speed_8_4953',
    'gImage_speed_9_4953',
    # Color preset UI2
    'gImage_color_183_57',
    'gImage_color_rize_69_28',
    # RGB UI3 - letter backgrounds (normal)
    'gImage_RGB_b_r_4853',
    'gImage_RGB_b_g_4853',
    'gImage_RGB_b_b_4753',
    # RGB UI3 - letter backgrounds (highlighted)
    'gImage_RGB_h_r_4853',
    'gImage_RGB_l_g_4853',
    'gImage_RGB_lan_b_4653',
    # RGB UI3 - strip names
    'gImage_RGB_middle_105_27',
    'gImage_RGB_left_5527',
    'gImage_RGB_right_8033',
    'gImage_RGB_back_7727',
    # RGB UI3 - Red digits (h_ prefix)
    'gImage_h_0_2425', 'gImage_h_1_1125', 'gImage_h_2_2225', 'gImage_h_3_1925',
    'gImage_h_4_2325', 'gImage_h_5_2125', 'gImage_h_6_2325', 'gImage_h_7_2125',
    'gImage_h_8_2125', 'gImage_h_9_2225',
    # RGB UI3 - Green digits (l_ prefix)
    'gImage_l_0_2425', 'gImage_l_1_0925', 'gImage_l_2_2325', 'gImage_l_3_2125',
    'gImage_l_4_2425', 'gImage_l_5_2225', 'gImage_l_6_2325', 'gImage_l_7_2125',
    'gImage_l_8_2325', 'gImage_l_9_2325',
    # RGB UI3 - Blue digits (b_ prefix)
    'gImage_b_0_2425', 'gImage_b_1_0925', 'gImage_b_2_2125', 'gImage_b_3_1925',
    'gImage_b_4_2325', 'gImage_b_5_2125', 'gImage_b_6_2325', 'gImage_b_7_2125',
    'gImage_b_8_2225', 'gImage_b_9_2325',
    # Brightness UI4
    'gImage_brt_6923',
]

# Defines we need to extract
NEEDED_DEFINES = [
    # Speed UI1 coordinates
    'speed_num_high', 'jianju', 'x_qi', 'y_qi',
    'fengshubiao_x', 'fengshubiao_y', 'fengshubiao_width', 'fengshubiao_high',
    'speed_kmh_x', 'speed_kmh_y', 'speed_kmh_width', 'speed_kmh_high',
    'speed_mph_x', 'speed_mph_y', 'speed_mph_width', 'speed_mph_high',
    # Status LED sizes
    'h_deng_width', 'h_deng_high',
    'l_deng_width', 'l_deng_high',
    'c_deng_width', 'c_deng_high',
    # Large digit widths
    'speed_0_width', 'speed_1_width', 'speed_2_width', 'speed_3_width',
    'speed_4_width', 'speed_5_width', 'speed_6_width', 'speed_7_width',
    'speed_8_width', 'speed_9_width',
    # Color preset UI2
    'color_x', 'color_y', 'color_width', 'color_high',
    'color_rize_x', 'color_rize_y', 'color_rize_width', 'color_rize_high',
    'pei_se_x', 'pei_se_y',
    # RGB UI3
    'num_r_x', 'num_r_y', 'num_g_x', 'num_g_y', 'num_b_x', 'num_b_y',
    'RGB_b_r_x', 'RGB_b_r_y', 'RGB_b_r_width', 'RGB_b_r_high',
    'RGB_b_g_x', 'RGB_b_g_y', 'RGB_b_g_width', 'RGB_b_g_high',
    'RGB_b_b_x', 'RGB_b_b_y', 'RGB_b_b_width', 'RGB_b_b_high',
    'RGB_h_r_width', 'RGB_h_r_high',
    'RGB_l_g_width', 'RGB_l_g_high',
    'RGB_lan_b_width', 'RGB_lan_b_high',
    'RGB_left_x', 'RGB_left_y', 'RGB_left_width', 'RGB_left_high',
    'RGB_middle_width', 'RGB_middle_high',
    'RGB_right_width', 'RGB_right_high',
    'RGB_back_width', 'RGB_back_high',
    'rgb_high',
    # RGB colored digit widths
    'h_0_width', 'h_1_width', 'h_2_width', 'h_3_width', 'h_4_width',
    'h_5_width', 'h_6_width', 'h_7_width', 'h_8_width', 'h_9_width',
    'l_0_width', 'l_1_width', 'l_2_width', 'l_3_width', 'l_4_width',
    'l_5_width', 'l_6_width', 'l_7_width', 'l_8_width', 'l_9_width',
    'b_0_width', 'b_1_width', 'b_2_width', 'b_3_width', 'b_4_width',
    'b_5_width', 'b_6_width', 'b_7_width', 'b_8_width', 'b_9_width',
    # Brightness UI4
    'ui4_jianju', 'ui4_x_qi', 'ui4_Y_qi',
    'brt_x', 'brt_y', 'brt_width', 'brt_high',
]

def extract():
    print(f"Reading {PIC_H}...")
    with open(PIC_H, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    lines = content.split('\n')
    print(f"Total lines: {len(lines)}")
    
    # Extract #define values
    defines = {}
    define_pattern = re.compile(r'#define\s+(\w+)\s+(.+)')
    for line in lines:
        m = define_pattern.match(line.strip())
        if m:
            name = m.group(1)
            if name in NEEDED_DEFINES:
                value = m.group(2).strip()
                # Remove trailing comments
                if '//' in value:
                    value = value[:value.index('//')].strip()
                defines[name] = value
    
    print(f"Found {len(defines)}/{len(NEEDED_DEFINES)} defines")
    missing_defines = set(NEEDED_DEFINES) - set(defines.keys())
    if missing_defines:
        print(f"Missing defines: {missing_defines}")
    
    # Extract arrays
    arrays = {}
    # Pattern: const unsigned char NAME[SIZE] = { ... };
    # Arrays can span many lines
    array_start_pattern = re.compile(
        r'const\s+unsigned\s+char\s+(\w+)\s*\[\s*(\d+)\s*\]\s*=\s*\{')
    
    i = 0
    while i < len(lines):
        m = array_start_pattern.search(lines[i])
        if m:
            name = m.group(1)
            size = int(m.group(2))
            if name in NEEDED_ARRAYS:
                # Collect all lines until closing };
                arr_lines = [lines[i]]
                j = i + 1
                while j < len(lines) and '};' not in lines[j-1] and '};' not in lines[i] if j == i+1 else True:
                    arr_lines.append(lines[j])
                    if '};' in lines[j]:
                        break
                    j += 1
                
                full_text = '\n'.join(arr_lines)
                arrays[name] = (size, full_text)
                print(f"  Extracted {name}[{size}] ({size*1} bytes)")
                i = j + 1
                continue
        i += 1
    
    print(f"\nFound {len(arrays)}/{len(NEEDED_ARRAYS)} arrays")
    missing_arrays = set(NEEDED_ARRAYS) - set(arrays.keys())
    if missing_arrays:
        print(f"Missing arrays: {missing_arrays}")
    
    # Also need to find gImage_color_183_57 which might have a different pattern
    # Let's check what we're missing and search more carefully
    for name in missing_arrays:
        # Try a broader search
        for idx, line in enumerate(lines):
            if name in line and '=' in line:
                print(f"  Found reference to {name} at line {idx+1}: {line[:100]}")
                break
    
    # Generate ui_images.h
    print(f"\nGenerating {OUTPUT_H}...")
    with open(OUTPUT_H, 'w', encoding='utf-8') as f:
        f.write('#pragma once\n')
        f.write('#include <stdint.h>\n\n')
        f.write('/**\n')
        f.write(' * @file ui_images.h\n')
        f.write(' * @brief Image resources extracted from F4 STM32 pic.h for sub-UI rendering.\n')
        f.write(' *        All images are RGB565 format, black background.\n')
        f.write(' */\n\n')
        
        f.write('/* ══════ Coordinate & Size Defines ══════ */\n\n')
        
        # Group defines by category
        categories = {
            'Speed UI1 - Number rendering': ['speed_num_high', 'jianju', 'x_qi', 'y_qi'],
            'Speed UI1 - Wind gauge': ['fengshubiao_x', 'fengshubiao_y', 'fengshubiao_width', 'fengshubiao_high'],
            'Speed UI1 - Unit labels': ['speed_kmh_x', 'speed_kmh_y', 'speed_kmh_width', 'speed_kmh_high',
                                         'speed_mph_x', 'speed_mph_y', 'speed_mph_width', 'speed_mph_high'],
            'Status LED indicators': ['h_deng_width', 'h_deng_high', 'l_deng_width', 'l_deng_high',
                                       'c_deng_width', 'c_deng_high'],
            'Large digit widths (height = speed_num_high = 53)': [
                'speed_0_width', 'speed_1_width', 'speed_2_width', 'speed_3_width', 'speed_4_width',
                'speed_5_width', 'speed_6_width', 'speed_7_width', 'speed_8_width', 'speed_9_width'],
            'Color Preset UI2': ['color_x', 'color_y', 'color_width', 'color_high',
                                  'color_rize_x', 'color_rize_y', 'color_rize_width', 'color_rize_high',
                                  'pei_se_x', 'pei_se_y'],
            'RGB UI3 - Number positions': ['num_r_x', 'num_r_y', 'num_g_x', 'num_g_y', 'num_b_x', 'num_b_y'],
            'RGB UI3 - Letter backgrounds': [
                'RGB_b_r_x', 'RGB_b_r_y', 'RGB_b_r_width', 'RGB_b_r_high',
                'RGB_b_g_x', 'RGB_b_g_y', 'RGB_b_g_width', 'RGB_b_g_high',
                'RGB_b_b_x', 'RGB_b_b_y', 'RGB_b_b_width', 'RGB_b_b_high',
                'RGB_h_r_width', 'RGB_h_r_high', 'RGB_l_g_width', 'RGB_l_g_high',
                'RGB_lan_b_width', 'RGB_lan_b_high'],
            'RGB UI3 - Strip names': [
                'RGB_left_x', 'RGB_left_y', 'RGB_left_width', 'RGB_left_high',
                'RGB_middle_width', 'RGB_middle_high',
                'RGB_right_width', 'RGB_right_high',
                'RGB_back_width', 'RGB_back_high'],
            'RGB UI3 - Colored digit sizes (height = rgb_high)': ['rgb_high',
                'h_0_width', 'h_1_width', 'h_2_width', 'h_3_width', 'h_4_width',
                'h_5_width', 'h_6_width', 'h_7_width', 'h_8_width', 'h_9_width',
                'l_0_width', 'l_1_width', 'l_2_width', 'l_3_width', 'l_4_width',
                'l_5_width', 'l_6_width', 'l_7_width', 'l_8_width', 'l_9_width',
                'b_0_width', 'b_1_width', 'b_2_width', 'b_3_width', 'b_4_width',
                'b_5_width', 'b_6_width', 'b_7_width', 'b_8_width', 'b_9_width'],
            'Brightness UI4': ['ui4_jianju', 'ui4_x_qi', 'ui4_Y_qi',
                                'brt_x', 'brt_y', 'brt_width', 'brt_high'],
        }
        
        for cat_name, cat_defines in categories.items():
            f.write(f'/* {cat_name} */\n')
            for d in cat_defines:
                if d in defines:
                    f.write(f'#define F4_{d.upper()}  {defines[d]}\n')
                else:
                    f.write(f'/* #define F4_{d.upper()}  MISSING */\n')
            f.write('\n')
        
        f.write('/* ══════ Image Array Declarations ══════ */\n\n')
        
        arr_categories = {
            'Full-screen background (240x240)': ['gImage_beijing_240_240'],
            'Speed UI1': ['gImage_fengshubiao_202_43', 'gImage_speed_kmh_6225', 'gImage_speed_mph_5225'],
            'Status LED indicators (12x21)': ['gImage_h_deng_1221', 'gImage_l_deng_1221', 'gImage_c_deng_1221'],
            'Large digits 0-9 (height=53, variable width)': [
                'gImage_speed_0_5153', 'gImage_speed_1_1553', 'gImage_speed_2_4853',
                'gImage_speed_3_4353', 'gImage_speed_4_5153', 'gImage_speed_5_4653',
                'gImage_speed_6_4953', 'gImage_speed_7_4653', 'gImage_speed_8_4953',
                'gImage_speed_9_4953'],
            'Color Preset UI2': ['gImage_color_183_57', 'gImage_color_rize_69_28'],
            'RGB UI3 - Letter backgrounds': [
                'gImage_RGB_b_r_4853', 'gImage_RGB_b_g_4853', 'gImage_RGB_b_b_4753',
                'gImage_RGB_h_r_4853', 'gImage_RGB_l_g_4853', 'gImage_RGB_lan_b_4653'],
            'RGB UI3 - Strip names': [
                'gImage_RGB_middle_105_27', 'gImage_RGB_left_5527',
                'gImage_RGB_right_8033', 'gImage_RGB_back_7727'],
            'RGB UI3 - Red digits': [f'gImage_h_{i}_' for i in range(10)],
            'RGB UI3 - Green digits': [f'gImage_l_{i}_' for i in range(10)],
            'RGB UI3 - Blue digits': [f'gImage_b_{i}_' for i in range(10)],
            'Brightness UI4': ['gImage_brt_6923'],
        }
        
        for cat_name, cat_arrays in arr_categories.items():
            f.write(f'/* {cat_name} */\n')
            for a in cat_arrays:
                # Find actual name in arrays dict
                actual = None
                for key in arrays:
                    if key.startswith(a) or key == a:
                        actual = key
                        break
                if actual and actual in arrays:
                    size = arrays[actual][0]
                    f.write(f'extern const unsigned char {actual}[{size}];\n')
                else:
                    f.write(f'/* extern const unsigned char {a}[]; MISSING */\n')
            f.write('\n')
    
    # Generate ui_images.c
    print(f"Generating {OUTPUT_C}...")
    with open(OUTPUT_C, 'w', encoding='utf-8') as f:
        f.write('#include "ui_images.h"\n\n')
        f.write('/**\n')
        f.write(' * @file ui_images.c\n')
        f.write(' * @brief Image data arrays extracted from F4 STM32 pic.h.\n')
        f.write(' *        All arrays are const (stored in flash, not RAM on ESP32).\n')
        f.write(' */\n\n')
        
        for name in NEEDED_ARRAYS:
            if name in arrays:
                size, text = arrays[name]
                f.write(f'/* {name} ({size} bytes) */\n')
                f.write(text)
                f.write('\n\n')
            else:
                f.write(f'/* {name} - NOT FOUND IN pic.h */\n\n')
    
    total_bytes = sum(s for s, _ in arrays.values())
    print(f"\nDone! Total image data: {total_bytes:,} bytes ({total_bytes/1024:.1f} KB)")
    print(f"Arrays extracted: {len(arrays)}/{len(NEEDED_ARRAYS)}")

if __name__ == '__main__':
    extract()
