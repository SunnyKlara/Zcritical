#include "ui_common.h"
#include "drv_lcd.h"
#include "app_state.h"

void ui_common_draw_progress_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t percent, uint16_t color)
{
    if (percent > 100) percent = 100;
    uint16_t fill_w = (uint16_t)((uint32_t)w * percent / 100);

    /* Background (dark gray) */
    drv_lcd_fill_rect(x, y, w, h, 0x2104);
    /* Filled portion */
    if (fill_w > 0) {
        drv_lcd_fill_rect(x, y, fill_w, h, color);
    }
}

void ui_common_draw_dot(uint16_t x, uint16_t y, uint16_t color)
{
    drv_lcd_draw_circle(x, y, 5, color, true);
}

void ui_common_clear_encoder_delta(void)
{
    g_app_state.encoder_delta = 0;
}
