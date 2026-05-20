"""Generate forza_accel.h from engine_gear_max.pcm (first 7 seconds)"""
import struct

INPUT = "main/resources/engine_pcm/engine_gear_max.pcm"
OUTPUT = "main/resources/forza_accel.h"
DURATION_S = 5
SAMPLE_RATE = 44100

with open(INPUT, "rb") as f:
    data = f.read()

total_samples = len(data) // 2
samples = struct.unpack(f"<{total_samples}h", data)

cut = SAMPLE_RATE * DURATION_S
samples = samples[:cut]
print(f"Truncated to {len(samples)} samples ({len(samples)/SAMPLE_RATE:.1f}s, {len(samples)*2/1024:.0f} KB)")

with open(OUTPUT, "w") as out:
    out.write(f"/* Forza full-throttle acceleration - {len(samples)} samples @ 44100Hz 16-bit */\n")
    out.write("#pragma once\n\n")
    out.write(f"#define FORZA_ACCEL_COUNT {len(samples)}\n\n")
    out.write("static const int16_t forza_accel[] = {\n")
    
    for i in range(0, len(samples), 16):
        row = samples[i:i+16]
        out.write("    " + ", ".join(str(s) for s in row) + ",\n")
    
    out.write("};\n")

print(f"Written: {OUTPUT}")
