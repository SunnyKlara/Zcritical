#!/usr/bin/env python3
"""
Extract 4 engine sound layers using frequency analysis (STFT).
Divides 54s acceleration into 4 time zones, finds most stable segment in each.
"""
import sys, os
import av
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.path.join(PROJECT_DIR, "main", "resources")
INPUT_FILE = os.path.join(PROJECT_DIR, "main", "resources", "audio_raw", "engine_full.mp3")
TARGET_SR = 22050
CROSSFADE_MS = 200
SEGMENT_S = 2.5
LAYERS = [("engine_idle", 800), ("engine_low", 2000), ("engine_mid", 4000), ("engine_high", 7000)]

def decode_audio(fp):
    c = av.open(fp); s = c.streams.audio[0]; frames = []
    for f in c.decode(audio=0): frames.append(f.to_ndarray())
    c.close(); audio = np.concatenate(frames, axis=1)
    mono = audio.mean(axis=0) if audio.shape[0] > 1 else audio[0]
    if s.rate != TARGET_SR:
        n = int(len(mono) * TARGET_SR / s.rate)
        mono = np.interp(np.linspace(0, len(mono)-1, n), np.arange(len(mono)), mono)
    return mono

def dominant_freq(samples, sr, hop_ms=100):
    hop = int(sr * hop_ms / 1000); win = hop * 4
    n = (len(samples) - win) // hop
    freqs = np.zeros(n); times = np.zeros(n)
    window = np.hanning(win)
    for i in range(n):
        s = i * hop; chunk = samples[s:s+win] * window
        fft = np.abs(np.fft.rfft(chunk))
        ff = np.fft.rfftfreq(win, 1.0/sr)
        mask = (ff >= 50) & (ff <= 500)
        if np.any(mask):
            freqs[i] = ff[mask][np.argmax(fft[mask])]
        times[i] = s / sr
    return times, freqs

def find_stable(freqs, frame_start, frame_end, seg_frames):
    best_cv, best_f = 999, frame_start
    for f in range(frame_start, min(frame_end, len(freqs) - seg_frames)):
        seg = freqs[f:f+seg_frames]
        m = np.mean(seg)
        if m < 30: continue
        cv = np.std(seg) / m if m > 0 else 999
        if cv < best_cv: best_cv, best_f = cv, f
    return best_f, best_cv

def crossfade_loop(samples, n):
    if n <= 0 or len(samples) < n*4: return samples
    r = samples.copy()
    r[:n] = samples[:n] * np.linspace(0,1,n) + samples[-n:] * np.linspace(1,0,n)
    return r[:-n]

def gen_header(name, data, sr):
    u = name.upper(); c = len(data)
    lines = [f"#pragma once", f"#include <stdint.h>", f"#define {u}_SAMPLE_RATE {sr}",
             f"#define {u}_SAMPLE_COUNT {c}", f"static const int8_t {name}_samples[] = {{"]
    for i in range(0, c, 16):
        ch = data[i:i+16]; row = ", ".join(str(int(s)) for s in ch)
        lines.append(f"{row}," if i+16 < c else row)
    lines.append("};"); lines.append("")
    return "\n".join(lines)

def main():
    print("="*60); print("Engine Layer Extractor v2 (frequency-based)"); print("="*60)
    if not os.path.exists(INPUT_FILE): print(f"ERROR: not found"); return 1

    mono = decode_audio(INPUT_FILE)
    dur = len(mono) / TARGET_SR
    print(f"\nDecoded: {dur:.1f}s @ {TARGET_SR}Hz")

    times, freqs = dominant_freq(mono, TARGET_SR)
    valid = freqs[freqs > 30]
    print(f"Frequency range: {np.min(valid):.0f} - {np.max(valid):.0f} Hz")

    # Frequency profile
    print(f"\nFrequency profile:")
    for i in range(0, len(times), 20):
        t = times[i]; f = np.mean(freqs[i:i+20])
        bar = int(f / 500 * 40)
        print(f"  {t:5.1f}s |{'#'*bar}{' '*(40-bar)}| {f:.0f} Hz")

    # 4 sequential time zones
    zone_dur = dur / 4
    hop_ms = 100; seg_frames = int(SEGMENT_S * 1000 / hop_ms)
    cf_samples = int(TARGET_SR * CROSSFADE_MS / 1000)
    hop_samples = int(TARGET_SR * hop_ms / 1000)
    total = 0

    print(f"\nExtracting layers:")
    for idx, (name, rpm) in enumerate(LAYERS):
        t0 = idx * zone_dur; t1 = (idx + 1) * zone_dur
        f0 = int(t0 * 1000 / hop_ms); f1 = int(t1 * 1000 / hop_ms) - seg_frames
        best_f, cv = find_stable(freqs, f0, f1, seg_frames)
        
        s_start = best_f * hop_samples
        s_end = s_start + int(SEGMENT_S * TARGET_SR)
        if s_end > len(mono): s_end = len(mono); s_start = s_end - int(SEGMENT_S * TARGET_SR)
        
        seg = mono[s_start:s_end]
        peak = np.max(np.abs(seg))
        if peak > 0: seg = seg * (0.85 / peak)
        looped = crossfade_loop(seg, cf_samples)
        int8 = np.clip(looped * 127, -128, 127).astype(np.int8)
        
        header = gen_header(name, int8, TARGET_SR)
        with open(os.path.join(OUTPUT_DIR, f"{name}.h"), "w") as f: f.write(header)
        
        mf = np.mean(freqs[best_f:best_f+seg_frames])
        ts = best_f * hop_ms / 1000
        print(f"  {name}: {ts:.1f}-{ts+SEGMENT_S:.1f}s, freq={mf:.0f}Hz, cv={cv:.3f}, {len(int8)/1024:.1f}KB")
        total += len(int8)

    print(f"\nTotal: {total/1024:.1f} KB")
    print("="*60); print("Done! Run 'idf.py build'")
    return 0

if __name__ == "__main__": sys.exit(main())
