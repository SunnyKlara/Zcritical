#include "drv_pwm.h"
#include "pin_config.h"
#include "board_config.h"
#include "driver/ledc.h"
#include "esp_log.h"

static const char *TAG = "drv_pwm";
static uint8_t s_duty;

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
    s_duty = 0;
    ESP_LOGI(TAG, "Fan PWM init: IO%d, %dHz", PIN_FAN, FAN_PWM_FREQ_HZ);
}

void drv_pwm_set_duty(uint8_t percent)
{
    if (percent > 100) percent = 100;
    s_duty = percent;
    uint32_t max_duty = (1 << LEDC_TIMER_10_BIT) - 1;  /* 1023 */
    uint32_t duty_val = (uint32_t)percent * max_duty / 100;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL, duty_val);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, FAN_LEDC_CHANNEL);
}

uint8_t drv_pwm_get_duty(void) { return s_duty; }
