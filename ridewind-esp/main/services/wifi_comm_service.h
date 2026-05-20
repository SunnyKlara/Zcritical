/**
 * @file wifi_comm_service.h
 * @brief WiFi WebSocket communication service — main data channel
 *
 * Provides a WebSocket server (port 81) for APP ↔ ESP32 communication.
 * Replaces BLE as the primary command/data channel after WiFi provisioning.
 *
 * Features:
 * - WebSocket server on port 81 (text frames = commands, binary = data)
 * - mDNS registration as "critical-t1.local"
 * - Receives text commands → protocol_parse() → cmd_queue
 * - Sends notifications/responses back to connected APP
 * - Supports binary frames for OTA/Logo/large data transfers
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>

/**
 * Initialize the WiFi communication service.
 * Creates the HTTP/WebSocket server and registers mDNS.
 * Must be called after WiFi is connected (has IP address).
 */
void wifi_comm_service_init(void);

/**
 * Start the WebSocket server.
 * Called automatically when WiFi connects. Can also be called manually.
 */
void wifi_comm_service_start(void);

/**
 * Stop the WebSocket server.
 * Called when WiFi disconnects or on shutdown.
 */
void wifi_comm_service_stop(void);

/**
 * Send a text notification to the connected WebSocket client.
 * Equivalent to ble_service_notify_str() but over WiFi.
 *
 * @param str  Null-terminated string to send
 */
void wifi_comm_service_notify_str(const char *str);

/**
 * Send binary data to the connected WebSocket client.
 *
 * @param data  Binary data buffer
 * @param len   Length in bytes
 */
void wifi_comm_service_notify_bin(const uint8_t *data, uint16_t len);

/**
 * Check if a WebSocket client is currently connected.
 */
bool wifi_comm_service_is_connected(void);

/**
 * Get the WebSocket server port number.
 */
uint16_t wifi_comm_service_get_port(void);
