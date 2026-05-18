#include "drv_pwm.h"
#include "pin_config.h"
#include "board_config.h"
#include "driver/ledc.h"
#include "driver/gpio.h"
#include "esp_log.h"

static const char *TAG = "drv_pwm";
static uint8_t s_duty;           /* Current actual PWM output (0-100) */
static uint8_t s_target_duty;    /* Target duty (what UI requested) */

/* ── Non-linear fan curve ──
 * Maps logical speed (0-100) to actual PWM output (0-100).
 * - 0 = completely off
 * - 1-100 maps to 25-100% (skip dead zone where fan won't spin)
 * - Piecewise: low speeds ramp faster for immediate feedback,
 *   high speeds ramp slower for fine control at max wind. */
static uint8_t fan_curve(uint8_t speed)
{
    if (speed == 0) return 0;
    uint8_t mapped;
    if (speed <= 30) {
        mapped = 25 + (uint8_t)((uint16_t)speed * 30 / 30);  /* 25→55 */
    } else if (speed <= 70) {
        mapped = 55 + (uint8_t)((uint16_t)(speed - 30) * 25 / 40);  /* 55→80 */
    } else {
        mapped = 80 + (uint8_t)((uint16_t)(speed - 70) * 20 / 30);  /* 80→100 */
    }
    if (mapped > 100) mapped = 100;
    return mapped;
}

void drv_pwm_init(void)
{
    ledc_timer_config_t timer = {
        .speed_mode      = LEDC_LOW_SPEED_MODE,
        .timer_num       = FAN_LEDC_TIMER,
        .duty_resolution = FAN_LEDC_RESOLUTION,
        .freq_hz         = FAN_PWM_FREQ_HZ,
        .clk_cfg         = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer));

    ledc_channel_config_t ch = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel    = FAN_LEDC_CHANNEL,
        .timer_sel  = FAN_LEDC_TIMER,
        .gpio_num   = PIN_FAN,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ch));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL);

    s_duty = 0;
    s_target_duty = 0;
    ESP_LOGI(TAG, "Fan PWM init: IO%d, %dHz, duty=0", PIN_FAN, FAN_PWM_FREQ_HZ);
}

/* Set target speed (0-100). Actual PWM goes through fan_curve + smooth ramp. */
void drv_pwm_set_duty(uint8_t percent)
{
    if (percent > 100) percent = 100;
    s_target_duty = fan_curve(percent);
    /* Instant on/off for responsive feel */
    if (percent == 0 && s_duty > 0) {
        s_duty = 0;
        ledc_set_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL, 0);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL);
    } else if (percent > 0 && s_duty == 0) {
        s_duty = s_target_duty;
        uint32_t max_duty = (1 << LEDC_TIMER_10_BIT) - 1;
        uint32_t duty_val = (uint32_t)s_duty * max_duty / 100;
        ledc_set_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL, duty_val);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL);
    }
}

/* Call every 20ms from main task. Smoothly ramps toward target. */
void drv_pwm_update(void)
{
    if (s_duty == s_target_duty) return;

    if (s_duty < s_target_duty) {
        s_duty += 2;  /* Accel: +2%/20ms = 0→100 in 1s */
        if (s_duty > s_target_duty) s_duty = s_target_duty;
    } else {
        if (s_duty >= 3) s_duty -= 3;  /* Decel: -3%/20ms = faster wind-down */
        else s_duty = 0;
        if (s_duty < s_target_duty) s_duty = s_target_duty;
    }

    uint32_t max_duty = (1 << LEDC_TIMER_10_BIT) - 1;
    uint32_t duty_val = (uint32_t)s_duty * max_duty / 100;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL, duty_val);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL);
}

uint8_t drv_pwm_get_duty(void) { return s_duty; }
