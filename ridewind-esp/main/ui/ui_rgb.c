#include "ui_rgb.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include "board_config.h"
#include <stdio.h>

/* UI3 - 3-Layer RGB Custom
 * Layer 0: select strip (0-3), red dot indicator
 * Layer 1: select channel R/G/B, green dot
 * Layer 2: adjust value 0-255 by +/-2/step
 * Single-click: 0->1, 1->2, 2->1
 * Double-click at any layer: save and return to UI5 */

static const char *STRIP_NAMES[4] = { "Main", "Left", "Right", "Tail" };
static const char *CHAN_NAMES[3]  = { "R", "G", "B" };

static uint8_t s_need_redraw = 1;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_rgb_screen(void)
{
    if (!s_need_redraw) return;

    uint8_t mode = g_app_state.ui3_mode;
    uint8_t strip = g_app_state.ui3_strip;
    uint8_t chan = g_app_state.ui3_channel;

    drv_lcd_clear(0x0000);

    /* Strip name with indicator dot */
    drv_lcd_draw_string(30, 20, STRIP_NAMES[strip], 0xFFFF, 0x0000, 2);
    uint16_t dot_color = (mode == 0) ? rgb565(255, 0, 0) : rgb565(0, 255, 0);
    drv_lcd_draw_circle(180, 28, 5, dot_color, true);

    /* RGB values */
    int16_t r = g_app_state.led_edit[strip][0];
    int16_t g = g_app_state.led_edit[strip][1];
    int16_t b = g_app_state.led_edit[strip][2];

    char buf[16];
    uint16_t colors[3] = { rgb565(255, 80, 80), rgb565(80, 255, 80), rgb565(80, 80, 255) };
    int16_t vals[3] = { r, g, b };

    for (int i = 0; i < 3; i++) {
        uint16_t y = 70 + i * 50;
        uint16_t fg = colors[i];

        /* Highlight selected channel in mode 1 or 2 */
        if ((mode == 1 || mode == 2) && chan == i) {
            fg = 0xFFFF;
            drv_lcd_fill_rect(20, y - 5, 200, 35, rgb565(0x20, 0x20, 0x20));
        }

        drv_lcd_draw_string(30, y, CHAN_NAMES[i], fg, 0x0000, 2);
        snprintf(buf, sizeof(buf), "%d", vals[i]);
        drv_lcd_draw_string(80, y, buf, fg, 0x0000, 2);

        /* Small color bar */
        uint8_t bar_w = (uint8_t)(vals[i] * 100 / 255);
        drv_lcd_fill_rect(140, y + 5, bar_w, 12, colors[i]);
    }

    /* Mode indicator text */
    const char *mode_str = (mode == 0) ? "Select Strip" :
                           (mode == 1) ? "Select Channel" : "Adjust Value";
    drv_lcd_draw_string(30, 220, mode_str, rgb565(0x60, 0x60, 0x60), 0x0000, 1);

    s_need_redraw = 0;
}

void ui_rgb_enter(void)
{
    s_need_redraw = 1;
    g_app_state.ui3_mode = 0;
    g_app_state.ui3_channel = 0;
    g_app_state.ui3_strip = 0;

    /* Deactivate streamlight and breathing (RGB custom has highest priority) */
    if (g_app_state.streamlight_active) {
        g_app_state.streamlight_active = 0;
        led_effects_streamlight_stop();
    }
    if (g_app_state.breath_mode) {
        g_app_state.breath_mode = 0;
        led_effects_breathing_stop();
    }

    /* Copy current colors to edit buffer */
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 3; j++) {
            g_app_state.led_edit[i][j] = g_app_state.led_colors[i][j];
        }
    }
}

void ui_rgb_update(void)
{

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            int16_t delta = evt.delta;
            uint8_t mode = g_app_state.ui3_mode;

            if (mode == 0) {
                /* Select strip: cycle 0-3 */
                int8_t s = g_app_state.ui3_strip + (delta > 0 ? 1 : -1);
                if (s < 0) s = 3;
                if (s > 3) s = 0;
                g_app_state.ui3_strip = s;
            } else if (mode == 1) {
                /* Select channel: cycle 0-2 */
                int8_t c = g_app_state.ui3_channel + (delta > 0 ? 1 : -1);
                if (c < 0) c = 2;
                if (c > 2) c = 0;
                g_app_state.ui3_channel = c;
            } else if (mode == 2) {
                /* Adjust value: +/-2 per step, clamp 0-255 */
                uint8_t strip = g_app_state.ui3_strip;
                uint8_t chan = g_app_state.ui3_channel;
                int16_t val = g_app_state.led_edit[strip][chan];
                val += delta * 2;
                if (val < 0) val = 0;
                if (val > 255) val = 255;
                g_app_state.led_edit[strip][chan] = val;

                /* Apply to LED in real time */
                drv_led_set_strip_color((led_strip_id_t)strip,
                    (uint8_t)g_app_state.led_edit[strip][0],
                    (uint8_t)g_app_state.led_edit[strip][1],
                    (uint8_t)g_app_state.led_edit[strip][2]);
                drv_led_refresh();
            }
            s_need_redraw = 1;
            break;
        }
        case ENC_EVT_CLICK:
            /* Advance layer: 0->1, 1->2, 2->1 */
            if (g_app_state.ui3_mode == 0) {
                g_app_state.ui3_mode = 1;
            } else if (g_app_state.ui3_mode == 1) {
                g_app_state.ui3_mode = 2;
            } else {
                g_app_state.ui3_mode = 1;
            }
            s_need_redraw = 1;
            break;

        case ENC_EVT_DOUBLE_CLICK:
            /* Save edit buffer to applied colors and return */
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 3; j++) {
                    g_app_state.led_colors[i][j] = (uint8_t)g_app_state.led_edit[i][j];
                }
            }
            /* TODO Phase 8: storage_save_settings() */
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_rgb_screen();
}
