#include "ui_treadmill.h"
#include "ui_common.h"
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
 * @brief UI8 — Treadmill control page (Forza Horizon style)
 *
 * Design inspired by Forza Horizon 5 speedometer HUD:
 *   - 270° arc tachometer (progress arc showing speed ratio)
 *   - Large centered speed number (digital, bold)
 *   - Status indicator (RUNNING/STOPPED) below speed
 *   - Minimal, dark background, semi-transparent feel
 *   - Color gradient: white → orange → red as speed increases
 *
 * LCD layout (240×240 round):
 *   - Outer arc: 270° progress arc (radius ~105, thickness 8px)
 *   - Background arc: dark gray 270° ring
 *   - Center: Large speed number "X.X"
 *   - Below number: "km/h" unit label
 *   - Bottom: Status text (RUNNING green / READY gray)
 *   - Tick marks at 0, 5, 10, 15, 20 positions on arc
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

/* ── Forza Horizon Style Colors (RGB565) ── */
#define COLOR_BG            0x0000   /* Pure black */
#define COLOR_ARC_BG        0x2104   /* Dark gray - background arc */
#define COLOR_ARC_WHITE     0xFFFF   /* White - low speed arc */
#define COLOR_ARC_ORANGE    0xFCA0   /* Orange - mid speed */
#define COLOR_ARC_RED       0xF800   /* Red - high speed / redline */
#define COLOR_SPEED_NUM     0xFFFF   /* White - speed digits */
#define COLOR_UNIT          0x7BEF   /* Medium gray - "km/h" */
#define COLOR_RUNNING       0x07E0   /* Green */
#define COLOR_STOPPED       0xF800   /* Red */
#define COLOR_TICK          0xAD55   /* Light gray - tick marks */
#define COLOR_TICK_ACTIVE   0xFFFF   /* White - active tick */
#define COLOR_HINT          0x4208   /* Dark gray - hint text */

/* ── Arc Geometry ── */
#define ARC_CENTER_X        120
#define ARC_CENTER_Y        120
#define ARC_RADIUS_OUTER    108
#define ARC_RADIUS_INNER    100      /* Thickness = 8px */
#define ARC_START_ANGLE     135      /* Start at bottom-left (degrees) */
#define ARC_SWEEP_ANGLE     270      /* Sweep 270 degrees clockwise */
#define ARC_TICK_RADIUS_OUT 112      /* Tick marks outside the arc */
#define ARC_TICK_RADIUS_IN  96       /* Tick marks inside the arc */

/* Speed range */
#define SPEED_MAX_X10       200      /* 20.0 km/h */
#define SPEED_TICKS         5        /* Tick marks: 0, 5, 10, 15, 20 */

/* ── Layout ── */
#define SPEED_NUM_Y         85       /* Y position for speed number */
#define UNIT_Y              145      /* Y position for "km/h" */
#define STATUS_Y            170      /* Y position for status */

/* ── Font rendering (reuse font_8x16) ── */
#include "font_8x16.h"

static void draw_char_scaled(uint16_t x, uint16_t y, char c,
                              uint16_t color, uint8_t scale)
{
    if (c < 32 || c > 126) return;
    const unsigned char *glyph = font_8x16[c - 32];
    for (uint8_t row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        for (uint8_t col = 0; col < 8; col++) {
            if (bits & (0x80 >> col)) {
                if (scale == 1) {
                    drv_lcd_fill_rect(x + col, y + row, 1, 1, color);
                } else {
                    drv_lcd_fill_rect(x + col * scale, y + row * scale,
                                      scale, scale, color);
                }
            }
        }
    }
}

static void draw_text_centered(uint16_t y, const char *text,
                                uint16_t color, uint8_t scale)
{
    uint16_t len = strlen(text);
    uint16_t char_w = 8 * scale;
    uint16_t total_w = len * char_w;
    uint16_t x = (LCD_WIDTH - total_w) / 2;
    for (uint16_t i = 0; i < len; i++) {
        draw_char_scaled(x + i * char_w, y, text[i], color, scale);
    }
}

/* ══════ Arc Drawing Engine ══════
 * Forza Horizon uses smooth thick arcs. We implement this with
 * a pixel-by-pixel approach checking if each pixel falls within
 * the arc's angular and radial bounds.
 *
 * For performance on ESP32, we use a scanline approach:
 * iterate rows in the arc's bounding box, compute valid pixels.
 */

/**
 * @brief Get arc color based on fill percentage (Forza gradient)
 *        0-40%: White
 *        40-70%: White → Orange gradient
 *        70-100%: Orange → Red gradient
 */
