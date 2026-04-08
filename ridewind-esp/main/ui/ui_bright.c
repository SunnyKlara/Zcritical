#include "ui_bright.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include "board_config.h"
#include <stdio.h>

/* UI4 - Brightness + Breathing Effect
 * Encoder rotation adjusts brightness 0-100 (when breathing off).
 * Single-click toggles Breathing_Effect on/off.
 * Double-click saves and returns to UI5. */

static uint8_t  s_need_redraw = 1;
static int16_t  s_last_bright = -1;
static uint8_t  s_last_breath = 0xFF;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_bright_screen(void)
{
    int16_t bright = g_app_state.brightness;
    uint8_t breath = g_app_state.breath_mode;

    if (bright != s_last_bright || breath != s_last_breath || s_need_redraw) {
        if (s_need_redraw) {
            drv_lcd_clear(0x0000);
            drv_lcd_draw_string(140, 150, "BRT", 0xFFFF, 0x0000, 1);
        }

        /* Brightness number */
        drv_lcd_fill_rect(20, 70, 130, 60, 0x0000);
        char buf[8];
        snprintf(buf, sizeof(buf), "%d", bright);
        uint8_t len = 0;
        while (buf[len]) len++;
        uint16_t x = 80 - len * 12;
        drv_lcd_draw_string(x, 80, buf, 0xFFFF, 0x0000, 3);

        /* Breathing indicator dot */
        uint16_t dot_color = breath ? rgb565(0, 255, 0) : rgb565(255, 0, 0);
        drv_lcd_fill_rect(195, 145, 20, 20, 0x0000);
        drv_lcd_draw_circle(205, 155, 5, dot_color, true);

        s_last_bright = bright;
        s_last_breath = breath;
        s_need_redraw = 0;
    }
}

void ui_bright_enter(void)
{
    s_need_redraw = 1;
    s_last_bright = -1;
    s_last_breath = 0xFF;
}

void ui_bright_update(void)
{

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE:
            if (!g_app_state.breath_mode) {
                /* Adjust brightness only when breathing is off */
                int16_t val = g_app_state.brightness + evt.delta;
                if (val < 0) val = 0;
                if (val > 100) val = 100;
                g_app_state.brightness = val;
                drv_led_set_brightness((uint8_t)val);
                drv_led_refresh();
                s_need_redraw = 1;
            }
            break;

        case ENC_EVT_CLICK:
            /* Toggle breathing effect */
            g_app_state.breath_mode ^= 1;
            if (g_app_state.breath_mode) {
                led_effects_breathing_start();
            } else {
                led_effects_breathing_stop();
                /* Restore static brightness */
                drv_led_set_brightness((uint8_t)g_app_state.brightness);
                drv_led_refresh();
            }
            s_need_redraw = 1;
            break;

        case ENC_EVT_DOUBLE_CLICK:
            /* Save and return to menu */
            /* TODO Phase 8: storage_save_settings() */
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_bright_screen();
}
