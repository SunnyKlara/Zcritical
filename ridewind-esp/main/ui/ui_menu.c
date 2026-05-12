/**
 * @file ui_menu.c
 * @brief UI5 — Bitmap-based menu with centered icon + text and navigation dots.
 *
 * Each menu page displays one centered icon bitmap and one centered text
 * bitmap (from the F4 STM32 project's existing arrays), plus 6 navigation
 * dots.  Page transitions use an 8-frame linear slide animation.
 */

#include "ui_menu.h"
#include "menu_icons.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

/* ── Static state ──────────────────────────────────────────── */

static int16_t  s_accum      = 0;   /* Encoder accumulator              */
static uint32_t s_last_tick  = 0;   /* Last page-switch timestamp (ms)  */
static uint8_t  s_need_redraw = 0;  /* Flag: full redraw needed         */

/* ── Helpers ───────────────────────────────────────────────── */

static uint8_t wrap_page(int8_t idx)
{
    return (uint8_t)((idx % MENU_PAGE_COUNT + MENU_PAGE_COUNT) % MENU_PAGE_COUNT);
}

/* ── Navigation dots ───────────────────────────────────────── */

static void draw_nav_dots(uint8_t active_idx)
{
    /* Clear the dot row */
    drv_lcd_fill_rect(0,
                      MENU_DOT_Y - MENU_DOT_RADIUS - 1,
                      LCD_WIDTH,
                      MENU_DOT_RADIUS * 2 + 3,
                      0x0000);

    /* Center 6 dots horizontally */
    uint16_t start_x = LCD_WIDTH / 2
                      - (MENU_PAGE_COUNT - 1) * MENU_DOT_SPACING / 2;

    for (uint8_t i = 0; i < MENU_PAGE_COUNT; i++) {
        uint16_t cx = start_x + i * MENU_DOT_SPACING;
        if (i == active_idx) {
            drv_lcd_draw_circle(cx, MENU_DOT_Y, MENU_DOT_RADIUS,
                                MENU_DOT_ACTIVE_COLOR, true);
        } else {
            drv_lcd_draw_circle(cx, MENU_DOT_Y, MENU_DOT_RADIUS,
                                MENU_DOT_INACTIVE_COLOR, true);
        }
    }
}

/* ── Clipped blit (for slide animation) ────────────────────── */

static void blit_clipped(const uint16_t *data, uint16_t w, uint16_t h,
                          int16_t x, uint16_t y)
{
    /* Fully off-screen — nothing to draw */
    if (x + (int16_t)w <= 0 || x >= (int16_t)LCD_WIDTH) {
        return;
    }

    /* Fully on-screen — single blit, no clipping needed */
    if (x >= 0 && x + w <= LCD_WIDTH) {
        drv_lcd_blit_rgb565((uint16_t)x, y, w, h, data);
        return;
    }

    /* Partially off-screen — row-by-row clipped blit */
    uint16_t src_x_offset = (x < 0) ? (uint16_t)(-x) : 0;
    uint16_t dst_x        = (x < 0) ? 0 : (uint16_t)x;
    uint16_t visible_w    = w - src_x_offset;

    if (visible_w > LCD_WIDTH - dst_x) {
        visible_w = LCD_WIDTH - dst_x;
    }

    for (uint16_t r = 0; r < h; r++) {
        drv_lcd_blit_rgb565(dst_x, y + r, visible_w, 1,
                            &data[r * w + src_x_offset]);
    }
}

/* ── Static page rendering ─────────────────────────────────── */

