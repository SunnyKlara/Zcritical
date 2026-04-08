#include "ui_preset.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include "preset_colors.h"
#include "ble_service.h"
#include "board_config.h"
#include <stdio.h>

/* UI2 - Color Presets + Streamlight
 * Encoder rotation cycles presets 1-14.
 * Single-click toggles Streamlight on/off.
 * Double-click saves and returns to UI5. */

static uint8_t s_need_redraw = 1;
static uint8_t s_last_preset = 0;
static uint8_t s_last_streamlight = 0xFF;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void apply_preset(uint8_t idx)
{
    if (idx < 1 || idx > COLOR_PRESET_COUNT) return;
    const color_preset_t *p = &COLOR_PRESETS[idx - 1];

    /* Main and Left get lr,lg,lb; Right and Tail get rr,rg,rb */
    g_app_state.led_colors[0][0] = p->lr;
    g_app_state.led_colors[0][1] = p->lg;
    g_app_state.led_colors[0][2] = p->lb;
    g_app_state.led_colors[1][0] = p->lr;
    g_app_state.led_colors[1][1] = p->lg;
    g_app_state.led_colors[1][2] = p->lb;
    g_app_state.led_colors[2][0] = p->rr;
    g_app_state.led_colors[2][1] = p->rg;
    g_app_state.led_colors[2][2] = p->rb;
    g_app_state.led_colors[3][0] = p->rr;
    g_app_state.led_colors[3][1] = p->rg;
    g_app_state.led_colors[3][2] = p->rb;

    /* Apply to LEDs */
    for (int i = 0; i < 4; i++) {
        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.led_colors[i][0],
            g_app_state.led_colors[i][1],
            g_app_state.led_colors[i][2]);
    }
    drv_led_refresh();
}

static void draw_preset_screen(void)
{
    uint8_t idx = g_app_state.preset_index;
    uint8_t sl = g_app_state.streamlight_active;

    if (idx != s_last_preset || sl != s_last_streamlight || s_need_redraw) {
        if (s_need_redraw) {
            drv_lcd_clear(0x0000);
        }

        const color_preset_t *p = &COLOR_PRESETS[idx - 1];

        /* Preset name */
        drv_lcd_fill_rect(20, 30, 200, 25, 0x0000);
        drv_lcd_draw_string(30, 35, p->name, 0xFFFF, 0x0000, 1);

        /* Preset number */
        char buf[8];
        snprintf(buf, sizeof(buf), "%d/14", idx);
        drv_lcd_fill_rect(170, 30, 60, 20, 0x0000);
        drv_lcd_draw_string(180, 35, buf, rgb565(0x80, 0x80, 0x80), 0x0000, 1);

        /* Color bar: gradient from left color to right color */
        uint16_t bar_y = 80;
        uint16_t bar_h = 30;
        for (uint16_t x = 0; x < 200; x++) {
            uint8_t r = p->lr + (int16_t)(p->rr - p->lr) * x / 200;
            uint8_t g = p->lg + (int16_t)(p->rg - p->lg) * x / 200;
            uint8_t b = p->lb + (int16_t)(p->rb - p->lb) * x / 200;
            uint16_t color = rgb565(r, g, b);
            drv_lcd_fill_rect(20 + x, bar_y, 1, bar_h, color);
        }

        /* Streamlight indicator dot */
        drv_lcd_fill_rect(100, 140, 40, 20, 0x0000);
        uint16_t dot_color = sl ? rgb565(0, 255, 0) : rgb565(255, 0, 0);
        drv_lcd_draw_circle(120, 150, 5, dot_color, true);
        drv_lcd_draw_string(80, 170, sl ? "Stream ON" : "Stream OFF",
            rgb565(0x80, 0x80, 0x80), 0x0000, 1);

        s_last_preset = idx;
        s_last_streamlight = sl;
        s_need_redraw = 0;
    }
}

void ui_preset_enter(void)
{
    s_need_redraw = 1;
    s_last_preset = 0;
    s_last_streamlight = 0xFF;
}

void ui_preset_update(void)
{

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            /* If streamlight active, deactivate it first */
            if (g_app_state.streamlight_active) {
                g_app_state.streamlight_active = 0;
                led_effects_streamlight_stop();
            }
            int8_t new_idx = g_app_state.preset_index + (evt.delta > 0 ? 1 : -1);
            if (new_idx < 1) new_idx = COLOR_PRESET_COUNT;
            if (new_idx > COLOR_PRESET_COUNT) new_idx = 1;
            g_app_state.preset_index = new_idx;
            apply_preset(new_idx);
            s_need_redraw = 1;
            /* Report */
            char buf[32];
            snprintf(buf, sizeof(buf), "PRESET_REPORT:%d\n", new_idx);
            ble_service_notify_str(buf);
            break;
        }
        case ENC_EVT_CLICK:
            /* Toggle streamlight */
            g_app_state.streamlight_active ^= 1;
            if (g_app_state.streamlight_active) {
                led_effects_streamlight_start();
            } else {
                led_effects_streamlight_stop();
                apply_preset(g_app_state.preset_index);
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

    if (s_need_redraw) draw_preset_screen();
}
