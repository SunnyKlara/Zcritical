#include "ui_speed.h"
#include "ui_common.h"
#include "ui_images.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "drv_pwm.h"
#include "drv_gpio.h"
#include "ble_service.h"
#include "audio_engine.h"
#include "audio_player.h"
#include "board_config.h"
#include <stdio.h>

/* UI1 - Speed Control + Throttle Mode
 *
 * Rendering strategy (flicker-free):
 *   - Full redraw only on enter(): background + wind gauge + all elements
 *   - Encoder rotation: only clear+redraw number area
 *   - Unit/LED change: only redraw unit label + LED (small area)
 */

static uint8_t  s_need_full_redraw = 1;
static int16_t  s_last_speed = -1;
static uint8_t  s_last_unit = 0xFF;
static uint8_t  s_last_wuhuaqi = 0xFF;
static uint8_t  s_throttle_mode = 0;

static void draw_speed_screen(void)
{
    int16_t spd_kmh = g_app_state.current_speed_kmh;
    uint8_t unit = g_app_state.speed_unit;
    int16_t display_spd;

    if (unit == 0) {
        display_spd = (int16_t)(spd_kmh * 3.4f + 0.5f);
        if (display_spd > 340) display_spd = 340;
    } else {
        display_spd = (int16_t)(spd_kmh * 3.4f * 0.621371f + 0.5f);
        if (display_spd > 211) display_spd = 211;
    }

    uint8_t wuhuaqi = g_app_state.wuhuaqi_state;

    /* Full redraw: only on enter() */
    if (s_need_full_redraw) {
        ui_draw_f4_background();
        ui_blit_f4_image(F4_FENGSHUBIAO_X, F4_FENGSHUBIAO_Y,
                         F4_FENGSHUBIAO_WIDTH, F4_FENGSHUBIAO_HIGH,
                         gImage_fengshubiao_202_43);

        /* Draw number — clear area matches F4: LCD_Fill(15, y_qi, 155, y_qi+speed_num_high) */
        drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                      (uint16_t)display_spd, F4_JIANJU);

        /* Draw unit + LED */
        drv_lcd_fill_rect(F4_SPEED_KMH_X, F4_SPEED_KMH_Y,
                          F4_SPEED_KMH_WIDTH + F4_H_DENG_WIDTH,
                          F4_H_DENG_HIGH, 0x0000);
        if (unit == 0) {
            ui_blit_f4_image(F4_SPEED_KMH_X, F4_SPEED_KMH_Y,
                             F4_SPEED_KMH_WIDTH, F4_SPEED_KMH_HIGH,
                             gImage_speed_kmh_6225);
        } else {
            ui_blit_f4_image(F4_SPEED_MPH_X, F4_SPEED_MPH_Y,
                             F4_SPEED_MPH_WIDTH, F4_SPEED_MPH_HIGH,
                             gImage_speed_mph_5225);
        }
        uint16_t led_x = (unit == 0)
            ? F4_SPEED_KMH_X + F4_SPEED_KMH_WIDTH
            : F4_SPEED_MPH_X + F4_SPEED_MPH_WIDTH;
        uint8_t led_state = (wuhuaqi == 2) ? 2 : (wuhuaqi == 1) ? 1 : 0;
        ui_draw_f4_led(led_x, F4_SPEED_KMH_Y, led_state);

        s_last_speed = display_spd;
        s_last_unit = unit;
        s_last_wuhuaqi = wuhuaqi;
        s_need_full_redraw = 0;
        return;
    }

    /* Partial: number only — clear matches F4 exactly */
    if (display_spd != s_last_speed) {
        drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);
        ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                      (uint16_t)display_spd, F4_JIANJU);
        s_last_speed = display_spd;
    }

    /* Partial: unit label + LED */
    if (unit != s_last_unit || wuhuaqi != s_last_wuhuaqi) {
        drv_lcd_fill_rect(F4_SPEED_KMH_X, F4_SPEED_KMH_Y,
                          F4_SPEED_KMH_WIDTH + F4_H_DENG_WIDTH,
                          F4_H_DENG_HIGH, 0x0000);
        if (unit == 0) {
            ui_blit_f4_image(F4_SPEED_KMH_X, F4_SPEED_KMH_Y,
                             F4_SPEED_KMH_WIDTH, F4_SPEED_KMH_HIGH,
                             gImage_speed_kmh_6225);
        } else {
            ui_blit_f4_image(F4_SPEED_MPH_X, F4_SPEED_MPH_Y,
                             F4_SPEED_MPH_WIDTH, F4_SPEED_MPH_HIGH,
                             gImage_speed_mph_5225);
        }
        uint16_t led_x = (unit == 0)
            ? F4_SPEED_KMH_X + F4_SPEED_KMH_WIDTH
            : F4_SPEED_MPH_X + F4_SPEED_MPH_WIDTH;
        uint8_t led_state = (wuhuaqi == 2) ? 2 : (wuhuaqi == 1) ? 1 : 0;
        ui_draw_f4_led(led_x, F4_SPEED_KMH_Y, led_state);
        s_last_unit = unit;
        s_last_wuhuaqi = wuhuaqi;
    }
}

