#!/usr/bin/env python3
"""
从 YouTube 批量下载引擎声音

为每辆车搜索 YouTube 上的引擎声视频，下载音频，裁剪 5 秒怠速片段，
转换为 44100Hz mono WAV 格式。

用法：
    python fetch_engine_sounds_yt.py [--limit N] [--start N] [--dry-run]

依赖：
    pip install yt-dlp imageio-ffmpeg
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# Paths
SPECS_PATH = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\car_thumbnails\car_specs.json')
OUTPUT_DIR = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\assets\sound\engine_individual')
TEMP_DIR = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\tools\.temp_audio')
PROGRESS_PATH = Path(r'c:\Users\Klara\Desktop\4.8\RideWind\tools\engine_sound_progress.json')

# Tools
YT_DLP = r'C:\Users\Klara\AppData\Roaming\Python\Python314\Scripts\yt-dlp.exe'
FFMPEG = r'C:\Users\Klara\AppData\Roaming\Python\Python314\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe'

# Audio settings
SAMPLE_RATE = 44100
DURATION_SEC = 5  # 5 seconds of idle sound
SKIP_SEC = 3  # Skip first 3 seconds (often has intro noise)


def sanitize_filename(name):
    """Remove special characters for safe filenames."""
    return re.sub(r'[<>:"/\\|?*\']', '', name).strip()


def build_search_query(car):
    """Build YouTube search query for engine sound."""
    brand = car.get('brand', '')
    model = car.get('model', '')

    # Clean up model name (remove Large, FE, WP, etc.)
    clean_model = re.sub(r'\s+(Large|FE|WP|Traffic)$', '', model)
    clean_model = re.sub(r'\s+\d{4}$', '', clean_model)  # Remove trailing year

    query = f"{brand} {clean_model} engine sound idle exhaust"
    return query


def search_and_download(query, output_path):
    """Search YouTube and download audio (raw, no conversion)."""
    try:
        cmd = [
            YT_DLP,
            f'ytsearch1:{query}',
            '--extract-audio',
            '--no-playlist',
            '--max-downloads', '1',
            '--output', str(output_path / '%(id)s.%(ext)s'),
            '--quiet',
            '--no-warnings',
            '--socket-timeout', '15',
            '--retries', '2',
            '--js-runtimes', 'node',
            '--remote-components', 'ejs:github',
        ]

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

        # Find any downloaded audio file
        for ext in ('*.opus', '*.webm', '*.m4a', '*.mp3', '*.wav', '*.ogg'):
            for f in output_path.glob(ext):
                return f
        return None
    except (subprocess.TimeoutExpired, Exception):
        return None


def trim_and_convert(input_path, output_path):
    """Trim to 5 seconds and convert to 44100Hz mono WAV."""
    try:
        cmd = [
            FFMPEG,
            '-y',
            '-i', str(input_path),
            '-ss', str(SKIP_SEC),
            '-t', str(DURATION_SEC),
            '-ar', str(SAMPLE_RATE),
            '-ac', '1',
            '-acodec', 'pcm_s16le',
            '-loglevel', 'error',
            str(output_path),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.returncode == 0
    except Exception:
        return False


def load_progress():
    """Load progress from previous runs."""
    if PROGRESS_PATH.exists():
        with open(PROGRESS_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {"completed": [], "failed": []}


def save_progress(progress):
    """Save progress for resume capability."""
    with open(PROGRESS_PATH, 'w', encoding='utf-8') as f:
        json.dump(progress, f, ensure_ascii=False, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Fetch engine sounds from YouTube")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of cars (0=all)")
    parser.add_argument("--start", type=int, default=0, help="Start from index N")
    parser.add_argument("--dry-run", action="store_true", help="Only print search queries")
    args = parser.parse_args()

    with open(SPECS_PATH, 'r', encoding='utf-8') as f:
        cars = json.load(f)

    print(f"📋 Total cars: {len(cars)}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    TEMP_DIR.mkdir(parents=True, exist_ok=True)

    progress = load_progress()
    completed_set = set(progress['completed'])

    # Filter: skip Large variants and already completed
    cars_to_process = []
    for car in cars:
        name = car['full_name']
        if 'Large' in name:
            continue
        if name in completed_set:
            continue
        cars_to_process.append(car)

    if args.start > 0:
        cars_to_process = cars_to_process[args.start:]
    if args.limit > 0:
        cars_to_process = cars_to_process[:args.limit]

    print(f"🎯 To process: {len(cars_to_process)} (skipping {len(completed_set)} already done)")

    if args.dry_run:
        print("\n--- DRY RUN ---")
        for car in cars_to_process[:20]:
            print(f"  {car['full_name']} → \"{build_search_query(car)}\"")
        return

    success = 0
    failed = 0

    for i, car in enumerate(cars_to_process):
        name = car['full_name']
        safe_name = sanitize_filename(name)
        output_wav = OUTPUT_DIR / f"{safe_name}.wav"

        if output_wav.exists():
            progress['completed'].append(name)
            completed_set.add(name)
            success += 1
            continue

        query = build_search_query(car)
        print(f"  [{i+1}/{len(cars_to_process)}] {name}...", end=" ", flush=True)

        # Clean temp
        for f in TEMP_DIR.glob('*'):
            try: f.unlink()
            except: pass

        downloaded = search_and_download(query, TEMP_DIR)
        if downloaded is None:
            print("❌ download")
            progress['failed'].append(name)
            failed += 1
            time.sleep(1)
            continue

        if trim_and_convert(downloaded, output_wav):
            size_kb = output_wav.stat().st_size // 1024
            print(f"✅ {size_kb}KB")
            progress['completed'].append(name)
            completed_set.add(name)
            success += 1
        else:
            print("❌ convert")
            progress['failed'].append(name)
            failed += 1

        try: downloaded.unlink()
        except: pass

        if (i + 1) % 10 == 0:
            save_progress(progress)

        time.sleep(2)

    save_progress(progress)
    print(f"\n📊 Done: {success} ✅ / {failed} ❌")
    print(f"💾 Output: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
