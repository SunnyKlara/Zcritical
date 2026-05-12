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
void wifi_audio_service_auto_connect(void);       /* Connect using saved NVS credentials */
