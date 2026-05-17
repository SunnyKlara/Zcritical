#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef enum {
    LED_EFFECT_RGB_CUSTOM  = 0,
    LED_EFFECT_BREATHING   = 1,
    LED_EFFECT_STREAMLIGHT = 2,
    LED_EFFECT_STATIC      = 3,
} led_effect_priority_t;

/* ── Throttle LED effect modes ── */
typedef enum {
    THROTTLE_FX_TACHOMETER  = 1,  /* 转速条填充: 速度→逐颗点亮 */
    THROTTLE_FX_PULSE       = 2,  /* 脉冲波: 中心向两端扩散 */
    THROTTLE_FX_CHASE       = 3,  /* 追逐流光: 光点奔跑 */
    THROTTLE_FX_ALTERNATE   = 4,  /* Main↔Tail 交替闪烁 */
    THROTTLE_FX_WAVE        = 5,  /* 波浪呼吸: 蛇形游动 */
    THROTTLE_FX_LIGHTNING   = 6,  /* 闪电爆发: 随机白闪 */
} throttle_fx_mode_t;

void led_effects_init(void);
void led_effects_process(void);
void led_effects_start_gradient(uint8_t strip, uint8_t r, uint8_t g, uint8_t b, uint8_t speed_mode);
bool led_effects_gradient_active(void);
void led_effects_streamlight_start(void);
void led_effects_streamlight_stop(void);
void led_effects_breathing_start(void);
void led_effects_breathing_stop(void);
led_effect_priority_t led_effects_get_active_priority(void);

/* ── Throttle effect API ── */
void led_effects_throttle_start(void);
void led_effects_throttle_stop(void);
void led_effects_set_throttle_mode(uint8_t mode);
uint8_t led_effects_get_throttle_mode(void);
bool led_effects_throttle_active(void);
