#include "ui_speed.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "drv_pwm.h"
#include "drv_gpio.h"
#include "ble_service.h"
#include "board_config.h"
#include "esp_log.h"
#include <stdio.h>

/* UI1 - Speed Control + Throttle Mode
 * Encoder rotation adjusts speed (0-340 km/h or 0-211 mph).
 * Single-click toggles unit (km/h <-> mph).
 * Double-click saves and returns to UI5.
 * Triple-click enters Throttle_Mode. */

static uint8_t  s_need_redraw = 1;
static int16_t  s_last_speed = -1;
static uint8_t  s_last_unit = 0xFF;
static uint8_t  s_throttle_mode = 0;

static uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

static void draw_speed_screen(void)
{
    int16_t spd_kmh = g_app_state.current_speed_kmh;
    uint8_t unit = g_app_state.speed_unit;
    int16_t display_spd;
    const char *unit_str;

    if (unit == 0) {
        display_spd = (int16_t)(spd_kmh * 3.4f + 0.5f);
        if (display_spd > 340) display_spd = 340;
        unit_str = "km/h";
    } else {
        display_spd = (int16_t)(spd_kmh * 3.4f * 0.621371f + 0.5f);
        if (display_spd > 211) display_spd = 211;
        unit_str = "mph";
    }

    /* Only redraw changed parts */
    if (display_spd != s_last_speed || unit != s_last_unit || s_need_redraw) {
        if (s_need_redraw) {
            drv_lcd_clear(0x0000);
            drv_lcd_draw_circle(120, 120, 118, rgb565(0x20, 0x20, 0x20), false);
        }

        /* Clear speed number area */
        drv_lcd_fill_rect(30, 70, 180, 60, 0x0000);
        /* Draw speed number */
        char buf[8];
        snprintf(buf, sizeof(buf), "%d", display_spd);
        uint8_t len = 0;
        while (buf[len]) len++;
        uint16_t x = (240 - len * 24) / 2;  /* size=3 -> 24px wide */
        drv_lcd_draw_string(x, 80, buf, 0xFFFF, 0x0000, 3);

        /* Unit string */
        drv_lcd_fill_rect(70, 145, 100, 25, 0x0000);
        uint8_t ulen = 0;
        while (unit_str[ulen]) ulen++;
        uint16_t ux = (240 - ulen * 8) / 2;
        drv_lcd_draw_string(ux, 150, unit_str, rgb565(0x80, 0x80, 0x80), 0x0000, 1);

        /* Throttle indicator */
        if (s_throttle_mode || g_app_state.wuhuaqi_state == 2) {
            uint16_t dot_color = rgb565(0xFF, 0x80, 0x00);  /* orange */
            drv_lcd_draw_circle(120, 190, 5, dot_color, true);
        } else {
            /* Humidifier state dot: green=on, red=off */
            uint16_t dot_color = (g_app_state.wuhuaqi_state == 1)
                ? rgb565(0x00, 0xFF, 0x00) : rgb565(0xFF, 0x00, 0x00);
            drv_lcd_draw_circle(120, 190, 5, dot_color, true);
        }

        s_last_speed = display_spd;
        s_last_unit = unit;
        s_need_redraw = 0;
    }
}

static void throttle_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    uint32_t elapsed = now - g_app_state.throttle_last_tick;

    if (drv_encoder_button_pressed()) {
        /* Accelerate */
        if (elapsed >= THROTTLE_ACCEL_MS) {
            g_app_state.throttle_last_tick = now;
            if (g_app_state.current_speed_kmh < 100)
                g_app_state.current_speed_kmh++;
            uint8_t fan = (uint8_t)((g_app_state.current_speed_kmh * 100 + 50) / 100);
            if (fan > 100) fan = 100;
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);
            s_need_redraw = 1;
        }
    } else {
        /* Decelerate */
        if (elapsed >= THROTTLE_DECEL_MS && g_app_state.current_speed_kmh > 0) {
            g_app_state.throttle_last_tick = now;
            g_app_state.current_speed_kmh--;
            uint8_t fan = (uint8_t)((g_app_state.current_speed_kmh * 100 + 50) / 100);
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);
            s_need_redraw = 1;

            if (g_app_state.current_speed_kmh == 0) {
                /* Exit throttle mode */
                s_throttle_mode = 0;
                g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
                g_app_state.fan_speed = 0;
                drv_pwm_set_duty(0);
                if (g_app_state.wuhuaqi_state == 0)
                    drv_gpio_set_humidifier(false);
                ble_service_notify_str("THROTTLE_REPORT:0\n");
            }
        }
    }
}

