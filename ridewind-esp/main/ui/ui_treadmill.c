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
 * @brief UI8 — Treadmill (Forza arc + F4 digits + throttle)
 *
 * 性能优化方案：预计算弧线像素查找表
 * - 启动时一次性计算所有弧线像素的坐标和角度百分比
 * - 更新时只需遍历变化范围的像素，用行缓冲批量 blit
 * - 数字不清除再画，直接覆盖（贴图自带黑色背景）
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static uint8_t  s_lut_built = 0;
static int16_t  s_treadmill_speed = 0;
static int16_t  s_last_drawn_speed = -1;
static uint32_t s_last_tick = 0;

/* ── Config ── */
#define TREAD_ACCEL_MS      150
#define TREAD_DECEL_MS      100
#define TREAD_MAX_SPEED     20

/* ── Colors ── */
#define COLOR_BG            0x0000
#define COLOR_ARC_BG        0x18E3

/* ── Arc Geometry ── */
#define ARC_CX              120
#define ARC_CY              120
#define ARC_R_OUTER         108
#define ARC_R_INNER         104
#define ARC_START_DEG       135.0f
#define ARC_SWEEP_DEG       270.0f

/* ══════ 预计算弧线像素查找表 ══════
 * 弧线 4px 厚, 半径 104-108, 270°
 * 估算像素数: 2π×106×(270/360)×4 ≈ 2000 像素
 * 每个像素存: x(uint8), y(uint8), pct(uint8) = 3 字节
 * 总 RAM: ~6KB
 */
#define ARC_LUT_MAX     2500

typedef struct {
    uint8_t x;
    uint8_t y;
    uint8_t pct;   /* 0-100: 在弧线中的位置百分比 */
} arc_pixel_t;

static arc_pixel_t s_arc_lut[ARC_LUT_MAX];
static uint16_t    s_arc_lut_count = 0;

/* 按行排序后的行索引 */
#define ARC_ROW_COUNT   (ARC_R_OUTER * 2 + 1)
static uint16_t s_row_start[ARC_ROW_COUNT];
static uint16_t s_row_end[ARC_ROW_COUNT];

static void build_arc_lut(void)
{
    s_arc_lut_count = 0;
    int32_t r_out_sq = (int32_t)ARC_R_OUTER * ARC_R_OUTER;
    int32_t r_in_sq  = (int32_t)ARC_R_INNER * ARC_R_INNER;

    memset(s_row_start, 0xFF, sizeof(s_row_start));
    memset(s_row_end, 0, sizeof(s_row_end));

    for (int16_t py = ARC_CY - ARC_R_OUTER; py <= ARC_CY + ARC_R_OUTER; py++) {
        if (py < 0 || py >= LCD_HEIGHT) continue;
        int16_t dy = py - ARC_CY;
        int32_t dy_sq = (int32_t)dy * dy;

        for (int16_t px = ARC_CX - ARC_R_OUTER; px <= ARC_CX + ARC_R_OUTER; px++) {
            if (px < 0 || px >= LCD_WIDTH) continue;
            int16_t dx = px - ARC_CX;
            int32_t d_sq = (int32_t)dx * dx + dy_sq;
            if (d_sq < r_in_sq || d_sq > r_out_sq) continue;

            float raw_deg = atan2f((float)dy, (float)dx) * (180.0f / (float)M_PI);
            if (raw_deg < 0.0f) raw_deg += 360.0f;
            float rel = raw_deg - ARC_START_DEG;
            if (rel < -0.5f) rel += 360.0f;
            if (rel < 0.0f) rel = 0.0f;
            if (rel > ARC_SWEEP_DEG + 0.5f) continue;

            uint8_t pct = (uint8_t)(rel * 100.0f / ARC_SWEEP_DEG);
            if (pct > 100) pct = 100;

            if (s_arc_lut_count >= ARC_LUT_MAX) break;

            s_arc_lut[s_arc_lut_count].x = (uint8_t)px;
            s_arc_lut[s_arc_lut_count].y = (uint8_t)py;
            s_arc_lut[s_arc_lut_count].pct = pct;

            uint16_t row = py - (ARC_CY - ARC_R_OUTER);
            if (s_row_start[row] == 0xFFFF) s_row_start[row] = s_arc_lut_count;
            s_row_end[row] = s_arc_lut_count;

            s_arc_lut_count++;
        }
        if (s_arc_lut_count >= ARC_LUT_MAX) break;
    }

    ESP_LOGI(TAG, "Arc LUT built: %d pixels", s_arc_lut_count);
}

