#include "ui_manager.h"
#include "app_state.h"
#include "drv_lcd.h"
#include "drv_encoder.h"
#include "encoder_handler.h"
#include "ui_menu.h"
#include "ui_speed.h"
#include "ui_preset.h"
#include "ui_rgb.h"
#include "ui_bright.h"
#include "ui_logo.h"
#include "ui_volume.h"
#include "ui_treadmill.h"
#include "audio_player.h"
#include "board_config.h"
#include "esp_log.h"

static const char *TAG = "UI_MGR";

void ui_manager_init(void)
{
    /* Boot into menu (UI5) — boot logo handled separately in main.c */
    g_app_state.ui  = 5;
    g_app_state.chu = 5;
}

static uint8_t s_last_ui = 0xFF;  /* track UI changes for init detection */

void ui_manager_update(void)
{
    uint8_t ui = g_app_state.ui;

    /* Skip UI updates when display is off */
    if (ui == 255) return;

    /* ── Detect UI transition and call enter() ── */
    if (ui != s_last_ui) {
        g_app_state.encoder_delta = 0;  /* Property 12: clear delta on transition */
        ESP_LOGI(TAG, "UI transition → %d", ui);

        switch (ui) {
        case 1: ui_speed_enter();  break;
        case 2: ui_preset_enter(); break;
        case 3: ui_rgb_enter();    break;
        case 4: ui_bright_enter(); break;
        case 5: ui_menu_enter();   break;
        case 6: ui_logo_enter();   break;
        case 7: ui_volume_enter(); break;
        case 8: ui_treadmill_enter(); break;
        default: break;
        }
        s_last_ui = ui;
    }

    /* ── Dispatch to per-screen update ── */
    switch (ui) {
    case 1: ui_speed_update();  break;
    case 2: ui_preset_update(); break;
    case 3: ui_rgb_update();    break;
    case 4: ui_bright_update(); break;
    case 5: ui_menu_update();   break;
    case 6: ui_logo_update();   break;
    case 7: ui_volume_update(); break;
    case 8: ui_treadmill_update(); break;
    default: break;
    }
}

void ui_manager_set_ui(uint8_t target_ui)
{
    uint8_t old_ui = g_app_state.ui;
    g_app_state.encoder_delta = 0;  /* Property 12 */
    g_app_state.ui  = target_ui;
    g_app_state.chu = target_ui;

    /* Exit cleanup for old UI — stop resources that shouldn't persist */
    if (old_ui == 1 && target_ui != 1) {
        /* Leaving speed UI: stop engine sound */
        audio_player_stop_engine();
    }
}

uint8_t ui_manager_get_ui(void)
{
    return g_app_state.ui;
}
