import re, sys

LO = (0, 180, 255)
MID = (255, 210, 80)
HI = (255, 40, 30)

def lerp(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return (int(c1[0]+(c2[0]-c1[0])*t), int(c1[1]+(c2[1]-c1[1])*t), int(c1[2]+(c2[2]-c1[2])*t))

def speed_color(pct):
    t = pct/100.0
    return lerp(LO, MID, t*2) if t <= 0.5 else lerp(MID, HI, (t-0.5)*2)

def parse_img(src, name):
    m = re.search(rf'const unsigned char {re.escape(name)}\[\d+\]\s*=\s*\{{', src)
    if not m: return None
    idx = m.end()
    bc = 1
    while idx < len(src) and bc > 0:
        if src[idx]=='{': bc+=1
        elif src[idx]=='}': bc-=1
        idx+=1
    content = src[m.end():idx-1]
    # CRITICAL FIX: Remove C comments before parsing hex values
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    return bytes([int(v,16) for v in re.findall(r'0[xX][0-9A-Fa-f]+', content)])

def tint(data, color):
    tr,tg,tb = color
    out = bytearray()
    for i in range(0, len(data), 2):
        val = (data[i]<<8)|data[i+1]
        if val == 0:
            out.extend(b'\x00\x00')
        else:
            r=((val>>11)&0x1F)*255//31
            g=((val>>5)&0x3F)*255//63
            b=(val&0x1F)*255//31
            lum = (r*299+g*587+b*114)/255000.0
            lum = lum**0.85
            nr=min(255,int(tr*lum))
            ng=min(255,int(tg*lum))
            nb=min(255,int(tb*lum))
            v = ((nr&0xF8)<<8)|((ng&0xFC)<<3)|(nb>>3)
            out.append((v>>8)&0xFF)
            out.append(v&0xFF)
    return bytes(out)

src_path = r'C:\Users\Klara\Desktop\4.8\ridewind-esp\main\resources\ui_images.c'
with open(src_path, 'r', encoding='utf-8', errors='ignore') as f:
    src = f.read()

names = ['gImage_speed_0_5153','gImage_speed_1_1553','gImage_speed_2_4853',
         'gImage_speed_3_4353','gImage_speed_4_5153','gImage_speed_5_4653',
         'gImage_speed_6_4953','gImage_speed_7_4653','gImage_speed_8_4953',
         'gImage_speed_9_4953']
widths = [51,40,48,43,51,46,49,46,49,49]

digits_raw = []
all_ok = True
for i, name in enumerate(names):
    d = parse_img(src, name)
    expected = widths[i] * 53 * 2
    status = "OK" if len(d)==expected else "MISMATCH"
    print(f'  {name}: {len(d)} bytes (expected {expected}) {status}')
    if len(d) != expected:
        all_ok = False
    digits_raw.append(d)

if not all_ok:
    print("ERROR: Size mismatch detected!")
    sys.exit(1)

out_c = r'C:\Users\Klara\Desktop\4.8\ridewind-esp\main\resources\colored_digits.c'
out_h = r'C:\Users\Klara\Desktop\4.8\ridewind-esp\main\resources\colored_digits.h'

with open(out_c, 'w') as f:
    f.write('/* Auto-generated colored digits - comments stripped, exact pixel match */\n')
    f.write('#include "colored_digits.h"\n\n')
    f.write('const uint8_t colored_digit_widths[10] = {\n    ')
    f.write(', '.join(str(w) for w in widths))
    f.write('\n};\n\n')
    total = 0
    for ci in range(11):
        color = speed_color(ci*10)
        for di in range(10):
            colored = tint(digits_raw[di], color)
            f.write(f'const unsigned char gImage_speed_{di}_c{ci}[{len(colored)}] = {{\n')
            for row in range(0, len(colored), 16):
                chunk = colored[row:row+16]
                f.write('  '+','.join(f'0x{b:02X}' for b in chunk)+',\n')
            f.write('};\n\n')
            total += len(colored)

with open(out_h, 'w') as f:
    f.write('#pragma once\n#include <stdint.h>\n\n')
    f.write('#define COLORED_DIGIT_STEPS 11\n\n')
    f.write('extern const uint8_t colored_digit_widths[10];\n\n')
    for ci in range(11):
        for di in range(10):
            size = widths[di] * 53 * 2
            f.write(f'extern const unsigned char gImage_speed_{di}_c{ci}[{size}];\n')
        f.write('\n')

print(f'\nDone! Total: {total} bytes ({total/1024:.1f} KB)')
print('All sizes match expected values - no header contamination.')
