#include "ui_bright.h"
#include "ui_common.h"
#include "ui_images.h"
#include "storage.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include <stdio.h>

/* UI4 - Brightness + Breathing Effect
 *
 * Rendering strategy (flicker-free):
 *   - s_need_full_redraw: set ONLY on enter(), draws background + all static elements
 *   - Value changes: only clear+redraw the number area (局部刷新)
 *   - LED changes: only redraw the LED indicator (12x21 pixels)
 *   - NEVER redraw background on encoder rotation
 */

static uint8_t  s_need_full_redraw = 1;
static int16_t  s_last_bright = -1;
static uint8_t  s_last_breath = 0xFF;

static void draw_bright_screen(void)
{
    int16_t bright = g_app_state.brightness;
    uint8_t breath = g_app_state.breath_mode;

    /* Full redraw: only on enter() */
    if (s_need_full_redraw) {
        ui_draw_f4_background();
        ui_blit_f4_image(F4_BRT_X, F4_BRT_Y, F4_BRT_WIDTH, F4_BRT_HIGH,
                         gImage_brt_6923);
        ui_draw_f4_led(F4_BRT_X + F4_BRT_WIDTH, F4_BRT_Y, breath ? 1 : 0);

        /* Clear number area and draw current value */
        drv_lcd_fill_rect(20, F4_UI4_Y_QI,
                          F4_UI4_X_QI + 5 - 20, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_UI4_X_QI, F4_UI4_Y_QI,
                                      (uint16_t)bright, F4_UI4_JIANJU);

        s_last_bright = bright;
        s_last_breath = breath;
        s_need_full_redraw = 0;
        return;
    }

    /* Partial update: number only */
    if (bright != s_last_bright) {
        drv_lcd_fill_rect(20, F4_UI4_Y_QI,
                          F4_UI4_X_QI + 5 - 20, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_UI4_X_QI, F4_UI4_Y_QI,
                                      (uint16_t)bright, F4_UI4_JIANJU);
        s_last_bright = bright;
    }

    /* Partial update: LED only */
    if (breath != s_last_breath) {
        ui_draw_f4_led(F4_BRT_X + F4_BRT_WIDTH, F4_BRT_Y, breath ? 1 : 0);
        s_last_breath = breath;
    }
}

void ui_bright_enter(void)
{
    s_need_full_redraw = 1;
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
                int16_t val = g_app_state.brightness + evt.delta;
                if (val < 0) val = 0;
                if (val > 100) val = 100;
                g_app_state.brightness = val;
                drv_led_set_brightness((uint8_t)val);
                drv_led_refresh();
                /* No s_need_full_redraw! draw_bright_screen detects value change */
            }
            break;

        case ENC_EVT_CLICK:
            g_app_state.breath_mode ^= 1;
            if (g_app_state.breath_mode) {
                led_effects_breathing_start();
            } else {
                led_effects_breathing_stop();
                drv_led_set_brightness((uint8_t)g_app_state.brightness);
                drv_led_refresh();
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            storage_save_current();
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_bright_screen();
}
