#include "ui_treadmill.h"
#include "ui_common.h"
#include "ui_images.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include "treadmill_service.h"
#include "esp_log.h"
#include "font_8x16.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "esp_heap_caps.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

/**
 * @file ui_treadmill.c
 * @brief UI8 - Treadmill gauge v6 (optimized)
 */

static const char *TAG = "UI_TREAD";

/* == State == */
static uint8_t  s_need_full_redraw = 1;
static uint8_t  s_lut_built = 0;
static int16_t  s_treadmill_speed = 0;
static int16_t  s_cruise_speed = 0;
static int16_t  s_last_drawn_speed = -1;
static float    s_display_speed = 0.0f;
static uint32_t s_last_tick = 0;
static float    s_last_needle_rad = 0;
static uint8_t  s_last_drawn_pct = 0;
static uint16_t s_last_display_num = 0xFFFF;  /* last drawn number value */

/* == Config == */
#define TREAD_ACCEL_MS      120
#define TREAD_DECEL_MS      80
#define TREAD_MAX_SPEED     20
#define DISPLAY_MAX         200
#define GEAR_MAX            8
#define SMOOTH_FACTOR       0.25f

/* == Colors (RGB565) == */
#define COLOR_BG            0x0000
#define COLOR_ARC_BG        0x1082
#define COLOR_ARC_BORDER    0x2945
#define COLOR_NEEDLE        0xF800
#define COLOR_NEEDLE_TIP    0xFFFF
#define COLOR_CENTER_DOT    0x4208
#define COLOR_TICK_DIM      0x2945
#define COLOR_LABEL_DIM     0x3186
#define COLOR_WHITE         0xFFFF
#define COLOR_GEAR_DIM      0x2104

/* == Arc Geometry (widened: 15px band + 2px border) == */
#define ARC_CX              120
#define ARC_CY              120
#define ARC_R_OUTER         110
#define ARC_R_INNER         93
#define ARC_START_DEG       135.0f
#define ARC_SWEEP_DEG       270.0f

/* == Tick Geometry == */
#define TICK_R_OUTER        (ARC_R_INNER - 2)
#define TICK_R_INNER_BIG    (TICK_R_OUTER - 13)

/* == Needle == */
#define NEEDLE_TIP_R        (ARC_R_INNER - 4)
#define NEEDLE_BASE_R       10
#define NEEDLE_BASE_HALF_W  3

/* == Number position == */
#define NUM_CENTER_Y        (ARC_CY + 15)

/* == Gear position == */
#define GEAR_CENTER_Y       (ARC_CY + 55)
#define GEAR_BLOCK_GAP      4

/* ====== Arc LUT (precomputed) ====== */
#define ARC_LUT_MAX     4000
typedef struct { uint8_t x, y, pct; } arc_pixel_t;
static arc_pixel_t *s_arc_lut = NULL;  /* Allocated in PSRAM on first use */
static uint16_t s_arc_lut_count = 0;

#define ARC_ROW_COUNT   (ARC_R_OUTER * 2 + 1)
static uint16_t s_row_start[ARC_ROW_COUNT];
static uint16_t s_row_end[ARC_ROW_COUNT];
static uint8_t s_line_buf[480];

