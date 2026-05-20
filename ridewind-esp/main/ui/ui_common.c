/**
 * @file ui_common.c
 * @brief 共享 UI 绘图工具 — 进度条/圆点/F4 位图渲染/数字绘制
 */

#include "ui_common.h"
#include "ui_images.h"
#include "colored_digits.h"
#include "drv_lcd.h"
#include "app_state.h"
#include "board_config.h"
#include <string.h>
#include <math.h>

/* ══════ Original helpers ══════ */

void ui_common_draw_progress_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t percent, uint16_t color)
{
    if (percent > 100) percent = 100;
    uint16_t fill_w = (uint16_t)((uint32_t)w * percent / 100);
    drv_lcd_fill_rect(x, y, w, h, 0x2104);
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

/* ══════ F4-style bitmap rendering ══════ */

/**
 * Blit F4 image array to LCD.
 * F4 arrays are RGB565 stored as big-endian byte pairs: {MSB, LSB}.
 * GC9A01 expects big-endian RGB565 over SPI, so we can send directly.
 *
 * Uses drv_lcd_blit_rgb565 which handles flash-resident const data
 * correctly (polling SPI, chunked transfers, no DMA requirement).
 */
void ui_blit_f4_image(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                      const unsigned char *data)
{
    drv_lcd_blit_rgb565(x, y, w, h, (const uint16_t *)data);
}

void ui_draw_f4_background(void)
{
    ui_blit_f4_image(0, 0, LCD_WIDTH, LCD_HEIGHT, gImage_beijing_240_240);
}

/* ── Large digit lookup tables ── */

static const unsigned char * const s_large_digit_data[10] = {
    gImage_speed_0_5153, gImage_speed_1_1553, gImage_speed_2_4853,
    gImage_speed_3_4353, gImage_speed_4_5153, gImage_speed_5_4653,
    gImage_speed_6_4953, gImage_speed_7_4653, gImage_speed_8_4953,
    gImage_speed_9_4953,
};

static const uint8_t s_large_digit_width[10] = {
    F4_SPEED_0_WIDTH, F4_SPEED_1_WIDTH, F4_SPEED_2_WIDTH, F4_SPEED_3_WIDTH,
    F4_SPEED_4_WIDTH, F4_SPEED_5_WIDTH, F4_SPEED_6_WIDTH, F4_SPEED_7_WIDTH,
    F4_SPEED_8_WIDTH, F4_SPEED_9_WIDTH,
};

uint8_t ui_large_digit_width(uint8_t digit)
{
    if (digit > 9) return 0;
    return s_large_digit_width[digit];
}

void ui_draw_large_digit(uint16_t x, uint16_t y, uint8_t digit)
{
    if (digit > 9) return;
    ui_blit_f4_image(x, y, s_large_digit_width[digit], F4_SPEED_NUM_HIGH,
                     s_large_digit_data[digit]);
}

/* ── Pre-rendered colored digit lookup table ── */

static const unsigned char * const s_colored_digit_data[COLORED_DIGIT_STEPS][10] = {
    { gImage_speed_0_c0, gImage_speed_1_c0, gImage_speed_2_c0, gImage_speed_3_c0, gImage_speed_4_c0, gImage_speed_5_c0, gImage_speed_6_c0, gImage_speed_7_c0, gImage_speed_8_c0, gImage_speed_9_c0 },
    { gImage_speed_0_c1, gImage_speed_1_c1, gImage_speed_2_c1, gImage_speed_3_c1, gImage_speed_4_c1, gImage_speed_5_c1, gImage_speed_6_c1, gImage_speed_7_c1, gImage_speed_8_c1, gImage_speed_9_c1 },
    { gImage_speed_0_c2, gImage_speed_1_c2, gImage_speed_2_c2, gImage_speed_3_c2, gImage_speed_4_c2, gImage_speed_5_c2, gImage_speed_6_c2, gImage_speed_7_c2, gImage_speed_8_c2, gImage_speed_9_c2 },
    { gImage_speed_0_c3, gImage_speed_1_c3, gImage_speed_2_c3, gImage_speed_3_c3, gImage_speed_4_c3, gImage_speed_5_c3, gImage_speed_6_c3, gImage_speed_7_c3, gImage_speed_8_c3, gImage_speed_9_c3 },
    { gImage_speed_0_c4, gImage_speed_1_c4, gImage_speed_2_c4, gImage_speed_3_c4, gImage_speed_4_c4, gImage_speed_5_c4, gImage_speed_6_c4, gImage_speed_7_c4, gImage_speed_8_c4, gImage_speed_9_c4 },
    { gImage_speed_0_c5, gImage_speed_1_c5, gImage_speed_2_c5, gImage_speed_3_c5, gImage_speed_4_c5, gImage_speed_5_c5, gImage_speed_6_c5, gImage_speed_7_c5, gImage_speed_8_c5, gImage_speed_9_c5 },
    { gImage_speed_0_c6, gImage_speed_1_c6, gImage_speed_2_c6, gImage_speed_3_c6, gImage_speed_4_c6, gImage_speed_5_c6, gImage_speed_6_c6, gImage_speed_7_c6, gImage_speed_8_c6, gImage_speed_9_c6 },
    { gImage_speed_0_c7, gImage_speed_1_c7, gImage_speed_2_c7, gImage_speed_3_c7, gImage_speed_4_c7, gImage_speed_5_c7, gImage_speed_6_c7, gImage_speed_7_c7, gImage_speed_8_c7, gImage_speed_9_c7 },
    { gImage_speed_0_c8, gImage_speed_1_c8, gImage_speed_2_c8, gImage_speed_3_c8, gImage_speed_4_c8, gImage_speed_5_c8, gImage_speed_6_c8, gImage_speed_7_c8, gImage_speed_8_c8, gImage_speed_9_c8 },
    { gImage_speed_0_c9, gImage_speed_1_c9, gImage_speed_2_c9, gImage_speed_3_c9, gImage_speed_4_c9, gImage_speed_5_c9, gImage_speed_6_c9, gImage_speed_7_c9, gImage_speed_8_c9, gImage_speed_9_c9 },
    { gImage_speed_0_c10, gImage_speed_1_c10, gImage_speed_2_c10, gImage_speed_3_c10, gImage_speed_4_c10, gImage_speed_5_c10, gImage_speed_6_c10, gImage_speed_7_c10, gImage_speed_8_c10, gImage_speed_9_c10 },
};

void ui_draw_large_digit_tinted(uint16_t x, uint16_t y, uint8_t digit, uint16_t tint_color)
{
    (void)tint_color;  /* Color is now selected via color_index, kept for API compat */
    if (digit > 9) return;
    /* Default to middle color step if called without proper index */
    ui_blit_f4_image(x, y, s_large_digit_width[digit], F4_SPEED_NUM_HIGH,
                     s_colored_digit_data[5][digit]);
}

/* Draw colored digit using pre-rendered color step index (0-10) */
void ui_draw_large_digit_colored(uint16_t x, uint16_t y, uint8_t digit, uint8_t color_index)
{
    if (digit > 9) return;
    if (color_index >= COLORED_DIGIT_STEPS) color_index = COLORED_DIGIT_STEPS - 1;
    ui_blit_f4_image(x, y, s_large_digit_width[digit], F4_SPEED_NUM_HIGH,
                     s_colored_digit_data[color_index][digit]);
}

void ui_draw_large_number_right(uint16_t right_x, uint16_t y,
                                uint16_t num, uint8_t spacing)
{
    /* Matches F4's formula: pos = right_x - width - spacing*N
     * F4 speed uses jianju=-2 (negative = tighter), brightness uses ui4_jianju=2.
     * The 'spacing' parameter here is the raw F4 jianju value cast to int8_t. */
    (void)spacing;  /* We use the raw signed value below */
}

/* Internal version with signed spacing to match F4 exactly */
void ui_draw_large_number_right_ex(uint16_t right_x, uint16_t y,
                                    uint16_t num, int8_t jianju)
{
    uint8_t d_a, d_b, d_c, count;

    if (num >= 100) {
        d_a = num / 100;
        d_b = (num % 100) / 10;
        d_c = num % 10;
        count = 3;
    } else if (num >= 10) {
        d_a = 0;
        d_b = num / 10;
        d_c = num % 10;
        count = 2;
    } else {
        d_a = 0;
        d_b = 0;
        d_c = num;
        count = 1;
    }

    uint8_t w_a = s_large_digit_width[d_a];
    uint8_t w_b = s_large_digit_width[d_b];
    uint8_t w_c = s_large_digit_width[d_c];

    /* F4 formula: LCD_ShowPicture(x_qi - total_width - jianju*N, y_qi, ...) */
    if (count == 3) {
        int16_t x3 = (int16_t)right_x - w_a - w_b - w_c - jianju * 3;
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit((uint16_t)x3, y, d_a);
        ui_draw_large_digit((uint16_t)x2, y, d_b);
        ui_draw_large_digit((uint16_t)x1, y, d_c);
    } else if (count == 2) {
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit((uint16_t)x2, y, d_b);
        ui_draw_large_digit((uint16_t)x1, y, d_c);
    } else {
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit((uint16_t)x1, y, d_c);
    }
}

/* Tinted version: same layout as above but uses colored digits */
void ui_draw_large_number_tinted_ex(uint16_t right_x, uint16_t y,
                                     uint16_t num, int8_t jianju, uint16_t tint_color)
{
    (void)tint_color;  /* Not used — color_index version below is preferred */
    ui_draw_large_number_colored_ex(right_x, y, num, jianju, 5);
}

/* Draw number with pre-rendered colored digits (color_index 0-10) */
void ui_draw_large_number_colored_ex(uint16_t right_x, uint16_t y,
                                      uint16_t num, int8_t jianju, uint8_t color_index)
{
    uint8_t d_a, d_b, d_c, count;

    if (num >= 100) {
        d_a = num / 100;
        d_b = (num % 100) / 10;
        d_c = num % 10;
        count = 3;
    } else if (num >= 10) {
        d_a = 0;
        d_b = num / 10;
        d_c = num % 10;
        count = 2;
    } else {
        d_a = 0;
        d_b = 0;
        d_c = num;
        count = 1;
    }

    uint8_t w_a = s_large_digit_width[d_a];
    uint8_t w_b = s_large_digit_width[d_b];
    uint8_t w_c = s_large_digit_width[d_c];

    if (count == 3) {
        int16_t x3 = (int16_t)right_x - w_a - w_b - w_c - jianju * 3;
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit_colored((uint16_t)x3, y, d_a, color_index);
        ui_draw_large_digit_colored((uint16_t)x2, y, d_b, color_index);
        ui_draw_large_digit_colored((uint16_t)x1, y, d_c, color_index);
    } else if (count == 2) {
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit_colored((uint16_t)x2, y, d_b, color_index);
        ui_draw_large_digit_colored((uint16_t)x1, y, d_c, color_index);
    } else {
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;
        ui_draw_large_digit_colored((uint16_t)x1, y, d_c, color_index);
    }
}

void ui_draw_f4_led(uint16_t x, uint16_t y, uint8_t state)
{
    const unsigned char *img;
    switch (state) {
    case 1:  img = gImage_l_deng_1221; break;  /* green */
    case 2:  img = gImage_c_deng_1221; break;  /* orange */
    default: img = gImage_h_deng_1221; break;  /* red */
    }
    ui_blit_f4_image(x, y, F4_H_DENG_WIDTH, F4_H_DENG_HIGH, img);
}

/* ══════ Rounded capsule color bars ══════ */

#define RGB565(r, g, b) (uint16_t)(((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3))

void ui_draw_solid_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                       uint8_t r, uint8_t g, uint8_t b)
{
    if (w < 2 || h < 2) return;

    uint16_t color = RGB565(r, g, b);
    int16_t radius = h / 2;
    int16_t cy = y + radius;
    int16_t left_cx = x + radius;
    int16_t right_cx = x + w - 1 - radius;
    int32_t r_sq = (int32_t)radius * radius;

    /* Row buffer: fill with solid color */
    static uint8_t buf[512];  /* max 256 pixels wide */
    for (int i = 0; i < 256 && i < w; i++) {
        buf[i * 2]     = color >> 8;
        buf[i * 2 + 1] = color & 0xFF;
    }

    for (int16_t row = 0; row < (int16_t)h; row++) {
        int16_t py = y + row;
        int16_t dy = py - cy;
        int32_t dy_sq = (int32_t)dy * dy;
        if (dy_sq >= r_sq) continue;

        int32_t diff = r_sq - dy_sq;
        int16_t dx_max = 0;
        if (diff > 0) {
            int32_t guess = radius;
            guess = (guess + diff / guess) >> 1;
            guess = (guess + diff / guess) >> 1;
            dx_max = (int16_t)guess;
        }

        int16_t row_x1 = left_cx - dx_max;
        if (row_x1 < (int16_t)x) row_x1 = x;
        int16_t row_x2 = right_cx + dx_max;
        if (row_x2 > (int16_t)(x + w - 1)) row_x2 = x + w - 1;

        if (row_x2 >= row_x1) {
            int16_t line_w = row_x2 - row_x1 + 1;
            drv_lcd_blit_rgb565(row_x1, py, line_w, 1, (const uint16_t *)buf);
        }
    }
}

