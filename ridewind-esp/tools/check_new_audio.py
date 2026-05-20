"""Check sizes of new audio files when decoded to 44100Hz 16-bit mono PCM"""
import miniaudio
import os
import shutil

SRC_DIR = "tools/new"
files = {
    "start": "start.mp3",
    "mid": "mid.mp3",
    "high": "high.mp3",
}

# Copy 加速满档 to ASCII name for miniaudio
accel_src = os.path.join(SRC_DIR, "加速满档.mp3")
accel_tmp = os.path.join(SRC_DIR, "accel_full.mp3")
if os.path.exists(accel_src) and not os.path.exists(accel_tmp):
    shutil.copy2(accel_src, accel_tmp)
files["accel"] = "accel_full.mp3"

total_kb = 0
for name, fname in files.items():
    path = os.path.join(SRC_DIR, fname)
    if not os.path.exists(path):
        print(f"  {name}: FILE NOT FOUND ({path})")
        continue
    decoded = miniaudio.decode_file(path, sample_rate=44100, nchannels=1,
                                     output_format=miniaudio.SampleFormat.SIGNED16)
    n_samples = len(decoded.samples) // 2
    duration = n_samples / 44100
    kb = n_samples * 2 / 1024
    total_kb += kb
    print(f"  {name}: {n_samples} samples ({duration:.1f}s) = {kb:.0f} KB")

print(f"\n  TOTAL PCM: {total_kb:.0f} KB")
print(f"  Firmware budget: ~700 KB max (current firmware uses 2.43MB of 3MB)")
if total_kb > 700:
    print(f"  WARNING: TOO LARGE! Need to truncate some files.")
else:
    print(f"  OK: Fits in firmware!")
