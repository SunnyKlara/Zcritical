#include "led_effects.h"
#include "app_state.h"
#include "drv_led.h"
#include "preset_colors.h"
#include "board_config.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <math.h>

/* LED Effect Engine
 * Called every 20ms from Main_Task.
 * Priority: RGB Custom > Breathing > Streamlight > Static */

static uint32_t s_gradient_tick = 0;
static uint32_t s_streamlight_tick = 0;
static uint32_t s_breathing_tick = 0;
static uint8_t  s_breathing_active = 0;
static uint8_t  s_streamlight_running = 0;

void led_effects_init(void)
{
    s_gradient_tick = 0;
    s_streamlight_tick = 0;
    s_breathing_tick = 0;
    s_breathing_active = 0;
    s_streamlight_running = 0;
}

/* ── Gradient ── */

void led_effects_start_gradient(uint8_t strip, uint8_t r, uint8_t g, uint8_t b, uint8_t speed_mode)
{
    if (strip > 3) return;

    uint16_t steps;
    switch (speed_mode) {
    case 0:  steps = GRADIENT_SPEED_FAST;   break;
    case 1:  steps = GRADIENT_SPEED_NORMAL; break;
    default: steps = GRADIENT_SPEED_SLOW;   break;
    }

    /* Property 15: start from current interpolated color */
    g_app_state.gradient[strip].start_r = g_app_state.gradient[strip].current_r;
    g_app_state.gradient[strip].start_g = g_app_state.gradient[strip].current_g;
    g_app_state.gradient[strip].start_b = g_app_state.gradient[strip].current_b;
    g_app_state.gradient[strip].target_r = r;
    g_app_state.gradient[strip].target_g = g;
    g_app_state.gradient[strip].target_b = b;
    g_app_state.gradient[strip].step = 0;
    g_app_state.gradient[strip].total_steps = steps;
    g_app_state.gradient[strip].active = 1;
}

bool led_effects_gradient_active(void)
{
    for (int i = 0; i < 4; i++) {
        if (g_app_state.gradient[i].active) return true;
    }
    return false;
}

static void gradient_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (now - s_gradient_tick < LED_GRADIENT_PERIOD_MS) return;
    s_gradient_tick = now;

    uint8_t any_active = 0;
    for (int i = 0; i < 4; i++) {
        if (!g_app_state.gradient[i].active) continue;
        any_active = 1;

        g_app_state.gradient[i].step++;
        uint16_t step = g_app_state.gradient[i].step;
        uint16_t total = g_app_state.gradient[i].total_steps;

        if (step >= total) {
            /* Gradient complete */
            g_app_state.gradient[i].current_r = g_app_state.gradient[i].target_r;
            g_app_state.gradient[i].current_g = g_app_state.gradient[i].target_g;
            g_app_state.gradient[i].current_b = g_app_state.gradient[i].target_b;
            g_app_state.gradient[i].active = 0;
        } else {
            /* Property 14: linear interpolation */
            uint8_t sr = g_app_state.gradient[i].start_r;
            uint8_t sg = g_app_state.gradient[i].start_g;
            uint8_t sb = g_app_state.gradient[i].start_b;
            uint8_t tr = g_app_state.gradient[i].target_r;
            uint8_t tg = g_app_state.gradient[i].target_g;
            uint8_t tb = g_app_state.gradient[i].target_b;

            g_app_state.gradient[i].current_r = sr + (int16_t)(tr - sr) * step / total;
            g_app_state.gradient[i].current_g = sg + (int16_t)(tg - sg) * step / total;
            g_app_state.gradient[i].current_b = sb + (int16_t)(tb - sb) * step / total;
        }

        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.gradient[i].current_r,
            g_app_state.gradient[i].current_g,
            g_app_state.gradient[i].current_b);
    }

    if (any_active) {
        drv_led_refresh();
    }
}

/* ── Streamlight ── */

void led_effects_streamlight_start(void)
{
    s_streamlight_running = 1;
    g_app_state.streamlight_phase = 0;
    g_app_state.streamlight_color_idx = g_app_state.preset_index - 1;
}

void led_effects_streamlight_stop(void)
{
    s_streamlight_running = 0;
}

