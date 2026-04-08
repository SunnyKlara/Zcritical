#include "ui_volume.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include <stdio.h>

/* UI7 - Volume Control
 * Encoder rotation adjusts volume 0-100.
 * Double-click saves and returns to UI5. */

static uint8_t s_need_redraw = 1;
static uint8_t s_last_vol = 0xFF;

void ui_volume_enter(void)
{
    s_need_redraw = 1;
    s_last_vol = 0xFF;
}

void ui_volume_update(void)
{

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            int16_t val = g_app_state.volume + evt.delta;
            if (val < 0) val = 0;
            if (val > 100) val = 100;
            g_app_state.volume = (uint8_t)val;
            /* TODO Phase 7: audio_engine_set_volume(val) */
            s_need_redraw = 1;
            break;
        }
        case ENC_EVT_DOUBLE_CLICK:
            /* TODO Phase 8: storage_save_settings() */
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    /* Draw */
    uint8_t vol = g_app_state.volume;
    if (vol != s_last_vol || s_need_redraw) {
        if (s_need_redraw) {
            drv_lcd_clear(0x0000);
            drv_lcd_draw_string(140, 150, "VOL", 0xFFFF, 0x0000, 1);
        }

        drv_lcd_fill_rect(20, 70, 130, 60, 0x0000);
        char buf[8];
        snprintf(buf, sizeof(buf), "%d", vol);
        uint8_t len = 0;
        while (buf[len]) len++;
        uint16_t x = 80 - len * 12;
        drv_lcd_draw_string(x, 80, buf, 0xFFFF, 0x0000, 3);

        s_last_vol = vol;
        s_need_redraw = 0;
    }
}
