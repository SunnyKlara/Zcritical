#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "board_config.h"

/* ═══════════════════════════════════════════════════════════════
 *  WS2812B LED Strip Driver (RMT peripheral)
 *  2 physical strips → 4 logical strips
 *
 *  Physical strip 1 (IO41, 10 LEDs):
 *    Left[0:1] + Main[2:7] + Right[8:9]
 *
 *  Physical strip 2 (IO16, 3 LEDs):
 *    Tail[0:2]
 * ═══════════════════════════════════════════════════════════════ */

typedef enum {
    LED_STRIP_MAIN  = 0,   /* Strip1 index 2..7  (6 LEDs) */
    LED_STRIP_LEFT  = 1,   /* Strip1 index 0..1  (2 LEDs) */
    LED_STRIP_RIGHT = 2,   /* Strip1 index 8..9  (2 LEDs) */
    LED_STRIP_TAIL  = 3,   /* Strip2 index 0..2  (3 LEDs) */
} led_strip_id_t;

void drv_led_init(void);

/* Set all pixels on a logical strip to one color */
void drv_led_set_strip_color(led_strip_id_t strip, uint8_t r, uint8_t g, uint8_t b);

/* Set a single physical pixel (strip 0=IO41, 1=IO16) */
void drv_led_set_pixel(uint8_t phys_strip, uint16_t index, uint8_t r, uint8_t g, uint8_t b);

/* Global brightness 0-100, applied on refresh */
void drv_led_set_brightness(uint8_t brightness);

/* Transmit all LED data via RMT */
void drv_led_refresh(void);

/* Clear all LEDs to off */
void drv_led_clear(void);
