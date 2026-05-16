#!/usr/bin/env python3
"""
Convert engine sound MP3 files to C header arrays for ESP32 firmware.

Input:  MP3 files in main/resources/audio_raw/
Output: C header files in main/resources/ (engine_idle.h, engine_low.h, etc.)

Format: 22050Hz, 8-bit signed PCM, mono, seamless loop (crossfade applied)

Usage:
  python tools/convert_engine_audio.py [--analyze-only]
"""

import sys
import os
import struct
import numpy as np

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import miniaudio

# ═══════════════════════════════════════════════════════════════
#  Configuration
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)  # ridewind-esp/
RAW_DIR = os.path.join(PROJECT_DIR, "main", "resources", "audio_raw")
OUTPUT_DIR = os.path.join(PROJECT_DIR, "main", "resources")

TARGET_SAMPLE_RATE = 22050
TARGET_BITS = 8  # signed 8-bit
CROSSFADE_MS = 200  # crossfade duration for seamless loop (longer = smoother)

# Layer mapping: source filename -> (output name, layer RPM, C array name)
# Original Chinese names -> English copies (miniaudio has unicode path issues)
# 启动加速.mp3 -> startup.mp3 (engine start/idle)
# 刹车.mp3 -> brake.mp3 (low RPM / decel)
# 中加速.mp3 -> mid_accel.mp3 (mid RPM acceleration)
# 长加速.mp3 -> long_accel.mp3 (high RPM sustained)
LAYER_MAP = {
    "startup.mp3": ("engine_idle", 800, "engine_idle"),
    "brake.mp3": ("engine_low", 2000, "engine_low"),
    "mid_accel.mp3": ("engine_mid", 4000, "engine_mid"),
    "long_accel.mp3": ("engine_high", 7000, "engine_high"),
}

# Steady-state segment cut points (seconds) — from stability analysis
# Only the most stable portion of each recording is used for looping
SEGMENT_CUTS = {
    "startup.mp3": (1.3, 3.2),      # 1.9s stable idle segment
    "brake.mp3": (0.5, 2.1),        # 1.6s stable low-RPM segment
    "mid_accel.mp3": (0.8, 2.3),    # 1.5s stable mid-RPM segment
    "long_accel.mp3": (6.0, 7.5),   # 1.5s stable high-RPM segment
}

# ═══════════════════════════════════════════════════════════════
#  Audio Processing Functions
# ═══════════════════════════════════════════════════════════════

def load_mp3(filepath):
    """Load MP3 file and return (samples_float32, sample_rate, channels)."""
    decoded = miniaudio.decode_file(filepath, output_format=miniaudio.SampleFormat.FLOAT32)
    samples = np.frombuffer(decoded.samples, dtype=np.float32)
    return samples, decoded.sample_rate, decoded.nchannels


def to_mono(samples, channels):
    """Convert to mono by averaging channels."""
    if channels == 1:
        return samples
    # Reshape to (n_frames, channels) and average
    frames = samples.reshape(-1, channels)
    return frames.mean(axis=1)


def resample(samples, src_rate, dst_rate):
    """Simple linear interpolation resampling."""
    if src_rate == dst_rate:
        return samples
    ratio = dst_rate / src_rate
    n_out = int(len(samples) * ratio)
    x_old = np.linspace(0, len(samples) - 1, len(samples))
    x_new = np.linspace(0, len(samples) - 1, n_out)
    return np.interp(x_new, x_old, samples)


def apply_crossfade_loop(samples, crossfade_samples):
    """Apply crossfade at loop boundary for seamless looping."""
    if crossfade_samples <= 0 or len(samples) < crossfade_samples * 4:
        return samples
    
    n = crossfade_samples
    # Create fade curves
    fade_out = np.linspace(1.0, 0.0, n)
    fade_in = np.linspace(0.0, 1.0, n)
    
    # Crossfade: blend end into beginning
    result = samples.copy()
    result[:n] = samples[:n] * fade_in + samples[-n:] * fade_out
    # Trim the tail that was blended into the head
    result = result[:-n]
    
    return result


def normalize(samples, target_peak=0.9):
    """Normalize to target peak level."""
    peak = np.max(np.abs(samples))
    if peak > 0:
        samples = samples * (target_peak / peak)
    return samples


def to_int8(samples_float):
    """Convert float32 [-1, 1] to signed int8 [-128, 127]."""
    # Scale to int8 range
    scaled = samples_float * 127.0
    # Clip and convert
    clipped = np.clip(scaled, -128, 127)
    return clipped.astype(np.int8)


def generate_header(name, samples_int8, sample_rate):
    """Generate C header file content."""
    count = len(samples_int8)
    upper_name = name.upper()
    
    lines = []
    lines.append(f"#pragma once")
    lines.append(f"#include <stdint.h>")
    lines.append(f"#define {upper_name}_SAMPLE_RATE {sample_rate}")
    lines.append(f"#define {upper_name}_SAMPLE_COUNT {count}")
    lines.append(f"static const int8_t {name}_samples[] = {{")
    
    # Write samples in rows of 16
    for i in range(0, count, 16):
        chunk = samples_int8[i:i+16]
        row = ", ".join(str(int(s)) for s in chunk)
        if i + 16 < count:
            lines.append(f"{row},")
        else:
            lines.append(f"{row}")
    
    lines.append("};")
    lines.append("")
    
    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

