"""
Generate treadmill menu icon (68x68) and text label ("RUN" 80x27) as RGB565 C arrays.
Style: white line art on black background, matching existing menu icons.
"""
from PIL import Image, ImageDraw, ImageFont
import struct

def rgb888_to_rgb565(r, g, b):
    """Convert RGB888 to RGB565 (big-endian bytes for F4 format)."""
    val = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
    return val

def image_to_c_array(img, var_name):
    """Convert PIL Image to C array of RGB565 big-endian bytes (F4 format)."""
    w, h = img.size
    pixels = img.load()
    data = []
    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y][:3]
            val = rgb888_to_rgb565(r, g, b)
            # Big-endian (F4 format): high byte first
            data.append(val >> 8)
            data.append(val & 0xFF)
    
    lines = []
    lines.append(f"/* Auto-generated treadmill icon: {w}x{h} RGB565 */")
    lines.append(f"const unsigned char {var_name}[] = {{")
    
    # 16 bytes per line
    for i in range(0, len(data), 16):
        chunk = data[i:i+16]
        hex_str = ", ".join(f"0x{b:02X}" for b in chunk)
        lines.append(f"    {hex_str},")
    
    lines.append("};")
    return "\n".join(lines)

def draw_treadmill_icon(size=68):
    """Draw a simple treadmill icon: running person + treadmill base."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    white = (255, 255, 255, 255)
    gray = (160, 160, 160, 255)
    
    # Scale factor
    s = size / 68.0
    
    # --- Treadmill base (bottom part) ---
    # Belt/platform
    belt_y = int(48 * s)
    belt_h = int(4 * s)
    belt_x1 = int(12 * s)
    belt_x2 = int(56 * s)
    draw.rounded_rectangle(
        [belt_x1, belt_y, belt_x2, belt_y + belt_h],
        radius=int(2 * s), fill=gray
    )
    
    # Front leg
    draw.line([(int(50 * s), belt_y + belt_h), (int(52 * s), int(58 * s))], 
              fill=gray, width=int(2 * s))
    # Rear leg
    draw.line([(int(16 * s), belt_y + belt_h), (int(14 * s), int(58 * s))],
              fill=gray, width=int(2 * s))
    
    # Handrail (vertical bar on right)
    draw.line([(int(50 * s), int(20 * s)), (int(50 * s), belt_y)],
              fill=gray, width=int(2 * s))
    # Handrail top
    draw.line([(int(46 * s), int(20 * s)), (int(54 * s), int(20 * s))],
              fill=gray, width=int(2 * s))
    
    # --- Running person (center-left) ---
    # Head
    head_cx = int(30 * s)
    head_cy = int(14 * s)
    head_r = int(5 * s)
    draw.ellipse([head_cx - head_r, head_cy - head_r, 
                  head_cx + head_r, head_cy + head_r], fill=white)
    
    # Body (torso) - slightly leaning forward
    body_top = (int(30 * s), int(20 * s))
    body_bot = (int(28 * s), int(36 * s))
    draw.line([body_top, body_bot], fill=white, width=int(3 * s))
    
    # Arms - one forward, one back (running pose)
    # Back arm
    draw.line([(int(29 * s), int(24 * s)), (int(22 * s), int(30 * s))],
              fill=white, width=int(2 * s))
    # Front arm
    draw.line([(int(30 * s), int(24 * s)), (int(38 * s), int(28 * s))],
              fill=white, width=int(2 * s))
    
    # Legs - running stride
    hip = (int(28 * s), int(36 * s))
    # Back leg (extended behind)
    draw.line([hip, (int(20 * s), int(44 * s))], fill=white, width=int(2.5 * s))
    draw.line([(int(20 * s), int(44 * s)), (int(18 * s), int(47 * s))],
              fill=white, width=int(2 * s))
    # Front leg (bent forward)
    draw.line([hip, (int(34 * s), int(43 * s))], fill=white, width=int(2.5 * s))
    draw.line([(int(34 * s), int(43 * s)), (int(36 * s), int(47 * s))],
              fill=white, width=int(2 * s))
    
    # --- Small speed lines (motion indicator) ---
    for i in range(3):
        ly = int((22 + i * 8) * s)
        lx1 = int(8 * s)
        lx2 = int(14 * s)
        draw.line([(lx1, ly), (lx2, ly)], fill=gray, width=1)
    
    return img.convert("RGB")

def draw_text_label(text="RUN", width=80, height=27):
    """Draw text label bitmap matching existing menu text style."""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    
    white = (255, 255, 255, 255)
    
    # Try to use a bold font, fall back to default
    font_size = int(height * 0.75)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", font_size)
    except:
        try:
            font = ImageFont.truetype("arial.ttf", font_size)
        except:
            font = ImageFont.load_default()
    
    # Center text
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (width - tw) // 2
    ty = (height - th) // 2 - bbox[1]
    
    draw.text((tx, ty), text, fill=white, font=font)
    
    return img.convert("RGB")

# Generate icon
icon_img = draw_treadmill_icon(68)
icon_c = image_to_c_array(icon_img, "gImage_treadmill_68_68")

# Generate text label
text_img = draw_text_label("RUN", 80, 27)
text_c = image_to_c_array(text_img, "gImage_treadmill_text")

# Write to C file
output = f"""/**
 * @file treadmill_icon.c
 * @brief Auto-generated treadmill menu icon (68x68) and text label (80x27).
 *        RGB565 big-endian format matching F4 style.
 *        Replace with proper designed bitmaps later.
 */

{icon_c}

{text_c}
"""

output_path = r"c:\Users\Klara\Desktop\4.8\ridewind-esp\main\resources\treadmill_icon.c"
with open(output_path, "w", encoding="utf-8") as f:
    f.write(output)

print(f"Generated: {output_path}")
print(f"Icon: 68x68 = {68*68*2} bytes")
print(f"Text: 80x27 = {80*27*2} bytes")