/* ══════ Arc Color ══════ */
static uint16_t arc_color(uint8_t pct)
{
    uint8_t r, g, b;
    if (pct <= 50) {
        uint16_t t = (uint16_t)pct * 2;
        r = 255;
        g = (uint8_t)(255 - (255 - 160) * t / 100);
        b = (uint8_t)(255 - 255 * t / 100);
    } else {
        uint16_t t = (uint16_t)(pct - 50) * 2;
        r = 255;
        g = (uint8_t)(160 - (160 - 30) * t / 100);
        b = 0;
    }
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/* ══════ Arc Rendering (LUT-based) ══════ */

static uint8_t s_line_buf[480];

static void draw_arc_full(uint8_t fill_pct)
{
    for (uint16_t row = 0; row < ARC_ROW_COUNT; row++) {
        if (s_row_start[row] == 0xFFFF) continue;

        uint16_t start = s_row_start[row];
        uint16_t end   = s_row_end[row];
        uint8_t  py    = s_arc_lut[start].y;
        uint8_t  x_min = s_arc_lut[start].x;
        uint8_t  x_max = s_arc_lut[start].x;

        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].x < x_min) x_min = s_arc_lut[i].x;
            if (s_arc_lut[i].x > x_max) x_max = s_arc_lut[i].x;
        }

        uint16_t w = x_max - x_min + 1;
        memset(s_line_buf, 0, w * 2);

        for (uint16_t i = start; i <= end; i++) {
            uint16_t color = (s_arc_lut[i].pct <= fill_pct)
                           ? arc_color(s_arc_lut[i].pct) : COLOR_ARC_BG;
            uint16_t idx = (s_arc_lut[i].x - x_min) * 2;
            s_line_buf[idx]     = color >> 8;
            s_line_buf[idx + 1] = color & 0xFF;
        }

        drv_lcd_blit_rgb565(x_min, py, w, 1, (const uint16_t *)s_line_buf);
    }
}

static void update_arc_fast(uint8_t old_pct, uint8_t new_pct)
{
    uint8_t lo = (new_pct > old_pct) ? old_pct : new_pct;
    uint8_t hi = (new_pct > old_pct) ? new_pct : old_pct;

    for (uint16_t row = 0; row < ARC_ROW_COUNT; row++) {
        if (s_row_start[row] == 0xFFFF) continue;

        uint16_t start = s_row_start[row];
        uint16_t end   = s_row_end[row];

        uint8_t has_change = 0;
        uint8_t x_min = 255, x_max = 0;

        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].pct >= lo && s_arc_lut[i].pct <= hi) {
                has_change = 1;
                if (s_arc_lut[i].x < x_min) x_min = s_arc_lut[i].x;
                if (s_arc_lut[i].x > x_max) x_max = s_arc_lut[i].x;
            }
        }

        if (!has_change) continue;

        uint8_t py = s_arc_lut[start].y;
        uint16_t w = x_max - x_min + 1;
        memset(s_line_buf, 0, w * 2);

        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].x < x_min || s_arc_lut[i].x > x_max) continue;
            uint16_t color = (s_arc_lut[i].pct <= new_pct)
                           ? arc_color(s_arc_lut[i].pct) : COLOR_ARC_BG;
            uint16_t idx = (s_arc_lut[i].x - x_min) * 2;
            s_line_buf[idx]     = color >> 8;
            s_line_buf[idx + 1] = color & 0xFF;
        }

        drv_lcd_blit_rgb565(x_min, py, w, 1, (const uint16_t *)s_line_buf);
    }
}

