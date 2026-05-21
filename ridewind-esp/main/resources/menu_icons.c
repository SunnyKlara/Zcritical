/**
 * @file menu_icons.c
 * @brief Menu bitmap data and lookup table.
 *
 * Includes the 12 F4 bitmap arrays (6 icons + 6 text labels) from the
 * 取模数组/ directory and defines the menu_pages[] lookup table used by
 * ui_menu.c for static rendering and slide animation.
 */

#include "menu_icons.h"

/* ── Icon bitmap arrays ── */
#include "fengsu_68_58.c"
#include "tiaosepan_74_74.c"
#include "rgbtubiao.c"
#include "brighttubiao.c"
#include "logotubiao.c"
#include "voicetubiao.c"

/* ── Text label bitmap arrays ── */
#include "speed_99_33.c"
#include "new_color.c"
#include "rgb.c"
#include "bright.c"
#include "logo.c"
#include "voice.c"
#include "VOI.c"

/* ── Lookup table: one entry per menu page ── */
const menu_page_info_t menu_pages[MENU_PAGE_COUNT] = {
    /* 0 — Speed */
    { (const uint16_t *)gImage_fengsu_68_58,     68, 58,
      (const uint16_t *)gImage_speed_99_33,      99, 33, 1 },
    /* 1 — Color (skip 8-byte header in gImage_new_color) */
    { (const uint16_t *)gImage_tiaosepan_74_74,  74, 74,
      (const uint16_t *)(gImage_new_color + 8),  88, 31, 2 },
    /* 2 — RGB */
    { (const uint16_t *)gImage_rgbtubiao,        65, 68,
      (const uint16_t *)gImage_rgb,              72, 27, 3 },
    /* 3 — Bright */
    { (const uint16_t *)gImage_brighttubiao,     72, 72,
      (const uint16_t *)gImage_bright,          103, 33, 4 },
    /* 4 — Logo */
    { (const uint16_t *)gImage_logotubiao,       68, 68,
      (const uint16_t *)gImage_logo,             79, 33, 6 },
};
