/**
 * @file app_state.c
 * @brief 全局应用状态初始化（工厂默认值）
 */

#include "app_state.h"
#include "led_effects.h"
#include <string.h>

app_state_t       g_app_state;
SemaphoreHandle_t g_app_state_mutex;

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
}
