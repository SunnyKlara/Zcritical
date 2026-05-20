"""Generate final audio headers: idle (2s), mid (3s), high (2s) from Forza recordings"""
import av
import numpy as np
import struct
import os

TARGET_RATE = 44100
SRC_DIR = "tools/new"
OUT_DIR = "main/resources"

# Source files -> output names and durations
LAYERS = [
    {"src": "怠速（增大音量）.mp3", "name": "forza_idle", "max_seconds": 2.0},
    {"src": "mid.mp3",              "name": "forza_mid",  "max_seconds": 3.0},
    {"src": "high.mp3",             "name": "forza_high", "max_seconds": 2.0},
]

def decode_file(path):
    """Decode audio file to 44100Hz 16-bit mono using PyAV"""
    container = av.open(path)
    resampler = av.AudioResampler(format='s16', layout='mono', rate=TARGET_RATE)
    samples = []
    for frame in container.decode(audio=0):
        resampled = resampler.resample(frame)
        for f in resampled if isinstance(resampled, list) else [resampled]:
            arr = f.to_ndarray().flatten()
            samples.extend(arr.tolist())
    return samples

def write_header(name, samples, out_dir):
    """Write C header file with int16_t array"""
    count = len(samples)
    define_name = name.upper() + "_COUNT"
    array_name = name

    path = os.path.join(out_dir, f"{name}.h")
    with open(path, "w") as f:
        f.write(f"/* {name} - {count} samples @ 44100Hz 16-bit mono */\n")
        f.write("#pragma once\n\n")
        f.write(f"#define {define_name} {count}\n\n")
        f.write(f"static const int16_t {array_name}[] = {{\n")
        for i in range(0, count, 16):
            row = samples[i:i+16]
            f.write("    " + ", ".join(str(s) for s in row) + ",\n")
        f.write("};\n")

    return path

total_kb = 0
for layer in LAYERS:
    src_path = os.path.join(SRC_DIR, layer["src"])
    print(f"Decoding {layer['src']}...")

    samples = decode_file(src_path)
    full_dur = len(samples) / TARGET_RATE

    # Truncate to max duration
    max_samples = int(layer["max_seconds"] * TARGET_RATE)
    if len(samples) > max_samples:
        samples = samples[:max_samples]

    dur = len(samples) / TARGET_RATE
    kb = len(samples) * 2 / 1024
    total_kb += kb

    # Write header
    out_path = write_header(layer["name"], samples, OUT_DIR)
    print(f"  -> {out_path}: {len(samples)} samples ({dur:.1f}s) = {kb:.0f}KB (from {full_dur:.1f}s)")

print(f"\nTotal PCM embedded: {total_kb:.0f} KB")
print("Done!")
