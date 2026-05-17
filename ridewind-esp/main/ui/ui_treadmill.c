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

/**
 * @file ui_treadmill.c
 * @brief UI8 — Treadmill control page (v3 — mirrors Speed UI design)
 *
 * Design philosophy: Same visual language as Speed (UI1)
 *   - F4 background image
 *   - Large white F4 digit bitmaps, right-aligned
 *   - Horizontal white bar below number (tracks speed %)
 *   - Throttle mode: hold button = accelerate, release = decelerate
 *   - No text labels, no arc, no decimal — pure integer 0-20
 *
 * Layout (240×240, same positions as Speed UI):
 *   - Background: gImage_beijing_240_240
 *   - Number: right-aligned at (F4_X_QI, F4_Y_QI), jianju=-2
 *   - Bar: below number, white, width proportional to speed
 *
 * Controls (throttle mode, like Speed's oil-gate mode):
 *   Hold button:   Accelerate (0→20, step 1 per tick)
 *   Release:       Decelerate back to 0
 *   Double click:  Return to menu
 *   Long press:    Return to menu
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static int16_t  s_treadmill_speed = 0;     /* 0-20 integer */
static int16_t  s_last_drawn_speed = -1;
static uint8_t  s_last_bar_w = 0;
static uint32_t s_last_tick = 0;

/* ── Timing ── */
#define TREAD_ACCEL_MS      150    /* ms per speed step when holding */
#define TREAD_DECEL_MS      100    /* ms per speed step when releasing */
#define TREAD_MAX_SPEED     20

/* ── Bar layout (below number, like speed's throttle bar) ── */
#define BAR_X               20
#define BAR_Y               (F4_Y_QI + F4_SPEED_NUM_HIGH + 4)
#define BAR_MAX_W           200
#define BAR_H               3
#define BAR_COLOR           0xFFFF  /* White */

/* ══════ Drawing ══════ */

static void draw_full_screen(void)
{
    /* F4 background (same as Speed UI) */
    ui_draw_f4_background();

    /* Draw number */
    drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);
    ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                  (uint16_t)s_treadmill_speed, F4_JIANJU);

    /* Draw bar */
    uint8_t bar_w = (uint8_t)((uint16_t)s_treadmill_speed * BAR_MAX_W / TREAD_MAX_SPEED);
    drv_lcd_fill_rect(BAR_X, BAR_Y, BAR_MAX_W, BAR_H, 0x0000);
    if (bar_w > 0) {
        drv_lcd_fill_rect(BAR_X, BAR_Y, bar_w, BAR_H, BAR_COLOR);
    }

    s_last_drawn_speed = s_treadmill_speed;
    s_last_bar_w = bar_w;
    s_need_full_redraw = 0;
}

static void update_number(void)
{
    drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);
    ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                  (uint16_t)s_treadmill_speed, F4_JIANJU);
    s_last_drawn_speed = s_treadmill_speed;
}

static void update_bar(void)
{
    uint8_t bar_w = (uint8_t)((uint16_t)s_treadmill_speed * BAR_MAX_W / TREAD_MAX_SPEED);
    if (bar_w == s_last_bar_w) return;

    drv_lcd_fill_rect(BAR_X, BAR_Y, BAR_MAX_W, BAR_H, 0x0000);
    if (bar_w > 0) {
        drv_lcd_fill_rect(BAR_X, BAR_Y, bar_w, BAR_H, BAR_COLOR);
    }
    s_last_bar_w = bar_w;
}

/* ══════ Throttle Processing ══════ */

static void throttle_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    uint32_t elapsed = now - s_last_tick;

    if (drv_encoder_button_pressed()) {
        /* Holding: accelerate */
        if (elapsed >= TREAD_ACCEL_MS) {
            s_last_tick = now;
            if (s_treadmill_speed < TREAD_MAX_SPEED) {
                s_treadmill_speed++;
                /* Notify BLE */
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_SPEED:%d\n", s_treadmill_speed);
                ble_service_notify_str(buf);
            }
        }
    } else {
        /* Released: decelerate */
        if (elapsed >= TREAD_DECEL_MS && s_treadmill_speed > 0) {
            s_last_tick = now;
            s_treadmill_speed--;
            /* Notify BLE */
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
    s_last_bar_w = 0;
    s_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
    /* Don't reset speed — preserve across menu visits */
    ESP_LOGI(TAG, "Treadmill UI entered, speed=%d", s_treadmill_speed);
}

void ui_treadmill_update(void)
{
    if (s_need_full_redraw) {
        draw_full_screen();
        return;
    }

    /* Handle encoder events (only double-click/long-press to exit) */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_DOUBLE_CLICK:
        case ENC_EVT_LONG_PRESS:
            /* Return to menu */
            ui_manager_set_ui(5);
            return;

        default:
            /* All other events ignored — throttle uses raw GPIO */
            break;
        }
    }

    /* Throttle mode: always active */
    throttle_process();

    /* Partial updates */
    if (s_treadmill_speed != s_last_drawn_speed) {
        update_number();
        update_bar();
    }
}
