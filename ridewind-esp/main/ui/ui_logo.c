/**
 * @file ui_logo.c
 * @brief UI6 — Logo Management
 *
 * Displays logo images from LittleFS slots using chunked reading.
 * F4 style: full-screen logo display, slot dots at bottom,
 * long-press delete with progress bar.
 *
 * Note: Logo UI doesn't use gImage_beijing_240_240 background —
 * it shows the actual logo image full-screen, or black if empty.
 */

#include "ui_logo.h"
#include "ui_common.h"
#include "ui_images.h"
#include "storage.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "board_config.h"
#include "esp_log.h"
#include <stdio.h>
#include <string.h>

static const char *TAG = "UI_LOGO";

static uint8_t s_need_redraw = 1;
static uint8_t s_last_slot = 0xFF;

/* Display logo from LittleFS by reading row-by-row */
static bool display_logo_from_file(uint8_t slot)
{
    char path[48];
    snprintf(path, sizeof(path), LITTLEFS_MOUNT_POINT "/logo_%d.bin", slot);

    FILE *f = fopen(path, "rb");
    if (!f) return false;

    logo_header_t hdr;
    if (fread(&hdr, 1, sizeof(hdr), f) != sizeof(hdr) ||
        hdr.magic != LOGO_MAGIC) {
        fclose(f);
        return false;
    }

    uint16_t row_buf[LOGO_WIDTH];
    for (uint16_t y = 0; y < LOGO_HEIGHT; y++) {
        size_t n = fread(row_buf, 1, sizeof(row_buf), f);
        if (n < sizeof(row_buf)) {
            memset((uint8_t *)row_buf + n, 0, sizeof(row_buf) - n);
        }
        drv_lcd_blit_rgb565(0, y, LOGO_WIDTH, 1, row_buf);
    }

    fclose(f);
    return true;
}

static void draw_logo_screen(void)
{
    uint8_t slot = g_app_state.logo_view_slot;

    if (slot == s_last_slot && !s_need_redraw) return;

    bool has_logo = storage_logo_exists(slot);

    if (has_logo) {
        if (!display_logo_from_file(slot)) {
            has_logo = false;
        }
    }

    if (!has_logo) {
        /* Empty slot: black screen with "No Custom Logo" text */
        drv_lcd_clear(0x0000);
        drv_lcd_draw_string(40, 100, "No Custom Logo", 0x4208, 0x0000, 1);
        char buf[16];
        snprintf(buf, sizeof(buf), "Slot %d", slot);
        drv_lcd_draw_string(85, 120, buf, 0x4208, 0x0000, 1);
    }

    /* Slot indicator dots at bottom */
    for (uint8_t i = 0; i < MAX_LOGO_SLOTS; i++) {
        uint16_t dx = 100 + i * 20;
        uint16_t color;
        if (i == slot) {
            color = 0xFFFF;  /* white = current */
        } else if (storage_logo_exists(i)) {
            color = 0x07E0;  /* green = has logo */
        } else {
            color = 0x4208;  /* dark gray = empty */
        }
        drv_lcd_draw_circle(dx, 220, 4, color, true);
    }

    /* Active indicator */
    if (slot == g_app_state.active_logo_slot && has_logo) {
        /* Green LED indicator at top */
        ui_draw_f4_led(110, 5, 1);
    }

    s_last_slot = slot;
    s_need_redraw = 0;
}

static void show_delete_progress(uint8_t slot)
{
    /* F4 style: rounded progress bar at bottom center */
    drv_lcd_fill_rect(40, 100, 160, 40, 0x2104);
    drv_lcd_draw_string(55, 105, "Deleting...", 0xFFFF, 0x2104, 1);

    for (int p = 0; p <= 100; p += 10) {
        uint16_t w = (uint16_t)(p * 140 / 100);
        drv_lcd_fill_rect(50, 125, w, 8, 0xF800);  /* red progress */
        vTaskDelay(pdMS_TO_TICKS(30));
    }

    storage_logo_delete(slot);

    if (g_app_state.active_logo_slot == slot) {
        g_app_state.active_logo_slot = 0;
        storage_save_current();
    }

    s_need_redraw = 1;
}

void ui_logo_enter(void)
{
    s_need_redraw = 1;
    s_last_slot = 0xFF;
    g_app_state.logo_view_slot = g_app_state.active_logo_slot;
}

void ui_logo_update(void)
{
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            int8_t s = g_app_state.logo_view_slot + (evt.delta > 0 ? 1 : -1);
            if (s < 0) s = MAX_LOGO_SLOTS - 1;
            if (s >= MAX_LOGO_SLOTS) s = 0;
            g_app_state.logo_view_slot = s;
            s_need_redraw = 1;
            break;
        }
        case ENC_EVT_CLICK:
            if (storage_logo_exists(g_app_state.logo_view_slot)) {
                g_app_state.active_logo_slot = g_app_state.logo_view_slot;
                storage_save_current();
                ESP_LOGI(TAG, "Active logo set to slot %d",
                         g_app_state.active_logo_slot);
            }
            s_need_redraw = 1;
            break;

        case ENC_EVT_LONG_PRESS:
            if (storage_logo_exists(g_app_state.logo_view_slot)) {
                show_delete_progress(g_app_state.logo_view_slot);
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }

    draw_logo_screen();
}
