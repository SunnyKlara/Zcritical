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

/**
 * @file ui_treadmill.c
 * @brief UI8 — Treadmill control page
 *
 * LCD layout (240×240):
 *   Top:    "TREADMILL" title (font_8x16 rendered)
 *   Center: Large speed number (0-20 km/h)
 *   Bottom: Status bar (STOPPED / RUNNING)
 *
 * Controls:
 *   Rotate:     Adjust target speed (0-20 km/h, step 0.5)
 *   Click:      Start / Stop treadmill
 *   Long press: Save and return to menu
 *   Double click: Return to menu
 */

static const char *TAG = "UI_TREAD";

/* ── State ── */
static uint8_t  s_need_full_redraw = 1;
static uint8_t  s_treadmill_running = 0;
static int16_t  s_target_speed_x10 = 0;   /* 0-200 (represents 0.0-20.0 km/h) */
static int16_t  s_last_drawn_speed = -1;
static uint8_t  s_last_drawn_running = 0xFF;

/* ── Colors ── */
#define COLOR_TITLE     0x07FF   /* Cyan */
#define COLOR_SPEED     0xFFFF   /* White */
#define COLOR_RUNNING   0x07E0   /* Green */
#define COLOR_STOPPED   0xF800   /* Red */
#define COLOR_UNIT      0xBDF7   /* Light gray */
#define COLOR_BG        0x0000   /* Black */

/* ── Layout constants ── */
#define TITLE_Y         20
#define SPEED_Y         70
#define SPEED_NUM_H     60
#define STATUS_Y        180
#define UNIT_Y          140

/* ── Simple text rendering using font_8x16 ── */
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

/* ── Drawing ── */

static void draw_full_screen(void)
{
    drv_lcd_clear(COLOR_BG);

    /* Title */
    draw_text_centered(TITLE_Y, "TREADMILL", COLOR_TITLE, 2);

    /* Speed number */
    char speed_str[16];
    snprintf(speed_str, sizeof(speed_str), "%d.%d",
             s_target_speed_x10 / 10, s_target_speed_x10 % 10);
    draw_text_centered(SPEED_Y, speed_str, COLOR_SPEED, 4);

    /* Unit */
    draw_text_centered(UNIT_Y, "km/h", COLOR_UNIT, 2);

    /* Status */
    if (s_treadmill_running) {
        draw_text_centered(STATUS_Y, "RUNNING", COLOR_RUNNING, 2);
    } else {
        draw_text_centered(STATUS_Y, "STOPPED", COLOR_STOPPED, 2);
    }

    /* Hint at bottom */
    draw_text_centered(220, "Click:Start/Stop  Hold:Back", COLOR_UNIT, 1);

    s_last_drawn_speed = s_target_speed_x10;
    s_last_drawn_running = s_treadmill_running;
}

static void update_speed_display(void)
{
    /* Clear speed area */
    drv_lcd_fill_rect(0, SPEED_Y, LCD_WIDTH, 16 * 4, COLOR_BG);

    char speed_str[16];
    snprintf(speed_str, sizeof(speed_str), "%d.%d",
             s_target_speed_x10 / 10, s_target_speed_x10 % 10);
    draw_text_centered(SPEED_Y, speed_str, COLOR_SPEED, 4);

    s_last_drawn_speed = s_target_speed_x10;
}

static void update_status_display(void)
{
    /* Clear status area */
    drv_lcd_fill_rect(0, STATUS_Y, LCD_WIDTH, 16 * 2, COLOR_BG);

    if (s_treadmill_running) {
        draw_text_centered(STATUS_Y, "RUNNING", COLOR_RUNNING, 2);
    } else {
        draw_text_centered(STATUS_Y, "STOPPED", COLOR_STOPPED, 2);
    }

    s_last_drawn_running = s_treadmill_running;
}

/* ── Public API ── */

void ui_treadmill_enter(void)
{
    s_need_full_redraw = 1;
    s_last_drawn_speed = -1;
    s_last_drawn_running = 0xFF;
    /* Don't reset speed/running state — preserve across menu visits */
    ESP_LOGI(TAG, "Treadmill UI entered, speed=%d.%d running=%d",
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
            if (s_target_speed_x10 > 200) s_target_speed_x10 = 200;

            /* TODO: Send treadmill speed command via BLE when protocol is defined */
            /* Example: ble_service_notify_str("TREADMILL_SPEED:xx\r\n"); */

            break;
        }

        case ENC_EVT_CLICK:
            /* Toggle start/stop */
            s_treadmill_running = !s_treadmill_running;
            ESP_LOGI(TAG, "Treadmill %s, speed=%d.%d",
                     s_treadmill_running ? "STARTED" : "STOPPED",
                     s_target_speed_x10 / 10, s_target_speed_x10 % 10);

            /* TODO: Send treadmill start/stop command via BLE */
            /* Example: ble_service_notify_str("TREADMILL:1\r\n"); */

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

    /* Partial updates */
    if (s_target_speed_x10 != s_last_drawn_speed) {
        update_speed_display();
    }
    if (s_treadmill_running != s_last_drawn_running) {
        update_status_display();
    }
}
