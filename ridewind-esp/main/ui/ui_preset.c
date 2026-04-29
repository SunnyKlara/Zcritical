#include "ui_preset.h"
#include "ui_common.h"
#include "ui_images.h"
#include "storage.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include "preset_colors.h"
#include "ble_service.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <stdio.h>

/* UI2 - Color Presets + Streamlight
 *
 * Rendering strategy (flicker-free):
 *   - Full redraw only on enter(): background + title + rize label
 *   - Preset change: only clear+redraw color bar area (115x16 pixels)
 *   - Streamlight toggle: only redraw LED indicator (12x21 pixels)
 */

#define BAR_WIDTH   115
#define BAR_HEIGHT  14

static uint8_t s_need_full_redraw = 1;
static uint8_t s_last_preset = 0;
static uint8_t s_last_streamlight = 0xFF;
static uint32_t s_streamlight_lcd_tick = 0;  /* Throttle LCD refresh to ~150ms (F4 behavior) */

static void apply_preset(uint8_t idx)
{
    if (idx < 1 || idx > COLOR_PRESET_COUNT) return;
    const color_preset_t *p = &COLOR_PRESETS[idx - 1];

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

    for (int i = 0; i < 4; i++) {
        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.led_colors[i][0],
            g_app_state.led_colors[i][1],
            g_app_state.led_colors[i][2]);
    }
    drv_led_refresh();
}

static void draw_color_bar(uint8_t idx)
{
    uint16_t bx = F4_PEI_SE_X;
    uint16_t by = F4_PEI_SE_Y + 1;

    /* Clear bar area */
    drv_lcd_fill_rect(F4_PEI_SE_X, F4_PEI_SE_Y, BAR_WIDTH, BAR_HEIGHT + 2, 0x0000);

    switch (idx) {
    case 1:  ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 138,43,226, 0,255,128); break;
    case 2:  ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 0,234,255); break;
    case 3:  ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,100,0, 0,200,255); break;
    case 4:  ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,210,0); break;
    case 5:  ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,0,0); break;
    case 6:  ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,0,0, 0,80,255); break;
    case 7:  ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,105,180, 255,0,80); break;
    case 8:  ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 180,0,255, 0,255,200); break;
    case 9:  ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 148,0,211); break;
    case 10: ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 0,255,180, 100,200,255); break;
    case 11: ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 0,255,65); break;
    case 12: ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 225,225,225); break;
    case 13: ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 255,80,0, 255,200,50); break;
    case 14: ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, 0,255,255, 255,0,255); break;
    default: break;
    }
}

static void draw_realtime_bar(uint8_t r1, uint8_t g1, uint8_t b1,
                              uint8_t r2, uint8_t g2, uint8_t b2)
{
    /* F4: lcd_pei_se_realtime — direct overwrite, no clear, no flicker */
    uint16_t bx = F4_PEI_SE_X;
    uint16_t by = F4_PEI_SE_Y + 1;

    /* If left==right color, draw solid; otherwise gradient */
    if (r1 == r2 && g1 == g2 && b1 == b2) {
        ui_draw_solid_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, r1, g1, b1);
    } else {
        ui_draw_gradient_bar(bx, by, BAR_WIDTH, BAR_HEIGHT, r1, g1, b1, r2, g2, b2);
    }
}

static void draw_preset_screen(void)
{
    uint8_t idx = g_app_state.preset_index;
    uint8_t sl = g_app_state.streamlight_active;

    if (s_need_full_redraw) {
        ui_draw_f4_background();
        ui_blit_f4_image(F4_COLOR_X, F4_COLOR_Y,
                         F4_COLOR_WIDTH, F4_COLOR_HIGH, gImage_color_183_57);
        ui_blit_f4_image(F4_COLOR_RIZE_X, F4_COLOR_RIZE_Y,
                         F4_COLOR_RIZE_WIDTH, F4_COLOR_RIZE_HIGH,
                         gImage_color_rize_69_28);
        draw_color_bar(idx);
        ui_draw_f4_led(F4_COLOR_RIZE_X + F4_COLOR_RIZE_WIDTH,
                       F4_COLOR_RIZE_Y + 5, sl ? 1 : 0);

        s_last_preset = idx;
        s_last_streamlight = sl;
        s_need_full_redraw = 0;
        return;
    }

    if (idx != s_last_preset) {
        draw_color_bar(idx);
        s_last_preset = idx;
    }

    /* Streamlight mode: realtime LCD color bar sync (F4: every 150ms) */
    if (sl && g_app_state.streamlight_lcd_dirty) {
        uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
        if (now - s_streamlight_lcd_tick >= 150) {
            draw_realtime_bar(
                g_app_state.streamlight_r1, g_app_state.streamlight_g1, g_app_state.streamlight_b1,
                g_app_state.streamlight_r2, g_app_state.streamlight_g2, g_app_state.streamlight_b2);
            s_streamlight_lcd_tick = now;
            g_app_state.streamlight_lcd_dirty = 0;
            /* Also track preset_index changes from streamlight for the bar cache */
            s_last_preset = g_app_state.preset_index;
        }
    }

    if (sl != s_last_streamlight) {
        ui_draw_f4_led(F4_COLOR_RIZE_X + F4_COLOR_RIZE_WIDTH,
                       F4_COLOR_RIZE_Y + 5, sl ? 1 : 0);
        s_last_streamlight = sl;
    }
}

void ui_preset_enter(void)
{
    s_need_full_redraw = 1;
    s_last_preset = 0;
    s_last_streamlight = 0xFF;
    s_streamlight_lcd_tick = 0;
}

void ui_preset_update(void)
{
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            if (g_app_state.streamlight_active) {
                g_app_state.streamlight_active = 0;
                led_effects_streamlight_stop();
            }
            int8_t new_idx = g_app_state.preset_index + (evt.delta > 0 ? 1 : -1);
            if (new_idx < 1) new_idx = COLOR_PRESET_COUNT;
            if (new_idx > COLOR_PRESET_COUNT) new_idx = 1;
            g_app_state.preset_index = new_idx;
            apply_preset(new_idx);
            char buf[32];
            snprintf(buf, sizeof(buf), "PRESET_REPORT:%d\n", new_idx);
            ble_service_notify_str(buf);
            break;
        }
        case ENC_EVT_CLICK:
            g_app_state.streamlight_active ^= 1;
            if (g_app_state.streamlight_active) {
                led_effects_streamlight_start();
            } else {
                led_effects_streamlight_stop();
                apply_preset(g_app_state.preset_index);
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            storage_save_current();
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_preset_screen();
}
