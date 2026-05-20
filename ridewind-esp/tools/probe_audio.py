"""Probe audio files in tools/new/ to check which ones decode OK"""
import miniaudio
import os

SRC_DIR = "tools/new"
for f in sorted(os.listdir(SRC_DIR)):
    if not f.endswith(".mp3"):
        continue
    path = os.path.join(SRC_DIR, f)
    size_kb = os.path.getsize(path) / 1024
    try:
        decoded = miniaudio.decode_file(path, sample_rate=44100, nchannels=1,
                                         output_format=miniaudio.SampleFormat.SIGNED16)
        n = len(decoded.samples) // 2
        dur = n / 44100
        pcm_kb = n * 2 / 1024
        print(f"  OK  {f:20s} {size_kb:6.0f}KB mp3 -> {n:>8d} samp ({dur:.1f}s) = {pcm_kb:.0f}KB pcm")
    except Exception as e:
        print(f"  ERR {f:20s} {size_kb:6.0f}KB mp3 -> DECODE FAILED: {e}")
