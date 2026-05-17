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
 * @brief UI8 — Treadmill control (Forza arc + F4 digits + throttle mode)
 *
 * Visual:
 *   - 270° thin arc gauge (Forza Horizon style, gradient white→red)
 *   - Large F4 digit bitmaps centered inside arc (integer 0-20)
 *   - No text, no labels, no decimal
 *   - Running indicator: green dot below number
 *
 * Controls (throttle mode, same as Speed UI):
 *   Hold button:    Accelerate (0→20)
 *   Release:        Decelerate (→0)
 *   Double click:   Return to menu
 *   Long press:     Return to menu
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static int16_t  s_treadmill_speed = 0;     /* 0-20 integer */
static int16_t  s_last_drawn_speed = -1;
static uint32_t s_last_tick = 0;

/* ── Timing ── */
#define TREAD_ACCEL_MS      150
#define TREAD_DECEL_MS      100
#define TREAD_MAX_SPEED     20

/* ── Colors ── */
#define COLOR_BG            0x0000
#define COLOR_ARC_BG        0x18E3   /* Very dark gray */

/* ── Arc Geometry ── */
#define ARC_CX              120
#define ARC_CY              120
#define ARC_R_OUTER         108
#define ARC_R_INNER         104      /* 4px thickness */
#define ARC_START_DEG       135.0f
#define ARC_SWEEP_DEG       270.0f

/* ── Number Layout — 直接使用 Speed UI 的 F4 坐标 (F4_X_QI, F4_Y_QI, F4_JIANJU) ── */

/* ── Indicator ── */
/* 已移除 — 不需要指示点 */

/* ══════ Arc Gradient Color ══════ */
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

/* ══════ Arc Drawing ══════ */

/**
 * 角度归一化：将 atan2 结果转为相对于 ARC_START_DEG 的偏移量
 * 返回值 [0, 360)，其中 0 = 弧的起点，ARC_SWEEP_DEG = 弧的终点
 * 超过 ARC_SWEEP_DEG 的像素不属于弧
 */
