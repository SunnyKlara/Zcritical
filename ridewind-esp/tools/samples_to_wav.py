"""
Convert engine sound header arrays to WAV files for preview.
Run: python tools/samples_to_wav.py
Output: tools/idle.wav, tools/rev.wav
"""
import struct, wave, os, re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RES_DIR = os.path.join(SCRIPT_DIR, '..', 'main', 'resources')

def parse_header(filename):
    """Extract signed int8 sample array from a C header file."""
    path = os.path.join(RES_DIR, filename)
    with open(path, 'r') as f:
        text = f.read()
    
    # Find the array content between { and };
    match = re.search(r'\{([^}]+)\}', text, re.DOTALL)
    if not match:
        raise ValueError(f"No array found in {filename}")
    
    # Parse comma-separated integers
    nums = re.findall(r'-?\d+', match.group(1))
    samples = [int(n) for n in nums]
    print(f"  {filename}: {len(samples)} samples, range [{min(samples)}, {max(samples)}]")
    return samples

def write_wav(filename, samples, sample_rate=22050, loops=10):
    """Write samples as 16-bit WAV, looped N times so you can hear it."""
    path = os.path.join(SCRIPT_DIR, filename)
    
    # Convert int8 (-128..127) to int16 (-32768..32512) 
    pcm16 = []
    for _ in range(loops):
        for s in samples:
            pcm16.append(max(-32768, min(32767, s * 256)))
    
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)  # 16-bit
        w.setframerate(sample_rate)
        w.writeframes(struct.pack(f'<{len(pcm16)}h', *pcm16))
    
    duration = len(pcm16) / sample_rate
    print(f"  -> {filename}: {duration:.1f}s, {len(pcm16)} samples")

if __name__ == '__main__':
    print("Parsing header files...")
    idle = parse_header('engine_idle.h')
    rev = parse_header('engine_rev.h')
    
    print("\nWriting WAV files...")
    write_wav('idle.wav', idle, loops=15)    # ~2s of idle looped
    write_wav('rev.wav', rev, loops=15)      # ~2s of rev looped
    
    # Also write a version at different playback speeds to simulate RPM change
    write_wav('idle_2x.wav', idle, sample_rate=44100, loops=15)  # 2x pitch
    write_wav('rev_2x.wav', rev, sample_rate=44100, loops=15)    # 2x pitch
    
    print(f"\nDone! Files in: {SCRIPT_DIR}")
    print("Play idle.wav to hear the idle sound at original pitch.")
    print("Play rev.wav to hear the rev sound at original pitch.")
    print("Play idle_2x.wav / rev_2x.wav to hear them at 2x pitch (higher RPM).")
