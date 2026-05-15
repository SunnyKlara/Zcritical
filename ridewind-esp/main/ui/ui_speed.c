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
static uint8_t  s_last_throttle_draw = 0;  /* Was last number draw in throttle mode? */

static uint8_t s_last_throttle_bar = 0;  /* Last drawn bar width (0=none) */

/* Speed-to-color mapping for throttle mode.
 * Matches Tixing project exactly:
 *   0%  = Blue    (0, 180, 255)
 *   50% = Yellow  (255, 210, 80)
 *   100% = Red    (255, 40, 30)
 * The digit bitmaps have anti-aliased edges (gray pixels),
 * so the tint preserves smooth gradients naturally. */
static uint16_t speed_color_565(uint8_t percent)
{
    uint8_t r, g, b;
    if (percent <= 50) {
        /* Blue (0,180,255) → Yellow (255,210,80) */
        uint16_t t = (uint16_t)percent * 2;  /* 0-100 */
        r = (uint8_t)(0 + 255 * t / 100);
        g = (uint8_t)(180 + (210 - 180) * t / 100);
        b = (uint8_t)(255 - (255 - 80) * t / 100);
    } else {
        /* Yellow (255,210,80) → Red (255,40,30) */
        uint16_t t = (uint16_t)(percent - 50) * 2;  /* 0-100 */
        r = 255;
        g = (uint8_t)(210 - (210 - 40) * t / 100);
        b = (uint8_t)(80 - (80 - 30) * t / 100);
    }
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

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
    if (display_spd != s_last_speed || s_throttle_mode != s_last_throttle_draw) {
        drv_lcd_fill_rect(15, F4_Y_QI, 155 - 15, F4_SPEED_NUM_HIGH, 0x0000);
        if (s_throttle_mode) {
            /* Throttle mode: use pre-rendered colored digits (0-10 steps) */
            uint8_t ci = (uint8_t)(g_app_state.current_speed_kmh / 10);
            if (ci > 10) ci = 10;
            ui_draw_large_number_colored_ex(F4_X_QI, F4_Y_QI,
                                            (uint16_t)display_spd, F4_JIANJU, ci);
        } else {
            ui_draw_large_number_right_ex(F4_X_QI, F4_Y_QI,
                                          (uint16_t)display_spd, F4_JIANJU);
        }
        s_last_speed = display_spd;
        s_last_throttle_draw = s_throttle_mode;
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

    /* ── Throttle mode color bar (only visible in throttle mode) ── */
    /* Position: above the wind gauge, below the number area */
    #define THROTTLE_BAR_X      30
    #define THROTTLE_BAR_Y      (F4_Y_QI + F4_SPEED_NUM_HIGH + 2)
    #define THROTTLE_BAR_MAX_W  140
    #define THROTTLE_BAR_H      3

    if (s_throttle_mode) {
        uint8_t bar_w = (uint8_t)((uint16_t)g_app_state.current_speed_kmh * THROTTLE_BAR_MAX_W / 100);
        if (bar_w > THROTTLE_BAR_MAX_W) bar_w = THROTTLE_BAR_MAX_W;
        uint16_t color = speed_color_565((uint8_t)g_app_state.current_speed_kmh);

        if (bar_w != s_last_throttle_bar) {
            drv_lcd_fill_rect(THROTTLE_BAR_X, THROTTLE_BAR_Y,
                              THROTTLE_BAR_MAX_W, THROTTLE_BAR_H, 0x0000);
            if (bar_w > 0) {
                drv_lcd_fill_rect(THROTTLE_BAR_X, THROTTLE_BAR_Y,
                                  bar_w, THROTTLE_BAR_H, color);
            }
            s_last_throttle_bar = bar_w;
        }
    } else if (s_last_throttle_bar > 0) {
        /* Exited throttle — clear bar area */
        drv_lcd_fill_rect(THROTTLE_BAR_X, THROTTLE_BAR_Y,
                          THROTTLE_BAR_MAX_W, THROTTLE_BAR_H, 0x0000);
        s_last_throttle_bar = 0;
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
            audio_player_set_target_rpm((uint8_t)g_app_state.current_speed_kmh);
        }
    } else {
        if (elapsed >= THROTTLE_DECEL_MS && g_app_state.current_speed_kmh > 0) {
            g_app_state.throttle_last_tick = now;
            g_app_state.current_speed_kmh--;
            uint8_t fan = (uint8_t)((g_app_state.current_speed_kmh * 100 + 50) / 100);
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);
            audio_player_set_target_rpm((uint8_t)g_app_state.current_speed_kmh);

            if (g_app_state.current_speed_kmh == 0) {
                /* Speed hit zero — stay in throttle mode, just idle.
                 * User can press again to accelerate, or rotate encoder to exit.
                 * This prevents accidental exit when user releases briefly. */
                g_app_state.fan_speed = 0;
                drv_pwm_set_duty(0);
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

    /* Only start engine sound if speed is already non-zero */
    if (g_app_state.current_speed_kmh > 0) {
        audio_player_start_engine();
        audio_player_set_target_rpm((uint8_t)g_app_state.current_speed_kmh);
    }
}

void ui_speed_update(void)
{
    /* Sync local throttle flag with remote BLE changes */
    if (!s_throttle_mode && g_app_state.wuhuaqi_state == 2) {
        s_throttle_mode = 1;
        g_app_state.throttle_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
    } else if (s_throttle_mode && g_app_state.wuhuaqi_state != 2) {
        s_throttle_mode = 0;
    }

    /* Throttle mode */
    if (s_throttle_mode) {
        /* Throttle mode event handling:
         * - ROTATE: exit throttle, return to normal mode
         * - DOUBLE_CLICK: exit throttle AND go to menu
         * - All other button events: ignored (throttle uses raw GPIO) */
        encoder_event_t evt;
        while (drv_encoder_poll(&evt)) {
            if (evt.type == ENC_EVT_ROTATE) {
                /* Exit throttle mode — preserve current speed as normal-mode value.
                 * No decay, no reset; fan PWM stays at current_speed_kmh. */
                s_throttle_mode = 0;
                g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
                /* Keep current_speed_kmh as-is, sync fan_speed to it */
                uint8_t fan = (uint8_t)g_app_state.current_speed_kmh;
                if (fan > 100) fan = 100;
                g_app_state.fan_speed = fan;
                drv_pwm_set_duty(fan);
                if (g_app_state.wuhuaqi_state == 0)
                    drv_gpio_set_humidifier(false);
                audio_engine_set_throttle_mode(false);
                /* Stop engine sound if speed dropped to 0 already */
                if (g_app_state.current_speed_kmh == 0 && audio_player_is_playing()) {
                    audio_player_stop_engine();
                }
                ble_service_notify_str("THROTTLE_REPORT:0\n");
                {
                    char buf[48];
                    int16_t disp = g_app_state.speed_unit == 0
                        ? (int16_t)(g_app_state.current_speed_kmh * 3.4f + 0.5f)
                        : (int16_t)(g_app_state.current_speed_kmh * 3.4f * 0.621371f + 0.5f);
                    snprintf(buf, sizeof(buf), "SPEED_REPORT:%d:%d\n", disp, g_app_state.speed_unit);
                    ble_service_notify_str(buf);
                }
                break;
            }
            if (evt.type == ENC_EVT_DOUBLE_CLICK) {
                /* Double click in throttle: exit throttle + go to menu */
                s_throttle_mode = 0;
                g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
                g_app_state.current_speed_kmh = 0;
                g_app_state.fan_speed = 0;
                drv_pwm_set_duty(0);
                if (g_app_state.wuhuaqi_state == 0)
                    drv_gpio_set_humidifier(false);
                audio_engine_set_throttle_mode(false);
                audio_player_stop_engine();
                ble_service_notify_str("THROTTLE_REPORT:0\n");
                ui_manager_set_ui(5);
                return;
            }
            /* PRESS, RELEASE, CLICK, LONG_PRESS — ignored.
             * Throttle acceleration uses raw GPIO in throttle_process(). */
        }
        if (s_throttle_mode) {
            throttle_process();
        }
        draw_speed_screen();
        return;
    }

    /* Normal mode
     * ─────────────────────────────────────────────────────────────
     * Button behavior:
     *   CLICK (short press)  → Enter throttle mode (油门模式)
     *   LONG_PRESS (hold)    → Toggle atomizer (雾化器) on/off
     *   DOUBLE_CLICK         → Switch to menu/treadmill screen
     * Key distinction: the encoder driver already separates click
     * (release within BUTTON_TIMEOUT_MS) from long press (held ≥
     * LONG_PRESS_MS). Throttle mode uses raw GPIO for acceleration.
     * ───────────────────────────────────────────────────────────── */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE:
            g_app_state.current_speed_kmh += evt.delta;
            if (g_app_state.current_speed_kmh < 0) g_app_state.current_speed_kmh = 0;
            if (g_app_state.current_speed_kmh > 100) g_app_state.current_speed_kmh = 100;
            g_app_state.fan_speed = (uint8_t)g_app_state.current_speed_kmh;
            drv_pwm_set_duty(g_app_state.fan_speed);

            /* Fan power: GPIO10 (humidifier MOS) also powers the fan circuit.
             * Turn on when speed > 0, off when speed = 0 (unless atomizer is on). */
            if (g_app_state.current_speed_kmh > 0) {
                drv_gpio_set_humidifier(true);
            } else if (g_app_state.wuhuaqi_state == 0) {
                drv_gpio_set_humidifier(false);
            }

            /* Engine sound: start when speed goes above 0, stop when it hits 0 */
            if (g_app_state.current_speed_kmh > 0) {
                if (!audio_player_is_playing()) {
                    audio_player_start_engine();
                }
                audio_player_set_target_rpm((uint8_t)g_app_state.current_speed_kmh);
            } else {
                if (audio_player_is_playing()) {
                    audio_player_stop_engine();
                }
            }
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
            /* Short press → Enter throttle mode (油门模式)
             * Throttle mode: hold button = accelerate, release = decelerate */
            s_throttle_mode = 1;
            g_app_state.wuhuaqi_state_saved = g_app_state.wuhuaqi_state;
            g_app_state.wuhuaqi_state = 2;
            g_app_state.throttle_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
            g_app_state.throttle_initialized = 1;
            drv_gpio_set_humidifier(true);
            audio_engine_set_throttle_mode(true);
            if (g_app_state.current_speed_kmh == 0) {
                g_app_state.current_speed_kmh = 10;
                g_app_state.fan_speed = 10;
                drv_pwm_set_duty(10);
            }
            if (!audio_player_is_playing()) {
                audio_player_start_engine();
            }
            audio_player_set_target_rpm((uint8_t)g_app_state.current_speed_kmh);
            ble_service_notify_str("THROTTLE_REPORT:1\n");
            break;

        case ENC_EVT_LONG_PRESS:
            /* Long press in normal mode → Toggle atomizer (雾化器)
             * Only toggles on/off; does NOT enter throttle mode */
            if (g_app_state.wuhuaqi_state == 0) {
                /* Turn atomizer ON */
                g_app_state.wuhuaqi_state = 1;
                drv_gpio_set_humidifier(true);
                ble_service_notify_str("ATOMIZER:ON\n");
            } else if (g_app_state.wuhuaqi_state == 1) {
                /* Turn atomizer OFF */
                g_app_state.wuhuaqi_state = 0;
                drv_gpio_set_humidifier(false);
                ble_service_notify_str("ATOMIZER:OFF\n");
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            audio_player_stop_engine();
            ui_manager_set_ui(5);
            return;

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
