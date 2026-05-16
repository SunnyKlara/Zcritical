#!/usr/bin/env python3
"""
Analyze engine audio MP3 files to find the most stable (steady-state) segments.
"""

import sys
import os
import math
import miniaudio
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
RAW_DIR = os.path.join(PROJECT_DIR, "main", "resources", "audio_raw")

TARGET_SR = 22050
WINDOW_MS = 100
MIN_SEGMENT_S = 1.5
MAX_SEGMENT_S = 4.0

FILES = {
    "startup.mp3": "启动加速 (idle candidate)",
    "brake.mp3": "刹车 (low candidate)",
    "mid_accel.mp3": "中加速 (mid candidate)",
    "long_accel.mp3": "长加速 (high candidate)",
}


def load_and_convert(filepath):
    decoded = miniaudio.decode_file(filepath, output_format=miniaudio.SampleFormat.FLOAT32)
    samples = np.frombuffer(decoded.samples, dtype=np.float32)
    sr = decoded.sample_rate
    ch = decoded.nchannels
    if ch > 1:
        samples = samples.reshape(-1, ch).mean(axis=1)
    if sr != TARGET_SR:
        ratio = TARGET_SR / sr
        n_out = int(len(samples) * ratio)
        x_old = np.linspace(0, len(samples) - 1, len(samples))
        x_new = np.linspace(0, len(samples) - 1, n_out)
        samples = np.interp(x_new, x_old, samples)
    return samples


def compute_rms_envelope(samples, window_samples):
    n_windows = len(samples) // window_samples
    rms = np.zeros(n_windows)
    for i in range(n_windows):
        start = i * window_samples
        end = start + window_samples
        chunk = samples[start:end]
        rms[i] = np.sqrt(np.mean(chunk ** 2))
    return rms


def find_stable_segments(rms_envelope, min_windows, max_windows):
    results = []
    for seg_len in range(min_windows, max_windows + 1):
        for start in range(len(rms_envelope) - seg_len):
            segment = rms_envelope[start:start + seg_len]
            mean_rms = np.mean(segment)
            if mean_rms < 0.01:
                continue
            std = np.std(segment)
            cv = std / mean_rms if mean_rms > 0 else 999
            results.append((cv, start, seg_len, mean_rms))
    results.sort(key=lambda x: x[0])
    return results


def analyze_file(filepath, description):
    print(f"\n{'='*60}")
    print(f"  {description}")
    print(f"  File: {os.path.basename(filepath)}")
    print(f"{'='*60}")

    samples = load_and_convert(filepath)
    duration = len(samples) / TARGET_SR
    print(f"  Duration: {duration:.2f}s ({len(samples)} samples)")

    window_samples = int(TARGET_SR * WINDOW_MS / 1000)
    rms = compute_rms_envelope(samples, window_samples)

    print(f"  Overall RMS: min={np.min(rms):.4f}, max={np.max(rms):.4f}, mean={np.mean(rms):.4f}")

    # Energy profile
    print(f"\n  Energy profile (each row = 0.5s):")
    max_rms = np.max(rms)
    bar_width = 40
    for i in range(0, len(rms), 5):
        chunk_rms = np.mean(rms[i:i+5])
        bar_len = int(chunk_rms / max_rms * bar_width) if max_rms > 0 else 0
        time_s = i * WINDOW_MS / 1000
        print(f"  {time_s:5.1f}s |{'#' * bar_len}{' ' * (bar_width - bar_len)}| {chunk_rms:.3f}")

    # Find stable segments
    min_windows = int(MIN_SEGMENT_S * 1000 / WINDOW_MS)
    max_windows = int(MAX_SEGMENT_S * 1000 / WINDOW_MS)

    stable = find_stable_segments(rms, min_windows, max_windows)

    if stable:
        print(f"\n  Top 3 most stable segments:")
        seen_ranges = []
        count = 0
        for cv, start, seg_len, mean_rms in stable:
            start_s = start * WINDOW_MS / 1000
            end_s = (start + seg_len) * WINDOW_MS / 1000
            overlap = False
            for s, e in seen_ranges:
                if not (end_s < s or start_s > e):
                    overlap = True
                    break
            if overlap:
                continue
            seen_ranges.append((start_s, end_s))
            print(f"    #{count+1}: {start_s:.1f}s - {end_s:.1f}s "
                  f"(len={seg_len*WINDOW_MS/1000:.1f}s, "
                  f"stability={cv:.3f}, RMS={mean_rms:.3f})")
            count += 1
            if count >= 3:
                break

        best = stable[0]
        best_start_s = best[1] * WINDOW_MS / 1000
        best_end_s = (best[1] + best[2]) * WINDOW_MS / 1000
        print(f"\n  >>> BEST: {best_start_s:.1f}s - {best_end_s:.1f}s (stability={best[0]:.3f})")
    else:
        print(f"\n  No stable segments found!")


def main():
    print("Engine Audio Stability Analyzer")
    print(f"Looking for {MIN_SEGMENT_S}-{MAX_SEGMENT_S}s steady-state segments\n")

    for filename, description in FILES.items():
        filepath = os.path.join(RAW_DIR, filename)
        if os.path.exists(filepath):
            analyze_file(filepath, description)
        else:
            print(f"\n  MISSING: {filename}")

    print(f"\n{'='*60}")
    print("For Forza Horizon quality, each layer needs a STEADY-STATE")
    print("segment (constant RPM). If none found, need new recordings")
    print("at fixed RPM points or use enginesound generator.")
    print("="*60)


if __name__ == "__main__":
    main()
