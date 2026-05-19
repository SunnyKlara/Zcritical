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
#include "font_8x16.h"
#include <stdio.h>
#include <string.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

/**
 * @file ui_treadmill.c
 * @brief UI8 — 跑步机仪表盘（Forza Horizon 风格 v5 最终版）
 *
 * 设计：
 *   - 270° 弧线渐变填充（白→橙→红）+ 外圈边框
 *   - 刻度线：每10小刻度(1px)，每50大刻度(3px)
 *   - 刻度数字：0/50/100/150/200
 *   - 指针：细长三角形（红色），draw_line 实现
 *   - 中心速度数字：F4 大号贴图居中，显示 0-200
 *   - 底部缺口挡位：font_8x16 缩放，1-8 / N
 *   - 操控：油门模式（按住加速，松开减速），双击退出
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static uint8_t  s_lut_built = 0;
static int16_t  s_treadmill_speed = 0;     /* 0-20 */
static int16_t  s_last_drawn_speed = -1;
static uint32_t s_last_tick = 0;
static float    s_last_needle_rad = 0;     /* 上一帧指针角度 */

/* ── Config ── */
#define TREAD_ACCEL_MS      150
#define TREAD_DECEL_MS      100
#define TREAD_MAX_SPEED     20
#define DISPLAY_MAX         200
#define GEAR_MAX            8

/* ── Colors (RGB565) ── */
#define COLOR_BG            0x0000
#define COLOR_ARC_BG        0x18E3
#define COLOR_ARC_BORDER    0x2945
#define COLOR_NEEDLE        0xF800   /* 红色 */
#define COLOR_CENTER_DOT    0x4208
#define COLOR_TICK_DIM      0x2945
#define COLOR_LABEL_DIM     0x3186
#define COLOR_WHITE         0xFFFF

/* ── Arc Geometry ── */
#define ARC_CX              120
#define ARC_CY              120
#define ARC_R_OUTER         108
#define ARC_R_INNER         104
#define ARC_START_DEG       135.0f
#define ARC_SWEEP_DEG       270.0f

/* ── Tick Geometry ── */
#define TICK_R_OUTER        (ARC_R_INNER - 2)
#define TICK_R_INNER_SMALL  (TICK_R_OUTER - 5)
#define TICK_R_INNER_BIG    (TICK_R_OUTER - 12)
#define LABEL_R             (TICK_R_INNER_BIG - 10)

/* ── Needle ── */
#define NEEDLE_TIP_R        (ARC_R_INNER - 3)
#define NEEDLE_BASE_R       8

/* ── Number position ── */
#define NUM_CENTER_Y        (ARC_CY + 26)

/* ── Gear position ── */
#define GEAR_CENTER_Y       (ARC_CY + 62)

/* ══════ Arc LUT (预计算) ══════ */
#define ARC_LUT_MAX     2500
typedef struct { uint8_t x, y, pct; } arc_pixel_t;
static arc_pixel_t s_arc_lut[ARC_LUT_MAX];
static uint16_t s_arc_lut_count = 0;

#define ARC_ROW_COUNT   (ARC_R_OUTER * 2 + 1)
static uint16_t s_row_start[ARC_ROW_COUNT];
static uint16_t s_row_end[ARC_ROW_COUNT];
static uint8_t s_line_buf[480];

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

            float raw = atan2f((float)dy, (float)dx) * (180.0f / (float)M_PI);
            if (raw < 0.0f) raw += 360.0f;
            float rel = raw - ARC_START_DEG;
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
    ESP_LOGI(TAG, "Arc LUT: %d pixels", s_arc_lut_count);
}

