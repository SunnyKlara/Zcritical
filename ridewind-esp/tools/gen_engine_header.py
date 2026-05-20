"""
gen_engine_header.py — Generate C header with embedded engine sound data.

Reads the 4 PCM files from storage_data/ and generates a single C header
with const int16_t arrays for direct compilation into firmware.

This avoids LittleFS dependency for the engine sounds.
Total size: ~246KB (well within 3MB firmware partition).
"""

import os
import struct
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STORAGE_DIR = os.path.join(SCRIPT_DIR, "..", "storage_data")
OUT_FILE = os.path.join(SCRIPT_DIR, "..", "main", "resources", "engine_sounds.h")

FILES = [
    ("engine_idle.pcm", "engine_idle", "Idle loop"),
    ("engine_rev.pcm", "engine_rev", "Rev loop"),
    ("engine_knock.pcm", "engine_knock", "Knock pulse"),
    ("engine_start.pcm", "engine_start", "Start sound"),
]


def pcm_to_array(filepath):
    """Read PCM file and return list of int16 values."""
    with open(filepath, 'rb') as f:
        data = f.read()
    count = len(data) // 2
    values = struct.unpack(f'<{count}h', data)
    return list(values)


def main():
    print("Generating engine_sounds.h...")

    lines = []
    lines.append("#pragma once")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append("/* Auto-generated from LaFerrari V12 sounds (TheDIYGuy999)")
    lines.append(" * Format: 44100Hz 16-bit signed mono PCM")
    lines.append(" * Source: extract_rc_sounds.py -> gen_engine_header.py */")
    lines.append("")

    total_bytes = 0

    for filename, varname, desc in FILES:
        filepath = os.path.join(STORAGE_DIR, filename)
        if not os.path.exists(filepath):
            print(f"  WARNING: {filename} not found, skipping")
            continue

        values = pcm_to_array(filepath)
        count = len(values)
        size_kb = count * 2 / 1024

        lines.append(f"/* {desc} -- {count} samples, {count*2} bytes ({size_kb:.1f}KB) */")
        lines.append(f"#define ENGINE_{varname.upper()}_COUNT {count}")
        lines.append(f"static const int16_t {varname}_samples[] = {{")

        # Write values in rows of 16
        for i in range(0, count, 16):
            row = values[i:i+16]
            row_str = ", ".join(str(v) for v in row)
            if i + 16 >= count:
                lines.append(f"  {row_str}")
            else:
                lines.append(f"  {row_str},")

        lines.append("};")
        lines.append("")

        total_bytes += count * 2
        print(f"  {filename}: {count} samples ({size_kb:.1f}KB)")

    # Write output
    with open(OUT_FILE, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
        f.write('\n')

    print(f"\nTotal: {total_bytes/1024:.1f}KB")
    print(f"Output: {OUT_FILE}")


if __name__ == "__main__":
    main()
