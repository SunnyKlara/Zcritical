#!/usr/bin/env python3
"""
Generate pre-rendered colored digit bitmaps for throttle mode.

Reads the existing white digit images from ui_images.c, TRIMS black padding
from left/right edges, applies Tixing-style color tinting with proper
anti-aliasing preservation, and outputs a C source file with 11 color
variants (0%-100% in 10% steps).

Key improvement: digits are trimmed to their actual content width,
eliminating black padding that causes overlap artifacts when digits
are placed adjacent to each other.
"""

import re
import os

# Tixing color stops
LO = (0, 180, 255)    # Blue
MID = (255, 210, 80)  # Yellow
HI = (255, 40, 30)    # Red

def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return (
        int(c1[0] + (c2[0] - c1[0]) * t),
        int(c1[1] + (c2[1] - c1[1]) * t),
        int(c1[2] + (c2[2] - c1[2]) * t),
    )

def speed_color(percent):
    t = percent / 100.0
    if t <= 0.5:
        return lerp_color(LO, MID, t * 2.0)
    else:
        return lerp_color(MID, HI, (t - 0.5) * 2.0)

def rgb565_to_rgb888(hi, lo):
    val = (hi << 8) | lo
    r = ((val >> 11) & 0x1F) * 255 // 31
    g = ((val >> 5) & 0x3F) * 255 // 63
    b = (val & 0x1F) * 255 // 31
    return r, g, b

def rgb888_to_rgb565_be(r, g, b):
    val = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    return (val >> 8) & 0xFF, val & 0xFF

def tint_pixel(src_r, src_g, src_b, tint_r, tint_g, tint_b):
    lum = (src_r * 299 + src_g * 587 + src_b * 114) / 1000.0 / 255.0
    lum = lum ** 0.85
    out_r = min(255, int(tint_r * lum))
    out_g = min(255, int(tint_g * lum))
    out_b = min(255, int(tint_b * lum))
    return out_r, out_g, out_b

def parse_image_data(c_source, name):
    start_pattern = rf'const unsigned char {re.escape(name)}\[\d+\]\s*=\s*\{{'
    match = re.search(start_pattern, c_source)
    if not match:
        return None
    start_idx = match.end()
    brace_count = 1
    idx = start_idx
    while idx < len(c_source) and brace_count > 0:
        if c_source[idx] == '{': brace_count += 1
        elif c_source[idx] == '}': brace_count -= 1
        idx += 1
    content = c_source[start_idx:idx-1]
    hex_values = re.findall(r'0[xX][0-9A-Fa-f]+', content)
    return bytes([int(v, 16) for v in hex_values])

def trim_bitmap(raw_data, width, height):
    """Find the leftmost and rightmost non-black columns, return trimmed data and new width."""
    pixels = []
    for row in range(height):
        row_pixels = []
        for col in range(width):
            idx = (row * width + col) * 2
            val = (raw_data[idx] << 8) | raw_data[idx + 1]
            row_pixels.append(val)
        pixels.append(row_pixels)
    
    left = width
    for col in range(width):
        for row in range(height):
            if pixels[row][col] != 0x0000:
                left = col
                break
        if left == col:
            break
    
    right = 0
    for col in range(width - 1, -1, -1):
        for row in range(height):
            if pixels[row][col] != 0x0000:
                right = col
                break
        if right == col:
            break
    
    # Add 1px padding on each side for anti-aliasing safety
    left = max(0, left - 1)
    right = min(width - 1, right + 1)
    
    new_width = right - left + 1
    
    trimmed = bytearray()
    for row in range(height):
        for col in range(left, right + 1):
            idx = (row * width + col) * 2
            trimmed.append(raw_data[idx])
            trimmed.append(raw_data[idx + 1])
    
    return bytes(trimmed), new_width, left

