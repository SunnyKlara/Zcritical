/**
 * @file app_state.c
 * @brief 全局应用状态初始化（工厂默认值）+ NVS 持久化
 */

#include "app_state.h"
#include "led_effects.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "APP_STATE";
#define NVS_NAMESPACE "ridewind"

app_state_t       g_app_state;
SemaphoreHandle_t g_app_state_mutex;

/* ── NVS helpers ── */

static void nvs_load_config(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) return;

    uint16_t u16;
    uint8_t u8;
    if (nvs_get_u16(h, "speed_max", &u16) == ESP_OK) g_app_state.speed_max_display = u16;
    if (nvs_get_u8(h, "fan_min", &u8) == ESP_OK) g_app_state.fan_range_min = u8;
    if (nvs_get_u8(h, "fan_max", &u8) == ESP_OK) g_app_state.fan_range_max = u8;
    if (nvs_get_u8(h, "volume", &u8) == ESP_OK) g_app_state.volume = u8;

    nvs_close(h);
    ESP_LOGI(TAG, "NVS loaded: speed_max=%u, fan=%u-%u, vol=%u",
             g_app_state.speed_max_display, g_app_state.fan_range_min,
             g_app_state.fan_range_max, g_app_state.volume);
}

void app_state_save_config(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) != ESP_OK) {
        ESP_LOGE(TAG, "NVS open failed");
        return;
    }
    nvs_set_u16(h, "speed_max", g_app_state.speed_max_display);
    nvs_set_u8(h, "fan_min", g_app_state.fan_range_min);
    nvs_set_u8(h, "fan_max", g_app_state.fan_range_max);
    nvs_set_u8(h, "volume", g_app_state.volume);
    nvs_commit(h);
    nvs_close(h);
    ESP_LOGI(TAG, "NVS saved: speed_max=%u, fan=%u-%u, vol=%u",
             g_app_state.speed_max_display, g_app_state.fan_range_min,
             g_app_state.fan_range_max, g_app_state.volume);
}

void app_state_init(void)
{
    g_app_state_mutex = xSemaphoreCreateMutex();
    memset(&g_app_state, 0, sizeof(g_app_state));

    /* ── Factory defaults (matching STM32 deng_init) ── */

    /* Main strip: white */
    g_app_state.led_colors[0][0] = 255;
    g_app_state.led_colors[0][1] = 255;
    g_app_state.led_colors[0][2] = 255;

    /* Left strip: white */
    g_app_state.led_colors[1][0] = 255;
    g_app_state.led_colors[1][1] = 255;
    g_app_state.led_colors[1][2] = 255;

    /* Right strip: white */
    g_app_state.led_colors[2][0] = 255;
    g_app_state.led_colors[2][1] = 255;
    g_app_state.led_colors[2][2] = 255;

    /* Tail strip: white */
    g_app_state.led_colors[3][0] = 255;
    g_app_state.led_colors[3][1] = 255;
    g_app_state.led_colors[3][2] = 255;

    /* Copy to edit buffer */
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 3; j++) {
            g_app_state.led_edit[i][j] = g_app_state.led_colors[i][j];
        }
    }

    g_app_state.brightness       = 100;
    g_app_state.volume           = 0;       /* Muted by default — engine audio still in dev */
    g_app_state.preset_index     = 1;
    g_app_state.speed_unit       = 0;       /* km/h */
    g_app_state.speed_max_display = 340;    /* Default max speed display */
    g_app_state.fan_range_min    = 0;       /* Default fan range: 0-100 */
    g_app_state.fan_range_max    = 100;
    g_app_state.wuhuaqi_state    = 0;       /* Humidifier off by default — user activates via APP or throttle */
    g_app_state.wuhuaqi_state_saved = 0;
    g_app_state.menu_selected    = 1;
    g_app_state.breath_color_index = 1;
    g_app_state.last_reported_speed = -1;
    g_app_state.throttle_frozen_speed = -1;
    g_app_state.throttle_fx_mode = THROTTLE_FX_STATIC;  /* Default: static (no effect) */

    /* Boot into menu */
    g_app_state.ui  = 5;
    g_app_state.chu = 5;

    /* Load saved config from NVS (overrides defaults if present) */
    nvs_load_config();
}
