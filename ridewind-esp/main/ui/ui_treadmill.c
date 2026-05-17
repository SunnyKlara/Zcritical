#include "ui_treadmill.h"
#include "ui_common.h"
#include "ui_images.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include "ble_service.h"
#include "esp_log.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

/**
 * @file ui_treadmill.c
 * @brief UI8 — Treadmill control page (Forza Horizon style v2)
 *
 * Design: Forza Horizon 5 inspired, minimal HUD
 *   - 270° thin arc gauge (4px thickness, smooth gradient)
 *   - Large pre-rendered digit bitmaps (same as Speed UI)
 *   - No text labels (no "km/h", no "RUNNING/STOPPED")
 *   - Status shown by small indicator dot
 *   - Pure visual: arc + number + dot
 *
 * LCD layout (240×240 round):
 *   - Outer arc: 270° progress arc (radius 108, thickness 4px)
 *   - Center: Large speed number using F4 digit bitmaps "X.X"
 *   - Small dot as decimal separator
 *   - Running indicator: green/gray dot below number
 *
 * Controls:
 *   Rotate:     Adjust target speed (0-20 km/h, step 0.5)
 *   Click:      Start / Stop treadmill
 *   Long press: Return to menu
 *   Double click: Return to menu
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static uint8_t  s_treadmill_running = 0;
static int16_t  s_target_speed_x10 = 0;   /* 0-200 (represents 0.0-20.0 km/h) */
static int16_t  s_last_drawn_speed = -1;
static uint8_t  s_last_drawn_running = 0xFF;

/* ── Colors (RGB565) ── */
#define COLOR_BG            0x0000   /* Pure black */
#define COLOR_ARC_BG        0x18E3   /* Very dark gray - background arc */
#define COLOR_ARC_WHITE     0xFFFF   /* White - low speed */
#define COLOR_ARC_RED       0xF800   /* Red - high speed */
#define COLOR_DOT_ON        0x07E0   /* Green - running indicator */
#define COLOR_DOT_OFF       0x3186   /* Dark gray - stopped indicator */
#define COLOR_DECIMAL       0xFFFF   /* White - decimal point */

/* ── Arc Geometry ── */
#define ARC_CX              120
#define ARC_CY              120
#define ARC_R_OUTER         108
#define ARC_R_INNER         104      /* 4px thickness — thin, elegant */
#define ARC_START_DEG       135.0f   /* Bottom-left */
#define ARC_SWEEP_DEG       270.0f   /* 270° sweep */

/* ── Number Layout ── */
#define NUM_Y               84       /* Vertical center for digits */
#define NUM_JIANJU          (-2)     /* Same tight spacing as speed UI */
#define DOT_SIZE            6        /* Decimal point: 6x6 filled square */
#define DOT_Y_OFFSET        (F4_SPEED_NUM_HIGH - DOT_SIZE - 4)  /* Baseline-aligned */

/* ── Running indicator ── */
#define INDICATOR_CX        120
#define INDICATOR_CY        155      /* Below the number */
#define INDICATOR_R         4

/* Speed range */
#define SPEED_MAX_X10       200      /* 20.0 km/h */

/* ══════ Arc Color Gradient ══════
 * Forza style: white at low, transitions to orange then red at high
 */
