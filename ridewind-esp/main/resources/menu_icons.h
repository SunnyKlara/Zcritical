#pragma once

#include <stdint.h>
#include "board_config.h"

/* ── Bitmap arrays (from F4 取模数组/) ── */

/* Icons */
extern const unsigned char gImage_fengsu_68_58[];      /* Speed icon:  68×58  */
extern const unsigned char gImage_tiaosepan_74_74[];   /* Color icon:  74×74  */
extern const unsigned char gImage_rgbtubiao[];         /* RGB icon:    65×68  */
extern const unsigned char gImage_brighttubiao[];      /* Bright icon: 72×72  */
extern const unsigned char gImage_logotubiao[];        /* Logo icon:   68×68  */
extern const unsigned char gImage_voicetubiao[];       /* Volume icon: 73×58  */

/* Text labels */
extern const unsigned char gImage_speed_99_33[];       /* "Speed":  99×33  */
extern const unsigned char gImage_new_color[];         /* "Color":  88×31 (has 8-byte header) */
extern const unsigned char gImage_rgb[];               /* "RGB":    72×27  */
extern const unsigned char gImage_bright[];            /* "Bright": 103×33 */
extern const unsigned char gImage_logo[];              /* "Logo":   79×33  */
extern const unsigned char gImage_voice[];             /* "Volume": 90×27  */

/* ── Lookup table ── */
typedef struct {
    const uint16_t *icon;
    uint16_t        icon_w;
    uint16_t        icon_h;
    const uint16_t *text;
    uint16_t        text_w;
    uint16_t        text_h;
    uint8_t         target_ui;   /* Sub-UI to enter on click */
} menu_page_info_t;

extern const menu_page_info_t menu_pages[MENU_PAGE_COUNT];
