#!/usr/bin/env python3
"""Convert MP3 to raw 16-bit signed LE PCM at 44100Hz mono.
Uses subprocess to call ffmpeg/ffprobe if available, otherwise
uses a pure-Python minimp3 approach via ctypes.

Output: engine_pcm.bin (raw int16 samples, 44100Hz, mono)
"""
import subprocess, sys, os, struct

INPUT = os.path.join(os.path.dirname(__file__), '../../audio参考项目/data/engine.mp3')
OUTPUT = os.path.join(os.path.dirname(__file__), '../main/resources/engine_pcm.bin')

def try_ffmpeg():
    """Try using ffmpeg to convert."""
    try:
        result = subprocess.run([
            'ffmpeg', '-y', '-i', INPUT,
            '-f', 's16le', '-acodec', 'pcm_s16le',
            '-ar', '44100', '-ac', '1',
            OUTPUT
        ], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return True
        print(f"ffmpeg failed: {result.stderr[:200]}")
    except FileNotFoundError:
        print("ffmpeg not found")
    return False

def try_minimp3_decode():
    """Pure Python MP3 decode using minimp3 via ctypes - too complex.
    Instead, embed the MP3 and decode at runtime with smaller stack."""
    return False

if __name__ == '__main__':
    if try_ffmpeg():
        size = os.path.getsize(OUTPUT)
        duration_ms = size / (44100 * 2) * 1000  # 2 bytes per sample, mono
        print(f"Success! {OUTPUT}")
        print(f"  Size: {size:,} bytes ({size/1024:.1f} KB)")
        print(f"  Duration: {duration_ms:.0f} ms")
        print(f"  Format: 44100Hz, 16-bit signed LE, mono")
    else:
        print("ERROR: ffmpeg is required. Install it from https://ffmpeg.org/download.html")
        print("Or manually convert: ffmpeg -i engine.mp3 -f s16le -ar 44100 -ac 1 engine_pcm.bin")
        sys.exit(1)
