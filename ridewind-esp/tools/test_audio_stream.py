#!/usr/bin/env python3
"""
Test script: generate a sine wave tone and stream it to ESP32 via TCP.

Usage:
  1. Connect your PC to WiFi "T1_Audio" (password: 12345678)
  2. Run: python test_audio_stream.py
  3. You should hear a 440Hz tone from the MAX98357 speaker

Press Ctrl+C to stop.
"""

import socket
import struct
import math
import time

ESP32_IP = "192.168.4.1"
TCP_PORT = 8080

SAMPLE_RATE = 44100
CHANNELS = 2        # stereo
FREQUENCY = 440     # Hz (A4 note)
AMPLITUDE = 16000   # ~50% of int16 max
CHUNK_MS = 20       # send 20ms chunks

samples_per_chunk = int(SAMPLE_RATE * CHUNK_MS / 1000)

def generate_sine_chunk(phase, freq, amp, sr, n_samples):
    """Generate stereo PCM sine wave samples, return (bytes, new_phase)."""
    data = bytearray()
    for i in range(n_samples):
        t = phase + 2.0 * math.pi * freq * i / sr
        val = int(amp * math.sin(t))
        # Clamp
        val = max(-32768, min(32767, val))
        # Stereo: same value for L and R
        data += struct.pack('<hh', val, val)
    new_phase = phase + 2.0 * math.pi * freq * n_samples / sr
    return bytes(data), new_phase

def main():
    print(f"Connecting to {ESP32_IP}:{TCP_PORT}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.connect((ESP32_IP, TCP_PORT))
    except Exception as e:
        print(f"Connection failed: {e}")
        print("Make sure your PC is connected to WiFi 'T1_Audio'")
        return

    print(f"Connected! Streaming {FREQUENCY}Hz sine wave...")
    print("Press Ctrl+C to stop")

    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    phase = 0.0
    try:
        while True:
            chunk, phase = generate_sine_chunk(
                phase, FREQUENCY, AMPLITUDE, SAMPLE_RATE, samples_per_chunk)
            sock.sendall(chunk)
            time.sleep(CHUNK_MS / 1000.0)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        sock.close()

if __name__ == "__main__":
    main()
