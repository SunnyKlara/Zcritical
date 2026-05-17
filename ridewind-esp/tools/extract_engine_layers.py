#!/usr/bin/env python3
"""
Extract 4 engine sound layers from a single continuous acceleration recording.
Uses PyAV for M4A/AAC decoding.
"""

import sys
import os
import av
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_DIR, "main", "resources")
INPUT_FILE = os.path.join(PROJECT_DIR, "main", "resources", "audio_raw", "engine_full.mp3")

TARGET_SR = 22050
WINDOW_MS = 100
CROSSFADE_MS = 200
SEGMENT_DURATION_S = 2.5

LAYERS = [
    ("engine_idle", 800),
    ("engine_low", 2000),
    ("engine_mid", 4000),
    ("engine_high", 7000),
]


def decode_audio(filepath):
    container = av.open(filepath)
    stream = container.streams.audio[0]
    frames = []
    for frame in container.decode(audio=0):
        frames.append(frame.to_ndarray())
    container.close()
    audio = np.concatenate(frames, axis=1)
    sr = stream.rate
    mono = audio.mean(axis=0) if audio.shape[0] > 1 else audio[0]
    if sr != TARGET_SR:
        ratio = TARGET_SR / sr
        n_out = int(len(mono) * ratio)
        x_old = np.linspace(0, len(mono) - 1, len(mono))
        x_new = np.linspace(0, len(mono) - 1, n_out)
        mono = np.interp(x_new, x_old, mono)
    return mono


def compute_rms(samples, window_samples):
    n = len(samples) // window_samples
    rms = np.zeros(n)
    for i in range(n):
        s = i * window_samples
        rms[i] = np.sqrt(np.mean(samples[s:s + window_samples] ** 2))
    return rms


def find_best_segment(rms, zone_lo, zone_hi, min_w, max_w):
    best_cv, best_start, best_len = 999, 0, min_w
    for seg_len in range(min_w, max_w + 1):
        for start in range(len(rms) - seg_len):
            seg = rms[start:start + seg_len]
            mean = np.mean(seg)
            if mean < zone_lo or mean > zone_hi or mean < 0.005:
                continue
            cv = np.std(seg) / mean
            if cv < best_cv:
                best_cv, best_start, best_len = cv, start, seg_len
    return best_start, best_len, best_cv


def apply_crossfade_loop(samples, n):
    if n <= 0 or len(samples) < n * 4:
        return samples
    fade_out = np.linspace(1.0, 0.0, n)
    fade_in = np.linspace(0.0, 1.0, n)
    result = samples.copy()
    result[:n] = samples[:n] * fade_in + samples[-n:] * fade_out
    return result[:-n]


def generate_header(name, data, sr):
    count = len(data)
    upper = name.upper()
    lines = [f"#pragma once", f"#include <stdint.h>",
             f"#define {upper}_SAMPLE_RATE {sr}",
             f"#define {upper}_SAMPLE_COUNT {count}",
             f"static const int8_t {name}_samples[] = {{"]
    for i in range(0, count, 16):
        chunk = data[i:i+16]
        row = ", ".join(str(int(s)) for s in chunk)
        lines.append(f"{row}," if i + 16 < count else row)
    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def main():
    print("=" * 60)
    print("Engine Layer Extractor (from 54s acceleration recording)")
    print("=" * 60)

    if not os.path.exists(INPUT_FILE):
        print(f"ERROR: {INPUT_FILE} not found")
        return 1

    print(f"\nDecoding: {os.path.basename(INPUT_FILE)}")
    mono = decode_audio(INPUT_FILE)
    duration = len(mono) / TARGET_SR
    print(f"  Result: {len(mono)} samples ({duration:.1f}s) @ {TARGET_SR}Hz mono")

    window_samples = int(TARGET_SR * WINDOW_MS / 1000)
    rms = compute_rms(mono, window_samples)
    print(f"  RMS range: {np.min(rms):.4f} - {np.max(rms):.4f}")

    # Energy profile
    print(f"\n  Energy profile:")
    max_rms = np.max(rms)
    for i in range(0, len(rms), 20):
        chunk_rms = np.mean(rms[i:i+20])
        bar = int(chunk_rms / max_rms * 40) if max_rms > 0 else 0
        print(f"  {i*WINDOW_MS/1000:5.1f}s |{'#'*bar}{' '*(40-bar)}| {chunk_rms:.4f}")

    # Divide into 4 energy zones
    valid = rms[rms > 0.005]
    valid.sort()
    p10 = valid[int(len(valid) * 0.10)]
    p35 = valid[int(len(valid) * 0.35)]
    p60 = valid[int(len(valid) * 0.60)]
    p85 = valid[int(len(valid) * 0.85)]
    p95 = valid[int(len(valid) * 0.95)]
    zones = [(p10, p35), (p35, p60), (p60, p85), (p85, p95)]

    print(f"\n  Zones: idle={p10:.4f}-{p35:.4f}, low={p35:.4f}-{p60:.4f}, mid={p60:.4f}-{p85:.4f}, high={p85:.4f}-{p95:.4f}")

    # Find segments
    min_w = int(1.5 * 1000 / WINDOW_MS)
    max_w = int(SEGMENT_DURATION_S * 1000 / WINDOW_MS)
    crossfade_samples = int(TARGET_SR * CROSSFADE_MS / 1000)
    total = 0

    print(f"\n  Extracting layers:")
    for (zone_lo, zone_hi), (name, rpm) in zip(zones, LAYERS):
        start, seg_len, cv = find_best_segment(rms, zone_lo, zone_hi, min_w, max_w)
        s_start = start * window_samples
        s_end = (start + seg_len) * window_samples
        segment = mono[s_start:s_end]

        # Normalize
        peak = np.max(np.abs(segment))
        if peak > 0:
            segment = segment * (0.85 / peak)

        # Loop
        looped = apply_crossfade_loop(segment, crossfade_samples)
        int8_data = np.clip(looped * 127, -128, 127).astype(np.int8)

        # Write
        header = generate_header(name, int8_data, TARGET_SR)
        path = os.path.join(OUTPUT_DIR, f"{name}.h")
        with open(path, "w", encoding="utf-8") as f:
            f.write(header)

        t_s = start * WINDOW_MS / 1000
        t_e = (start + seg_len) * WINDOW_MS / 1000
        print(f"    {name}.h: {t_s:.1f}-{t_e:.1f}s, stability={cv:.3f}, {len(int8_data)/1024:.1f}KB")
        total += len(int8_data)

    print(f"\n  Total flash: {total/1024:.1f} KB")
    print(f"\n{'='*60}")
    print("Done! Run 'idf.py build' to compile with new audio.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