static uint16_t arc_gradient_color(uint8_t percent)
{
    uint8_t r, g, b;

    if (percent <= 50) {
        /* White (255,255,255) → Orange (255,160,0) */
        uint16_t t = (uint16_t)percent * 2;  /* 0-100 */
        r = 255;
        g = (uint8_t)(255 - (255 - 160) * t / 100);
        b = (uint8_t)(255 - 255 * t / 100);
    } else {
        /* Orange (255,160,0) → Red (255,30,0) */
        uint16_t t = (uint16_t)(percent - 50) * 2;  /* 0-100 */
        r = 255;
        g = (uint8_t)(160 - (160 - 30) * t / 100);
        b = 0;
    }

    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/* ══════ Arc Drawing (optimized scanline) ══════ */

static inline float norm_angle(float a)
{
    while (a < 0.0f) a += 360.0f;
    while (a >= 360.0f) a -= 360.0f;
    return a;
}

/**
 * @brief Draw the full arc (background + filled portion)
 */
static void draw_arc(uint8_t fill_pct)
{
    if (fill_pct > 100) fill_pct = 100;

    float fill_sweep = ARC_SWEEP_DEG * fill_pct / 100.0f;
    int32_t r_out_sq = (int32_t)ARC_R_OUTER * ARC_R_OUTER;
    int32_t r_in_sq  = (int32_t)ARC_R_INNER * ARC_R_INNER;

    int16_t scan_min = ARC_CY - ARC_R_OUTER;
    int16_t scan_max = ARC_CY + ARC_R_OUTER;
    if (scan_min < 0) scan_min = 0;
    if (scan_max >= LCD_HEIGHT) scan_max = LCD_HEIGHT - 1;

    for (int16_t py = scan_min; py <= scan_max; py++) {
        int16_t dy = py - ARC_CY;
        int32_t dy_sq = (int32_t)dy * dy;

        int32_t x_range_sq = r_out_sq - dy_sq;
        if (x_range_sq < 0) continue;

        int16_t dx_max_out = (int16_t)sqrtf((float)x_range_sq);
        int16_t px_start = ARC_CX - dx_max_out;
        int16_t px_end   = ARC_CX + dx_max_out;
        if (px_start < 0) px_start = 0;
        if (px_end >= LCD_WIDTH) px_end = LCD_WIDTH - 1;

        for (int16_t px = px_start; px <= px_end; px++) {
            int16_t dx = px - ARC_CX;
            int32_t dist_sq = (int32_t)dx * dx + dy_sq;

            if (dist_sq < r_in_sq || dist_sq > r_out_sq) continue;

            float angle = atan2f((float)dy, (float)dx) * 180.0f / (float)M_PI;
            angle = norm_angle(angle);

            float rel = norm_angle(angle - ARC_START_DEG);
            if (rel > ARC_SWEEP_DEG) continue;

            if (rel <= fill_sweep) {
                uint8_t pos_pct = (uint8_t)(rel * 100.0f / ARC_SWEEP_DEG);
                drv_lcd_fill_rect(px, py, 1, 1, arc_gradient_color(pos_pct));
            } else {
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

/**
 * @brief Partial arc update — only redraw the delta region
 */
static void update_arc_delta(int16_t old_speed, int16_t new_speed)
{
    uint8_t old_pct = (old_speed <= 0) ? 0 : (uint8_t)((uint32_t)old_speed * 100 / SPEED_MAX_X10);
    uint8_t new_pct = (uint8_t)((uint32_t)new_speed * 100 / SPEED_MAX_X10);
    if (old_pct > 100) old_pct = 100;
    if (new_pct > 100) new_pct = 100;
    if (old_pct == new_pct) return;

    float old_sweep = ARC_SWEEP_DEG * old_pct / 100.0f;
    float new_sweep = ARC_SWEEP_DEG * new_pct / 100.0f;

    float redraw_lo, redraw_hi;
    if (new_pct > old_pct) {
        redraw_lo = old_sweep;
        redraw_hi = new_sweep;
    } else {
        redraw_lo = new_sweep;
        redraw_hi = old_sweep;
    }

    int32_t r_out_sq = (int32_t)ARC_R_OUTER * ARC_R_OUTER;
    int32_t r_in_sq  = (int32_t)ARC_R_INNER * ARC_R_INNER;

    int16_t scan_min = ARC_CY - ARC_R_OUTER;
    int16_t scan_max = ARC_CY + ARC_R_OUTER;
    if (scan_min < 0) scan_min = 0;
    if (scan_max >= LCD_HEIGHT) scan_max = LCD_HEIGHT - 1;

    for (int16_t py = scan_min; py <= scan_max; py++) {
        int16_t dy = py - ARC_CY;
        int32_t dy_sq = (int32_t)dy * dy;

        int32_t x_range_sq = r_out_sq - dy_sq;
        if (x_range_sq < 0) continue;

        int16_t dx_max = (int16_t)sqrtf((float)x_range_sq);
        int16_t px_start = ARC_CX - dx_max;
        int16_t px_end   = ARC_CX + dx_max;
        if (px_start < 0) px_start = 0;
        if (px_end >= LCD_WIDTH) px_end = LCD_WIDTH - 1;

        for (int16_t px = px_start; px <= px_end; px++) {
            int16_t dx = px - ARC_CX;
            int32_t dist_sq = (int32_t)dx * dx + dy_sq;
            if (dist_sq < r_in_sq || dist_sq > r_out_sq) continue;

            float angle = atan2f((float)dy, (float)dx) * 180.0f / (float)M_PI;
            angle = norm_angle(angle);
            float rel = norm_angle(angle - ARC_START_DEG);
            if (rel > ARC_SWEEP_DEG) continue;

            if (rel < redraw_lo || rel > redraw_hi) continue;

            if (rel <= new_sweep) {
                uint8_t pos_pct = (uint8_t)(rel * 100.0f / ARC_SWEEP_DEG);
                drv_lcd_fill_rect(px, py, 1, 1, arc_gradient_color(pos_pct));
            } else {
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

/* ══════ Number Drawing (F4 digit bitmaps) ══════ */

/**
 * @brief Draw treadmill speed "X.X" using F4 large digit bitmaps, centered
 */
static void draw_speed_number(void)
{
    int16_t whole = s_target_speed_x10 / 10;
    int16_t frac  = s_target_speed_x10 % 10;

    uint8_t d_tens = whole / 10;
    uint8_t d_ones = whole % 10;
    uint8_t d_frac = (uint8_t)frac;

    uint8_t w_tens  = (whole >= 10) ? ui_large_digit_width(d_tens) : 0;
    uint8_t w_ones  = ui_large_digit_width(d_ones);
    uint8_t w_frac  = ui_large_digit_width(d_frac);
    uint8_t w_dot   = DOT_SIZE + 4;  /* dot width + spacing */

    int16_t total_w = w_ones + w_dot + w_frac;
    if (whole >= 10) {
        total_w += w_tens + NUM_JIANJU;
    }

    /* Center horizontally */
    int16_t x = (LCD_WIDTH - total_w) / 2;

    /* Clear number area */
    drv_lcd_fill_rect(10, NUM_Y, 220, F4_SPEED_NUM_HIGH, COLOR_BG);

    /* Draw tens digit (if >= 10) */
    if (whole >= 10) {
        ui_draw_large_digit((uint16_t)x, NUM_Y, d_tens);
        x += w_tens + NUM_JIANJU;
    }

    /* Draw ones digit */
    ui_draw_large_digit((uint16_t)x, NUM_Y, d_ones);
    x += w_ones + 2;  /* small gap before dot */

    /* Draw decimal point (small filled square at baseline) */
    int16_t dot_y = NUM_Y + DOT_Y_OFFSET;
    drv_lcd_fill_rect((uint16_t)x, (uint16_t)dot_y, DOT_SIZE, DOT_SIZE, COLOR_DECIMAL);
    x += DOT_SIZE + 2;  /* small gap after dot */

    /* Draw fractional digit */
    ui_draw_large_digit((uint16_t)x, NUM_Y, d_frac);
}

/**
 * @brief Draw running status indicator (small dot below number)
 */
static void draw_indicator(void)
{
    uint16_t color = s_treadmill_running ? COLOR_DOT_ON : COLOR_DOT_OFF;
    /* Clear old indicator first */
    drv_lcd_fill_rect(INDICATOR_CX - INDICATOR_R - 1, INDICATOR_CY - INDICATOR_R - 1,
                      (INDICATOR_R + 1) * 2, (INDICATOR_R + 1) * 2, COLOR_BG);
    drv_lcd_draw_circle(INDICATOR_CX, INDICATOR_CY, INDICATOR_R, color, true);
}

/* ══════ Full Screen Draw ══════ */

static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);

    /* Arc gauge */
    uint8_t fill_pct = (uint8_t)((uint32_t)s_target_speed_x10 * 100 / SPEED_MAX_X10);
    draw_arc(fill_pct);

    /* Speed number (F4 bitmaps) */
    draw_speed_number();

    /* Running indicator dot */
    draw_indicator();

    s_last_drawn_speed = s_target_speed_x10;
    s_last_drawn_running = s_treadmill_running;
}

/* ══════ Public API ══════ */

void ui_treadmill_enter(void)
{
    s_need_full_redraw = 1;
    s_last_drawn_speed = -1;
    s_last_drawn_running = 0xFF;
    ESP_LOGI(TAG, "Treadmill UI entered, speed=%d.%d running=%d",
             s_target_speed_x10 / 10, s_target_speed_x10 % 10,
             s_treadmill_running);
}

void ui_treadmill_update(void)
{
    if (s_need_full_redraw) {
        draw_full_screen();
        s_need_full_redraw = 0;
        return;
    }

    /* Process encoder events */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            s_target_speed_x10 += evt.delta * 5;
            if (s_target_speed_x10 < 0) s_target_speed_x10 = 0;
            if (s_target_speed_x10 > SPEED_MAX_X10) s_target_speed_x10 = SPEED_MAX_X10;

            {
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_SPEED:%d.%d\n",
                         s_target_speed_x10 / 10, s_target_speed_x10 % 10);
                ble_service_notify_str(buf);
            }
            break;
        }

        case ENC_EVT_CLICK:
            s_treadmill_running = !s_treadmill_running;
            ESP_LOGI(TAG, "Treadmill %s, speed=%d.%d",
                     s_treadmill_running ? "START" : "STOP",
                     s_target_speed_x10 / 10, s_target_speed_x10 % 10);
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_RUN:%d\n", s_treadmill_running);
                ble_service_notify_str(buf);
            }
            break;

        case ENC_EVT_LONG_PRESS:
        case ENC_EVT_DOUBLE_CLICK:
            ui_manager_set_ui(5);
            return;

        default:
            break;
        }
    }

    /* Partial updates */
    if (s_target_speed_x10 != s_last_drawn_speed) {
        update_arc_delta(s_last_drawn_speed, s_target_speed_x10);
        draw_speed_number();
        s_last_drawn_speed = s_target_speed_x10;
    }

    if (s_treadmill_running != s_last_drawn_running) {
        draw_indicator();
        s_last_drawn_running = s_treadmill_running;
    }
}