static uint16_t get_arc_color(uint8_t percent)
{
    uint8_t r, g, b;

    if (percent <= 40) {
        /* Pure white */
        return COLOR_ARC_WHITE;
    } else if (percent <= 70) {
        /* White (255,255,255) → Orange (252,160,0) */
        uint16_t t = (uint16_t)(percent - 40) * 100 / 30;
        r = 255;
        g = (uint8_t)(255 - (255 - 160) * t / 100);
        b = (uint8_t)(255 - 255 * t / 100);
    } else {
        /* Orange (252,160,0) → Red (248,0,0) */
        uint16_t t = (uint16_t)(percent - 70) * 100 / 30;
        r = (uint8_t)(252 - (252 - 248) * t / 100);
        g = (uint8_t)(160 - 160 * t / 100);
        b = 0;
    }

    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/**
 * @brief Normalize angle to 0-360 range
 */
static inline float normalize_angle(float angle)
{
    while (angle < 0) angle += 360.0f;
    while (angle >= 360.0f) angle -= 360.0f;
    return angle;
}

/**
 * @brief Check if an angle is within the arc sweep
 *        Arc goes from start_angle clockwise for sweep degrees
 */
static inline bool angle_in_range(float angle, float start, float sweep)
{
    float a = normalize_angle(angle - start);
    return (a <= sweep);
}

/**
 * @brief Draw a thick arc segment (Forza Horizon style)
 * @param fill_percent  0-100, how much of the 270° arc to fill
 *
 * Draws the filled portion with gradient color, and the unfilled
 * portion with the background arc color.
 */
static void draw_arc_gauge(uint8_t fill_percent)
{
    if (fill_percent > 100) fill_percent = 100;

    float start_deg = (float)ARC_START_ANGLE;
    float sweep_deg = (float)ARC_SWEEP_ANGLE;
    float fill_sweep = sweep_deg * fill_percent / 100.0f;

    int16_t r_out = ARC_RADIUS_OUTER;
    int16_t r_in  = ARC_RADIUS_INNER;
    int32_t r_out_sq = (int32_t)r_out * r_out;
    int32_t r_in_sq  = (int32_t)r_in * r_in;

    /* Scan the bounding box of the arc */
    int16_t x_min = ARC_CENTER_X - r_out;
    int16_t x_max = ARC_CENTER_X + r_out;
    int16_t y_min = ARC_CENTER_Y - r_out;
    int16_t y_max = ARC_CENTER_Y + r_out;

    /* Clamp to screen */
    if (x_min < 0) x_min = 0;
    if (y_min < 0) y_min = 0;
    if (x_max >= LCD_WIDTH) x_max = LCD_WIDTH - 1;
    if (y_max >= LCD_HEIGHT) y_max = LCD_HEIGHT - 1;

    for (int16_t py = y_min; py <= y_max; py++) {
        int16_t dy = py - ARC_CENTER_Y;
        int32_t dy_sq = (int32_t)dy * dy;

        for (int16_t px = x_min; px <= x_max; px++) {
            int16_t dx = px - ARC_CENTER_X;
            int32_t dist_sq = (int32_t)dx * dx + dy_sq;

            /* Check if pixel is within the ring (between inner and outer radius) */
            if (dist_sq < r_in_sq || dist_sq > r_out_sq) continue;

            /* Calculate angle of this pixel (atan2, convert to degrees) */
            float angle = atan2f((float)dy, (float)dx) * 180.0f / (float)M_PI;
            angle = normalize_angle(angle);

            /* Check if within the full arc sweep */
            if (!angle_in_range(angle, start_deg, sweep_deg)) continue;

            /* Determine if this pixel is in the filled or background portion */
            float pixel_sweep = normalize_angle(angle - start_deg);

            if (pixel_sweep <= fill_sweep) {
                /* Filled portion — use gradient color */
                uint8_t local_pct = (uint8_t)(pixel_sweep * 100.0f / sweep_deg);
                uint16_t color = get_arc_color(local_pct);
                drv_lcd_fill_rect(px, py, 1, 1, color);
            } else {
                /* Background portion */
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

/**
 * @brief Draw tick marks around the arc (0, 5, 10, 15, 20 km/h)
 */
static void draw_tick_marks(void)
{
    float start_deg = (float)ARC_START_ANGLE;
    float sweep_deg = (float)ARC_SWEEP_ANGLE;

    for (int i = 0; i <= SPEED_TICKS; i++) {
        float tick_angle_deg = start_deg + sweep_deg * i / SPEED_TICKS;
        float tick_rad = tick_angle_deg * (float)M_PI / 180.0f;

        /* Outer point */
        int16_t x1 = ARC_CENTER_X + (int16_t)(ARC_TICK_RADIUS_OUT * cosf(tick_rad));
        int16_t y1 = ARC_CENTER_Y + (int16_t)(ARC_TICK_RADIUS_OUT * sinf(tick_rad));

        /* Inner point */
        int16_t x2 = ARC_CENTER_X + (int16_t)(ARC_TICK_RADIUS_IN * cosf(tick_rad));
        int16_t y2 = ARC_CENTER_Y + (int16_t)(ARC_TICK_RADIUS_IN * sinf(tick_rad));

        /* Use white for active ticks, gray for inactive */
        uint16_t color = COLOR_TICK;
        int16_t tick_speed_x10 = i * (SPEED_MAX_X10 / SPEED_TICKS);
        if (s_target_speed_x10 >= tick_speed_x10) {
            color = COLOR_TICK_ACTIVE;
        }

        drv_lcd_draw_line(x1, y1, x2, y2, color);
    }
}

/**
 * @brief Draw the large speed number centered (Forza style: big, bold, white)
 *        Format: "X.X" for 0.0-20.0
 */
static void draw_speed_number(void)
{
    /* Clear the number area */
    drv_lcd_fill_rect(30, SPEED_NUM_Y, 180, 16 * 4, COLOR_BG);

    char speed_str[16];
    int16_t whole = s_target_speed_x10 / 10;
    int16_t frac  = s_target_speed_x10 % 10;
    snprintf(speed_str, sizeof(speed_str), "%d.%d", whole, frac);

    /* Draw with scale 4 (large, bold — Forza style) */
    draw_text_centered(SPEED_NUM_Y, speed_str, COLOR_SPEED_NUM, 4);
}

/**
 * @brief Draw the "km/h" unit label (Forza style: small, gray, below number)
 */
static void draw_unit_label(void)
{
    draw_text_centered(UNIT_Y, "km/h", COLOR_UNIT, 2);
}

/**
 * @brief Draw the status indicator (RUNNING/READY)
 */
static void draw_status(void)
{
    /* Clear status area */
    drv_lcd_fill_rect(30, STATUS_Y, 180, 16 * 2, COLOR_BG);

    if (s_treadmill_running) {
        draw_text_centered(STATUS_Y, "RUNNING", COLOR_RUNNING, 2);
    } else {
        draw_text_centered(STATUS_Y, "READY", COLOR_UNIT, 2);
    }
}

/* ══════ Optimized Partial Arc Update ══════
 * Full pixel-by-pixel arc redraw is expensive (~23k pixels to check).
 * For partial updates, we only redraw the changed segment.
 */

/**
 * @brief Redraw only the arc portion that changed between old and new fill levels
 */
static void update_arc_partial(int16_t old_speed, int16_t new_speed)
{
    /* Convert speeds to fill percentages */
    uint8_t old_pct = (old_speed < 0) ? 0 : (uint8_t)((uint32_t)old_speed * 100 / SPEED_MAX_X10);
    uint8_t new_pct = (uint8_t)((uint32_t)new_speed * 100 / SPEED_MAX_X10);

    if (old_pct > 100) old_pct = 100;
    if (new_pct > 100) new_pct = 100;

    /* Determine the angular range that needs redrawing */
    float start_deg = (float)ARC_START_ANGLE;
    float sweep_deg = (float)ARC_SWEEP_ANGLE;

    float old_fill_sweep = sweep_deg * old_pct / 100.0f;
    float new_fill_sweep = sweep_deg * new_pct / 100.0f;

    /* Only redraw the delta region */
    float redraw_start, redraw_end;
    if (new_pct > old_pct) {
        /* Growing: redraw from old end to new end (fill with color) */
        redraw_start = old_fill_sweep;
        redraw_end = new_fill_sweep;
    } else {
        /* Shrinking: redraw from new end to old end (fill with bg) */
        redraw_start = new_fill_sweep;
        redraw_end = old_fill_sweep;
    }

    int16_t r_out = ARC_RADIUS_OUTER;
    int16_t r_in  = ARC_RADIUS_INNER;
    int32_t r_out_sq = (int32_t)r_out * r_out;
    int32_t r_in_sq  = (int32_t)r_in * r_in;

    int16_t x_min = ARC_CENTER_X - r_out;
    int16_t x_max = ARC_CENTER_X + r_out;
    int16_t y_min = ARC_CENTER_Y - r_out;
    int16_t y_max = ARC_CENTER_Y + r_out;

    if (x_min < 0) x_min = 0;
    if (y_min < 0) y_min = 0;
    if (x_max >= LCD_WIDTH) x_max = LCD_WIDTH - 1;
    if (y_max >= LCD_HEIGHT) y_max = LCD_HEIGHT - 1;

    for (int16_t py = y_min; py <= y_max; py++) {
        int16_t dy = py - ARC_CENTER_Y;
        int32_t dy_sq = (int32_t)dy * dy;

        for (int16_t px = x_min; px <= x_max; px++) {
            int16_t dx = px - ARC_CENTER_X;
            int32_t dist_sq = (int32_t)dx * dx + dy_sq;

            if (dist_sq < r_in_sq || dist_sq > r_out_sq) continue;

            float angle = atan2f((float)dy, (float)dx) * 180.0f / (float)M_PI;
            angle = normalize_angle(angle);

            if (!angle_in_range(angle, start_deg, sweep_deg)) continue;

            float pixel_sweep = normalize_angle(angle - start_deg);

            /* Only process pixels in the delta region */
            if (pixel_sweep < redraw_start || pixel_sweep > redraw_end) continue;

            if (pixel_sweep <= new_fill_sweep) {
                /* Should be filled */
                uint8_t local_pct = (uint8_t)(pixel_sweep * 100.0f / sweep_deg);
                uint16_t color = get_arc_color(local_pct);
                drv_lcd_fill_rect(px, py, 1, 1, color);
            } else {
                /* Should be background */
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

/* ══════ Full Screen Draw ══════ */

static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);

    /* Draw the arc gauge */
    uint8_t fill_pct = (uint8_t)((uint32_t)s_target_speed_x10 * 100 / SPEED_MAX_X10);
    draw_arc_gauge(fill_pct);

    /* Draw tick marks */
    draw_tick_marks();

    /* Draw speed number */
    draw_speed_number();

    /* Draw unit */
    draw_unit_label();

    /* Draw status */
    draw_status();

    s_last_drawn_speed = s_target_speed_x10;
    s_last_drawn_running = s_treadmill_running;
}

/* ══════ Public API ══════ */

void ui_treadmill_enter(void)
{
    s_need_full_redraw = 1;
    s_last_drawn_speed = -1;
    s_last_drawn_running = 0xFF;
    ESP_LOGI(TAG, "Treadmill UI entered (Forza style), speed=%d.%d running=%d",
             s_target_speed_x10 / 10, s_target_speed_x10 % 10,
             s_treadmill_running);
}

void ui_treadmill_update(void)
{
    /* Full redraw on enter */
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
            /* Adjust speed: step 5 = 0.5 km/h per detent */
            s_target_speed_x10 += evt.delta * 5;
            if (s_target_speed_x10 < 0) s_target_speed_x10 = 0;
            if (s_target_speed_x10 > SPEED_MAX_X10) s_target_speed_x10 = SPEED_MAX_X10;

            /* Send speed update via BLE */
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_SPEED:%d.%d\n",
                         s_target_speed_x10 / 10, s_target_speed_x10 % 10);
                ble_service_notify_str(buf);
            }
            break;
        }

        case ENC_EVT_CLICK:
            /* Toggle start/stop */
            s_treadmill_running = !s_treadmill_running;
            ESP_LOGI(TAG, "Treadmill %s, speed=%d.%d",
                     s_treadmill_running ? "STARTED" : "STOPPED",
                     s_target_speed_x10 / 10, s_target_speed_x10 % 10);

            /* Send start/stop via BLE */
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_RUN:%d\n", s_treadmill_running);
                ble_service_notify_str(buf);
            }
            break;

        case ENC_EVT_LONG_PRESS:
        case ENC_EVT_DOUBLE_CLICK:
            /* Return to menu */
            ui_manager_set_ui(5);
            return;

        default:
            break;
        }
    }

    /* Partial updates — only redraw what changed */
    if (s_target_speed_x10 != s_last_drawn_speed) {
        /* Update arc (partial redraw for performance) */
        update_arc_partial(s_last_drawn_speed, s_target_speed_x10);

        /* Update tick marks */
        draw_tick_marks();

        /* Update speed number */
        draw_speed_number();

        s_last_drawn_speed = s_target_speed_x10;
    }

    if (s_treadmill_running != s_last_drawn_running) {
        draw_status();
        s_last_drawn_running = s_treadmill_running;
    }
}
