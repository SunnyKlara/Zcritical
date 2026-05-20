#pragma once
#include <stdint.h>
#include <stdbool.h>

void wifi_audio_service_init(void);
void wifi_audio_service_scan(void);     /* Scan WiFi, report via BLE: WIFI_AP:ssid:rssi:auth */
void wifi_audio_service_connect(const char *ssid, const char *password);
bool wifi_audio_service_is_streaming(void);
bool wifi_audio_service_is_connected(void);
const char *wifi_audio_service_get_ip(void);
void wifi_audio_service_stop(void);
void wifi_audio_service_clear_credentials(void);  /* Erase saved WiFi from NVS */
void wifi_audio_service_notify_status(void);      /* Re-send WIFI_IP if connected */
void wifi_audio_service_auto_connect(void);       /* Connect using saved NVS credentials (blocking) */
bool wifi_audio_service_has_credentials(void);    /* Check if NVS has saved WiFi credentials */

/**
 * @brief Connect WiFi with provisioning flow (async, with BLE coordination).
 *
 * Called from WIFI:ssid:pass command handler. Saves credentials, stops BLE
 * advertising, attempts WiFi connection (10s timeout). On success: restarts
 * BLE and notifies WIFI_IP. On failure: restarts BLE and notifies error.
 *
 * @param ssid      WiFi SSID
 * @param password  WiFi password
 *
 * @note This spawns a FreeRTOS task to handle the async flow.
 *       BLE is stopped before WiFi CONNECTING to avoid RF contention.
 */
void wifi_audio_service_provision(const char *ssid, const char *password);
