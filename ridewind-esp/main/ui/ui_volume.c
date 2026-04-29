#include "ui_volume.h"
#include "ui_common.h"
#include "ui_images.h"
#include "storage.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "audio_engine.h"
#include <stdio.h>

/* UI7 - Volume Control
 *
 * Rendering strategy (flicker-free):
 *   - Full redraw only on enter()
 *   - Encoder rotation: only clear+redraw number area
 */

/* VOI text image (in 取模数组/VOI.c, has 8-byte header) */
extern const unsigned char gImage_VOI[];

#define VOI_X       140
#define VOI_Y       150
#define VOI_WIDTH   73
#define VOI_HIGH    20
#define VOI_HEADER  8

static uint8_t s_need_full_redraw = 1;
static uint8_t s_last_vol = 0xFF;

static void draw_volume_screen(void)
{
    uint8_t vol = g_app_state.volume;

    if (s_need_full_redraw) {
        drv_lcd_clear(0x0000);
        ui_blit_f4_image(VOI_X, VOI_Y, VOI_WIDTH, VOI_HIGH,
                         gImage_VOI + VOI_HEADER);
        ui_draw_f4_led(VOI_X + VOI_WIDTH, VOI_Y, 0);

        drv_lcd_fill_rect(20, F4_UI4_Y_QI,
                          F4_UI4_X_QI + 5 - 20, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_UI4_X_QI, F4_UI4_Y_QI,
                                      (uint16_t)vol, F4_UI4_JIANJU);

        s_last_vol = vol;
        s_need_full_redraw = 0;
        return;
    }

    if (vol != s_last_vol) {
        drv_lcd_fill_rect(20, F4_UI4_Y_QI,
                          F4_UI4_X_QI + 5 - 20, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_UI4_X_QI, F4_UI4_Y_QI,
                                      (uint16_t)vol, F4_UI4_JIANJU);
        s_last_vol = vol;
    }
}

void ui_volume_enter(void)
{
    s_need_full_redraw = 1;
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
            audio_engine_set_volume((uint8_t)val);
            break;
        }
        case ENC_EVT_DOUBLE_CLICK:
            storage_save_current();
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_volume_screen();
}