void ui_draw_gradient_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                          uint8_t r1, uint8_t g1, uint8_t b1,
                          uint8_t r2, uint8_t g2, uint8_t b2)
{
    if (w < 2 || h < 2) return;

    int16_t radius = h / 2;
    int16_t cy = y + radius;
    int16_t left_cx = x + radius;
    int16_t right_cx = x + w - 1 - radius;
    int32_t r_sq = (int32_t)radius * radius;

    int32_t dr_256 = ((int32_t)r2 - (int32_t)r1) * 256 / w;
    int32_t dg_256 = ((int32_t)g2 - (int32_t)g1) * 256 / w;
    int32_t db_256 = ((int32_t)b2 - (int32_t)b1) * 256 / w;

    static uint8_t line_buf[512];

    for (int16_t row = 0; row < (int16_t)h; row++) {
        int16_t py = y + row;
        int16_t dy = py - cy;
        int32_t dy_sq = (int32_t)dy * dy;
        if (dy_sq >= r_sq) continue;

        int32_t diff = r_sq - dy_sq;
        int16_t dx_max = 0;
        if (diff > 0) {
            int32_t guess = radius;
            guess = (guess + diff / guess) >> 1;
            guess = (guess + diff / guess) >> 1;
            dx_max = (int16_t)guess;
        }

        int16_t row_x1 = left_cx - dx_max;
        if (row_x1 < (int16_t)x) row_x1 = x;
        int16_t row_x2 = right_cx + dx_max;
        if (row_x2 > (int16_t)(x + w - 1)) row_x2 = x + w - 1;
        if (row_x2 < row_x1) continue;

        int16_t line_w = row_x2 - row_x1 + 1;
        int32_t col_start = row_x1 - x;

        for (int16_t i = 0; i < line_w; i++) {
            int32_t col = col_start + i;
            uint8_t cr = r1 + (dr_256 * col) / 256;
            uint8_t cg = g1 + (dg_256 * col) / 256;
            uint8_t cb = b1 + (db_256 * col) / 256;
            uint16_t color = RGB565(cr, cg, cb);
            line_buf[i * 2]     = color >> 8;
            line_buf[i * 2 + 1] = color & 0xFF;
        }

        drv_lcd_blit_rgb565(row_x1, py, line_w, 1, (const uint16_t *)line_buf);
    }
}
