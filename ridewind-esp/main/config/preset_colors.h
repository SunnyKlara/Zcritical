#pragma once
#include <stdint.h>

/* ═══════════════════════════════════════════════════════════════
 *  14 Color Presets — Single Source of Truth
 *  Used by UI2 (presets), streamlight, breathing, and BLE PRESET command
 * ═══════════════════════════════════════════════════════════════ */

typedef struct {
    const char *name;
    uint8_t lr, lg, lb;   /* Left/Main strip color */
    uint8_t rr, rg, rb;   /* Right/Tail strip color */
} color_preset_t;

static const color_preset_t COLOR_PRESETS[14] = {
    { "Cyber Neon",     138,  43, 226,     0, 255, 128 },  /*  1 */
    { "Ice Crystal",      0, 234, 255,     0, 234, 255 },  /*  2 */
    { "Sunset Lava",    255, 100,   0,     0, 200, 255 },  /*  3 */
    { "Racing Gold",    255, 210,   0,   255, 210,   0 },  /*  4 */
    { "Flame Red",      255,   0,   0,   255,   0,   0 },  /*  5 */
    { "Police Flash",   255,   0,   0,     0,  80, 255 },  /*  6 */
    { "Sakura Pink",    255, 105, 180,   255,   0,  80 },  /*  7 */
    { "Aurora Purple",  180,   0, 255,     0, 255, 200 },  /*  8 */
    { "Amethyst",       148,   0, 211,   148,   0, 211 },  /*  9 */
    { "Mint Breeze",      0, 255, 180,   100, 200, 255 },  /* 10 */
    { "Jungle Green",     0, 255,  65,     0, 255,  65 },  /* 11 */
    { "Pure White",     225, 225, 225,   225, 225, 225 },  /* 12 */
    { "Blaze Orange",   255,  80,   0,   255, 200,  50 },  /* 13 */
    { "Neon Party",       0, 255, 255,   255,   0, 255 },  /* 14 */
};
