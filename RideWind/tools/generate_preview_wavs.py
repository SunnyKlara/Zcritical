#!/usr/bin/env python3
"""
生成引擎声音预览 WAV 文件（用于 APP 端试听）

从 storage_data/sounds/ 中的 PCM 文件生成 WAV 格式，
只取每个 profile 的 idle 声音（循环 3 秒），输出到 assets/sound/engine/

格式: 44100Hz, 16-bit, mono WAV
"""

import json
import struct
import numpy as np
from pathlib import Path

PCM_DIR = Path(r'c:\Users\Klara\Desktop\4.8\ridewind-esp\storage_data\sounds')
OUTPUT_DIR = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\sound\engine')
MAP_PATH = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\engine_sound_map.json')

SAMPLE_RATE = 44100
BITS_PER_SAMPLE = 16
NUM_CHANNELS = 1
PREVIEW_DURATION_SEC = 3  # 预览时长


def write_wav(filepath, pcm_data, sample_rate=44100, bits=16, channels=1):
    """Write PCM data as WAV file."""
    data_size = len(pcm_data)
    file_size = 36 + data_size
    byte_rate = sample_rate * channels * (bits // 8)
    block_align = channels * (bits // 8)

    with open(filepath, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', file_size))
        f.write(b'WAVE')
        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))  # chunk size
        f.write(struct.pack('<H', 1))   # PCM format
        f.write(struct.pack('<H', channels))
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', byte_rate))
        f.write(struct.pack('<H', block_align))
        f.write(struct.pack('<H', bits))
        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(pcm_data)


def main():
    print("=" * 60)
    print("Generate Engine Sound Preview WAVs for Flutter APP")
    print("=" * 60)

    with open(MAP_PATH, 'r', encoding='utf-8') as f:
        sound_map = json.load(f)

    profiles = sound_map['profiles']
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    total_size = 0
    target_samples = SAMPLE_RATE * PREVIEW_DURATION_SEC

    for profile in profiles:
        pid = profile['profile_id']
        idle_pcm_path = PCM_DIR / f"{pid}_idle.pcm"

        if not idle_pcm_path.exists():
            print(f"  ⚠️  {pid}_idle.pcm not found, skipping")
            continue

        # Read PCM data
        pcm_raw = idle_pcm_path.read_bytes()
        samples = np.frombuffer(pcm_raw, dtype=np.int16)

        if len(samples) < 100:
            # Too short (probably dummy/silent), write minimal wav
            samples = np.zeros(target_samples, dtype=np.int16)
        else:
            # Loop to fill 3 seconds
            if len(samples) < target_samples:
                repeats = (target_samples // len(samples)) + 1
                samples = np.tile(samples, repeats)[:target_samples]
            else:
                samples = samples[:target_samples]

        # Apply fade in/out to avoid clicks
        fade_len = min(2000, len(samples) // 4)
        fade_in = np.linspace(0, 1, fade_len)
        fade_out = np.linspace(1, 0, fade_len)
        samples_float = samples.astype(np.float32)
        samples_float[:fade_len] *= fade_in
        samples_float[-fade_len:] *= fade_out
        samples = samples_float.astype(np.int16)

        # Write WAV
        wav_path = OUTPUT_DIR / f"{pid}.wav"
        write_wav(wav_path, samples.tobytes())

        file_size = wav_path.stat().st_size
        total_size += file_size
        print(f"  ✅ {pid}.wav ({file_size/1024:.1f} KB)")

    print(f"\n📊 Total: {len(profiles)} files, {total_size/1024:.1f} KB ({total_size/1024/1024:.2f} MB)")
    print(f"💾 Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