/* ══════ Arc Color ══════ */
static uint16_t arc_color(uint8_t pct)
{
    uint8_t r, g, b;
    if (pct <= 50) {
        uint16_t t = (uint16_t)pct * 2;
        r = 255; g = (uint8_t)(255 - 95 * t / 100); b = (uint8_t)(255 - 255 * t / 100);
    } else {
        uint16_t t = (uint16_t)(pct - 50) * 2;
        r = 255; g = (uint8_t)(160 - 130 * t / 100); b = 0;
    }
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/* ══════ Arc Render ══════ */
static void draw_arc_full(uint8_t fill_pct)
{
    for (uint16_t row = 0; row < ARC_ROW_COUNT; row++) {
        if (s_row_start[row] == 0xFFFF) continue;
        uint16_t start = s_row_start[row], end = s_row_end[row];
        uint8_t py = s_arc_lut[start].y;
        uint8_t x_min = 255, x_max = 0;
        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].x < x_min) x_min = s_arc_lut[i].x;
            if (s_arc_lut[i].x > x_max) x_max = s_arc_lut[i].x;
        }
        uint16_t w = x_max - x_min + 1;
        memset(s_line_buf, 0, w * 2);
        for (uint16_t i = start; i <= end; i++) {
            uint16_t c = (s_arc_lut[i].pct <= fill_pct) ? arc_color(s_arc_lut[i].pct) : COLOR_ARC_BG;
            uint16_t idx = (s_arc_lut[i].x - x_min) * 2;
            s_line_buf[idx] = c >> 8; s_line_buf[idx + 1] = c & 0xFF;
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
        uint16_t start = s_row_start[row], end = s_row_end[row];
        uint8_t has = 0, x_min = 255, x_max = 0;
        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].pct >= lo && s_arc_lut[i].pct <= hi) {
                has = 1;
                if (s_arc_lut[i].x < x_min) x_min = s_arc_lut[i].x;
                if (s_arc_lut[i].x > x_max) x_max = s_arc_lut[i].x;
            }
        }
        if (!has) continue;
        uint8_t py = s_arc_lut[start].y;
        uint16_t w = x_max - x_min + 1;
        memset(s_line_buf, 0, w * 2);
        for (uint16_t i = start; i <= end; i++) {
            if (s_arc_lut[i].x < x_min || s_arc_lut[i].x > x_max) continue;
            uint16_t c = (s_arc_lut[i].pct <= new_pct) ? arc_color(s_arc_lut[i].pct) : COLOR_ARC_BG;
            uint16_t idx = (s_arc_lut[i].x - x_min) * 2;
            s_line_buf[idx] = c >> 8; s_line_buf[idx + 1] = c & 0xFF;
        }
        drv_lcd_blit_rgb565(x_min, py, w, 1, (const uint16_t *)s_line_buf);
    }
}

/* ══════ Tick Marks ══════ */
static void draw_ticks(uint8_t fill_pct)
{
    for (int val = 0; val <= DISPLAY_MAX; val += 10) {
        float t = (float)val / DISPLAY_MAX;
        float deg = ARC_START_DEG + ARC_SWEEP_DEG * t;
        float rad = deg * (float)M_PI / 180.0f;

        int is_big = (val % 50 == 0);
        int16_t r_in = is_big ? TICK_R_INNER_BIG : TICK_R_INNER_SMALL;

        uint16_t color;
        uint8_t tick_pct = (uint8_t)(t * 100);
        if (tick_pct <= fill_pct) {
            uint16_t c = arc_color(tick_pct);
            uint8_t cr = ((c >> 11) & 0x1F) * 60 / 100;
            uint8_t cg = ((c >> 5) & 0x3F) * 60 / 100;
            uint8_t cb = (c & 0x1F) * 60 / 100;
            color = (cr << 11) | (cg << 5) | cb;
        } else {
            color = COLOR_TICK_DIM;
        }

        int16_t x0 = ARC_CX + (int16_t)(TICK_R_OUTER * cosf(rad));
        int16_t y0 = ARC_CY + (int16_t)(TICK_R_OUTER * sinf(rad));
        int16_t x1 = ARC_CX + (int16_t)(r_in * cosf(rad));
        int16_t y1 = ARC_CY + (int16_t)(r_in * sinf(rad));

        drv_lcd_draw_line(x0, y0, x1, y1, color);
        if (is_big) {
            float perp = rad + (float)M_PI / 2.0f;
            int16_t ox = (int16_t)(1.0f * cosf(perp));
            int16_t oy = (int16_t)(1.0f * sinf(perp));
            drv_lcd_draw_line(x0 + ox, y0 + oy, x1 + ox, y1 + oy, color);
            drv_lcd_draw_line(x0 - ox, y0 - oy, x1 - ox, y1 - oy, color);
        }
    }
}

/* ══════ Tick Labels ══════ */
static void draw_tick_labels(uint8_t fill_pct)
{
    int labels[] = {0, 50, 100, 150, 200};
    for (int i = 0; i < 5; i++) {
        float t = (float)labels[i] / DISPLAY_MAX;
        float deg = ARC_START_DEG + ARC_SWEEP_DEG * t;
        float rad = deg * (float)M_PI / 180.0f;

        int16_t lx = ARC_CX + (int16_t)(LABEL_R * cosf(rad));
        int16_t ly = ARC_CY + (int16_t)(LABEL_R * sinf(rad));

        uint16_t color = ((uint8_t)(t * 100) <= fill_pct) ? COLOR_LABEL_DIM : COLOR_TICK_DIM;

        char buf[8];
        snprintf(buf, sizeof(buf), "%d", labels[i]);
        uint16_t tw = strlen(buf) * 8;
        int16_t tx = lx - tw / 2;
        int16_t ty = ly - 8;
        drv_lcd_draw_string(tx, ty, buf, color, COLOR_BG, 1);
    }
}

