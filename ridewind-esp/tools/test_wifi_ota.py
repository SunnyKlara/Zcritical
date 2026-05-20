#!/usr/bin/env python3
"""
WiFi OTA 测试脚本 — 直接通过 WebSocket 验证 ESP32 OTA 流程

用法：
  python test_wifi_ota.py <firmware.bin> [esp32_ip]

示例：
  python test_wifi_ota.py ../build/ridewind-esp.bin 192.168.1.95

流程：
  1. 连接 ws://ip:81/ws
  2. 发送 text: "OTA_BEGIN:size\n"
  3. 等待 text: "OTA_READY:partition_size\r\n"
  4. 发送 binary frames (4KB each)
  5. 每帧等待 text: "OTA_ACK:bytes\r\n"
  6. 发送 text: "OTA_END\n"
  7. 等待 text: "OTA_OK:version\r\n"

如果这个脚本成功，说明 ESP32 端完全正常，问题在 APP 端。
如果这个脚本失败，说明 ESP32 端有问题。
"""

import asyncio
import sys
import time
import os

try:
    import websockets
except ImportError:
    print("需要安装 websockets: pip install websockets")
    sys.exit(1)


CHUNK_SIZE = 4096
DEFAULT_IP = "192.168.1.95"
WS_PORT = 81


async def ota_upload(firmware_path: str, ip: str):
    # 读取固件
    if not os.path.exists(firmware_path):
        print(f"[ERROR] firmware not found: {firmware_path}")
        return False

    with open(firmware_path, "rb") as f:
        firmware_data = f.read()

    total_size = len(firmware_data)
    print(f"[INFO] Firmware size: {total_size} bytes ({total_size/1024:.1f} KB)")

    if total_size == 0 or total_size > 3 * 1024 * 1024:
        print("[ERROR] Invalid firmware size (0 or >3MB)")
        return False

    uri = f"ws://{ip}:{WS_PORT}/ws"
    print(f"[INFO] Connecting to {uri} ...")

    try:
        async with websockets.connect(uri, ping_interval=None, max_size=None) as ws:
            print("[OK] WebSocket connected")

            # Step 1: Send OTA_BEGIN
            begin_cmd = f"OTA_BEGIN:{total_size}\n"
            print(f"[SEND] {begin_cmd.strip()}")
            await ws.send(begin_cmd)

            # Step 2: Wait for OTA_READY
            print("[WAIT] OTA_READY (erasing partition, up to 15s)...")
            try:
                resp = await asyncio.wait_for(ws.recv(), timeout=15.0)
                resp = resp.strip()
                print(f"[RECV] {resp}")
            except asyncio.TimeoutError:
                print("[ERROR] Timeout waiting for OTA_READY")
                return False

            if not resp.startswith("OTA_READY:"):
                print(f"[ERROR] Unexpected response: {resp}")
                return False

            # Step 3: Send firmware data
            print(f"\n[INFO] Starting transfer ({total_size} bytes, {CHUNK_SIZE} bytes/chunk)...")
            sent = 0
            start_time = time.time()
            ack_count = 0

            while sent < total_size:
                # Send one chunk
                end = min(sent + CHUNK_SIZE, total_size)
                chunk = firmware_data[sent:end]
                await ws.send(chunk)
                sent += len(chunk)

                # Wait for ACK
                try:
                    ack = await asyncio.wait_for(ws.recv(), timeout=10.0)
                    ack = ack.strip()
                except asyncio.TimeoutError:
                    print(f"\n[ERROR] ACK timeout (sent={sent}/{total_size})")
                    return False

                if ack.startswith("OTA_ACK:"):
                    ack_count += 1
                    acked_bytes = int(ack.split(":")[1])
                    progress = sent / total_size * 100
                    speed = sent / 1024 / (time.time() - start_time)
                    print(f"\r  Progress: {progress:.1f}% | {sent}/{total_size} | ACK={acked_bytes} | {speed:.0f} KB/s", end="", flush=True)
                elif ack.startswith("OTA_FAIL:"):
                    print(f"\n[ERROR] Transfer failed: {ack}")
                    return False
                else:
                    print(f"\n[WARN] Unexpected response: {ack}")

            elapsed = time.time() - start_time
            speed = total_size / 1024 / elapsed
            print(f"\n\n[OK] Transfer complete: {elapsed:.1f}s, {speed:.0f} KB/s, {ack_count} ACKs")

            # Step 4: Send OTA_END
            print("[SEND] OTA_END")
            await ws.send("OTA_END\n")

            # Step 5: Wait for verification result
            print("[WAIT] Verification result (up to 15s)...")
            try:
                result = await asyncio.wait_for(ws.recv(), timeout=15.0)
                result = result.strip()
                print(f"[RECV] {result}")
            except asyncio.TimeoutError:
                print("[ERROR] Timeout waiting for verification result")
                return False

            if result.startswith("OTA_OK:"):
                version = result.split(":")[1]
                print(f"\n[SUCCESS] OTA complete! New firmware version: {version}")
                print("  ESP32 will restart in 500ms...")
                return True
            elif result.startswith("OTA_FAIL:"):
                print(f"\n[ERROR] OTA verification failed: {result}")
                return False
            else:
                print(f"\n[WARN] Unexpected result: {result}")
                return False

    except ConnectionRefusedError:
        print(f"[ERROR] Connection refused - is ESP32 WebSocket running? ({uri})")
        return False
    except Exception as e:
        print(f"[ERROR] Exception: {e}")
        return False


def main():
    if len(sys.argv) < 2:
        print("Usage: python test_wifi_ota.py <firmware.bin> [esp32_ip]")
        print("Example: python test_wifi_ota.py ../build/ridewind-esp.bin 192.168.1.95")
        sys.exit(1)

    firmware_path = sys.argv[1]
    ip = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_IP

    print("=" * 60)
    print("  WiFi OTA Test Tool")
    print("=" * 60)
    print(f"  Firmware: {firmware_path}")
    print(f"  Target:   {ip}:{WS_PORT}")
    print("=" * 60)
    print()

    success = asyncio.run(ota_upload(firmware_path, ip))

    print()
    if success:
        print("[PASS] ESP32 WiFi OTA works correctly")
    else:
        print("[FAIL] Check ESP32 serial log for details")

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
