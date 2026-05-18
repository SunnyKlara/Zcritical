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
static uint8_t  s_throttle_fx_active = 0;
static uint32_t s_throttle_fx_tick = 0;
static uint16_t s_throttle_fx_phase = 0;

/* Forward declaration */
static void throttle_fx_process(void);

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

    /* ── Wind-reactive period: faster LED motion at higher fan speed ── */
    /* speed 0..100 → period 30ms..6ms (linear inverse) */
    uint8_t spd = (uint8_t)g_app_state.current_speed_kmh;
    if (spd > 100) spd = 100;
    uint32_t period_ms = STREAMLIGHT_PERIOD_MS - ((STREAMLIGHT_PERIOD_MS - 6) * spd / 100);

    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (now - s_streamlight_tick < period_ms) return;
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

    /* ── Wind-reactive brightness: speed 0..100 → scale 50%..100% ──
     * Throttle mode: add 4Hz pulse on top (±15%) for racing intensity. */
    uint16_t bright_scale = 128 + (128 * spd / 100);   /* 128..256 (0.5..1.0 in Q8) */

    if (g_app_state.wuhuaqi_state == 2) {
        /* 4Hz sine pulse ≈ 250ms period. Phase drives via streamlight_tick. */
        static uint16_t s_pulse_phase = 0;
        s_pulse_phase += (period_ms * 6283UL / 250) >> 8;  /* scale to Q4 approx */
        /* Simple triangular pulse (avoid sinf() dependency): 0..64..0 over 2π */
        uint16_t p = s_pulse_phase & 0xFF;
        int16_t pulse = (p < 128) ? (int16_t)p : (int16_t)(255 - p);  /* 0..128..0 */
        /* Map to ±38 (±15% of 256) */
        int16_t pulse_delta = (pulse - 64) * 38 / 64;
        int32_t scaled = (int32_t)bright_scale + pulse_delta;
        if (scaled < 64) scaled = 64;
        if (scaled > 256) scaled = 256;
        bright_scale = (uint16_t)scaled;
    }

    /* Apply brightness scale to computed colors (Q8 multiplication) */
    uint8_t br1 = (uint8_t)((uint16_t)r1 * bright_scale >> 8);
    uint8_t bg1 = (uint8_t)((uint16_t)g1 * bright_scale >> 8);
    uint8_t bb1 = (uint8_t)((uint16_t)b1 * bright_scale >> 8);
    uint8_t br2 = (uint8_t)((uint16_t)r2 * bright_scale >> 8);
    uint8_t bg2 = (uint8_t)((uint16_t)g2 * bright_scale >> 8);
    uint8_t bb2 = (uint8_t)((uint16_t)b2 * bright_scale >> 8);

    /* Store interpolated (raw, not scaled) colors for LCD sync */
    g_app_state.streamlight_r1 = r1;
    g_app_state.streamlight_g1 = g1;
    g_app_state.streamlight_b1 = b1;
    g_app_state.streamlight_r2 = r2;
    g_app_state.streamlight_g2 = g2;
    g_app_state.streamlight_b2 = b2;
    g_app_state.streamlight_lcd_dirty = 1;

    /* Apply brightness-scaled colors to strips */
    drv_led_set_strip_color(LED_STRIP_MAIN, br1, bg1, bb1);
    drv_led_set_strip_color(LED_STRIP_LEFT, br1, bg1, bb1);
    drv_led_set_strip_color(LED_STRIP_RIGHT, br2, bg2, bb2);
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
    /* Throttle effect takes highest priority when active */
    if (s_throttle_fx_active) {
        throttle_fx_process();
        return;
    }

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

/* ═══════════════════════════════════════════════════════════════════════
 *  Throttle LED Effects — 6 speed-reactive modes for throttle mode
 *  All effects use g_app_state.current_speed_kmh (0-100) as input.
 *  Hardware: Main strip (6 LEDs, indices 2-7 on phys strip 0)
 *            Tail strip (3 LEDs, indices 0-2 on phys strip 1)
 * ═══════════════════════════════════════════════════════════════════════ */