static void build_arc_lut(void)
{
    /* Allocate LUT in PSRAM to save DRAM */
    if (!s_arc_lut) {
        s_arc_lut = (arc_pixel_t *)heap_caps_malloc(
            ARC_LUT_MAX * sizeof(arc_pixel_t), MALLOC_CAP_SPIRAM);
        if (!s_arc_lut) {
            ESP_LOGE(TAG, "Failed to alloc arc LUT in PSRAM!");
            return;
        }
    }
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

/* ====== Arc Color ====== */
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

/* ====== Arc Render ====== */
static void draw_arc_full(uint8_t fill_pct)
{
    /* All arc pixels (including border) rendered via LUT */
    /* Draw main arc band using LUT */
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

/* ====== Tick Marks (major + minor alternating) ====== */
#define TICK_TOTAL          21   /* 0,10,20,...200 → 21 positions */
#define TICK_MAJOR_EVERY    5    /* Every 5th tick is major (0,50,100,150,200) */
#define TICK_R_MINOR_INNER  (TICK_R_OUTER - 7)   /* Short thin tick */

static void draw_single_tick(int i, uint8_t fill_pct)
{
    float t = (float)i / (TICK_TOTAL - 1);
    float deg = ARC_START_DEG + ARC_SWEEP_DEG * t;
    float rad = deg * (float)M_PI / 180.0f;

    uint8_t tick_pct = (uint8_t)(t * 100);
    uint16_t color = (tick_pct <= fill_pct) ? arc_color(tick_pct) : COLOR_TICK_DIM;

    uint8_t is_major = (i % TICK_MAJOR_EVERY == 0);
    int16_t r_inner = is_major ? TICK_R_INNER_BIG : TICK_R_MINOR_INNER;

    float cos_r = cosf(rad);
    float sin_r = sinf(rad);
    int16_t x0 = ARC_CX + (int16_t)(TICK_R_OUTER * cos_r);
    int16_t y0 = ARC_CY + (int16_t)(TICK_R_OUTER * sin_r);
    int16_t x1 = ARC_CX + (int16_t)(r_inner * cos_r);
    int16_t y1 = ARC_CY + (int16_t)(r_inner * sin_r);

    drv_lcd_draw_line(x0, y0, x1, y1, color);

    if (is_major) {
        float perp = rad + (float)M_PI / 2.0f;
        int16_t ox = (int16_t)(1.0f * cosf(perp));
        int16_t oy = (int16_t)(1.0f * sinf(perp));
        drv_lcd_draw_line(x0 + ox, y0 + oy, x1 + ox, y1 + oy, color);
        drv_lcd_draw_line(x0 - ox, y0 - oy, x1 - ox, y1 - oy, color);
    }
}

static void draw_ticks(uint8_t fill_pct)
{
    for (int i = 0; i < TICK_TOTAL; i++) {
        draw_single_tick(i, fill_pct);
    }
}

/* Only redraw ticks whose pct falls within [lo, hi] range */
static void draw_ticks_range(uint8_t lo, uint8_t hi, uint8_t fill_pct)
{
    for (int i = 0; i < TICK_TOTAL; i++) {
        uint8_t tick_pct = (uint8_t)((float)i / (TICK_TOTAL - 1) * 100);
        if (tick_pct >= lo && tick_pct <= hi) {
            draw_single_tick(i, fill_pct);
        }
    }
}

/* ====== Needle (wedge triangle) ====== */
static void draw_needle_wedge(float rad, uint16_t color, uint16_t tip_color)
{
    float cos_n = cosf(rad);
    float sin_n = sinf(rad);
    float perp = rad + (float)M_PI / 2.0f;
    float cos_p = cosf(perp);
    float sin_p = sinf(perp);

    int16_t tip_x = ARC_CX + (int16_t)(NEEDLE_TIP_R * cos_n);
    int16_t tip_y = ARC_CY + (int16_t)(NEEDLE_TIP_R * sin_n);

    int16_t base_cx = ARC_CX + (int16_t)(NEEDLE_BASE_R * cos_n);
    int16_t base_cy = ARC_CY + (int16_t)(NEEDLE_BASE_R * sin_n);

    /* Fill triangle with fan of lines from tip to base */
    for (int i = -NEEDLE_BASE_HALF_W; i <= NEEDLE_BASE_HALF_W; i++) {
        int16_t bx = base_cx + (int16_t)(i * cos_p);
        int16_t by = base_cy + (int16_t)(i * sin_p);
        drv_lcd_draw_line(tip_x, tip_y, bx, by, color);
    }

    /* Tip highlight */
    if (tip_color != COLOR_BG) {
        int16_t hl_x = ARC_CX + (int16_t)((NEEDLE_TIP_R - 3) * cos_n);
        int16_t hl_y = ARC_CY + (int16_t)((NEEDLE_TIP_R - 3) * sin_n);
        drv_lcd_fill_rect(hl_x, hl_y, 2, 2, tip_color);
    }
}

static void update_needle_smooth(void)
{
    float pct = s_display_speed / TREAD_MAX_SPEED;
    if (pct > 1.0f) pct = 1.0f;
    if (pct < 0.0f) pct = 0.0f;
    float deg = ARC_START_DEG + ARC_SWEEP_DEG * pct;
    float new_rad = deg * (float)M_PI / 180.0f;

    /* Skip redraw if angle barely changed (reduces flicker + CPU) */
    if (fabsf(new_rad - s_last_needle_rad) < 0.02f) return;

    draw_needle_wedge(s_last_needle_rad, COLOR_BG, COLOR_BG);
    draw_needle_wedge(new_rad, COLOR_NEEDLE, COLOR_NEEDLE_TIP);

    s_last_needle_rad = new_rad;
}

/* ====== Speed Number ====== */
static void draw_speed_number(void)
{
    uint16_t display_spd = (uint16_t)(s_display_speed * 10.0f + 0.5f);
    if (display_spd > DISPLAY_MAX) display_spd = DISPLAY_MAX;
    if (display_spd == s_last_display_num) return;  /* Skip if unchanged */
    s_last_display_num = display_spd;

    drv_lcd_fill_rect(40, NUM_CENTER_Y - 26, 160, F4_SPEED_NUM_HIGH, COLOR_BG);

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

    /* Unit label */
    const char *unit = "km/h";
    uint16_t uw = strlen(unit) * 8;
    drv_lcd_draw_string((LCD_WIDTH - uw) / 2, NUM_CENTER_Y + F4_SPEED_NUM_HIGH / 2 + 4,
                        unit, COLOR_LABEL_DIM, COLOR_BG, 1);
}

/* ====== Gear (progressive width + gradient color) ====== */
static uint16_t gear_color(int idx)
{
    /* Pure red: light pink(1) -> deep red(8) */
    uint8_t t = (uint8_t)((idx - 1) * 100 / (GEAR_MAX - 1));
    uint8_t r = (uint8_t)(120 + 135 * t / 100);  /* 120 -> 255 */
    uint8_t g = (uint8_t)(60 - 60 * t / 100);    /* 60 -> 0 */
    uint8_t b = (uint8_t)(60 - 60 * t / 100);    /* 60 -> 0 */
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_gear_blocks(void)
{
    int gear = 0;
    if (s_treadmill_speed >= 1) {
        gear = (s_treadmill_speed * GEAR_MAX + TREAD_MAX_SPEED / 2) / TREAD_MAX_SPEED;
        if (gear < 1) gear = 1;
        if (gear > GEAR_MAX) gear = GEAR_MAX;
    }

    /* Equal width (6px), progressive height: 4,6,8,10,12,14,16,18 */
    #define GEAR_W  6
    uint16_t total_w = GEAR_MAX * GEAR_W + (GEAR_MAX - 1) * GEAR_BLOCK_GAP;
    uint16_t start_x = ARC_CX - total_w / 2;
    uint16_t base_y = GEAR_CENTER_Y + 18;  /* bottom-aligned */

    /* Clear gear area */
    drv_lcd_fill_rect(start_x - 2, GEAR_CENTER_Y - 2, total_w + 4, 22, COLOR_BG);

    for (int i = 1; i <= GEAR_MAX; i++) {
        uint8_t h = 4 + (uint8_t)((i - 1) * 2);  /* height: 4,6,8,10,12,14,16,18 */
        uint16_t bx = start_x + (i - 1) * (GEAR_W + GEAR_BLOCK_GAP);
        uint16_t by = base_y - h;  /* bottom-aligned */
        uint16_t color = (i <= gear) ? gear_color(i) : COLOR_GEAR_DIM;
        drv_lcd_fill_rect(bx, by, GEAR_W, h, color);
    }
    #undef GEAR_W
}

/* ====== Full Screen ====== */
static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);
    s_display_speed = (float)s_treadmill_speed;
    uint8_t pct = (uint8_t)((uint32_t)s_treadmill_speed * 100 / TREAD_MAX_SPEED);

    draw_arc_full(pct);
    draw_ticks(pct);

    float deg = ARC_START_DEG + ARC_SWEEP_DEG * (float)s_treadmill_speed / TREAD_MAX_SPEED;
    s_last_needle_rad = deg * (float)M_PI / 180.0f;
    draw_needle_wedge(s_last_needle_rad, COLOR_NEEDLE, COLOR_NEEDLE_TIP);

    draw_speed_number();
    draw_gear_blocks();
    s_last_drawn_speed = s_treadmill_speed;
}

/* ====== Speed Process (throttle + cruise) ====== */
static void speed_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    uint32_t elapsed = now - s_last_tick;

    if (drv_encoder_button_pressed()) {
        if (elapsed >= TREAD_ACCEL_MS) {
            s_last_tick = now;
            if (s_treadmill_speed < TREAD_MAX_SPEED) {
                s_treadmill_speed++;
                treadmill_service_set_speed((uint8_t)s_treadmill_speed);
            }
        }
    } else {
        if (s_treadmill_speed > s_cruise_speed && elapsed >= TREAD_DECEL_MS) {
            s_last_tick = now;
            s_treadmill_speed--;
            treadmill_service_set_speed((uint8_t)s_treadmill_speed);
        }
    }
}