static void streamlight_process(void)
{
    if (!s_streamlight_running) return;

    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (now - s_streamlight_tick < STREAMLIGHT_PERIOD_MS) return;
    s_streamlight_tick = now;

    uint8_t curr_idx = g_app_state.streamlight_color_idx;
    uint8_t next_idx = (curr_idx + 1) % COLOR_PRESET_COUNT;
    uint16_t phase = g_app_state.streamlight_phase;

    const color_preset_t *curr = &COLOR_PRESETS[curr_idx];
    const color_preset_t *next = &COLOR_PRESETS[next_idx];

    /* Interpolate left/main colors */
    uint8_t r1 = curr->lr + (int16_t)(next->lr - curr->lr) * phase / STREAMLIGHT_INTERP_STEPS;
    uint8_t g1 = curr->lg + (int16_t)(next->lg - curr->lg) * phase / STREAMLIGHT_INTERP_STEPS;
    uint8_t b1 = curr->lb + (int16_t)(next->lb - curr->lb) * phase / STREAMLIGHT_INTERP_STEPS;

    /* Interpolate right/tail colors */
    uint8_t r2 = curr->rr + (int16_t)(next->rr - curr->rr) * phase / STREAMLIGHT_INTERP_STEPS;
    uint8_t g2 = curr->rg + (int16_t)(next->rg - curr->rg) * phase / STREAMLIGHT_INTERP_STEPS;
    uint8_t b2 = curr->rb + (int16_t)(next->rb - curr->rb) * phase / STREAMLIGHT_INTERP_STEPS;

    /* Apply to strips: Main+Left get color1, Right+Tail get color2 */
    drv_led_set_strip_color(LED_STRIP_MAIN, r1, g1, b1);
    drv_led_set_strip_color(LED_STRIP_LEFT, r1, g1, b1);
    drv_led_set_strip_color(LED_STRIP_RIGHT, r2, g2, b2);
    /* Tail stays static during streamlight (matching STM32 behavior) */
    drv_led_refresh();

    /* Advance phase */
    g_app_state.streamlight_phase++;
    if (g_app_state.streamlight_phase >= STREAMLIGHT_INTERP_STEPS) {
        g_app_state.streamlight_phase = 0;
        g_app_state.streamlight_color_idx = next_idx;
        g_app_state.preset_index = next_idx + 1;
    }
}

/* ── Breathing ── */

void led_effects_breathing_start(void)
{
    s_breathing_active = 1;
    g_app_state.breath_phase = 0;
}

void led_effects_breathing_stop(void)
{
    s_breathing_active = 0;
}

static void breathing_process(void)
{
    if (!s_breathing_active) return;

    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (now - s_breathing_tick < BREATHING_PERIOD_MS) return;
    s_breathing_tick = now;

    /* Phase increment: 4 per 20ms -> period ~3.14s */
    g_app_state.breath_phase += 4;
    if (g_app_state.breath_phase >= 628) g_app_state.breath_phase = 0;

    /* Property 20: scale = 0.6 + 0.4 * (sin(phase) + 1) / 2 */
    float sin_val = sinf(g_app_state.breath_phase * 0.01f);
    float scale = BREATHING_MIN_SCALE + (BREATHING_MAX_SCALE - BREATHING_MIN_SCALE) * (sin_val + 1.0f) / 2.0f;

    /* Apply scaled brightness to all strips */
    uint8_t breath_bright = (uint8_t)(g_app_state.brightness * scale);
    drv_led_set_brightness(breath_bright);

    for (int i = 0; i < 4; i++) {
        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.led_colors[i][0],
            g_app_state.led_colors[i][1],
            g_app_state.led_colors[i][2]);
    }
    drv_led_refresh();
}

/* ── Priority Resolution ── */

led_effect_priority_t led_effects_get_active_priority(void)
{
    /* Property 13: RGB Custom > Breathing > Streamlight > Static */
    if (g_app_state.ui == 3) return LED_EFFECT_RGB_CUSTOM;
    if (s_breathing_active)  return LED_EFFECT_BREATHING;
    if (s_streamlight_running) return LED_EFFECT_STREAMLIGHT;
    return LED_EFFECT_STATIC;
}

/* ── Main process (called every 20ms) ── */

void led_effects_process(void)
{
    led_effect_priority_t prio = led_effects_get_active_priority();

    switch (prio) {
    case LED_EFFECT_RGB_CUSTOM:
        /* UI3 handles LED directly */
        break;
    case LED_EFFECT_BREATHING:
        breathing_process();
        break;
    case LED_EFFECT_STREAMLIGHT:
        streamlight_process();
        break;
    case LED_EFFECT_STATIC:
        gradient_process();
        break;
    }
}
