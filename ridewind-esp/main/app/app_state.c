#include "app_state.h"
#include <string.h>

app_state_t       g_app_state;
SemaphoreHandle_t g_app_state_mutex;

void app_state_init(void)
{
    g_app_state_mutex = xSemaphoreCreateMutex();
    memset(&g_app_state, 0, sizeof(g_app_state));

    /* ── Factory defaults (matching STM32 deng_init) ── */

    /* Main strip: deep orange-red */
    g_app_state.led_colors[0][0] = 150;
    g_app_state.led_colors[0][1] = 20;
    g_app_state.led_colors[0][2] = 0;

    /* Left strip: pure red */
    g_app_state.led_colors[1][0] = 255;
    g_app_state.led_colors[1][1] = 0;
    g_app_state.led_colors[1][2] = 0;

    /* Right strip: blue */
    g_app_state.led_colors[2][0] = 33;
    g_app_state.led_colors[2][1] = 126;
    g_app_state.led_colors[2][2] = 222;

    /* Tail strip: pure red */
    g_app_state.led_colors[3][0] = 255;
    g_app_state.led_colors[3][1] = 0;
    g_app_state.led_colors[3][2] = 0;

    /* Copy to edit buffer */
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 3; j++) {
            g_app_state.led_edit[i][j] = g_app_state.led_colors[i][j];
        }
    }

    g_app_state.brightness       = 100;
    g_app_state.volume           = 80;
    g_app_state.preset_index     = 1;
    g_app_state.speed_unit       = 0;       /* km/h */
    g_app_state.wuhuaqi_state    = 1;       /* Humidifier on by default */
    g_app_state.wuhuaqi_state_saved = 1;
    g_app_state.menu_selected    = 1;
    g_app_state.breath_color_index = 1;
    g_app_state.last_reported_speed = -1;
    g_app_state.throttle_frozen_speed = -1;

    /* Boot into menu */
    g_app_state.ui  = 5;
    g_app_state.chu = 5;
}