/* Speed-to-color: blue(0%) → yellow(50%) → red(100%) */
static void speed_to_rgb(uint8_t percent, uint8_t *r, uint8_t *g, uint8_t *b)
{
    if (percent > 100) percent = 100;
    if (percent <= 50) {
        uint16_t t = (uint16_t)percent * 2;
        *r = (uint8_t)(0 + 255 * t / 100);
        *g = (uint8_t)(180 + 30 * t / 100);
        *b = (uint8_t)(255 - 175 * t / 100);
    } else {
        uint16_t t = (uint16_t)(percent - 50) * 2;
        *r = 255;
        *g = (uint8_t)(210 - 170 * t / 100);
        *b = (uint8_t)(80 - 50 * t / 100);
    }
}

/* ── Effect 1: Tachometer Fill ──
 * Speed maps to how many of the 6 Main LEDs are lit.
 * Color shifts blue→red with speed. Tail flashes at speed-proportional rate. */
static void throttle_fx_tachometer(uint8_t spd)
{
    uint8_t r, g, b;
    speed_to_rgb(spd, &r, &g, &b);

    /* Main: fill 0-6 LEDs based on speed */
    uint8_t lit = (uint8_t)((uint16_t)spd * 6 / 100);
    if (spd > 0 && lit == 0) lit = 1;

    for (int i = 0; i < 6; i++) {
        if (i < lit) {
            drv_led_set_pixel(0, LED_MAIN_START + i, r, g, b);
        } else {
            drv_led_set_pixel(0, LED_MAIN_START + i, 0, 0, 0);
        }
    }

    /* Tail: flash at speed-proportional rate (0=steady, 100=10Hz) */
    if (spd < 10) {
        /* Below 10%: tail steady on */
        for (int i = 0; i < LED_TAIL_COUNT; i++)
            drv_led_set_pixel(1, LED_TAIL_START + i, r, g, b);
    } else {
        /* Flash period: 500ms(spd=10) → 50ms(spd=100) */
        uint16_t period = 500 - (uint16_t)(spd - 10) * 450 / 90;
        uint8_t on = (s_throttle_fx_phase % period) < (period / 2);
        for (int i = 0; i < LED_TAIL_COUNT; i++) {
            if (on) drv_led_set_pixel(1, LED_TAIL_START + i, r, g, b);
            else    drv_led_set_pixel(1, LED_TAIL_START + i, 0, 0, 0);
        }
    }

    /* Redline flash: all blink at 90%+ */
    if (spd >= 90) {
        uint8_t blink = (s_throttle_fx_phase % 80) < 40;
        if (!blink) {
            for (int i = 0; i < 6; i++)
                drv_led_set_pixel(0, LED_MAIN_START + i, 0, 0, 0);
        }
    }

    drv_led_refresh();
}

/* ── Effect 2: Pulse Wave ──
 * Pulse expands from center (LED 3) outward. Speed controls frequency. */
static void throttle_fx_pulse(uint8_t spd)
{
    uint8_t r, g, b;
    speed_to_rgb(spd, &r, &g, &b);

    /* Pulse period: 1000ms(spd=0) → 100ms(spd=100) */
    uint16_t period = (spd == 0) ? 1000 : 1000 - (uint16_t)spd * 900 / 100;
    if (period < 100) period = 100;

    /* Phase within one pulse cycle (0 to period) */
    uint16_t phase_in_cycle = s_throttle_fx_phase % period;
    /* Normalize to 0-3 (expansion radius) */
    uint8_t radius = (uint8_t)((uint32_t)phase_in_cycle * 4 / period);

    /* Center is LED index 2,3 (middle of 6). Expand outward. */
    for (int i = 0; i < 6; i++) {
        int dist = (i < 3) ? (2 - i) : (i - 3);
        uint8_t brightness;
        if (dist == radius) {
            brightness = 255;
        } else if (radius > 0 && dist == radius - 1) {
            brightness = 100;
        } else {
            brightness = 0;
        }
        drv_led_set_pixel(0, LED_MAIN_START + i,
            (uint8_t)((uint16_t)r * brightness / 255),
            (uint8_t)((uint16_t)g * brightness / 255),
            (uint8_t)((uint16_t)b * brightness / 255));
    }

    /* Tail: sync flash with pulse peak */
    uint8_t tail_on = (radius >= 2);
    for (int i = 0; i < LED_TAIL_COUNT; i++) {
        if (tail_on) drv_led_set_pixel(1, LED_TAIL_START + i, r, g, b);
        else         drv_led_set_pixel(1, LED_TAIL_START + i, 0, 0, 0);
    }

    drv_led_refresh();
}

