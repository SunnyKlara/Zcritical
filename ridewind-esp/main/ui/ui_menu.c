#include "ui_menu.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include <string.h>

static const char *MENU_NAMES[6] = {"Speed","Color","RGB","Bright","Logo","Volume"};
static const uint8_t MENU_TARGET_UI[6] = {1,2,3,4,6,7};
static int16_t s_accum_delta = 0;
static uint32_t s_last_switch_tick = 0;
static uint8_t s_need_redraw = 0;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_menu_page(uint8_t sel) {
    drv_lcd_clear(0x0000);
    const char *name = MENU_NAMES[sel - 1];
    uint16_t tw = strlen(name) * 16;
    drv_lcd_draw_string((240 - tw) / 2, 90, name, 0xFFFF, 0x0000, 2);
    uint16_t dx0 = (240 - 5 * 15) / 2;
    for (uint8_t i = 0; i < 6; i++) {
        uint16_t c = (i == sel - 1) ? 0xFFFF : rgb565(66,66,66);
        drv_lcd_draw_circle(dx0 + i*15, 200, 3, c, true);
    }
    if (sel > 1) drv_lcd_draw_string(5, 105, "<", rgb565(128,128,128), 0x0000, 2);
    if (sel < 6) drv_lcd_draw_string(220, 105, ">", rgb565(128,128,128), 0x0000, 2);
}

void ui_menu_enter(void) {
    s_accum_delta = 0;
    s_need_redraw = 1;
}

void ui_menu_update(void) {
    if (g_app_state.auto_enter) {
        g_app_state.auto_enter = 0;
        uint8_t sel = g_app_state.menu_selected;
        if (sel >= 1 && sel <= 6) { ui_manager_set_ui(MENU_TARGET_UI[sel-1]); return; }
    }
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        if (evt.type == ENC_EVT_ROTATE) {
            uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
            s_accum_delta += evt.delta;
            if ((now - s_last_switch_tick >= MENU_SWITCH_DEBOUNCE_MS) && (s_accum_delta >= MENU_DELTA_THRESHOLD || s_accum_delta <= -MENU_DELTA_THRESHOLD)) {
                int8_t dir = (s_accum_delta > 0) ? 1 : -1;
                int8_t ns = g_app_state.menu_selected + dir;
                if (ns < 1) ns = 6;
                if (ns > 6) ns = 1;
                g_app_state.menu_selected = ns;
                s_accum_delta = 0;
                s_last_switch_tick = now;
                s_need_redraw = 1;
            }
        } else if (evt.type == ENC_EVT_CLICK) {
            uint8_t sel = g_app_state.menu_selected;
            if (sel >= 1 && sel <= 6) { ui_manager_set_ui(MENU_TARGET_UI[sel-1]); return; }
        }
    }
    if (s_need_redraw) { draw_menu_page(g_app_state.menu_selected); s_need_redraw = 0; }
}
