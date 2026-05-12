"""Convert 4 WAV layers to C headers for multi-layer engine synth."""
import struct, sys, os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RES_DIR = os.path.join(SCRIPT_DIR, '..', 'main', 'resources')

def wav_to_int8(wav_path):
    with open(wav_path, 'rb') as f:
        data = f.read()
    pos = 12
    fmt_data = audio_data = None
    while pos < len(data) - 8:
        cid = data[pos:pos+4]; csz = struct.unpack('<I', data[pos+4:pos+8])[0]
        if cid == b'fmt ': fmt_data = data[pos+8:pos+8+csz]
        elif cid == b'data': audio_data = data[pos+8:pos+8+csz]
        pos += 8 + csz + (csz % 2)
    nch = struct.unpack('<H', fmt_data[2:4])[0]
    sr = struct.unpack('<I', fmt_data[4:8])[0]
    bits = struct.unpack('<H', fmt_data[14:16])[0]
    af = struct.unpack('<H', fmt_data[0:2])[0]
    is_float = af == 3 or (af == 0xFFFE and len(fmt_data) >= 40 and fmt_data[24] == 3)
    samples = []
    bps = bits // 8; fsz = bps * nch
    for i in range(0, len(audio_data) - fsz + 1, fsz):
        if is_float and bits == 32: v = struct.unpack_from('<f', audio_data, i)[0]
        elif bits == 16: v = struct.unpack_from('<h', audio_data, i)[0] / 32768.0
        else: v = 0.0
        samples.append(v)
    peak = max(abs(s) for s in samples) if samples else 1.0
    if peak > 0: samples = [s / peak for s in samples]
    return [max(-127, min(127, int(s * 127))) for s in samples], sr

def write_h(filename, prefix, samples, sr):
    path = os.path.join(RES_DIR, filename)
    with open(path, 'w') as f:
        f.write(f'#pragma once\n#include <stdint.h>\n')
        f.write(f'#define ENGINE_{prefix}_SAMPLE_RATE {sr}\n')
        f.write(f'#define ENGINE_{prefix}_SAMPLE_COUNT {len(samples)}\n')
        f.write(f'static const int8_t engine_{prefix.lower()}_samples[] = {{\n')
        for i in range(0, len(samples), 16):
            f.write(', '.join(str(v) for v in samples[i:i+16]) + ',\n')
        f.write('};\n')
    print(f"  {filename}: {len(samples)} samples ({len(samples)/1024:.1f}KB)")

layers = [
    ("layer_idle.wav", "engine_idle.h", "IDLE"),
    ("layer_low.wav",  "engine_low.h",  "LOW"),
    ("layer_mid.wav",  "engine_mid.h",  "MID"),
    ("layer_high.wav", "engine_high.h", "HIGH"),
]
src = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\Klara\Desktop\4.8\其他\enginesound-1.6"
for wav, hdr, prefix in layers:
    s, sr = wav_to_int8(os.path.join(src, wav))
    write_h(hdr, prefix, s, sr)
print("Done!")
