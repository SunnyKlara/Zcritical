/**
 * @file app_state.h
 * @brief 全局应用状态结构体 — 所有可变状态的唯一真相源，由 mutex 保护
 */

#pragma once

#include <stdint.h>
#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "board_config.h"

/* ═══════════════════════════════════════════════════════════════
 *  Unified Application State
 *  Single source of truth for all mutable state.
 *  Protected by g_app_state_mutex. Only Main_Task writes.
 * ═══════════════════════════════════════════════════════════════ */

typedef struct {
    /* ── UI ── */
    uint8_t  ui;                    /* Current screen (0-7, 255=off) */
    uint8_t  chu;                   /* Screen init flag */
    uint8_t  menu_selected;         /* Menu selection (1-6) */
    uint8_t  auto_enter;            /* BLE auto-enter flag */

    /* ── Speed / Fan ── */
    int16_t  fan_speed;             /* 0-100 (Num) */
    int16_t  current_speed_kmh;     /* 0-340 */
    uint8_t  speed_unit;            /* 0=km/h, 1=mph */
    uint16_t speed_max_display;     /* 极速上限 display value (default 340 km/h) */
    uint8_t  fan_range_min;         /* 风力下限 0-100 (default 0) */
    uint8_t  fan_range_max;         /* 风力上限 0-100 (default 100) */

    /* ── Humidifier / Throttle ── */
    uint8_t  wuhuaqi_state;         /* 0=off, 1=on, 2=throttle */
    uint8_t  wuhuaqi_state_saved;   /* Saved before throttle mode */

    /* ── LED colors (applied) ── */
    uint8_t  led_colors[4][3];      /* [strip][r,g,b] 0=Main,1=Left,2=Right,3=Tail */

    /* ── LED colors (edit buffer for UI3) ── */
    int16_t  led_edit[4][3];        /* Temporary edit values, int16 for ±2 step */

    /* ── LED effects ── */
    uint8_t  preset_index;          /* 1-14 */
    uint8_t  streamlight_active;    /* 0=off, 1=on */
    uint8_t  breath_mode;           /* 0=off, 1=on */
    uint16_t breath_phase;          /* 0-628 (0 to 2π × 100) */
    uint8_t  breath_color_index;    /* 1-14 */

    /* ── Brightness & Volume ── */
    int16_t  brightness;            /* 0-100 */
    uint8_t  volume;                /* 0-100 */

    /* ── UI3 RGB state machine ── */
    uint8_t  ui3_mode;              /* 0=select strip, 1=select channel, 2=adjust */
    uint8_t  ui3_channel;           /* 0=R, 1=G, 2=B */
    int8_t   ui3_strip;             /* 0-3 (Main/Left/Right/Tail) */

    /* ── Encoder ── */
    int16_t  encoder_delta;

    /* ── Button state machine ── */
    uint8_t  key_state;             /* Click count or 0xFF=long press handled */
    uint32_t key_tick;              /* Button press timestamp */
    uint32_t key_state_tick;        /* Last click timestamp */

    /* ── Remote control ── */
    uint32_t remote_active_tick;    /* Last BLE command timestamp */
    uint8_t  preset_dirty;          /* Preset changed by BLE, LCD needs refresh */

    /* ── Logo ── */
    uint8_t  active_logo_slot;      /* 0-2 */
    uint8_t  logo_view_slot;        /* Currently viewed in UI6 */

    /* ── Throttle timing ── */
    uint32_t throttle_last_tick;
    uint8_t  throttle_initialized;
    uint8_t  throttle_was_remote;
    int16_t  throttle_frozen_speed;

    /* ── LED gradient (per strip) ── */
    struct {
        uint8_t  active;
        uint8_t  current_r, current_g, current_b;
        uint8_t  target_r, target_g, target_b;
        uint8_t  start_r, start_g, start_b;
        uint16_t step;
        uint16_t total_steps;
    } gradient[4];

    /* ── Streamlight ── */
    uint16_t streamlight_phase;     /* 0-99 interpolation step */
    uint8_t  streamlight_color_idx; /* Current color index 0-13 */
    uint8_t  streamlight_r1, streamlight_g1, streamlight_b1; /* Current left/main interpolated color */
    uint8_t  streamlight_r2, streamlight_g2, streamlight_b2; /* Current right interpolated color */
    uint8_t  streamlight_lcd_dirty;  /* 1 = LCD color bar needs refresh */

    /* ── Speed reporting ── */
    int16_t  last_reported_speed;

    /* ── Throttle LED effect ── */
    uint8_t  throttle_fx_mode;      /* 1-6, see throttle_fx_mode_t */

} app_state_t;

extern app_state_t       g_app_state;
extern SemaphoreHandle_t g_app_state_mutex;

/* Init with factory defaults */
void app_state_init(void);

/* Save user config (speed_max, fan_range, volume) to NVS flash */
void app_state_save_config(void);

/* Thread-safe lock/unlock */
#define APP_STATE_LOCK()   xSemaphoreTake(g_app_state_mutex, portMAX_DELAY)
#define APP_STATE_UNLOCK() xSemaphoreGive(g_app_state_mutex)
