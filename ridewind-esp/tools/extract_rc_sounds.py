"""
extract_rc_sounds.py — Extract LaFerrari sounds from TheDIYGuy999 header files.

Reads the signed 8-bit 22050Hz arrays from .h files, upsamples to 44100Hz 16-bit,
and writes PCM files to storage_data/ for LittleFS flashing.

Output files:
  engine_idle.pcm   — Idle loop (44100Hz 16-bit mono)
  engine_rev.pcm    — Rev loop (44100Hz 16-bit mono)  
  engine_knock.pcm  — Single knock pulse (44100Hz 16-bit mono)
  engine_start.pcm  — Start sound one-shot (44100Hz 16-bit mono)
"""

import os
import re
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Source: TheDIYGuy999 header files (either from git clone or user's download)
SOUNDS_DIR_1 = os.path.join(SCRIPT_DIR, "rc_engine_ref", "src", "vehicles", "sounds")
SOUNDS_DIR_2 = os.path.join(SCRIPT_DIR, "..", "..", "Rc_Engine_Sound_ESP32-9.14.0", "src", "vehicles", "sounds")

# Output directory
OUT_DIR = os.path.join(SCRIPT_DIR, "..", "storage_data")

# Target format
TARGET_SR = 44100
SOURCE_SR = 22050  # All TheDIYGuy999 sounds are 22050Hz


def find_sounds_dir():
    """Find the sounds directory from either source."""
    if os.path.isdir(SOUNDS_DIR_1):
        return SOUNDS_DIR_1
    if os.path.isdir(SOUNDS_DIR_2):
        return SOUNDS_DIR_2
    raise FileNotFoundError(f"Cannot find sounds directory at:\n  {SOUNDS_DIR_1}\n  {SOUNDS_DIR_2}")


def parse_header(filepath):
    """Parse a TheDIYGuy999 sound header file and extract the int8 array."""
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # Find the array values between { and }
    match = re.search(r'\{([^}]+)\}', content)
    if not match:
        raise ValueError(f"No array found in {filepath}")

    values_str = match.group(1)
    # Parse comma-separated signed integers
    values = [int(x.strip()) for x in values_str.split(',') if x.strip() and x.strip().lstrip('-').isdigit()]

    return np.array(values, dtype=np.int8)


def upsample_2x(samples_8bit):
    """Convert 8-bit 22050Hz to 16-bit 44100Hz with linear interpolation."""
    # Convert to float
    float_samples = samples_8bit.astype(np.float32) / 128.0  # -1.0 to ~+1.0

    # 2x upsample with linear interpolation
    n = len(float_samples)
    out_len = n * 2
    out = np.zeros(out_len, dtype=np.float32)

    for i in range(n):
        out[i * 2] = float_samples[i]
        # Interpolate between current and next (wrap for loop)
        next_i = (i + 1) % n
        out[i * 2 + 1] = (float_samples[i] + float_samples[next_i]) / 2.0

    # Convert to 16-bit (scale up from 8-bit range)
    pcm16 = np.clip(out * 32767, -32768, 32767).astype(np.int16)
    return pcm16


def main():
    print("=" * 60)
    print("LaFerrari Sound Extraction (TheDIYGuy999 -> 16-bit 44100Hz)")
    print("=" * 60)

    sounds_dir = find_sounds_dir()
    print(f"\nSource: {sounds_dir}")
    print(f"Output: {OUT_DIR}")

    os.makedirs(OUT_DIR, exist_ok=True)

    # Files to extract
    files = {
        "LaFerrariIdle.h": "engine_idle.pcm",
        "LaFerrariRev.h": "engine_rev.pcm",
        "LaFerrariKnock.h": "engine_knock.pcm",
        "LaFerrariStart.h": "engine_start.pcm",
    }

    total_bytes = 0
    print(f"\nExtracting {len(files)} sounds:")
    print("-" * 60)

    for src_name, out_name in files.items():
        src_path = os.path.join(sounds_dir, src_name)
        if not os.path.exists(src_path):
            print(f"  WARNING: {src_name} not found, skipping")
            continue

        # Parse header
        samples_8bit = parse_header(src_path)

        # Upsample to 44100Hz 16-bit
        pcm16 = upsample_2x(samples_8bit)

        # Write PCM file
        out_path = os.path.join(OUT_DIR, out_name)
        with open(out_path, 'wb') as f:
            f.write(pcm16.tobytes())

        file_size = len(pcm16) * 2
        duration_ms = len(pcm16) * 1000 / TARGET_SR
        total_bytes += file_size

        print(f"  {src_name:25s} -> {out_name:20s} | "
              f"{len(samples_8bit):5d} -> {len(pcm16):5d} samples | "
              f"{duration_ms:6.1f}ms | {file_size/1024:.1f}KB")

    print("-" * 60)
    print(f"  Total: {total_bytes/1024:.1f}KB")
    print("\nDone! Files ready for LittleFS flashing.")
    print("Run 'idf.py build' then 'idf.py flash' to deploy.")


if __name__ == "__main__":
    main()