/* ====== Public API ====== */
void ui_treadmill_enter(void)
{
    if (!s_lut_built) {
        build_arc_lut();
        s_lut_built = 1;
    }
    s_need_full_redraw = 1;
    s_last_drawn_speed = -1;
    s_display_speed = (float)s_treadmill_speed;
    s_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
    ESP_LOGI(TAG, "Treadmill entered, speed=%d, cruise=%d", s_treadmill_speed, s_cruise_speed);
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
        if (evt.type == ENC_EVT_CLICK || evt.type == ENC_EVT_DOUBLE_CLICK ||
            evt.type == ENC_EVT_LONG_PRESS) {
            ui_manager_set_ui(5);
            return;
        }
        if (evt.type == ENC_EVT_ROTATE) {
            s_cruise_speed += evt.delta;
            if (s_cruise_speed < 0) s_cruise_speed = 0;
            if (s_cruise_speed > TREAD_MAX_SPEED) s_cruise_speed = TREAD_MAX_SPEED;
            if (!drv_encoder_button_pressed()) {
                s_treadmill_speed = s_cruise_speed;
                treadmill_service_set_speed((uint8_t)s_treadmill_speed);
            }
        }
    }

    speed_process();

    float target = (float)s_treadmill_speed;
    if (fabsf(s_display_speed - target) > 0.05f) {
        s_display_speed += (target - s_display_speed) * SMOOTH_FACTOR;
    } else {
        s_display_speed = target;
    }

    /* ONLY redraw when integer speed changes - prevents WDT and lag */
    int16_t visual_speed = (int16_t)(s_display_speed + 0.5f);
    if (visual_speed == s_last_drawn_speed) return;

    uint8_t new_pct = (uint8_t)((uint32_t)visual_speed * 100 / TREAD_MAX_SPEED);
    if (new_pct > 100) new_pct = 100;

    if (new_pct != s_last_drawn_pct) {
        update_arc_fast(s_last_drawn_pct, new_pct);
        /* Only redraw ticks that cross the old/new boundary */
        uint8_t lo = (new_pct > s_last_drawn_pct) ? s_last_drawn_pct : new_pct;
        uint8_t hi = (new_pct > s_last_drawn_pct) ? new_pct : s_last_drawn_pct;
        draw_ticks_range(lo, hi, new_pct);
        s_last_drawn_pct = new_pct;
    }

    update_needle_smooth();
    draw_speed_number();
    draw_gear_blocks();
    s_last_drawn_speed = visual_speed;
}