/* ── Effect 3: Chase ──
 * Light point runs across Main strip, then jumps to Tail. */
static void throttle_fx_chase(uint8_t spd)
{
    uint8_t r, g, b;
    speed_to_rgb(spd, &r, &g, &b);

    /* Total positions: 6 (Main) + 3 (Tail) = 9 */
    uint16_t period = (spd == 0) ? 600 : 600 - (uint16_t)spd * 540 / 100;
    if (period < 60) period = 60;

    uint8_t pos = (uint8_t)((uint32_t)(s_throttle_fx_phase % period) * 9 / period);

    /* Clear all */
    for (int i = 0; i < 6; i++)
        drv_led_set_pixel(0, LED_MAIN_START + i, 0, 0, 0);
    for (int i = 0; i < LED_TAIL_COUNT; i++)
        drv_led_set_pixel(1, LED_TAIL_START + i, 0, 0, 0);

    /* Draw head + trail */
    if (pos < 6) {
        drv_led_set_pixel(0, LED_MAIN_START + pos, r, g, b);
        if (pos > 0)
            drv_led_set_pixel(0, LED_MAIN_START + pos - 1, r/3, g/3, b/3);
    } else {
        uint8_t tp = pos - 6;
        drv_led_set_pixel(1, LED_TAIL_START + tp, r, g, b);
        if (tp > 0)
            drv_led_set_pixel(1, LED_TAIL_START + tp - 1, r/3, g/3, b/3);
        else
            drv_led_set_pixel(0, LED_MAIN_START + 5, r/3, g/3, b/3);
    }

    drv_led_refresh();
}

/* ── Effect 4: Alternate ──
 * Main and Tail alternate on/off. Speed controls flash rate. */
static void throttle_fx_alternate(uint8_t spd)
{
    uint8_t r, g, b;
    speed_to_rgb(spd, &r, &g, &b);

    /* Period: 500ms(spd=0, 1Hz) → 33ms(spd=100, 15Hz) */
    uint16_t period = (spd == 0) ? 500 : 500 - (uint16_t)spd * 467 / 100;
    if (period < 33) period = 33;

    uint8_t main_on = (s_throttle_fx_phase % period) < (period / 2);

    for (int i = 0; i < 6; i++) {
        if (main_on) drv_led_set_pixel(0, LED_MAIN_START + i, r, g, b);
        else         drv_led_set_pixel(0, LED_MAIN_START + i, 0, 0, 0);
    }
    for (int i = 0; i < LED_TAIL_COUNT; i++) {
        if (!main_on) drv_led_set_pixel(1, LED_TAIL_START + i, r, g, b);
        else          drv_led_set_pixel(1, LED_TAIL_START + i, 0, 0, 0);
    }

    drv_led_refresh();
}

/* ── Effect 5: Wave (Continuous wide sine — left to right, with tidal overlay) ──
 *
 * Wide sine wave sweeps left→right, 2.5s period, 20fps.
 * Phase spacing 25 (wide wave — adjacent LEDs very similar brightness).
 * Tidal overlay: 8s slow modulation of base brightness.
 * Uses preset color. */
