#!/usr/bin/env python3
"""
批量提取所有引擎声音 Profile 为 PCM 格式

从 TheDIYGuy999 的 .h 文件中提取 int8 数组，
上采样到 44100Hz 16-bit mono PCM，输出到 storage_data/sounds/ 目录。

每个 profile 输出 4 个文件：
  {profile_id}_idle.pcm
  {profile_id}_rev.pcm
  {profile_id}_knock.pcm
  {profile_id}_start.pcm

用法：
    python extract_all_engine_sounds.py
"""

import json
import os
import re
import numpy as np
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SOUNDS_DIR = SCRIPT_DIR / "rc_engine_ref" / "src" / "vehicles" / "sounds"
OUTPUT_DIR = SCRIPT_DIR.parent / "storage_data" / "sounds"
MAP_PATH = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\engine_sound_map.json')

TARGET_SR = 44100
SOURCE_SR = 22050


def parse_header(filepath):
    """Parse a TheDIYGuy999 sound header file and extract the int8 array."""
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    match = re.search(r'\{([^}]+)\}', content)
    if not match:
        return None

    values_str = match.group(1)
    values = []
    for x in values_str.split(','):
        x = x.strip()
        if x and (x.lstrip('-').isdigit()):
            values.append(int(x))

    if not values:
        return None

    return np.array(values, dtype=np.int8)


def upsample_2x(samples_8bit):
    """Convert 8-bit 22050Hz to 16-bit 44100Hz with linear interpolation."""
    float_samples = samples_8bit.astype(np.float32) / 128.0
    n = len(float_samples)
    out = np.zeros(n * 2, dtype=np.float32)

    out[0::2] = float_samples
    out[1::2] = (float_samples + np.roll(float_samples, -1)) / 2.0

    pcm16 = np.clip(out * 32767, -32768, 32767).astype(np.int16)
    return pcm16


def main():
    print("=" * 60)
    print("RideWind Engine Sound Batch Extraction")
    print(f"Source: {SOUNDS_DIR}")
    print(f"Output: {OUTPUT_DIR}")
    print("=" * 60)

    if not SOUNDS_DIR.exists():
        print(f"ERROR: Sounds directory not found: {SOUNDS_DIR}")
        print("Run: git clone https://github.com/TheDIYGuy999/Rc_Engine_Sound_ESP32.git ridewind-esp/tools/rc_engine_ref")
        return

    # Load sound map
    with open(MAP_PATH, 'r', encoding='utf-8') as f:
        sound_map = json.load(f)

    profiles = sound_map['profiles']
    print(f"\n📋 {len(profiles)} profiles to extract\n")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    total_bytes = 0
    total_files = 0
    failed_files = []

    for profile in profiles:
        pid = profile['profile_id']
        files = profile['files']
        print(f"  [{pid}] {profile['display_name']}")

        for sound_type, filename in files.items():
            src_path = SOUNDS_DIR / filename
            out_name = f"{pid}_{sound_type}.pcm"
            out_path = OUTPUT_DIR / out_name

            if not src_path.exists():
                print(f"    ⚠️  {filename} not found")
                failed_files.append(f"{pid}/{filename}")
                # Write empty/silent PCM
                silent = np.zeros(1000, dtype=np.int16)
                with open(out_path, 'wb') as f:
                    f.write(silent.tobytes())
                total_files += 1
                continue

            samples = parse_header(src_path)
            if samples is None:
                print(f"    ⚠️  {filename} parse failed")
                failed_files.append(f"{pid}/{filename}")
                silent = np.zeros(1000, dtype=np.int16)
                with open(out_path, 'wb') as f:
                    f.write(silent.tobytes())
                total_files += 1
                continue

            pcm16 = upsample_2x(samples)
            with open(out_path, 'wb') as f:
                f.write(pcm16.tobytes())

            file_size = len(pcm16) * 2
            duration_ms = len(pcm16) * 1000 / TARGET_SR
            total_bytes += file_size
            total_files += 1

        print(f"    ✅ 4 files extracted")

    print("\n" + "=" * 60)
    print(f"📊 Summary:")
    print(f"   Total files: {total_files}")
    print(f"   Total size: {total_bytes / 1024:.1f} KB ({total_bytes / 1024 / 1024:.2f} MB)")
    print(f"   Failed: {len(failed_files)}")
    if failed_files:
        print(f"   Missing files:")
        for f in failed_files:
            print(f"     - {f}")
    print("=" * 60)


if __name__ == "__main__":
    main()
