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
    /*  1 紫→绿渐变 (Cyber Neon) */
    { "Cyber Neon",     138,  43, 226,     0, 255, 128 },
    /*  2 冰蓝纯色 (Ice Crystal) */
    { "Ice Crystal",      0, 234, 255,     0, 234, 255 },
    /*  3 橙→蓝渐变 (Sunset Lava) */
    { "Sunset Lava",    255, 100,   0,     0, 200, 255 },
    /*  4 金色纯色 (Racing Gold) */
    { "Racing Gold",    255, 210,   0,   255, 210,   0 },
    /*  5 纯红 (Flame Red) */
    { "Flame Red",      255,   0,   0,   255,   0,   0 },
    /*  6 红→蓝渐变 (Police Flash) */
    { "Police Flash",   255,   0,   0,     0,  80, 255 },
    /*  7 粉→玫红渐变 (Sakura Pink) */
    { "Sakura Pink",    255, 105, 180,   255,   0,  80 },
    /*  8 紫→青渐变 (Aurora Purple) */
    { "Aurora Purple",  180,   0, 255,     0, 255, 200 },
    /*  9 紫水晶纯色 (Amethyst) */
    { "Amethyst",       148,   0, 211,   148,   0, 211 },
    /* 10 薄荷→蓝渐变 (Mint Breeze) */
    { "Mint Breeze",      0, 255, 180,   100, 200, 255 },
    /* 11 丛林绿纯色 (Jungle Green) */
    { "Jungle Green",     0, 255,  65,     0, 255,  65 },
    /* 12 纯白 (Pure White) */
    { "Pure White",     225, 225, 225,   225, 225, 225 },
    /* 13 橙→金渐变 (Blaze Orange) */
    { "Blaze Orange",   255,  80,   0,   255, 200,  50 },
    /* 14 青→品红渐变 (Neon Party) */
    { "Neon Party",       0, 255, 255,   255,   0, 255 },
};