void ui_speed_enter(void)
{
    s_need_redraw = 1;
    s_last_speed = -1;
    s_last_unit = 0xFF;
    s_throttle_mode = 0;
}

void ui_speed_update(void)
{

    /* Throttle mode processing */
    if (s_throttle_mode || g_app_state.wuhuaqi_state == 2) {
        /* Check for rotation to exit throttle */
        encoder_event_t evt;
        while (drv_encoder_poll(&evt)) {
            if (evt.type == ENC_EVT_ROTATE) {
                s_throttle_mode = 0;
                g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
                g_app_state.fan_speed = 0;
                g_app_state.current_speed_kmh = 0;
                drv_pwm_set_duty(0);
                if (g_app_state.wuhuaqi_state == 0)
                    drv_gpio_set_humidifier(false);
                ble_service_notify_str("THROTTLE_REPORT:0\n");
                s_need_redraw = 1;
                break;
            }
        }
        if (s_throttle_mode || g_app_state.wuhuaqi_state == 2) {
            throttle_process();
        }
        if (s_need_redraw) draw_speed_screen();
        return;
    }

    /* Normal mode: process encoder events */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE:
            g_app_state.current_speed_kmh += evt.delta;
            if (g_app_state.current_speed_kmh < 0) g_app_state.current_speed_kmh = 0;
            if (g_app_state.current_speed_kmh > 100) g_app_state.current_speed_kmh = 100;
            /* Sync fan PWM proportionally */
            g_app_state.fan_speed = (uint8_t)g_app_state.current_speed_kmh;
            drv_pwm_set_duty(g_app_state.fan_speed);
            s_need_redraw = 1;
            /* Report speed */
            {
                char buf[48];
                int16_t disp = g_app_state.speed_unit == 0
                    ? (int16_t)(g_app_state.current_speed_kmh * 3.4f + 0.5f)
                    : (int16_t)(g_app_state.current_speed_kmh * 3.4f * 0.621371f + 0.5f);
                snprintf(buf, sizeof(buf), "SPEED_REPORT:%d:%d\n", disp, g_app_state.speed_unit);
                ble_service_notify_str(buf);
            }
            break;

        case ENC_EVT_CLICK:
            /* Toggle unit */
            g_app_state.speed_unit ^= 1;
            s_need_redraw = 1;
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "UNIT_REPORT:%d\n", g_app_state.speed_unit);
                ble_service_notify_str(buf);
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            /* Save and return to menu */
            ui_manager_set_ui(5);
            return;

        case ENC_EVT_TRIPLE_CLICK:
            /* Enter throttle mode */
            s_throttle_mode = 1;
            g_app_state.wuhuaqi_state_saved = g_app_state.wuhuaqi_state;
            g_app_state.wuhuaqi_state = 2;
            g_app_state.throttle_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
            g_app_state.throttle_initialized = 1;
            drv_gpio_set_humidifier(true);
            ble_service_notify_str("THROTTLE_REPORT:1\n");
            s_need_redraw = 1;
            break;

        default: break;
        }
    }

    /* Check for remote speed freeze */
    if (g_app_state.remote_active_tick) {
        uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
        if (now - g_app_state.remote_active_tick < REMOTE_FREEZE_WINDOW_MS) {
            s_need_redraw = 1;
        }
    }

    if (s_need_redraw) draw_speed_screen();
}