static float angle_to_arc_pos(float raw_deg)
{
    /* raw_deg 是 atan2 结果 [-180, 180]，先归一到 [0, 360) */
    if (raw_deg < 0.0f) raw_deg += 360.0f;
    /* 计算相对于起始角的偏移 */
    float rel = raw_deg - ARC_START_DEG;
    if (rel < 0.0f) rel += 360.0f;
    return rel;
}

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
        int32_t x_range = r_out_sq - dy_sq;
        if (x_range < 0) continue;

        int16_t dx_max = (int16_t)sqrtf((float)x_range);
        int16_t px_s = ARC_CX - dx_max;
        int16_t px_e = ARC_CX + dx_max;
        if (px_s < 0) px_s = 0;
        if (px_e >= LCD_WIDTH) px_e = LCD_WIDTH - 1;

        for (int16_t px = px_s; px <= px_e; px++) {
            int16_t dx = px - ARC_CX;
            int32_t d_sq = (int32_t)dx * dx + dy_sq;
            if (d_sq < r_in_sq || d_sq > r_out_sq) continue;

            float raw_deg = atan2f((float)dy, (float)dx) * (180.0f / (float)M_PI);
            float rel = angle_to_arc_pos(raw_deg);
            if (rel > ARC_SWEEP_DEG + 0.5f) continue;  /* +0.5 容差 */

            if (rel <= fill_sweep) {
                uint8_t pos = (uint8_t)(rel * 100.0f / ARC_SWEEP_DEG);
                drv_lcd_fill_rect(px, py, 1, 1, arc_color(pos));
            } else {
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

static void update_arc_delta(int16_t old_spd, int16_t new_spd)
{
    uint8_t old_pct = (old_spd <= 0) ? 0 : (uint8_t)((uint32_t)old_spd * 100 / TREAD_MAX_SPEED);
    uint8_t new_pct = (uint8_t)((uint32_t)new_spd * 100 / TREAD_MAX_SPEED);
    if (old_pct > 100) old_pct = 100;
    if (new_pct > 100) new_pct = 100;
    if (old_pct == new_pct) return;

    float old_sw = ARC_SWEEP_DEG * old_pct / 100.0f;
    float new_sw = ARC_SWEEP_DEG * new_pct / 100.0f;
    float lo = (new_pct > old_pct) ? old_sw : new_sw;
    float hi = (new_pct > old_pct) ? new_sw : old_sw;

    int32_t r_out_sq = (int32_t)ARC_R_OUTER * ARC_R_OUTER;
    int32_t r_in_sq  = (int32_t)ARC_R_INNER * ARC_R_INNER;

    int16_t scan_min = ARC_CY - ARC_R_OUTER;
    int16_t scan_max = ARC_CY + ARC_R_OUTER;
    if (scan_min < 0) scan_min = 0;
    if (scan_max >= LCD_HEIGHT) scan_max = LCD_HEIGHT - 1;

    for (int16_t py = scan_min; py <= scan_max; py++) {
        int16_t dy = py - ARC_CY;
        int32_t dy_sq = (int32_t)dy * dy;
        int32_t x_range = r_out_sq - dy_sq;
        if (x_range < 0) continue;

        int16_t dx_max = (int16_t)sqrtf((float)x_range);
        int16_t px_s = ARC_CX - dx_max;
        int16_t px_e = ARC_CX + dx_max;
        if (px_s < 0) px_s = 0;
        if (px_e >= LCD_WIDTH) px_e = LCD_WIDTH - 1;

        for (int16_t px = px_s; px <= px_e; px++) {
            int16_t dx = px - ARC_CX;
            int32_t d_sq = (int32_t)dx * dx + dy_sq;
            if (d_sq < r_in_sq || d_sq > r_out_sq) continue;

            float raw_deg = atan2f((float)dy, (float)dx) * (180.0f / (float)M_PI);
            float rel = angle_to_arc_pos(raw_deg);
            if (rel > ARC_SWEEP_DEG + 0.5f) continue;

            /* 只处理变化区域 */
            if (rel < lo - 0.5f || rel > hi + 0.5f) continue;

            if (rel <= new_sw) {
                uint8_t pos = (uint8_t)(rel * 100.0f / ARC_SWEEP_DEG);
                drv_lcd_fill_rect(px, py, 1, 1, arc_color(pos));
            } else {
                drv_lcd_fill_rect(px, py, 1, 1, COLOR_ARC_BG);
            }
        }
    }
}

/* ══════ Number Drawing ══════
 * 完全参考 Speed UI (ui_speed.c) 的 draw_speed_screen():
 * - 清除区域: drv_lcd_fill_rect(15, F4_Y_QI, 155-15, F4_SPEED_NUM_HIGH, 0x0000)
 * - 渲染: ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI, display_spd, F4_JIANJU)
 * 跑步机显示 0-20，直接用相同函数和坐标
 */

static void draw_number(void)
{
    /* 精确清除 — 和 Speed 完全一样的区域 */
    drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);

    /* 右对齐渲染，和 Speed 完全相同 */
    ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                  (uint16_t)s_treadmill_speed, F4_JIANJU);
}

/* ══════ Full Screen ══════ */

static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);
    uint8_t pct = (uint8_t)((uint32_t)s_treadmill_speed * 100 / TREAD_MAX_SPEED);
    draw_arc(pct);
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
            /* 双击退出到菜单（长按是加速，不能用来退出） */
            ui_manager_set_ui(5);
            return;
        }
        /* 其他事件忽略 — 油门模式通过 raw GPIO 检测按住状态 */
    }

    throttle_process();

    if (s_treadmill_speed != s_last_drawn_speed) {
        update_arc_delta(s_last_drawn_speed, s_treadmill_speed);
        draw_number();
        s_last_drawn_speed = s_treadmill_speed;
    }
}
