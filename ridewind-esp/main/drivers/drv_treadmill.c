/**
 * @file drv_treadmill.c
 * @brief LEDC PWM 跑步机驱动 — GPIO14, 20kHz, 软启停
 *
 * Mirrors drv_pwm.c (fan) pattern: target/current duty pair updated by
 * 20 ms tick from main loop. No external dependencies beyond ESP-IDF + config.
 */

#include "drv_treadmill.h"
#include "pin_config.h"
#include "board_config.h"
#include "driver/ledc.h"
#include "esp_log.h"

static const char *TAG = "drv_tread";

static uint8_t s_duty;          /* Current actual PWM output (0-100) */
static uint8_t s_target_duty;   /* Target duty (what service requested) */

void drv_treadmill_init(void)
{
    ledc_timer_config_t timer = {
        .speed_mode      = LEDC_LOW_SPEED_MODE,
        .timer_num       = TREAD_LEDC_TIMER,
        .duty_resolution = TREAD_LEDC_RESOLUTION,
        .freq_hz         = TREAD_PWM_FREQ_HZ,
        .clk_cfg         = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));

    ledc_channel_config_t ch = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel    = TREAD_LEDC_CHANNEL,
        .timer_sel  = TREAD_LEDC_TIMER,
        .gpio_num   = PIN_TREADMILL,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ch));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, TREAD_LEDC_CHANNEL);

    s_duty = 0;
    s_target_duty = 0;
    ESP_LOGI(TAG, "Treadmill PWM init: IO%d, %dHz, duty=0",
             PIN_TREADMILL, TREAD_PWM_FREQ_HZ);
}

void drv_treadmill_set_duty(uint8_t percent)
{
    if (percent > 100) percent = 100;
    s_target_duty = percent;

    /* Instant kill on stop request — safety. */
    if (percent == 0 && s_duty > 0) {
        s_duty = 0;
        ledc_set_duty(LEDC_LOW_SPEED_MODE, TREAD_LEDC_CHANNEL, 0);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, TREAD_LEDC_CHANNEL);
    }
}

/* Smooth ramp toward target. Called every 20 ms from main loop. */
void drv_treadmill_update(void)
{
    if (s_duty == s_target_duty) return;

    if (s_duty < s_target_duty) {
        s_duty += 1;  /* Accel: +1%/20ms = 0→100 in 2 s (gentle on belt) */
    } else {
        if (s_duty >= 2) s_duty -= 2;  /* Decel: -2%/20ms = 1 s wind-down */
        else s_duty = 0;
    }

    uint32_t max_duty = (1u << TREAD_LEDC_RESOLUTION) - 1u;
    uint32_t duty_val = (uint32_t)s_duty * max_duty / 100u;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, TREAD_LEDC_CHANNEL, duty_val);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, TREAD_LEDC_CHANNEL);
}

uint8_t drv_treadmill_get_duty(void) { return s_duty; }
