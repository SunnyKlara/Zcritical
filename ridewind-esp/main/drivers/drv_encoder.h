#pragma once

#include <stdint.h>
#include <stdbool.h>

/* ═══════════════════════════════════════════════════════════════
 *  EC11 Rotary Encoder Driver
 *  Rotation: PCNT peripheral (A=IO17, B=IO18)
 *  Button:   GPIO input (KEY=IO8, active low)
 * ═══════════════════════════════════════════════════════════════ */

typedef enum {
    ENC_EVT_NONE = 0,
    ENC_EVT_ROTATE,
    ENC_EVT_CLICK,
    ENC_EVT_DOUBLE_CLICK,
    ENC_EVT_TRIPLE_CLICK,
    ENC_EVT_LONG_PRESS,
    ENC_EVT_PRESS,
    ENC_EVT_RELEASE,
} encoder_event_type_t;

typedef struct {
    encoder_event_type_t type;
    int16_t delta;   /* Only valid for ENC_EVT_ROTATE */
} encoder_event_t;

void drv_encoder_init(void);

/* Poll for next event. Returns true if event available. */
bool drv_encoder_poll(encoder_event_t *evt);

/* Raw button state for throttle mode hold detection */
bool drv_encoder_button_pressed(void);