def generate_colored_digit(raw_data, tint_rgb):
    result = bytearray()
    tint_r, tint_g, tint_b = tint_rgb
    for i in range(0, len(raw_data), 2):
        src_r, src_g, src_b = rgb565_to_rgb888(raw_data[i], raw_data[i+1])
        if src_r == 0 and src_g == 0 and src_b == 0:
            result.extend(b'\x00\x00')
        else:
            out_r, out_g, out_b = tint_pixel(src_r, src_g, src_b, tint_r, tint_g, tint_b)
            hi, lo = rgb888_to_rgb565_be(out_r, out_g, out_b)
            result.append(hi)
            result.append(lo)
    return bytes(result)

def main():
    src_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'main', 'resources', 'ui_images.c'))
    print(f"Reading: {src_path}")
    with open(src_path, 'r', encoding='utf-8', errors='ignore') as f:
        c_source = f.read()

    digit_names = [
        "gImage_speed_0_5153",
        "gImage_speed_1_1553",
        "gImage_speed_2_4853",
        "gImage_speed_3_4353",
        "gImage_speed_4_5153",
        "gImage_speed_5_4653",
        "gImage_speed_6_4953",
        "gImage_speed_7_4653",
        "gImage_speed_8_4953",
        "gImage_speed_9_4953",
    ]
    HEIGHT = 53

    print("Parsing and trimming digit bitmaps...")
    digit_data = []
    for name in digit_names:
        data = parse_image_data(c_source, name)
        if data is None:
            print(f"  ERROR: {name} not found")
            return
        orig_width = len(data) // 2 // HEIGHT
        trimmed, new_width, left_offset = trim_bitmap(data, orig_width, HEIGHT)
        print(f"  {name}: {orig_width}px -> {new_width}px (trimmed {orig_width - new_width}px padding)")
        digit_data.append((name, trimmed, new_width))

    color_steps = 11
    out_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'main', 'resources', 'colored_digits.c'))
    hdr_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'main', 'resources', 'colored_digits.h'))

    print(f"\nGenerating {color_steps} color variants...")
    total_bytes = 0

    with open(out_path, 'w') as f:
        f.write("/* Auto-generated colored digit bitmaps for throttle mode */\n")
        f.write("/* Digits are TRIMMED to content width (no black padding) */\n")
        f.write('#include "colored_digits.h"\n\n')

        f.write("const uint8_t colored_digit_widths[10] = {\n")
        f.write("    " + ", ".join(str(d[2]) for d in digit_data) + "\n")
        f.write("};\n\n")

        for ci in range(color_steps):
            percent = ci * 10
            color = speed_color(percent)
            print(f"  Step {ci} ({percent}%): RGB({color[0]},{color[1]},{color[2]})")

            for digit_idx, (name, trimmed_data, width) in enumerate(digit_data):
                colored = generate_colored_digit(trimmed_data, color)
                arr_name = f"gImage_speed_{digit_idx}_c{ci}"
                f.write(f"const unsigned char {arr_name}[{len(colored)}] = {{\n")
                for row in range(0, len(colored), 16):
                    chunk = colored[row:row+16]
                    f.write("  " + ",".join(f"0x{b:02X}" for b in chunk) + ",\n")
                f.write("};\n\n")
                total_bytes += len(colored)

    with open(hdr_path, 'w') as f:
        f.write("#pragma once\n#include <stdint.h>\n\n")
        f.write(f"#define COLORED_DIGIT_STEPS {color_steps}\n\n")
        f.write("extern const uint8_t colored_digit_widths[10];\n\n")
        for ci in range(color_steps):
            for digit_idx, (name, trimmed_data, width) in enumerate(digit_data):
                f.write(f"extern const unsigned char gImage_speed_{digit_idx}_c{ci}[{len(trimmed_data)}];\n")
            f.write("\n")

    print(f"\nDone! Total: {total_bytes} bytes ({total_bytes/1024:.1f} KB)")
    print(f"Trimmed widths: {[d[2] for d in digit_data]}")
    print(f"Output: {out_path}")
    print(f"Header: {hdr_path}")

if __name__ == '__main__':
    main()