static void throttle_fx_wave(uint8_t spd)
{
    (void)spd;

    uint8_t cr = g_app_state.led_colors[0][0];
    uint8_t cg = g_app_state.led_colors[0][1];
    uint8_t cb = g_app_state.led_colors[0][2];
    uint8_t tr = g_app_state.led_colors[3][0];
    uint8_t tg = g_app_state.led_colors[3][1];
    uint8_t tb = g_app_state.led_colors[3][2];

    uint32_t t = s_throttle_fx_phase;

    /* Wind-reactive: speed 0=calm, 100=storm */
    uint8_t wind = (uint8_t)g_app_state.current_speed_kmh;
    if (wind > 100) wind = 100;

    /* Speed 0: static light, no wave motion */
    if (wind == 0) {
        for (int i = 0; i < 6; i++) {
            drv_led_set_pixel(0, LED_MAIN_START + i, cr, cg, cb);
        }
        for (int i = 0; i < LED_TAIL_COUNT; i++) {
            drv_led_set_pixel(1, LED_TAIL_START + i, tr, tg, tb);
        }
        drv_led_refresh();
        return;
    }

    uint16_t wave_cycle = 2500 - (uint16_t)wind * 17;   /* 2500→800ms */
    uint8_t base_bright = (uint8_t)(38 - wind * 38 / 100);  /* 38→0 */
    uint8_t phase_step = 25 + (uint8_t)(wind * 30 / 100);   /* 25→55 */
    uint16_t tidal_cycle = 8000 - (uint16_t)wind * 50;  /* 8000→3000ms */

    #define PEAK_BRIGHT   255

    uint8_t wave_phase = (uint8_t)((uint32_t)(t % wave_cycle) * 255 / wave_cycle);

    /* Tidal overlay */
    uint8_t tidal_phase = (uint8_t)((uint32_t)(t % tidal_cycle) * 255 / tidal_cycle);
    uint8_t tidal_raw = (tidal_phase < 128) ? tidal_phase * 2 : (255 - tidal_phase) * 2;
    uint8_t tidal_base = base_bright + (uint8_t)((uint16_t)tidal_raw * base_bright / 255);

    /* Main strip: wide wave moves left to right */
    for (int i = 0; i < 6; i++) {
        uint8_t led_phase = wave_phase + (uint8_t)(i * phase_step);

        uint8_t raw;
        if (led_phase < 128) {
            raw = led_phase * 2;
        } else {
            raw = (255 - led_phase) * 2;
        }
        uint8_t smooth = (uint8_t)((uint16_t)raw * raw / 255);
        uint8_t brightness = tidal_base + (uint8_t)((uint16_t)smooth * (PEAK_BRIGHT - tidal_base) / 255);

        drv_led_set_pixel(0, LED_MAIN_START + i,
            (uint8_t)((uint16_t)cr * brightness / 255),
            (uint8_t)((uint16_t)cg * brightness / 255),
            (uint8_t)((uint16_t)cb * brightness / 255));
    }

    /* Tail: same wave, slightly behind */
    for (int i = 0; i < LED_TAIL_COUNT; i++) {
        uint8_t led_phase = wave_phase + (uint8_t)((2 - i) * phase_step) - 60;

        uint8_t raw;
        if (led_phase < 128) {
            raw = led_phase * 2;
        } else {
            raw = (255 - led_phase) * 2;
        }
        uint8_t smooth = (uint8_t)((uint16_t)raw * raw / 255);
        uint8_t brightness = tidal_base + (uint8_t)((uint16_t)smooth * (PEAK_BRIGHT - tidal_base) / 255);

        drv_led_set_pixel(1, LED_TAIL_START + i,
            (uint8_t)((uint16_t)tr * brightness / 255),
            (uint8_t)((uint16_t)tg * brightness / 255),
            (uint8_t)((uint16_t)tb * brightness / 255));
    }

    #undef PEAK_BRIGHT

    drv_led_refresh();
}