/* ══════ Number Drawing ══════ */

static void draw_number(void)
{
    uint16_t display_spd = (uint16_t)(s_treadmill_speed * 17);

    /* 缩小清除区域，避免覆盖弧线 */
    drv_lcd_fill_rect(50, F4_Y_QI, 140, F4_SPEED_NUM_HIGH, 0x0000);

    uint8_t d_h, d_t, d_o, count;
    if (display_spd >= 100) {
        d_h = display_spd / 100; d_t = (display_spd % 100) / 10; d_o = display_spd % 10; count = 3;
    } else if (display_spd >= 10) {
        d_h = 0; d_t = display_spd / 10; d_o = display_spd % 10; count = 2;
    } else {
        d_h = 0; d_t = 0; d_o = display_spd; count = 1;
    }

    uint8_t w_h = ui_large_digit_width(d_h);
    uint8_t w_t = ui_large_digit_width(d_t);
    uint8_t w_o = ui_large_digit_width(d_o);

    int16_t total_w = (count == 3) ? (w_h + w_t + w_o + F4_JIANJU * 2)
                    : (count == 2) ? (w_t + w_o + F4_JIANJU)
                    : w_o;

    int16_t x = (LCD_WIDTH - total_w) / 2;

    if (count == 3) {
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_h); x += w_h + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_t); x += w_t + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_o);
    } else if (count == 2) {
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_t); x += w_t + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_o);
    } else {
        ui_draw_large_digit((uint16_t)x, F4_Y_QI, d_o);
    }
}

/* ══════ Full Screen ══════ */

static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);
    uint8_t pct = (uint8_t)((uint32_t)s_treadmill_speed * 100 / TREAD_MAX_SPEED);
    draw_arc_full(pct);
    draw_number();
    s_last_drawn_speed = s_treadmill_speed;
}

/* ══════ Throttle ══════ */

static void throttle_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    uint32_t elapsed = now - s_last_tick;

    if (drv_encoder_button_pressed()) {
        if (elapsed >= TREAD_ACCEL_MS) {
            s_last_tick = now;
            if (s_treadmill_speed < TREAD_MAX_SPEED) {
                s_treadmill_speed++;
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_SPEED:%d\n", s_treadmill_speed);
                ble_service_notify_str(buf);
            }
        }
    } else {
        if (elapsed >= TREAD_DECEL_MS && s_treadmill_speed > 0) {
            s_last_tick = now;
            s_treadmill_speed--;
            char buf[32];
            snprintf(buf, sizeof(buf), "TREAD_SPEED:%d\n", s_treadmill_speed);
            ble_service_notify_str(buf);
        }
    }
}

/* ══════ Public API ══════ */

void ui_treadmill_enter(void)
{
    if (!s_lut_built) {
        build_arc_lut();
        s_lut_built = 1;
    }
    s_need_full_redraw = 1;
    s_last_drawn_speed = -1;
    s_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
    ESP_LOGI(TAG, "Treadmill entered, speed=%d", s_treadmill_speed);
}

void ui_treadmill_update(void)
{
    if (s_need_full_redraw) {
        draw_full_screen();
        s_need_full_redraw = 0;
        return;
    }

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        if (evt.type == ENC_EVT_DOUBLE_CLICK) {
            ui_manager_set_ui(5);
            return;
        }
    }

    throttle_process();

    if (s_treadmill_speed != s_last_drawn_speed) {
        uint8_t old_pct = (s_last_drawn_speed <= 0) ? 0 : (uint8_t)((uint32_t)s_last_drawn_speed * 100 / TREAD_MAX_SPEED);
        uint8_t new_pct = (uint8_t)((uint32_t)s_treadmill_speed * 100 / TREAD_MAX_SPEED);
        update_arc_fast(old_pct, new_pct);
        draw_number();
        s_last_drawn_speed = s_treadmill_speed;
    }
}
