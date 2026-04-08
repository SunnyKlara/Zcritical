#pragma once

#include <stdint.h>

void drv_pwm_init(void);
void drv_pwm_set_duty(uint8_t percent);  /* 0-100 */
uint8_t drv_pwm_get_duty(void);
