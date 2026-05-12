#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef enum {
    LED_EFFECT_RGB_CUSTOM  = 0,
    LED_EFFECT_BREATHING   = 1,
    LED_EFFECT_STREAMLIGHT = 2,
    LED_EFFECT_STATIC      = 3,
} led_effect_priority_t;

void led_effects_init(void);
void led_effects_process(void);
void led_effects_start_gradient(uint8_t strip, uint8_t r, uint8_t g, uint8_t b, uint8_t speed_mode);
bool led_effects_gradient_active(void);
void led_effects_streamlight_start(void);
void led_effects_streamlight_stop(void);
void led_effects_breathing_start(void);
void led_effects_breathing_stop(void);
led_effect_priority_t led_effects_get_active_priority(void);
