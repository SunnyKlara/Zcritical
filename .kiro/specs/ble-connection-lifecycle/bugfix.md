# Bugfix Requirements Document

## Introduction

When a phone (Phone A) has the RideWind app connected to the ESP32 device and the user switches the app to background, the OS maintains the BLE connection indefinitely. This prevents any other phone (Phone B) from connecting to the device. The connection is only released when Phone A's app process is completely killed by the OS or user. This creates a poor multi-device experience — the device becomes "locked" to a backgrounded app that isn't actively using it.

The fix requires a coordinated approach across firmware (idle connection timeout) and app (proactive disconnect on background, graceful reconnect on foreground return).

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the app goes to background while connected to the ESP32 device THEN the system maintains the BLE connection indefinitely through the OS, holding the single connection slot without active use

1.2 WHEN Phone B attempts to connect while Phone A holds a backgrounded (idle) connection THEN the system rejects Phone B's connection with GATT error 133 or timeout, providing no mechanism to release the stale connection

1.3 WHEN Phone A's app is backgrounded and the ESP32 receives no BLE data for an extended period THEN the firmware takes no action to release the idle connection, keeping the slot occupied indefinitely

1.4 WHEN Phone B's connection fails due to device being occupied THEN the system only shows a generic "device busy" message with no actionable recovery option beyond asking the user to kill the other app

1.5 WHEN the user returns the app from background after the connection has been released (by timeout or other mechanism) THEN the system has no graceful recovery path — the auto-reconnect may trigger stale state or fail silently

### Expected Behavior (Correct)

2.1 WHEN the app goes to background while connected to the ESP32 device THEN the system SHALL proactively disconnect the BLE connection after a short grace period (e.g., 5-10 seconds), freeing the device for other connections

2.2 WHEN Phone B attempts to connect while the device is genuinely idle (no active data exchange from the connected phone) THEN the system SHALL allow Phone B to connect, either because the idle connection was already released or through a firmware-side idle timeout mechanism

2.3 WHEN the ESP32 receives no BLE data from a connected client for a configurable timeout period (e.g., 30-60 seconds) THEN the firmware SHALL terminate the idle connection and restart advertising, making the device available for new connections

2.4 WHEN a connection attempt fails because the device is occupied by an active session THEN the system SHALL inform the user clearly that the device is in use and suggest waiting or retrying, distinguishing between "device actively in use" and "device held by stale connection"

2.5 WHEN the user returns the app from background after the BLE connection was released THEN the system SHALL detect the disconnection, show appropriate UI feedback, and offer a one-tap reconnect option that cleanly re-establishes the connection and re-syncs hardware state

### Unchanged Behavior (Regression Prevention)

3.1 WHEN the app is in foreground and actively communicating with the ESP32 THEN the system SHALL CONTINUE TO maintain a stable BLE connection with normal command/response flow

3.2 WHEN the user manually disconnects from the device THEN the system SHALL CONTINUE TO cleanly release the connection and stop auto-reconnect attempts

3.3 WHEN the device is powered off or goes out of range THEN the system SHALL CONTINUE TO detect disconnection and attempt auto-reconnect with exponential backoff (max 5 attempts)

3.4 WHEN the app performs BLE operations (scan, connect, send commands) THEN the system SHALL CONTINUE TO use the existing flutter_blue_plus and Bluedroid GATTS stack without protocol changes

3.5 WHEN the ESP32 is connected and receiving active commands (speed, LED, fan control) THEN the firmware SHALL CONTINUE TO process commands normally without premature disconnection from the idle timeout

3.6 WHEN WiFi audio provisioning is in progress (BLE disconnect is expected during RF switch) THEN the system SHALL CONTINUE TO handle the temporary BLE disconnection gracefully without triggering background-disconnect logic
