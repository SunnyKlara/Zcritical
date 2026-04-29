#pragma once
#include <stdint.h>

/* ═══════════════════════════════════════════════════════════════
 *  14 Color Presets — Single Source of Truth
 *  Used by UI2 (presets), streamlight, breathing, and BLE PRESET command
 *
 *  排列逻辑：暖色→冷色→中性色→渐变混色
 *  重要：修改此文件时必须同步修改 RideWind/lib/data/led_presets.dart
 * ═══════════════════════════════════════════════════════════════ */

typedef struct {
    const char *name;
    uint8_t lr, lg, lb;   /* Left/Main strip color */
    uint8_t rr, rg, rb;   /* Right/Tail strip color */
} color_preset_t;

#define COLOR_PRESET_COUNT 14

static const color_preset_t COLOR_PRESETS[COLOR_PRESET_COUNT] = {
    /* ── 暖色系 ── */
    { "Flame Red",      255,   0,   0,   255,   0,   0 },  /*  1 纯红 */
    { "Blaze Orange",   255,  80,   0,   255, 200,  50 },  /*  2 烈焰橙 */
    { "Racing Gold",    255, 210,   0,   255, 210,   0 },  /*  3 竞速金 */

    /* ── 粉紫系 ── */
    { "Sakura Pink",    255, 105, 180,   255,   0,  80 },  /*  4 樱花粉 */
    { "Amethyst",       148,   0, 211,   148,   0, 211 },  /*  5 紫水晶 */

    /* ── 蓝紫系 ── */
    { "Aurora Purple",  180,   0, 255,     0, 255, 200 },  /*  6 极光紫 */
    { "Ice Crystal",      0, 234, 255,     0, 234, 255 },  /*  7 冰晶蓝 */

    /* ── 青绿系 ── */
    { "Mint Breeze",      0, 255, 180,   100, 200, 255 },  /*  8 薄荷微风 */
    { "Jungle Green",     0, 255,  65,     0, 255,  65 },  /*  9 丛林绿 */

    /* ── 中性色 ── */
    { "Pure White",     225, 225, 225,   225, 225, 225 },  /* 10 纯白 */

    /* ── 双色渐变 ── */
    { "Police Flash",   255,   0,   0,     0,  80, 255 },  /* 11 警灯红蓝 */
    { "Sunset Lava",    255, 100,   0,     0, 200, 255 },  /* 12 日落熔岩 */
    { "Cyber Neon",     138,  43, 226,     0, 255, 128 },  /* 13 赛博霓虹 */
    { "Neon Party",       0, 255, 255,   255,   0, 255 },  /* 14 霓虹派对 */
};