/* ══════ Needle ══════ */
static void draw_needle(float rad, uint16_t color)
{
    float cos_n = cosf(rad);
    float sin_n = sinf(rad);

    int16_t tip_x = ARC_CX + (int16_t)(NEEDLE_TIP_R * cos_n);
    int16_t tip_y = ARC_CY + (int16_t)(NEEDLE_TIP_R * sin_n);
    int16_t base_x = ARC_CX + (int16_t)(NEEDLE_BASE_R * cos_n);
    int16_t base_y = ARC_CY + (int16_t)(NEEDLE_BASE_R * sin_n);

    drv_lcd_draw_line(tip_x, tip_y, base_x, base_y, color);
    float perp = rad + (float)M_PI / 2.0f;
    int16_t ox = (int16_t)(0.7f * cosf(perp));
    int16_t oy = (int16_t)(0.7f * sinf(perp));
    if (ox != 0 || oy != 0) {
        drv_lcd_draw_line(tip_x + ox, tip_y + oy, base_x + ox, base_y + oy, color);
        drv_lcd_draw_line(tip_x - ox, tip_y - oy, base_x - ox, base_y - oy, color);
    }
}

static void update_needle(int16_t speed)
{
    float pct = (float)speed / TREAD_MAX_SPEED;
    float deg = ARC_START_DEG + ARC_SWEEP_DEG * pct;
    float new_rad = deg * (float)M_PI / 180.0f;

    draw_needle(s_last_needle_rad, COLOR_BG);
    draw_needle(new_rad, COLOR_NEEDLE);
    drv_lcd_draw_circle(ARC_CX, ARC_CY, 3, COLOR_CENTER_DOT, true);

    s_last_needle_rad = new_rad;
}

/* ══════ Speed Number ══════ */
static void draw_speed_number(void)
{
    uint16_t display_spd = (uint16_t)(s_treadmill_speed * 10);
    drv_lcd_fill_rect(50, NUM_CENTER_Y - 26, 140, F4_SPEED_NUM_HIGH, COLOR_BG);

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
                    : (count == 2) ? (w_t + w_o + F4_JIANJU) : w_o;
    int16_t x = (LCD_WIDTH - total_w) / 2;
    int16_t y = NUM_CENTER_Y - F4_SPEED_NUM_HIGH / 2;

    if (count == 3) {
        ui_draw_large_digit((uint16_t)x, y, d_h); x += w_h + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, y, d_t); x += w_t + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, y, d_o);
    } else if (count == 2) {
        ui_draw_large_digit((uint16_t)x, y, d_t); x += w_t + F4_JIANJU;
        ui_draw_large_digit((uint16_t)x, y, d_o);
    } else {
        ui_draw_large_digit((uint16_t)x, y, d_o);
    }
}

/* ══════ Gear ══════ */
static void draw_gear(void)
{
    drv_lcd_fill_rect(100, GEAR_CENTER_Y - 10, 40, 20, COLOR_BG);
    char buf[4];
    if (s_treadmill_speed < 1) {
        buf[0] = 'N'; buf[1] = '\0';
    } else {
        int gear = (s_treadmill_speed * GEAR_MAX + TREAD_MAX_SPEED / 2) / TREAD_MAX_SPEED;
        if (gear < 1) gear = 1;
        if (gear > GEAR_MAX) gear = GEAR_MAX;
        snprintf(buf, sizeof(buf), "%d", gear);
    }
    uint16_t tw = strlen(buf) * 16;
    int16_t tx = ARC_CX - tw / 2;
    int16_t ty = GEAR_CENTER_Y - 8;
    drv_lcd_draw_string(tx, ty, buf, COLOR_WHITE, COLOR_BG, 2);
}

/* ══════ Full Screen ══════ */
static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);
    uint8_t pct = (uint8_t)((uint32_t)s_treadmill_speed * 100 / TREAD_MAX_SPEED);

    draw_arc_full(pct);
    draw_ticks(pct);
    draw_tick_labels(pct);

    float deg = ARC_START_DEG + ARC_SWEEP_DEG * (float)s_treadmill_speed / TREAD_MAX_SPEED;
    s_last_needle_rad = deg * (float)M_PI / 180.0f;
    draw_needle(s_last_needle_rad, COLOR_NEEDLE);
    drv_lcd_draw_circle(ARC_CX, ARC_CY, 3, COLOR_CENTER_DOT, true);

    draw_speed_number();
    draw_gear();
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
        draw_ticks(new_pct);
        update_needle(s_treadmill_speed);
        draw_speed_number();
        draw_gear();

        s_last_drawn_speed = s_treadmill_speed;
    }
}