static void draw_static_page(uint8_t page_idx)
{
    const menu_page_info_t *page = &menu_pages[page_idx];

    /* Icon: centered horizontally, vertically centered on MENU_ICON_CENTER_Y */
    uint16_t icon_x = (LCD_WIDTH - page->icon_w) / 2;
    uint16_t icon_y = MENU_ICON_CENTER_Y - page->icon_h / 2;
    drv_lcd_blit_rgb565(icon_x, icon_y,
                        page->icon_w, page->icon_h,
                        (const uint16_t *)page->icon);

    /* Text: centered horizontally at MENU_TEXT_Y */
    uint16_t text_x = (LCD_WIDTH - page->text_w) / 2;
    drv_lcd_blit_rgb565(text_x, MENU_TEXT_Y,
                        page->text_w, page->text_h,
                        (const uint16_t *)page->text);

    /* Navigation dots */
    draw_nav_dots(page_idx);
}

/* ── Slide animation ───────────────────────────────────────── */

/* ── Scanline-composited slide animation (flicker-free) ──── */

/* Row buffer: one full-width scanline, 240 × 2 = 480 bytes on stack */
#define ROW_BUF_BYTES  (LCD_WIDTH * 2)

/**
 * Composite one bitmap row into the line buffer at a given X offset.
 * Handles clipping: pixels outside [0, LCD_WIDTH) are skipped.
 * Only non-black pixels are written (black = background = 0x0000).
 */
static void composite_row(uint8_t *buf, const uint16_t *bmp,
                          uint16_t bmp_w, uint16_t bmp_row,
                          int16_t bmp_x)
{
    const uint8_t *src = (const uint8_t *)&bmp[bmp_row * bmp_w];
    for (int16_t col = 0; col < (int16_t)bmp_w; col++) {
        int16_t sx = bmp_x + col;
        if (sx < 0) continue;
        if (sx >= (int16_t)LCD_WIDTH) break;
        uint16_t off = (uint16_t)sx * 2;
        uint8_t hi = src[col * 2];
        uint8_t lo = src[col * 2 + 1];
        if (hi | lo) {  /* skip black pixels (background) */
            buf[off]     = hi;
            buf[off + 1] = lo;
        }
    }
}

static uint8_t do_slide_animation(uint8_t cur_page, int8_t direction)
{
    uint8_t new_page = wrap_page((int8_t)cur_page + direction);

    /* Update dots immediately */
    draw_nav_dots(new_page);

    const menu_page_info_t *out_pg = &menu_pages[cur_page];
    const menu_page_info_t *in_pg  = &menu_pages[new_page];

    /* Pre-compute Y positions */
    uint16_t out_icon_y = MENU_ICON_CENTER_Y - out_pg->icon_h / 2;
    uint16_t out_text_y = MENU_TEXT_Y;
    uint16_t in_icon_y  = MENU_ICON_CENTER_Y - in_pg->icon_h / 2;
    uint16_t in_text_y  = MENU_TEXT_Y;

    uint16_t zone_top = MENU_ANIM_ZONE_TOP;
    uint16_t zone_bot = MENU_ANIM_ZONE_BOTTOM;
    uint16_t zone_h   = zone_bot - zone_top;

    uint8_t row_buf[ROW_BUF_BYTES];

    for (uint8_t frame = 0; frame < MENU_ANIM_FRAMES; frame++) {
        int16_t progress = (int16_t)((frame + 1) * LCD_WIDTH / MENU_ANIM_FRAMES);

        int16_t out_off, in_off;
        if (direction > 0) {
            out_off = -progress;
            in_off  = (int16_t)(LCD_WIDTH - progress);
        } else {
            out_off = progress;
            in_off  = -(int16_t)(LCD_WIDTH - progress);
        }

        /* Outgoing icon/text X (centered + offset) */
        int16_t out_icon_x = LCD_WIDTH / 2 + out_off - out_pg->icon_w / 2;
        int16_t out_text_x = LCD_WIDTH / 2 + out_off - out_pg->text_w / 2;
        int16_t in_icon_x  = LCD_WIDTH / 2 + in_off  - in_pg->icon_w / 2;
        int16_t in_text_x  = LCD_WIDTH / 2 + in_off  - in_pg->text_w / 2;

        /* Set window for the entire animation zone, write row by row */
        drv_lcd_set_window(0, zone_top, LCD_WIDTH - 1, zone_bot - 1);

        for (uint16_t row = 0; row < zone_h; row++) {
            uint16_t screen_y = zone_top + row;

            /* Start with black row */
            memset(row_buf, 0, ROW_BUF_BYTES);

            /* Composite outgoing icon */
            if (screen_y >= out_icon_y &&
                screen_y < out_icon_y + out_pg->icon_h) {
                composite_row(row_buf, out_pg->icon,
                              out_pg->icon_w,
                              screen_y - out_icon_y,
                              out_icon_x);
            }
            /* Composite outgoing text */
            if (screen_y >= out_text_y &&
                screen_y < out_text_y + out_pg->text_h) {
                composite_row(row_buf, out_pg->text,
                              out_pg->text_w,
                              screen_y - out_text_y,
                              out_text_x);
            }
            /* Composite incoming icon */
            if (screen_y >= in_icon_y &&
                screen_y < in_icon_y + in_pg->icon_h) {
                composite_row(row_buf, in_pg->icon,
                              in_pg->icon_w,
                              screen_y - in_icon_y,
                              in_icon_x);
            }
            /* Composite incoming text */
            if (screen_y >= in_text_y &&
                screen_y < in_text_y + in_pg->text_h) {
                composite_row(row_buf, in_pg->text,
                              in_pg->text_w,
                              screen_y - in_text_y,
                              in_text_x);
            }

            drv_lcd_write_data(row_buf, ROW_BUF_BYTES);
        }

        vTaskDelay(pdMS_TO_TICKS(MENU_ANIM_FRAME_DELAY));
    }

    /* Final static render */
    drv_lcd_fill_rect(0, zone_top, LCD_WIDTH, zone_h, 0x0000);
    draw_static_page(new_page);
    return new_page;
}

