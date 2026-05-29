/**
 * @file drv_treadmill.h
 * @brief LEDC PWM 跑步机驱动 — 单线 PWM 控制车模传送带电机
 *
 * Output: GPIO14, 20kHz LEDC PWM, 10-bit duty.
 * Input:  duty 0-100% (logical), driver applies smooth ramp internally.
 */

#pragma once
#include <stdint.h>

void drv_treadmill_init(void);
void drv_treadmill_set_duty(uint8_t percent);  /* 0-100 logical, 0 = stop */
void drv_treadmill_update(void);               /* Call every 20ms for smooth ramp */
uint8_t drv_treadmill_get_duty(void);
