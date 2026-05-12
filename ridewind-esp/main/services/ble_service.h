#pragma once
#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Initialize Bluedroid BLE GATTS with service 0xFFE0 / char 0xFFE1
 * @note  Must be called after NVS init. Registers GATTS app and creates service.
 */
void ble_service_init(void);

/**
 * @brief Start BLE advertising with device name "T1"
 */
void ble_service_start(void);

/**
 * @brief Stop BLE advertising
 */
void ble_service_stop(void);

/**
 * @brief Send notification to connected BLE client
 * @param data  Raw data bytes
 * @param len   Data length
 */
void ble_service_notify(const char *data, uint16_t len);

/**
 * @brief Send null-terminated string as BLE notification
 */
void ble_service_notify_str(const char *str);

/**
 * @brief Check if a BLE client is connected
 */
bool ble_service_is_connected(void);