/* ── Public API ────────────────────────────────────────────── */

void ui_menu_enter(void)
{
    s_accum = 0;
    s_need_redraw = 1;
}

void ui_menu_update(void)
{
    /* ── 1. BLE auto-enter ── */
    if (g_app_state.auto_enter) {
        g_app_state.auto_enter = 0;
        uint8_t sel = g_app_state.menu_selected;
        if (sel >= 1 && sel <= MENU_PAGE_COUNT) {
            ui_manager_set_ui(menu_pages[sel - 1].target_ui);
        }
        return;
    }

    /* ── 2. Full redraw on enter ── */
    if (s_need_redraw) {
        drv_lcd_clear(0x0000);
        draw_static_page(g_app_state.menu_selected - 1);
        s_need_redraw = 0;
    }

    /* ── 3. Poll encoder events ── */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        if (evt.type == ENC_EVT_ROTATE) {
            uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
            s_accum += evt.delta;

            if ((now - s_last_tick >= MENU_SWITCH_DEBOUNCE_MS) &&
                (s_accum >= MENU_DELTA_THRESHOLD ||
                 s_accum <= -MENU_DELTA_THRESHOLD))
            {
                int8_t dir = (s_accum > 0) ? 1 : -1;
                uint8_t cur_page = g_app_state.menu_selected - 1;

                uint8_t new_page = do_slide_animation(cur_page, dir);

                g_app_state.menu_selected = new_page + 1;

                /* Drain pending encoder events */
                encoder_event_t drain;
                while (drv_encoder_poll(&drain)) {}

                s_accum = 0;
                s_last_tick = xTaskGetTickCount() * portTICK_PERIOD_MS;
            }
        }
        else if (evt.type == ENC_EVT_CLICK) {
            uint8_t sel = g_app_state.menu_selected;
            if (sel >= 1 && sel <= MENU_PAGE_COUNT) {
                ui_manager_set_ui(menu_pages[sel - 1].target_ui);
                return;
            }
        }
    }
}
