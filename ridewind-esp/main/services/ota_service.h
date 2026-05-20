#pragma once

#include <stdint.h>
#include <stdbool.h>

/**
 * @file ota_service.h
 * @brief BLE OTA firmware update service
 *
 * Streaming OTA: receives firmware data via BLE binary mode,
 * writes directly to flash using internal SRAM buffer (4KB).
 * Does NOT use PSRAM (inaccessible during flash writes).
 *
 * Protocol:
 *   App → ESP32: OTA_BEGIN:size:sha256_hex\n
 *   ESP32 → App: OTA_READY:partition_size\r\n  (after erase completes)
 *   App → ESP32: [binary mode — raw firmware bytes]
 *   ESP32 → App: OTA_ACK:received_bytes\r\n    (every ~4KB)
 *   App → ESP32: OTA_END\n
 *   ESP32 → App: OTA_OK:version\r\n  or  OTA_FAIL:reason\r\n
 *   ESP32: esp_restart() after 500ms
 */

/**
 * Initialize OTA service state. Call once at boot.
 * Also performs rollback self-test if firmware is pending verification.
 */
void ota_service_init(void);

/**
 * Start OTA session. Erases target partition.
 * @param firmware_size  Total firmware .bin size in bytes
 * @param sha256_hex     Expected SHA256 hex string (64 chars) or NULL to skip
 * @return true if session started successfully
 */
bool ota_service_begin(uint32_t firmware_size, const char *sha256_hex);

/**
 * Feed binary data from BLE. Called from BLE callback context.
 * Buffers internally (4KB SRAM) and writes to flash when full.
 * @param data  Raw firmware bytes
 * @param len   Number of bytes in this packet
 */
void ota_service_feed_data(const uint8_t *data, uint16_t len);

/**
 * Finalize OTA: flush buffer, validate image, set boot partition.
 * Sends OTA_OK or OTA_FAIL via BLE notify.
 * On success, schedules esp_restart() after 500ms.
 */
void ota_service_end(void);

/**
 * Abort current OTA session and free resources.
 */
void ota_service_abort(void);

/**
 * Check if OTA binary mode is active (for BLE routing).
 */
bool ota_is_binary_mode(void);
