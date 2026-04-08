#include "ui_logo.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include <stdio.h>

/* UI6 - Logo Management
 * Encoder rotation switches between logo slots.
 * Single-click sets current slot as active boot logo.
 * Long-press deletes current slot.
 * Double-click returns to UI5.
 * Note: actual LittleFS operations are Phase 9 stubs. */

static uint8_t s_need_redraw = 1;
static uint8_t s_last_slot = 0xFF;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_logo_screen(void)
{
    uint8_t slot = g_app_state.logo_view_slot;

    if (slot != s_last_slot || s_need_redraw) {
        if (s_need_redraw) {
            drv_lcd_clear(0x0000);
            drv_lcd_draw_string(80, 20, "Logo", 0xFFFF, 0x0000, 2);
        }

        /* Slot indicator */
        drv_lcd_fill_rect(60, 100, 120, 30, 0x0000);
        char buf[16];
        snprintf(buf, sizeof(buf), "Slot %d", slot);
        drv_lcd_draw_string(80, 105, buf, 0xFFFF, 0x0000, 2);

        /* Active indicator */
        drv_lcd_fill_rect(60, 140, 120, 20, 0x0000);
        if (slot == g_app_state.active_logo_slot) {
            drv_lcd_draw_string(75, 145, "[Active]",
                rgb565(0, 255, 0), 0x0000, 1);
        } else {
            drv_lcd_draw_string(80, 145, "(empty)",
                rgb565(0x60, 0x60, 0x60), 0x0000, 1);
        }

        /* Slot dots */
        for (uint8_t i = 0; i < 3; i++) {
            uint16_t dx = 100 + i * 20;
            uint16_t color = (i == slot) ? 0xFFFF : rgb565(0x42, 0x42, 0x42);
            drv_lcd_draw_circle(dx, 200, 3, color, true);
        }

        s_last_slot = slot;
        s_need_redraw = 0;
    }
}

void ui_logo_enter(void)
{
    s_need_redraw = 1;
    s_last_slot = 0xFF;
    g_app_state.logo_view_slot = g_app_state.active_logo_slot;
}

void ui_logo_update(void)
{

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            int8_t s = g_app_state.logo_view_slot + (evt.delta > 0 ? 1 : -1);
            if (s < 0) s = 2;
            if (s > 2) s = 0;
            g_app_state.logo_view_slot = s;
            s_need_redraw = 1;
            break;
        }
        case ENC_EVT_CLICK:
            /* Set current slot as active boot logo */
            g_app_state.active_logo_slot = g_app_state.logo_view_slot;
            /* TODO Phase 8: save to NVS */
            s_need_redraw = 1;
            break;

        case ENC_EVT_LONG_PRESS:
            /* Delete current slot */
            /* TODO Phase 9: storage_logo_delete() with progress bar */
            s_need_redraw = 1;
            break;

        case ENC_EVT_DOUBLE_CLICK:
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_logo_screen();
}
