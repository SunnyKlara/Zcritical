#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "app_state.h"
#include "board_config.h"
#include "protocol.h"
#include "ble_service.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "drv_pwm.h"
#include "drv_gpio.h"
#include "led_effects.h"
#include "preset_colors.h"
#include "ui_manager.h"
#include "encoder_handler.h"

static const char *TAG = "MAIN";

static inline uint16_t rgb565_color(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/* Command message queue: BLE → Main_Task */
QueueHandle_t cmd_queue;

/* ═══════════════════════════════════════════════════════════════
 *  BLE Command Dispatch — apply cmd_msg_t to AppState + hardware
 * ═══════════════════════════════════════════════════════════════ */
static void dispatch_ble_command(const cmd_msg_t *cmd)
{
    char resp[64];

    APP_STATE_LOCK();

    switch (cmd->type) {

    /* ── FAN:xx ── */
    case CMD_FAN:
        if (g_app_state.wuhuaqi_state != 2) {  /* not in throttle mode */
            g_app_state.fan_speed = cmd->param.u8_val;
            drv_pwm_set_duty(cmd->param.u8_val);
        }
        ble_service_notify_str("OK:FAN\r\n");
        break;

    /* ── SPEED:xxx ── */
    case CMD_SPEED: {
        int16_t spd = cmd->param.i16_val;
        g_app_state.current_speed_kmh = spd;
        g_app_state.last_reported_speed = spd;
        /* Map speed to fan: binary threshold at 60 km/h */
        if (g_app_state.wuhuaqi_state == 2) {
            /* Throttle mode: proportional fan */
            uint8_t fan = (uint8_t)((spd * 100 + 170) / 340);
            if (fan > 100) fan = 100;
            g_app_state.fan_speed = fan;
            drv_pwm_set_duty(fan);
            g_app_state.remote_active_tick = xTaskGetTickCount();
        }
        /* No OK response for SPEED (matches STM32 behavior) */
        break;
    }

    /* ── WUHUA:x ── */
    case CMD_WUHUA:
        if (g_app_state.wuhuaqi_state != 2) {
            g_app_state.wuhuaqi_state = cmd->param.u8_val;
            g_app_state.wuhuaqi_state_saved = cmd->param.u8_val;
            drv_gpio_set_humidifier(cmd->param.u8_val != 0);
        }
        ble_service_notify_str("OK:WUHUA\r\n");
        break;

    /* ── LED:s:r:g:b ── */
    case CMD_LED: {
        uint8_t s = cmd->param.led.strip - 1;  /* 1-based → 0-based */
        if (s < 4) {
            g_app_state.led_colors[s][0] = cmd->param.led.r;
            g_app_state.led_colors[s][1] = cmd->param.led.g;
            g_app_state.led_colors[s][2] = cmd->param.led.b;
            g_app_state.led_edit[s][0] = cmd->param.led.r;
            g_app_state.led_edit[s][1] = cmd->param.led.g;
            g_app_state.led_edit[s][2] = cmd->param.led.b;
            drv_led_set_strip_color((led_strip_id_t)s,
                cmd->param.led.r, cmd->param.led.g, cmd->param.led.b);
            drv_led_refresh();
        }
        ble_service_notify_str("OK:LED\r\n");
        break;
    }

    /* ── PRESET:x ── */
    case CMD_PRESET: {
        uint8_t idx = cmd->param.u8_val;
        g_app_state.preset_index = idx;
        g_app_state.preset_dirty = 1;
        /* Apply preset colors from table (1-based index) */
        if (idx >= 1 && idx <= COLOR_PRESET_COUNT) {
            const color_preset_t *p = &COLOR_PRESETS[idx - 1];
            /* Left/Main strip gets lr,lg,lb; Right/Tail gets rr,rg,rb */
            g_app_state.led_colors[0][0] = p->lr;  /* Main */
            g_app_state.led_colors[0][1] = p->lg;
            g_app_state.led_colors[0][2] = p->lb;
            g_app_state.led_colors[1][0] = p->lr;  /* Left */
            g_app_state.led_colors[1][1] = p->lg;
            g_app_state.led_colors[1][2] = p->lb;
            g_app_state.led_colors[2][0] = p->rr;  /* Right */
            g_app_state.led_colors[2][1] = p->rg;
            g_app_state.led_colors[2][2] = p->rb;
            g_app_state.led_colors[3][0] = p->rr;  /* Tail */
            g_app_state.led_colors[3][1] = p->rg;
            g_app_state.led_colors[3][2] = p->rb;
            /* Apply to LEDs */
            for (int i = 0; i < 4; i++) {
                drv_led_set_strip_color((led_strip_id_t)i,
                    g_app_state.led_colors[i][0],
                    g_app_state.led_colors[i][1],
                    g_app_state.led_colors[i][2]);
            }
            drv_led_refresh();
        }
        ble_service_notify_str("OK:PRESET\r\n");
        break;
    }

    /* ── BRIGHT:xx ── */
    case CMD_BRIGHT:
        g_app_state.brightness = cmd->param.u8_val;
        drv_led_set_brightness(cmd->param.u8_val);
        drv_led_refresh();
        ble_service_notify_str("OK:BRIGHT\r\n");
        break;

    /* ── UI:x ── */
    case CMD_UI:
        /* Use ui_manager for proper transition with encoder delta clear */
        if (cmd->param.u8_val >= 1 && cmd->param.u8_val <= 4) {
            g_app_state.menu_selected = cmd->param.u8_val;
            g_app_state.auto_enter = 1;
            ui_manager_set_ui(5);
        } else {
            ui_manager_set_ui(cmd->param.u8_val);
        }
        ble_service_notify_str("OK:UI\r\n");
        break;

    /* ── LCD:x ── */
    case CMD_LCD:
        if (cmd->param.u8_val == 0) {
            drv_lcd_clear(0x0000);
            g_app_state.ui = 255;  /* disable UI updates */
        } else {
            g_app_state.ui = 5;
            g_app_state.chu = 5;
        }
        ble_service_notify_str("OK:LCD\r\n");
        break;

    /* ── UNIT:x ── */
    case CMD_UNIT:
        g_app_state.speed_unit = cmd->param.u8_val;
        ble_service_notify_str("OK:UNIT\r\n");
        break;

    /* ── THROTTLE:x ── */
    case CMD_THROTTLE:
        if (cmd->param.u8_val == 1) {
            g_app_state.wuhuaqi_state_saved = g_app_state.wuhuaqi_state;
            g_app_state.wuhuaqi_state = 2;
            g_app_state.throttle_was_remote = 1;
            drv_gpio_set_humidifier(true);
            /* TODO Phase 7: EngineAudio_Start() */
        } else {
            g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
            g_app_state.fan_speed = 0;
            g_app_state.current_speed_kmh = 0;
            drv_pwm_set_duty(0);
            g_app_state.throttle_was_remote = 0;
            if (g_app_state.wuhuaqi_state == 0) {
                drv_gpio_set_humidifier(false);
            }
            /* TODO Phase 7: EngineAudio_Stop() */
        }
        ble_service_notify_str("OK:THROTTLE\r\n");
        break;

    /* ── STREAMLIGHT:x ── */
    case CMD_STREAMLIGHT: {
        g_app_state.streamlight_active = cmd->param.u8_val;
        if (cmd->param.u8_val) {
            led_effects_streamlight_start();
        } else {
            led_effects_streamlight_stop();
        }
        snprintf(resp, sizeof(resp), "OK:STREAMLIGHT:%d\r\n", cmd->param.u8_val);
        ble_service_notify_str(resp);
        break;
    }

    /* ── LED_GRADIENT:s:r:g:b:speed ── */
    case CMD_LED_GRADIENT: {
        uint8_t s = cmd->param.led_gradient.strip - 1;
        if (s < 4) {
            g_app_state.led_colors[s][0] = cmd->param.led_gradient.r;
            g_app_state.led_colors[s][1] = cmd->param.led_gradient.g;
            g_app_state.led_colors[s][2] = cmd->param.led_gradient.b;
            g_app_state.led_edit[s][0] = cmd->param.led_gradient.r;
            g_app_state.led_edit[s][1] = cmd->param.led_gradient.g;
            g_app_state.led_edit[s][2] = cmd->param.led_gradient.b;
            led_effects_start_gradient(s,
                cmd->param.led_gradient.r,
                cmd->param.led_gradient.g,
                cmd->param.led_gradient.b,
                cmd->param.led_gradient.speed);
        }
        ble_service_notify_str("OK:LED_GRADIENT\r\n");
        break;
    }

    /* ── VOL:xx ── */
    case CMD_VOLUME:
        g_app_state.volume = cmd->param.u8_val;
        /* TODO Phase 7: audio_engine_set_volume(cmd->param.u8_val) */
        ble_service_notify_str("OK:VOL\r\n");
        break;

    /* ── GET commands ── */
    case CMD_GET_FAN:
        snprintf(resp, sizeof(resp), "FAN:%d\r\n", g_app_state.fan_speed);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_WUHUA:
        snprintf(resp, sizeof(resp), "WUHUA:%d\r\n",
                 g_app_state.wuhuaqi_state == 1 ? 1 : 0);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_BRIGHT:
        snprintf(resp, sizeof(resp), "BRIGHT:%d\r\n", g_app_state.brightness);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_STREAMLIGHT:
        snprintf(resp, sizeof(resp), "STREAMLIGHT:%d\r\n", g_app_state.streamlight_active);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_PRESET:
        snprintf(resp, sizeof(resp), "PRESET_REPORT:%d\r\n", g_app_state.preset_index);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_ALL:
        snprintf(resp, sizeof(resp), "STATUS:FAN:%d:WUHUA:%d:BRIGHT:%d\r\n",
                 g_app_state.fan_speed,
                 g_app_state.wuhuaqi_state == 1 ? 1 : 0,
                 g_app_state.brightness);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_UI:
        snprintf(resp, sizeof(resp), "UI:%d\r\n", g_app_state.ui);
        ble_service_notify_str(resp);
        break;

    case CMD_GET_LOGO:
        /* TODO Phase 9: return logo slot info */
        ble_service_notify_str("LOGO:NONE\r\n");
        break;

    case CMD_GET_VOLUME:
        snprintf(resp, sizeof(resp), "VOL:%d\r\n", g_app_state.volume);
        ble_service_notify_str(resp);
        break;

    /* ── LOGO / OTA — stub for Phase 9/10 ── */
    case CMD_LOGO_START:
    case CMD_LOGO_DATA:
    case CMD_LOGO_END:
    case CMD_LOGO_DELETE:
        /* TODO Phase 9: logo upload handling */
        ble_service_notify_str("ERR:NOT_IMPL\r\n");
        break;

    case CMD_OTA_START:
    case CMD_OTA_DATA:
    case CMD_OTA_END:
        /* TODO Phase 10: OTA handling */
        ble_service_notify_str("ERR:NOT_IMPL\r\n");
        break;

    default:
        break;
    }

    APP_STATE_UNLOCK();
}

/* ═══════════════════════════════════════════════════════════════
 *  Main Control Task — Core 1, 20ms period
 *  Single modifier of AppState. Processes encoder, UI, LED, PWM.
 * ═══════════════════════════════════════════════════════════════ */
static void main_task(void *arg)
{
    cmd_msg_t cmd;

    for (;;) {
        /* Drain command queue (non-blocking) */
        while (xQueueReceive(cmd_queue, &cmd, 0) == pdTRUE) {
            dispatch_ble_command(&cmd);
        }

        /* Phase 6: UI state machine + LED effects */
        ui_manager_update();
        led_effects_process();

        /* Feed watchdog — LCD SPI operations can take a while */
        vTaskDelay(pdMS_TO_TICKS(MAIN_TASK_PERIOD_MS));
    }
}

/* ═══════════════════════════════════════════════════════════════ */
void app_main(void)
{
    ESP_LOGI(TAG, "RideWind ESP32 started");

    /* 0. NVS flash init (required by Bluedroid) */
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* 1. AppState init (factory defaults) */
    app_state_init();

    /* 2. Command queue */
    cmd_queue = xQueueCreate(CMD_QUEUE_DEPTH, sizeof(cmd_msg_t));

    /* Phase 1: LCD init + test pattern */
    drv_lcd_init();
    drv_lcd_fill_rect(0, 0, 240, 240, 0x0000);
    drv_lcd_draw_string(40, 100, "RideWind", 0x07FF, 0x0000, 2);
    drv_lcd_draw_string(60, 140, "ESP32-S3", 0xFFFF, 0x0000, 2);
    drv_lcd_draw_circle(120, 120, 118, 0x07FF, false);
    ESP_LOGI(TAG, "LCD test pattern displayed");

    /* Phase 2: LED init */
    drv_led_init();
    ESP_LOGI(TAG, "LED init complete");

    /* Phase 3: Encoder init */
    drv_encoder_init();

    /* Phase 4: Fan PWM + Humidifier GPIO */
    drv_pwm_init();
    drv_gpio_init();
    drv_pwm_set_duty(0);  /* Fan off at boot */
    drv_gpio_set_humidifier(g_app_state.wuhuaqi_state != 0);
    ESP_LOGI(TAG, "Fan PWM + Humidifier init");

    /* Phase 5: BLE init + advertising */
    ble_service_init();
    ESP_LOGI(TAG, "BLE initialized, advertising as \"%s\"", BLE_DEVICE_NAME);

    /* Phase 6: LED effects init */
    led_effects_init();

    /* Initialize gradient current colors from AppState */
    for (int i = 0; i < 4; i++) {
        g_app_state.gradient[i].current_r = g_app_state.led_colors[i][0];
        g_app_state.gradient[i].current_g = g_app_state.led_colors[i][1];
        g_app_state.gradient[i].current_b = g_app_state.led_colors[i][2];
    }

    /* Apply factory default LED colors */
    drv_led_set_brightness((uint8_t)g_app_state.brightness);
    for (int i = 0; i < 4; i++) {
        drv_led_set_strip_color((led_strip_id_t)i,
            g_app_state.led_colors[i][0],
            g_app_state.led_colors[i][1],
            g_app_state.led_colors[i][2]);
    }
    drv_led_refresh();

    /* UI manager init (sets UI5 menu as default) */
    ui_manager_init();

    /* Phase 6 Task 13.14: Boot logo display (2 seconds) */
    drv_lcd_clear(0x0000);
    drv_lcd_draw_string(50, 90, "RideWind", 0x07FF, 0x0000, 2);
    drv_lcd_draw_string(75, 130, "v1.0", rgb565_color(0x80, 0x80, 0x80), 0x0000, 1);
    drv_lcd_draw_circle(120, 120, 60, 0x07FF, false);
    /* TODO Phase 9: load custom logo from LittleFS if available */
    vTaskDelay(pdMS_TO_TICKS(BOOT_LOGO_DURATION_MS));
    /* Transition to UI5 menu */
    ui_manager_set_ui(5);

    /* TODO Phase 7: drv_audio_init(), a2dp_service_init(), audio_engine_init() */
    /* TODO Phase 8: storage_init(), storage_load_settings() */

    /* Start Main_Task on Core 1 */
    xTaskCreatePinnedToCore(main_task, "main_task", 8192, NULL, 5, NULL, 1);

    ESP_LOGI(TAG, "Main task started on Core 1");
}