def analyze_file(filepath, name):
    """Analyze an audio file and print info."""
    samples, sr, ch = load_mp3(filepath)
    duration = len(samples) / ch / sr
    print(f"  {name}:")
    print(f"    File: {os.path.basename(filepath)}")
    print(f"    Sample rate: {sr} Hz")
    print(f"    Channels: {ch}")
    print(f"    Duration: {duration:.2f}s")
    print(f"    Samples: {len(samples) // ch}")
    
    # After conversion estimate
    mono = to_mono(samples, ch)
    resampled = resample(mono, sr, TARGET_SAMPLE_RATE)
    print(f"    After conversion (22050Hz mono): {len(resampled)} samples ({len(resampled)/TARGET_SAMPLE_RATE:.2f}s)")
    print(f"    Estimated size in flash: {len(resampled)} bytes ({len(resampled)/1024:.1f} KB)")
    print()


def convert_file(filepath, output_name, rpm):
    """Convert MP3 to C header."""
    filename = os.path.basename(filepath)
    print(f"  Converting: {filename} -> {output_name}.h")
    
    # Load
    samples, sr, ch = load_mp3(filepath)
    duration = len(samples) / ch / sr
    print(f"    Input: {sr}Hz, {ch}ch, {duration:.2f}s")
    
    # To mono
    mono = to_mono(samples, ch)
    
    # Resample to 22050Hz
    resampled = resample(mono, sr, TARGET_SAMPLE_RATE)
    print(f"    Resampled: {TARGET_SAMPLE_RATE}Hz, {len(resampled)} samples ({len(resampled)/TARGET_SAMPLE_RATE:.2f}s)")
    
    # Cut to steady-state segment if defined
    if filename in SEGMENT_CUTS:
        start_s, end_s = SEGMENT_CUTS[filename]
        start_sample = int(start_s * TARGET_SAMPLE_RATE)
        end_sample = int(end_s * TARGET_SAMPLE_RATE)
        resampled = resampled[start_sample:end_sample]
        print(f"    Cut to steady-state: {start_s:.1f}s-{end_s:.1f}s ({len(resampled)} samples, {len(resampled)/TARGET_SAMPLE_RATE:.2f}s)")
    
    # Normalize
    normalized = normalize(resampled, target_peak=0.85)
    
    # Apply crossfade for seamless loop
    crossfade_samples = int(TARGET_SAMPLE_RATE * CROSSFADE_MS / 1000)
    looped = apply_crossfade_loop(normalized, crossfade_samples)
    print(f"    After crossfade loop: {len(looped)} samples")
    
    # Convert to int8
    int8_data = to_int8(looped)
    print(f"    Output: {len(int8_data)} bytes ({len(int8_data)/1024:.1f} KB)")
    
    # Generate header
    header_content = generate_header(output_name, int8_data, TARGET_SAMPLE_RATE)
    
    # Write
    output_path = os.path.join(OUTPUT_DIR, f"{output_name}.h")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(header_content)
    
    print(f"    Written: {output_path}")
    print()
    
    return len(int8_data)


def main():
    analyze_only = "--analyze-only" in sys.argv
    
    print("=" * 60)
    print("Engine Sound MP3 -> C Header Converter")
    print("=" * 60)
    print()
    
    # Check input files
    print(f"Source directory: {RAW_DIR}")
    print(f"Output directory: {OUTPUT_DIR}")
    print()
    
    missing = []
    found = []
    for filename, (output_name, rpm, _) in LAYER_MAP.items():
        filepath = os.path.join(RAW_DIR, filename)
        if os.path.exists(filepath):
            found.append((filepath, filename, output_name, rpm))
        else:
            missing.append(filename)
    
    if missing:
        print(f"WARNING: Missing files: {missing}")
    
    if not found:
        print("ERROR: No source files found!")
        return 1
    
    print(f"Found {len(found)}/{len(LAYER_MAP)} source files")
    print()
    
    if analyze_only:
        print("-- Analysis Mode --")
        print()
        for filepath, filename, output_name, rpm in found:
            analyze_file(filepath, f"{output_name} (RPM {rpm})")
        return 0
    
    # Convert
    print("-- Converting --")
    print()
    total_size = 0
    for filepath, filename, output_name, rpm in found:
        size = convert_file(filepath, output_name, rpm)
        total_size += size
    
    print("=" * 60)
    print(f"Done! Total flash usage: {total_size/1024:.1f} KB")
    print()
    print("Layer mapping:")
    for filepath, filename, output_name, rpm in found:
        print(f"  {filename} -> {output_name}.h (RPM {rpm})")
    print()
    print("NOTE: Review the layer mapping above!")
    print("   If the assignment doesn't match your intent, edit LAYER_MAP in this script.")
    print()
    print("Next step: run 'idf.py build' to compile with new audio.")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