/* ── Effect 6: Lightning ──
 * Random white flashes. Higher speed = more frequent. */
static void throttle_fx_lightning(uint8_t spd)
{
    uint8_t r, g, b;
    speed_to_rgb(spd, &r, &g, &b);

    static uint8_t s_flash_countdown = 0;
    static uint8_t s_flash_duration = 0;

    if (s_flash_duration > 0) {
        s_flash_duration--;
        for (int i = 0; i < 6; i++)
            drv_led_set_pixel(0, LED_MAIN_START + i, 255, 255, 255);
        for (int i = 0; i < LED_TAIL_COUNT; i++)
            drv_led_set_pixel(1, LED_TAIL_START + i, 255, 255, 255);
    } else {
        uint8_t dim = 40 + spd / 4;
        for (int i = 0; i < 6; i++)
            drv_led_set_pixel(0, LED_MAIN_START + i,
                (uint8_t)((uint16_t)r * dim / 255),
                (uint8_t)((uint16_t)g * dim / 255),
                (uint8_t)((uint16_t)b * dim / 255));
        for (int i = 0; i < LED_TAIL_COUNT; i++)
            drv_led_set_pixel(1, LED_TAIL_START + i,
                (uint8_t)((uint16_t)r * dim / 255),
                (uint8_t)((uint16_t)g * dim / 255),
                (uint8_t)((uint16_t)b * dim / 255));

        if (s_flash_countdown == 0) {
            uint8_t max_interval = (spd == 0) ? 250 : (uint8_t)(250 - spd * 240 / 100);
            if (max_interval < 10) max_interval = 10;
            s_flash_countdown = (uint8_t)((s_throttle_fx_phase * 7 + 13) % max_interval) + 3;
        } else {
            s_flash_countdown--;
            if (s_flash_countdown == 0) {
                s_flash_duration = 2 + (s_throttle_fx_phase & 0x03);
            }
        }
    }

    drv_led_refresh();
}

/* ── Throttle FX dispatcher ── */

static void throttle_fx_process(void)
{
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (now - s_throttle_fx_tick < 20) return;  /* 50fps */
    s_throttle_fx_tick = now;
    s_throttle_fx_phase += 20;

    uint8_t spd = (uint8_t)g_app_state.current_speed_kmh;
    if (spd > 100) spd = 100;

    switch (g_app_state.throttle_fx_mode) {
    case THROTTLE_FX_TACHOMETER: throttle_fx_tachometer(spd); break;
    case THROTTLE_FX_PULSE:      throttle_fx_pulse(spd);      break;
    case THROTTLE_FX_CHASE:      throttle_fx_chase(spd);      break;
    case THROTTLE_FX_ALTERNATE:  throttle_fx_alternate(spd);  break;
    case THROTTLE_FX_WAVE:       throttle_fx_wave(spd);       break;
    case THROTTLE_FX_LIGHTNING:  throttle_fx_lightning(spd);  break;
    default:                     throttle_fx_alternate(spd);  break;
    }
}

/* ── Throttle FX public API ── */

void led_effects_throttle_start(void)
{
    s_throttle_fx_active = 1;
    s_throttle_fx_tick = 0;
    s_throttle_fx_phase = 0;
}

void led_effects_throttle_stop(void)
{
    s_throttle_fx_active = 0;
    /* Restore static colors */
    for (int i = 0; i < 4; i++) {
        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.led_colors[i][0],
            g_app_state.led_colors[i][1],
            g_app_state.led_colors[i][2]);
    }
    drv_led_refresh();
}

void led_effects_set_throttle_mode(uint8_t mode)
{
    if (mode >= 1 && mode <= 6) {
        g_app_state.throttle_fx_mode = mode;
    }
}

uint8_t led_effects_get_throttle_mode(void)
{
    return g_app_state.throttle_fx_mode;
}

bool led_effects_throttle_active(void)
{
    return s_throttle_fx_active != 0;
}