/* ── Throttle mode processing (unchanged) ── */

static void throttle_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    uint32_t elapsed = now - g_app_state.throttle_last_tick;

    if (drv_encoder_button_pressed()) {
        if (elapsed >= THROTTLE_ACCEL_MS) {
            g_app_state.throttle_last_tick = now;
            if (g_app_state.current_speed_kmh < 100)
                g_app_state.current_speed_kmh++;
            uint8_t fan = (uint8_t)((g_app_state.current_speed_kmh * 100 + 50) / 100);
            if (fan > 100) fan = 100;
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);
        }
    } else {
        if (elapsed >= THROTTLE_DECEL_MS && g_app_state.current_speed_kmh > 0) {
            g_app_state.throttle_last_tick = now;
            g_app_state.current_speed_kmh--;
            uint8_t fan = (uint8_t)((g_app_state.current_speed_kmh * 100 + 50) / 100);
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);

            if (g_app_state.current_speed_kmh == 0) {
                s_throttle_mode = 0;
                g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
                g_app_state.fan_speed = 0;
                drv_pwm_set_duty(0);
                if (g_app_state.wuhuaqi_state == 0)
                    drv_gpio_set_humidifier(false);
                ble_service_notify_str("THROTTLE_REPORT:0\n");
                audio_engine_set_throttle_mode(false);
            }
        }
    }
}

void ui_speed_enter(void)
{
    s_need_full_redraw = 1;
    s_last_speed = -1;
    s_last_unit = 0xFF;
    s_last_wuhuaqi = 0xFF;
    s_throttle_mode = 0;

    /* Start engine sound when entering speed UI */
    audio_player_start_engine();
    audio_player_set_engine_volume((uint8_t)g_app_state.current_speed_kmh);
}

void ui_speed_update(void)
{
    /* Throttle mode */
    if (s_throttle_mode || g_app_state.wuhuaqi_state == 2) {
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
                audio_engine_set_throttle_mode(false);
                ble_service_notify_str("THROTTLE_REPORT:0\n");
                break;
            }
        }
        if (s_throttle_mode || g_app_state.wuhuaqi_state == 2) {
            throttle_process();
        }
        draw_speed_screen();
        return;
    }

    /* Normal mode */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE:
            g_app_state.current_speed_kmh += evt.delta;
            if (g_app_state.current_speed_kmh < 0) g_app_state.current_speed_kmh = 0;
            if (g_app_state.current_speed_kmh > 100) g_app_state.current_speed_kmh = 100;
            g_app_state.fan_speed = (uint8_t)g_app_state.current_speed_kmh;
            drv_pwm_set_duty(g_app_state.fan_speed);
            /* Update engine sound volume with speed */
            audio_player_set_engine_volume((uint8_t)g_app_state.current_speed_kmh);
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
            g_app_state.speed_unit ^= 1;
            {
                char buf[32];
                snprintf(buf, sizeof(buf), "UNIT_REPORT:%d\n", g_app_state.speed_unit);
                ble_service_notify_str(buf);
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            audio_player_stop_engine();
            ui_manager_set_ui(5);
            return;

        case ENC_EVT_TRIPLE_CLICK:
            s_throttle_mode = 1;
            g_app_state.wuhuaqi_state_saved = g_app_state.wuhuaqi_state;
            g_app_state.wuhuaqi_state = 2;
            g_app_state.throttle_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
            g_app_state.throttle_initialized = 1;
            drv_gpio_set_humidifier(true);
            audio_engine_set_throttle_mode(true);
            ble_service_notify_str("THROTTLE_REPORT:1\n");
            break;

        default: break;
        }
    }

    if (g_app_state.remote_active_tick) {
        uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
        if (now - g_app_state.remote_active_tick < REMOTE_FREEZE_WINDOW_MS) {
            /* Remote speed update — just let draw_speed_screen detect the change */
        }
    }

    draw_speed_screen();
}
