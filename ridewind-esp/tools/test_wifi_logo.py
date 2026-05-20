#!/usr/bin/env python3
"""
WiFi Logo 上传测试脚本 — 验证 ESP32 Logo 接收流程

用法：
  python test_wifi_logo.py [esp32_ip]

生成一个 115200 字节的测试 RGB565 图片（渐变色），通过 WebSocket 上传。
如果成功，ESP32 LCD 会显示这张测试图片。
"""

import asyncio
import sys
import time
import zlib

try:
    import websockets
except ImportError:
    print("pip install websockets")
    sys.exit(1)

DEFAULT_IP = "192.168.1.95"
WS_PORT = 81
CHUNK_SIZE = 4096
LOGO_SIZE = 240 * 240 * 2  # 115200 bytes


def generate_test_logo():
    """Generate a 240x240 RGB565 gradient test image"""
    data = bytearray(LOGO_SIZE)
    for y in range(240):
        for x in range(240):
            r = int(x / 240 * 31) & 0x1F
            g = int(y / 240 * 63) & 0x3F
            b = int((x + y) / 480 * 31) & 0x1F
            rgb565 = (r << 11) | (g << 5) | b
            offset = (y * 240 + x) * 2
            data[offset] = (rgb565 >> 8) & 0xFF
            data[offset + 1] = rgb565 & 0xFF
    return bytes(data)


def calculate_crc32(data):
    """CRC32 matching ESP32's implementation"""
    return zlib.crc32(data) & 0xFFFFFFFF


async def logo_upload(ip: str):
    print(f"[INFO] Generating 240x240 RGB565 test image ({LOGO_SIZE} bytes)...")
    logo_data = generate_test_logo()
    crc32 = calculate_crc32(logo_data)
    print(f"[INFO] CRC32: 0x{crc32:08X}")

    uri = f"ws://{ip}:{WS_PORT}/ws"
    print(f"[INFO] Connecting to {uri} ...")

    try:
        async with websockets.connect(uri, ping_interval=None, max_size=None) as ws:
            print("[OK] WebSocket connected")

            # Step 1: LOGO_START_BIN (slot=0 + binary flag = 0x80)
            slot = 0x80
            cmd = f"LOGO_START_BIN:{slot}:{LOGO_SIZE}:{crc32}\n"
            print(f"[SEND] {cmd.strip()}")
            await ws.send(cmd)

            # Step 2: Wait LOGO_READY
            print("[WAIT] LOGO_READY...")
            try:
                resp = await asyncio.wait_for(ws.recv(), timeout=5.0)
                resp = resp.strip()
                print(f"[RECV] {resp}")
            except asyncio.TimeoutError:
                print("[ERROR] Timeout waiting for LOGO_READY")
                return False

            if not resp.startswith("LOGO_READY:"):
                print(f"[ERROR] Unexpected: {resp}")
                return False

            # Step 3: Send binary data
            print(f"[INFO] Sending {LOGO_SIZE} bytes in {CHUNK_SIZE}-byte chunks...")
            sent = 0
            start_time = time.time()
            ack_count = 0

            while sent < LOGO_SIZE:
                end = min(sent + CHUNK_SIZE, LOGO_SIZE)
                chunk = logo_data[sent:end]
                await ws.send(chunk)
                sent += len(chunk)

                try:
                    ack = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    ack = ack.strip()
                except asyncio.TimeoutError:
                    print(f"\n[ERROR] ACK timeout (sent={sent}/{LOGO_SIZE})")
                    return False

                if ack.startswith("LOGO_ACK_BIN:") or ack.startswith("LOGO_ACK:"):
                    ack_count += 1
                    progress = sent / LOGO_SIZE * 100
                    print(f"\r  Progress: {progress:.0f}% | {sent}/{LOGO_SIZE} | ACKs={ack_count}", end="", flush=True)
                elif ack.startswith("LOGO_ERROR:") or ack.startswith("LOGO_FAIL:"):
                    print(f"\n[ERROR] {ack}")
                    return False
                else:
                    print(f"\n[WARN] Unexpected: {ack}")

            elapsed = time.time() - start_time
            speed = LOGO_SIZE / 1024 / elapsed
            print(f"\n[OK] Data sent: {elapsed:.1f}s, {speed:.0f} KB/s, {ack_count} ACKs")

            # Step 4: LOGO_END
            print("[SEND] LOGO_END")
            await ws.send("LOGO_END\n")

            # Step 5: Wait result
            print("[WAIT] LOGO_OK/LOGO_FAIL...")
            try:
                result = await asyncio.wait_for(ws.recv(), timeout=5.0)
                result = result.strip()
                print(f"[RECV] {result}")
            except asyncio.TimeoutError:
                print("[ERROR] Timeout waiting for result")
                return False

            if result.startswith("LOGO_OK:"):
                print(f"\n[SUCCESS] Logo uploaded to slot {result.split(':')[1]}")
                return True
            else:
                print(f"\n[ERROR] {result}")
                return False

    except ConnectionRefusedError:
        print(f"[ERROR] Connection refused ({uri}) - WebSocket server not running?")
        return False
    except Exception as e:
        print(f"[ERROR] {e}")
        return False


def main():
    ip = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IP
    print("=" * 50)
    print("  WiFi Logo Upload Test")
    print("=" * 50)
    print(f"  Target: {ip}:{WS_PORT}")
    print("=" * 50)
    print()

    success = asyncio.run(logo_upload(ip))
    print()
    print("[PASS] Logo WiFi upload works!" if success else "[FAIL] Check ESP32 log")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
