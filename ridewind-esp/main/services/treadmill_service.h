/**
 * @file treadmill_service.h
 * @brief 跑步机业务层 — UI 档位映射 / 启停 / BLE 状态广播
 *
 * UI passes a logical speed in 0..TREAD_UI_MAX (matches ui_treadmill gauge).
 * Service maps to driver duty 0..100 and forwards via drv_treadmill.
 */

#pragma once
#include <stdint.h>
#include <stdbool.h>

#define TREAD_UI_MAX        20      /* UI gauge top (matches ui_treadmill TREAD_MAX_SPEED) */

void treadmill_service_init(void);

/* Set logical speed. 0 stops the motor; >0 maps to PWM duty. */
void treadmill_service_set_speed(uint8_t ui_speed);

/* Get last logical speed sent (for UI / BLE GET handlers). */
uint8_t treadmill_service_get_speed(void);

/* Hard stop — used by safety paths (BLE disconnect, error, etc.). */
void treadmill_service_stop(void);
