/**
 * @file main.c
 * @brief 应用入口 + BLE 命令分发 + 外设初始化序列
 *
 * app_main() 按阶段初始化所有外设，然后启动 main_task。
 * main_task 以 20ms 周期运行：排空命令队列 → 更新 UI → 刷新 LED → 风扇平滑。
 * dispatch_ble_command() 是所有 BLE 命令的唯一入口。
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_crc.h"
#include "esp_heap_caps.h"
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
#include "drv_audio.h"
#include "wifi_audio_service.h"
#include "wifi_comm_service.h"
#include "audio_engine.h"
#include "audio_player.h"
#include "storage.h"
#include "boot_logo_240.h"
#include "ota_service.h"
#include "selftest.h"
#include "esp_app_desc.h"

static const char *TAG = "MAIN";

/* Helper: notify both BLE and WebSocket for Logo/Audio upload responses.
 * Commands can arrive from either channel, so responses go to both. */
static void dual_notify_str(const char *str)
{
    ble_service_notify_str(str);
    wifi_comm_service_notify_str(str);
}

static inline uint16_t rgb565_color(uint8_t r, uint8_t g, uint8_t b)
{
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

/* Command message queue: BLE → Main_Task */
QueueHandle_t cmd_queue;

/* ═══════════════════════════════════════════════════════════════
 *  Logo upload — Simple PSRAM buffer approach (like F4)
 *
 *  Key insight: Don't use ring buffers or async file I/O.
 *  Just buffer everything in PSRAM, write file once at the end.
 *  BLE callback does: hex decode → PSRAM memcpy → ACK. All synchronous.
 *
 *  Protocol (hex mode, compatible with F4 APP):
 *    APP sends: LOGO_START:slot:size:crc32\n
 *    ESP replies: LOGO_READY:slot\r\n
 *    APP sends: LOGO_DATA:seq:hex\n × N
 *    ESP replies: LOGO_ACK:seq\r\n (every 16 packets)
 *    APP sends: LOGO_END\n
 *    ESP replies: LOGO_OK:slot\r\n or LOGO_FAIL:reason\r\n
 * ═══════════════════════════════════════════════════════════════ */

#include <sys/stat.h>

#define LOGO_PKT_SIZE       16
#define LOGO_BATCH_SIZE     16    /* ACK every 16 packets */

static struct {
    bool     active;
    uint8_t  slot;
    uint32_t expected_size;
    uint32_t expected_crc32;
    uint32_t received;       /* bytes decoded into PSRAM buffer */
    int32_t  last_seq;
    uint32_t pkt_count;      /* packets since last ACK */
    uint8_t *buf;            /* PSRAM buffer for entire image */
} s_logo_rx = {0};

/* ═══════════════════════════════════════════════════════════════
 *  Hex decode + PSRAM buffer — called from BLE callback (Core 0)
 *  Fast: just decode hex and memcpy. No file I/O, no ring buffer.
 * ═══════════════════════════════════════════════════════════════ */
static uint8_t hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return 0xFF;
}

void logo_upload_feed_hex(const char *hex_str, uint16_t len)
{
    if (!s_logo_rx.active || !hex_str || !s_logo_rx.buf) {
        dual_notify_str("LOGO_ERROR:NO_SESSION\r\n");
        return;
    }

    /* Parse seq number: "seq:hex_data" */
    int seq = 0;
    const char *p = hex_str;
    while (*p >= '0' && *p <= '9' && p < hex_str + len) {
        seq = seq * 10 + (*p - '0');
        p++;
    }
    if (*p == ':') { p++; } else { p = hex_str; seq = -1; }

    /* Decode hex pairs directly into PSRAM buffer */
    uint16_t remaining = (uint16_t)(len - (uint16_t)(p - hex_str));
    for (uint16_t i = 0; i + 1 < remaining; i += 2) {
        uint8_t hi = hex_nibble(p[i]);
        uint8_t lo = hex_nibble(p[i + 1]);
        if (hi == 0xFF || lo == 0xFF) continue;

        if (s_logo_rx.received < s_logo_rx.expected_size) {
            s_logo_rx.buf[s_logo_rx.received++] = (hi << 4) | lo;
        }
    }

    /* Track seq and send ACK every 16 packets — synchronous, no waiting */
    if (seq >= 0) {
        s_logo_rx.last_seq = seq;
        s_logo_rx.pkt_count++;

        if (s_logo_rx.pkt_count >= LOGO_BATCH_SIZE) {
            char ack[32];
            snprintf(ack, sizeof(ack), "LOGO_ACK:%d\r\n", seq);
            dual_notify_str(ack);
            ESP_LOGI(TAG, "ACK sent: seq=%d received=%u", seq, (unsigned)s_logo_rx.received);
            s_logo_rx.pkt_count = 0;
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Binary logo upload — raw bytes directly to PSRAM (no hex decode)
 *  Called from BLE callback when binary mode is active.
 *  ~8x faster than hex mode: 244 bytes/packet vs 16 bytes/packet
 * ═══════════════════════════════════════════════════════════════ */
static bool s_logo_binary_mode = false;
static uint32_t s_logo_bin_batch_bytes = 0;  /* bytes since last ACK */
/* ACK every ~4KB (matches APP segment size: 16 BLE packets × 244 bytes) */
#define LOGO_BIN_ACK_INTERVAL  (16 * 244)  /* ~3904 bytes */

void logo_upload_feed_binary(const uint8_t *data, uint16_t len)
{
    if (!s_logo_rx.active || !s_logo_rx.buf || !data || len == 0) {
        if (!s_logo_rx.active) {
            dual_notify_str("LOGO_ERROR:NO_SESSION\r\n");
        }
        return;
    }

    /* Bounds check: prevent writing past allocated buffer */
    if (s_logo_rx.received >= s_logo_rx.expected_size) return;

    /* Copy raw bytes directly to PSRAM — no hex decode needed */
    uint32_t space = s_logo_rx.expected_size - s_logo_rx.received;
    uint16_t copy_len = (len <= space) ? len : (uint16_t)space;
    memcpy(s_logo_rx.buf + s_logo_rx.received, data, copy_len);
    s_logo_rx.received += copy_len;

    /* ACK based on byte count (equivalent to every 16 hex packets) */
    s_logo_bin_batch_bytes += copy_len;
    if (s_logo_bin_batch_bytes >= LOGO_BIN_ACK_INTERVAL ||
        s_logo_rx.received >= s_logo_rx.expected_size) {
        char ack[48];
        snprintf(ack, sizeof(ack), "LOGO_ACK_BIN:%u\r\n", (unsigned)s_logo_rx.received);
        ESP_LOGI(TAG, "BIN ACK: received=%u/%u", (unsigned)s_logo_rx.received,
                 (unsigned)s_logo_rx.expected_size);
        dual_notify_str(ack);
        s_logo_bin_batch_bytes = 0;
    }
}

bool logo_is_binary_mode(void) { return s_logo_binary_mode; }

static void logo_rx_cleanup(void)
{
    s_logo_rx.active = false;
    s_logo_rx.received = 0;
    s_logo_rx.expected_size = 0;
    s_logo_rx.last_seq = -1;
    s_logo_rx.pkt_count = 0;
    s_logo_binary_mode = false;
    s_logo_bin_batch_bytes = 0;
    if (s_logo_rx.buf) {
        free(s_logo_rx.buf);
        s_logo_rx.buf = NULL;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Audio upload — PSRAM buffer approach (same pattern as Logo)
 *
 *  Protocol (binary mode):
 *    APP sends: AUDIO_START_BIN:layer:size:crc32\n
 *    ESP replies: AUDIO_READY:layer\r\n
 *    APP sends: raw binary PCM data in BLE packets
 *    ESP replies: AUDIO_ACK_BIN:received_bytes\r\n (every ~4KB)
 *    APP sends: AUDIO_END\n
 *    ESP replies: AUDIO_OK:layer\r\n or AUDIO_FAIL:reason\r\n
 * ═══════════════════════════════════════════════════════════════ */
static struct {
    bool     active;
    uint8_t  layer;          /* 0=idle, 1=low, 2=mid, 3=high */
    uint32_t expected_size;
    uint32_t expected_crc32;
    uint32_t received;
    uint8_t *buf;            /* PSRAM buffer */
} s_audio_rx = {0};

static bool s_audio_binary_mode = false;
static uint32_t s_audio_bin_batch_bytes = 0;
#define AUDIO_BIN_ACK_INTERVAL  (16 * 244)

/* Called from BLE callback for binary audio data */
void audio_upload_feed_binary(const uint8_t *data, uint16_t len)
{
    if (!s_audio_rx.active || !s_audio_rx.buf || !data || len == 0) {
        if (!s_audio_rx.active) {
            dual_notify_str("AUDIO_ERROR:NO_SESSION\r\n");
        }
        return;
    }

    if (s_audio_rx.received >= s_audio_rx.expected_size) return;

    uint32_t space = s_audio_rx.expected_size - s_audio_rx.received;
    uint16_t copy_len = (len <= space) ? len : (uint16_t)space;
    memcpy(s_audio_rx.buf + s_audio_rx.received, data, copy_len);
    s_audio_rx.received += copy_len;

    s_audio_bin_batch_bytes += copy_len;
    if (s_audio_bin_batch_bytes >= AUDIO_BIN_ACK_INTERVAL ||
        s_audio_rx.received >= s_audio_rx.expected_size) {
        char ack[48];
        snprintf(ack, sizeof(ack), "AUDIO_ACK_BIN:%u\r\n", (unsigned)s_audio_rx.received);
        dual_notify_str(ack);
        s_audio_bin_batch_bytes = 0;
    }
}

bool audio_is_binary_mode(void) { return s_audio_binary_mode; }

static void audio_rx_cleanup(void)
{
    s_audio_rx.active = false;
    s_audio_rx.received = 0;
    s_audio_rx.expected_size = 0;
    s_audio_binary_mode = false;
    s_audio_bin_batch_bytes = 0;
    if (s_audio_rx.buf) {
        free(s_audio_rx.buf);
        s_audio_rx.buf = NULL;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  BLE Command Dispatch — apply cmd_msg_t to AppState + hardware
 * ═══════════════════════════════════════════════════════════════ */
static void dispatch_ble_command(const cmd_msg_t *cmd)
{
    char resp[64];

    APP_STATE_LOCK();

    switch (cmd->type) {

    // ═══ SECTION: 基础控制命令 (FAN/SPEED/WUHUA/BRIGHT/VOL/UNIT/LCD) ═══

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
        /* APP sends display value (0-340 km/h or 0-211 mph).
         * Convert back to internal value (0-100) for storage.
         * display = internal * 3.4, so internal = display / 3.4 */
        int16_t internal_spd = (int16_t)(spd / 3.4f + 0.5f);
        if (internal_spd < 0) internal_spd = 0;
        if (internal_spd > 100) internal_spd = 100;
        g_app_state.current_speed_kmh = internal_spd;
        g_app_state.last_reported_speed = spd;  /* Keep display value for reporting */
        /* Map speed to fan: proportional 0-100 */
        if (g_app_state.wuhuaqi_state == 2) {
            /* Throttle mode: proportional fan */
            g_app_state.fan_speed = (uint8_t)internal_spd;
            drv_pwm_set_duty((uint8_t)internal_spd);
            g_app_state.remote_active_tick = xTaskGetTickCount();
        }
        /* Update engine sound based on speed */
        if (internal_spd > 0) {
            if (!audio_player_is_playing()) {
                audio_player_start_engine();
            }
            audio_player_set_target_rpm((uint8_t)internal_spd);
        } else {
            if (audio_player_is_playing()) {
                audio_player_stop_engine();
            }
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

    // ═══ SECTION: LED 颜色命令 (LED/PRESET/STREAMLIGHT/LED_GRADIENT/THROTTLE_FX) ═══

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

    // ═══ SECTION: UI 控制命令 (UI/THROTTLE) ═══

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
            audio_engine_set_throttle_mode(true);
        } else {
            g_app_state.wuhuaqi_state = g_app_state.wuhuaqi_state_saved;
            g_app_state.fan_speed = 0;
            g_app_state.current_speed_kmh = 0;
            drv_pwm_set_duty(0);
            g_app_state.throttle_was_remote = 0;
            if (g_app_state.wuhuaqi_state == 0) {
                drv_gpio_set_humidifier(false);
            }
            audio_engine_set_throttle_mode(false);
        }
        ble_service_notify_str("OK:THROTTLE\r\n");
        break;

    /* ── THROTTLE_FX:mode ── */
    case CMD_THROTTLE_FX:
        led_effects_set_throttle_mode(cmd->param.u8_val);
        snprintf(resp, sizeof(resp), "OK:THROTTLE_FX:%d\r\n", cmd->param.u8_val);
        ble_service_notify_str(resp);
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
        audio_engine_set_volume(cmd->param.u8_val);
        ble_service_notify_str("OK:VOL\r\n");
        break;

    // ═══ SECTION: 状态查询命令 (GET:ALL/GET:PRESET/GET:VOL/...) ═══

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

    case CMD_GET_LOGO: {
        /* Return logo slot info: which slots have valid logos
         * Format matches F4 and APP expectation:
         * LOGO_SLOTS:v0:v1:v2:active */
        char logo_resp[64];
        snprintf(logo_resp, sizeof(logo_resp), "LOGO_SLOTS:%d:%d:%d:%d\r\n",
                 storage_logo_exists(0) ? 1 : 0,
                 storage_logo_exists(1) ? 1 : 0,
                 storage_logo_exists(2) ? 1 : 0,
                 g_app_state.active_logo_slot);
        dual_notify_str(logo_resp);
        break;
    }

    case CMD_GET_VOLUME:
        snprintf(resp, sizeof(resp), "VOL:%d\r\n", g_app_state.volume);
        ble_service_notify_str(resp);
        break;

    // ═══ SECTION: Logo 上传协议 (LOGO_START/DATA/END/DELETE) ═══

    /* ── LOGO upload protocol (Phase 9) ── */
    case CMD_LOGO_START: {
        /* LOGO_START:size:crc32 or LOGO_START:slot:size:crc32
         * LOGO_START_BIN variant: slot has bit 7 set to signal binary mode */
        if (s_logo_rx.active) {
            logo_rx_cleanup();
        }
        uint32_t size = cmd->param.logo_start.size;
        uint32_t crc = cmd->param.logo_start.crc32;
        uint8_t raw_slot = cmd->param.logo_start.slot;

        /* Check binary mode flag (bit 7 of slot) */
        bool binary_mode = (raw_slot & 0x80) != 0;
        uint8_t slot = raw_slot & 0x7F;  /* Clear bit 7 to get actual slot */

        if (size == 0 || size > LOGO_PIXEL_BYTES) {
            char err[48];
            snprintf(err, sizeof(err), "LOGO_ERROR:SIZE_MISMATCH:%u\r\n",
                     (unsigned)LOGO_PIXEL_BYTES);
            dual_notify_str(err);
            break;
        }

        /* Auto-assign slot if 0xFF */
        if (slot == 0xFF) {
            slot = storage_logo_find_empty();
            if (slot >= MAX_LOGO_SLOTS) slot = 0;
        }
        if (slot >= MAX_LOGO_SLOTS) {
            dual_notify_str("LOGO_ERROR:INVALID_SLOT\r\n");
            break;
        }

        /* Allocate PSRAM buffer for entire image — no file I/O during transfer */
        s_logo_rx.buf = (uint8_t *)heap_caps_malloc(size, MALLOC_CAP_SPIRAM);
        if (!s_logo_rx.buf) {
            ESP_LOGE(TAG, "PSRAM alloc failed for %u bytes", (unsigned)size);
            dual_notify_str("LOGO_ERROR:MEM\r\n");
            break;
        }
        memset(s_logo_rx.buf, 0, size);

        s_logo_rx.slot = slot;
        s_logo_rx.expected_size = size;
        s_logo_rx.expected_crc32 = crc;
        s_logo_rx.received = 0;
        s_logo_rx.last_seq = -1;
        s_logo_rx.pkt_count = 0;
        s_logo_rx.active = true;

        /* Enable binary mode if requested */
        s_logo_binary_mode = binary_mode;
        s_logo_bin_batch_bytes = 0;

        ESP_LOGI(TAG, "Logo upload started: slot=%d size=%u crc=0x%08X mode=%s (PSRAM buf)",
                 slot, (unsigned)size, (unsigned)crc,
                 binary_mode ? "BINARY" : "HEX");

        char ready[32];
        snprintf(ready, sizeof(ready), "LOGO_READY:%d\r\n", slot);
        dual_notify_str(ready);
        break;
    }

    case CMD_LOGO_DATA:
        /* LOGO_DATA hex is handled directly in BLE service via logo_upload_feed_hex() */
        break;

    case CMD_LOGO_END: {
        if (!s_logo_rx.active || !s_logo_rx.buf) {
            dual_notify_str("LOGO_ERROR:NO_SESSION\r\n");
            break;
        }

        /* Send final ACK for last batch */
        if (s_logo_rx.last_seq >= 0) {
            char ack[32];
            snprintf(ack, sizeof(ack), "LOGO_ACK:%d\r\n", (int)s_logo_rx.last_seq);
            dual_notify_str(ack);
        }

        uint32_t data_size = s_logo_rx.received;
        ESP_LOGI(TAG, "Logo END: received=%u expected=%u last_seq=%d",
                 (unsigned)data_size, (unsigned)s_logo_rx.expected_size,
                 (int)s_logo_rx.last_seq);

        /* Debug: find first non-zero byte and dump some data */
        {
            uint32_t first_nz = data_size;
            for (uint32_t i = 0; i < data_size; i++) {
                if (s_logo_rx.buf[i] != 0) { first_nz = i; break; }
            }
            ESP_LOGI(TAG, "First non-zero at offset %u", (unsigned)first_nz);
            if (first_nz < data_size) {
                ESP_LOGI(TAG, "Bytes at offset %u: %02X %02X %02X %02X %02X %02X %02X %02X",
                         (unsigned)first_nz,
                         s_logo_rx.buf[first_nz], s_logo_rx.buf[first_nz+1],
                         s_logo_rx.buf[first_nz+2], s_logo_rx.buf[first_nz+3],
                         s_logo_rx.buf[first_nz+4], s_logo_rx.buf[first_nz+5],
                         s_logo_rx.buf[first_nz+6], s_logo_rx.buf[first_nz+7]);
            }
            /* Also compute how many non-zero bytes total */
            uint32_t nz_count = 0;
            for (uint32_t i = 0; i < data_size; i++) {
                if (s_logo_rx.buf[i] != 0) nz_count++;
            }
            ESP_LOGI(TAG, "Non-zero bytes: %u / %u", (unsigned)nz_count, (unsigned)data_size);
        }

        /* Debug: CRC of first row (480 bytes) for comparison */
        {
            uint32_t row_crc = esp_crc32_le(~0U, s_logo_rx.buf, 480) ^ ~0U;
            ESP_LOGI(TAG, "CRC of first 480 bytes (row 0): 0x%08X", (unsigned)row_crc);
            /* Also print bytes 238-242 (around the first non-zero) */
            ESP_LOGI(TAG, "Bytes 238-247: %02X %02X %02X %02X %02X %02X %02X %02X %02X %02X",
                     s_logo_rx.buf[238], s_logo_rx.buf[239],
                     s_logo_rx.buf[240], s_logo_rx.buf[241],
                     s_logo_rx.buf[242], s_logo_rx.buf[243],
                     s_logo_rx.buf[244], s_logo_rx.buf[245],
                     s_logo_rx.buf[246], s_logo_rx.buf[247]);
        }

        /* Size check */
        if (data_size != s_logo_rx.expected_size) {
            char fail[64];
            snprintf(fail, sizeof(fail), "LOGO_FAIL:SIZE:%u/%u\r\n",
                     (unsigned)data_size, (unsigned)s_logo_rx.expected_size);
            dual_notify_str(fail);
            logo_rx_cleanup();
            break;
        }

        /* CRC32 on PSRAM buffer — use same table as APP and F4 */
        static const uint32_t crc32_table[256] = {
            0x00000000,0x77073096,0xEE0E612C,0x990951BA,0x076DC419,0x706AF48F,0xE963A535,0x9E6495A3,
            0x0EDB8832,0x79DCB8A4,0xE0D5E91E,0x97D2D988,0x09B64C2B,0x7EB17CBD,0xE7B82D07,0x90BF1D91,
            0x1DB71064,0x6AB020F2,0xF3B97148,0x84BE41DE,0x1ADAD47D,0x6DDDE4EB,0xF4D4B551,0x83D385C7,
            0x136C9856,0x646BA8C0,0xFD62F97A,0x8A65C9EC,0x14015C4F,0x63066CD9,0xFA0F3D63,0x8D080DF5,
            0x3B6E20C8,0x4C69105E,0xD56041E4,0xA2677172,0x3C03E4D1,0x4B04D447,0xD20D85FD,0xA50AB56B,
            0x35B5A8FA,0x42B2986C,0xDBBBC9D6,0xACBCF940,0x32D86CE3,0x45DF5C75,0xDCD60DCF,0xABD13D59,
            0x26D930AC,0x51DE003A,0xC8D75180,0xBFD06116,0x21B4F4B5,0x56B3C423,0xCFBA9599,0xB8BDA50F,
            0x2802B89E,0x5F058808,0xC60CD9B2,0xB10BE924,0x2F6F7C87,0x58684C11,0xC1611DAB,0xB6662D3D,
            0x76DC4190,0x01DB7106,0x98D220BC,0xEFD5102A,0x71B18589,0x06B6B51F,0x9FBFE4A5,0xE8B8D433,
            0x7807C9A2,0x0F00F934,0x9609A88E,0xE10E9818,0x7F6A0DBB,0x086D3D2D,0x91646C97,0xE6635C01,
            0x6B6B51F4,0x1C6C6162,0x856530D8,0xF262004E,0x6C0695ED,0x1B01A57B,0x8208F4C1,0xF50FC457,
            0x65B0D9C6,0x12B7E950,0x8BBEB8EA,0xFCB9887C,0x62DD1DDF,0x15DA2D49,0x8CD37CF3,0xFBD44C65,
            0x4DB26158,0x3AB551CE,0xA3BC0074,0xD4BB30E2,0x4ADFA541,0x3DD895D7,0xA4D1C46D,0xD3D6F4FB,
            0x4369E96A,0x346ED9FC,0xAD678846,0xDA60B8D0,0x44042D73,0x33031DE5,0xAA0A4C5F,0xDD0D7CC9,
            0x5005713C,0x270241AA,0xBE0B1010,0xC90C2086,0x5768B525,0x206F85B3,0xB966D409,0xCE61E49F,
            0x5EDEF90E,0x29D9C998,0xB0D09822,0xC7D7A8B4,0x59B33D17,0x2EB40D81,0xB7BD5C3B,0xC0BA6CAD,
            0xEDB88320,0x9ABFB3B6,0x03B6E20C,0x74B1D29A,0xEAD54739,0x9DD277AF,0x04DB2615,0x73DC1683,
            0xE3630B12,0x94643B84,0x0D6D6A3E,0x7A6A5AA8,0xE40ECF0B,0x9309FF9D,0x0A00AE27,0x7D079EB1,
            0xF00F9344,0x8708A3D2,0x1E01F268,0x6906C2FE,0xF762575D,0x806567CB,0x196C3671,0x6E6B06E7,
            0xFED41B76,0x89D32BE0,0x10DA7A5A,0x67DD4ACC,0xF9B9DF6F,0x8EBEEFF9,0x17B7BE43,0x60B08ED5,
            0xD6D6A3E8,0xA1D1937E,0x38D8C2C4,0x4FDFF252,0xD1BB67F1,0xA6BC5767,0x3FB506DD,0x48B2364B,
            0xD80D2BDA,0xAF0A1B4C,0x36034AF6,0x41047A60,0xDF60EFC3,0xA867DF55,0x316E8EEF,0x4669BE79,
            0xCB61B38C,0xBC66831A,0x256FD2A0,0x5268E236,0xCC0C7795,0xBB0B4703,0x220216B9,0x5505262F,
            0xC5BA3BBE,0xB2BD0B28,0x2BB45A92,0x5CB36A04,0xC2D7FFA7,0xB5D0CF31,0x2CD99E8B,0x5BDEAE1D,
            0x9B64C2B0,0xEC63F226,0x756AA39C,0x026D930A,0x9C0906A9,0xEB0E363F,0x72076785,0x05005713,
            0x95BF4A82,0xE2B87A14,0x7BB12BAE,0x0CB61B38,0x92D28E9B,0xE5D5BE0D,0x7CDCEFB7,0x0BDBDF21,
            0x86D3D2D4,0xF1D4E242,0x68DDB3F8,0x1FDA836E,0x81BE16CD,0xF6B9265B,0x6FB077E1,0x18B74777,
            0x88085AE6,0xFF0F6A70,0x66063BCA,0x11010B5C,0x8F659EFF,0xF862AE69,0x616BFFD3,0x166CCF45,
            0xA00AE278,0xD70DD2EE,0x4E048354,0x3903B3C2,0xA7672661,0xD06016F7,0x4969474D,0x3E6E77DB,
            0xAED16A4A,0xD9D65ADC,0x40DF0B66,0x37D83BF0,0xA9BCAE53,0xDEBB9EC5,0x47B2CF7F,0x30B5FFE9,
            0xBDBDF21C,0xCABAC28A,0x53B39330,0x24B4A3A6,0xBAD03605,0xCDD706B3,0x54DE5729,0x23D967BF,
            0xB3667A2E,0xC4614AB8,0x5D681B02,0x2A6F2B94,0xB40BBE37,0xC30C8EA1,0x5A05DF1B,0x2D02EF8D,
        };
        uint32_t calc_crc = 0xFFFFFFFF;
        for (uint32_t i = 0; i < data_size; i++) {
            calc_crc = (calc_crc >> 8) ^ crc32_table[(calc_crc ^ s_logo_rx.buf[i]) & 0xFF];
        }
        calc_crc ^= 0xFFFFFFFF;
        ESP_LOGI(TAG, "Logo CRC: calc=0x%08X expect=0x%08X",
                 (unsigned)calc_crc, (unsigned)s_logo_rx.expected_crc32);

        if (s_logo_rx.expected_crc32 != 0 && calc_crc != s_logo_rx.expected_crc32) {
            char fail[64];
            snprintf(fail, sizeof(fail), "LOGO_FAIL:CRC:0x%08X:0x%08X\r\n",
                     (unsigned)s_logo_rx.expected_crc32, (unsigned)calc_crc);
            dual_notify_str(fail);
            ESP_LOGE(TAG, "CRC mismatch — aborting, not writing corrupted data");
            logo_rx_cleanup();
            break;
        }

        /* Write header + pixel data to LittleFS in one shot */
        char final_path[48];
        snprintf(final_path, sizeof(final_path),
                 LITTLEFS_MOUNT_POINT "/logo_%d.bin", s_logo_rx.slot);

        FILE *dst = fopen(final_path, "wb");
        if (dst) {
            logo_header_t hdr = {
                .magic = LOGO_MAGIC, .width = LOGO_WIDTH, .height = LOGO_HEIGHT,
                .reserved = 0, .data_size = data_size, .crc32 = calc_crc,
            };
            fwrite(&hdr, 1, sizeof(hdr), dst);
            fwrite(s_logo_rx.buf, 1, data_size, dst);
            fclose(dst);

            g_app_state.active_logo_slot = s_logo_rx.slot;
            storage_save_current();
            ESP_LOGI(TAG, "Logo slot %d written OK (%u bytes)", s_logo_rx.slot, (unsigned)data_size);

            char ok_resp[32];
            snprintf(ok_resp, sizeof(ok_resp), "LOGO_OK:%d\r\n", s_logo_rx.slot);
            dual_notify_str(ok_resp);
        } else {
            dual_notify_str("LOGO_FAIL:WRITE\r\n");
        }

        logo_rx_cleanup();
        break;
    }

    case CMD_LOGO_DELETE: {
        uint8_t slot = cmd->param.u8_val;
        if (slot >= MAX_LOGO_SLOTS) {
            dual_notify_str("LOGO_ERROR:SLOT\r\n");
            break;
        }
        if (storage_logo_delete(slot)) {
            if (g_app_state.active_logo_slot == slot) {
                g_app_state.active_logo_slot = 0;
                storage_save_current();
            }
            dual_notify_str("OK:LOGO_DELETE\r\n");
        } else {
            dual_notify_str("LOGO_ERROR:DELETE\r\n");
        }
        break;
    }

    // ═══ SECTION: OTA 升级协议 (OTA_START/DATA/END) ═══

    case CMD_OTA_START: {
        /* OTA_BEGIN:size or OTA_BEGIN:size:sha256
         * Extract SHA256 from the raw command if present.
         * The protocol parser stored size in ota_size.
         * We need to re-parse the raw text for SHA256 — but cmd_msg_t
         * only carries ota_size. For SHA256, we pass NULL (optional).
         * Future: extend cmd_msg_t or pass via a side channel.
         * For now, App can omit SHA256 and rely on esp_ota_end() validation. */
        APP_STATE_UNLOCK();
        ota_service_begin(cmd->param.ota_size, NULL);
        return;  /* Already unlocked */
    }

    case CMD_OTA_DATA:
        /* Binary data is routed directly via ota_service_feed_data()
         * from BLE callback. This case shouldn't normally be hit. */
        break;

    case CMD_OTA_END:
        APP_STATE_UNLOCK();
        ota_service_end();
        return;  /* Already unlocked */

    case CMD_OTA_VERSION: {
        /* Reply with firmware version from app descriptor */
        const esp_app_desc_t *desc = esp_app_get_description();
        snprintf(resp, sizeof(resp), "OTA_VERSION:%s\r\n", desc->version);
        ble_service_notify_str(resp);
        break;
    }

    // ═══ SECTION: WiFi 音频命令 (WIFI/WIFI_SCAN) ═══

    /* ── WIFI:ssid:password ── */
    case CMD_WIFI: {
        char ssid_copy[33], pass_copy[65];
        strncpy(ssid_copy, cmd->param.wifi.ssid, sizeof(ssid_copy) - 1);
        ssid_copy[sizeof(ssid_copy) - 1] = '\0';
        strncpy(pass_copy, cmd->param.wifi.password, sizeof(pass_copy) - 1);
        pass_copy[sizeof(pass_copy) - 1] = '\0';
        APP_STATE_UNLOCK();  /* Release lock — provisioning runs async */
        ble_service_notify_str("OK:WIFI\r\n");
        /* Use provisioning flow: stop BLE → connect WiFi → restart BLE.
         * This avoids RF contention during WiFi CONNECTING phase. */
        wifi_audio_service_provision(ssid_copy, pass_copy);
        return;  /* Already unlocked */
    }

    /* ── WIFI_SCAN ── */
    case CMD_WIFI_SCAN:
        wifi_audio_service_scan();
        break;

    // ═══ SECTION: 自定义音频上传 (AUDIO_START_BIN/DATA/END/DELETE) ═══

    /* ── Audio upload protocol ── */
    case CMD_AUDIO_START: {
        if (s_audio_rx.active) {
            audio_rx_cleanup();
        }
        uint8_t raw_layer = cmd->param.audio_start.layer;
        uint32_t size = cmd->param.audio_start.size;
        uint32_t crc = cmd->param.audio_start.crc32;

        bool binary_mode = (raw_layer & 0x80) != 0;
        uint8_t layer = raw_layer & 0x7F;

        if (layer >= AUDIO_LAYER_COUNT) {
            dual_notify_str("AUDIO_ERROR:INVALID_LAYER\r\n");
            break;
        }
        if (size == 0 || size > AUDIO_MAX_PCM_SIZE) {
            char err[64];
            snprintf(err, sizeof(err), "AUDIO_ERROR:SIZE:%u (max %u)\r\n",
                     (unsigned)size, AUDIO_MAX_PCM_SIZE);
            dual_notify_str(err);
            break;
        }

        s_audio_rx.buf = (uint8_t *)heap_caps_malloc(size, MALLOC_CAP_SPIRAM);
        if (!s_audio_rx.buf) {
            ESP_LOGE(TAG, "Audio PSRAM alloc failed for %u bytes", (unsigned)size);
            dual_notify_str("AUDIO_ERROR:MEM\r\n");
            break;
        }
        memset(s_audio_rx.buf, 0, size);

        s_audio_rx.layer = layer;
        s_audio_rx.expected_size = size;
        s_audio_rx.expected_crc32 = crc;
        s_audio_rx.received = 0;
        s_audio_rx.active = true;
        s_audio_binary_mode = binary_mode;
        s_audio_bin_batch_bytes = 0;

        ESP_LOGI(TAG, "Audio upload started: layer=%d size=%u crc=0x%08X mode=%s",
                 layer, (unsigned)size, (unsigned)crc,
                 binary_mode ? "BINARY" : "HEX");

        char ready[32];
        snprintf(ready, sizeof(ready), "AUDIO_READY:%d\r\n", layer);
        dual_notify_str(ready);
        break;
    }

    case CMD_AUDIO_DATA:
        /* Hex mode handled in BLE service if needed; binary goes through feed_binary */
        break;

    case CMD_AUDIO_END: {
        if (!s_audio_rx.active || !s_audio_rx.buf) {
            dual_notify_str("AUDIO_ERROR:NO_SESSION\r\n");
            break;
        }

        uint32_t data_size = s_audio_rx.received;
        ESP_LOGI(TAG, "Audio END: layer=%d received=%u expected=%u",
                 s_audio_rx.layer, (unsigned)data_size, (unsigned)s_audio_rx.expected_size);

        if (data_size != s_audio_rx.expected_size) {
            char fail[64];
            snprintf(fail, sizeof(fail), "AUDIO_FAIL:SIZE:%u/%u\r\n",
                     (unsigned)data_size, (unsigned)s_audio_rx.expected_size);
            dual_notify_str(fail);
            audio_rx_cleanup();
            break;
        }

        /* CRC32 check */
        uint32_t calc_crc = storage_crc32(s_audio_rx.buf, data_size);
        ESP_LOGI(TAG, "Audio CRC: calc=0x%08X expect=0x%08X",
                 (unsigned)calc_crc, (unsigned)s_audio_rx.expected_crc32);

        if (s_audio_rx.expected_crc32 != 0 && calc_crc != s_audio_rx.expected_crc32) {
            char fail[64];
            snprintf(fail, sizeof(fail), "AUDIO_FAIL:CRC:0x%08X:0x%08X\r\n",
                     (unsigned)s_audio_rx.expected_crc32, (unsigned)calc_crc);
            dual_notify_str(fail);
            audio_rx_cleanup();
            break;
        }

        /* Write to LittleFS */
        if (storage_audio_write(s_audio_rx.layer, s_audio_rx.buf, data_size, calc_crc)) {
            ESP_LOGI(TAG, "Audio layer %d written OK (%u bytes)", s_audio_rx.layer, (unsigned)data_size);
            char ok_resp[32];
            snprintf(ok_resp, sizeof(ok_resp), "AUDIO_OK:%d\r\n", s_audio_rx.layer);
            dual_notify_str(ok_resp);

            /* If all 4 layers are now present, reload the audio engine */
            if (storage_audio_count() == AUDIO_LAYER_COUNT) {
                audio_player_reload_layers();
                dual_notify_str("AUDIO_RELOAD:OK\r\n");
            }
        } else {
            dual_notify_str("AUDIO_FAIL:WRITE\r\n");
        }

        audio_rx_cleanup();
        break;
    }

    case CMD_AUDIO_DELETE: {
        uint8_t layer = cmd->param.u8_val;
        if (layer == 0xFF) {
            /* Delete all custom audio */
            storage_audio_delete_all();
            audio_player_reload_layers();
            dual_notify_str("OK:AUDIO_DELETE_ALL\r\n");
        } else if (layer < AUDIO_LAYER_COUNT) {
            storage_audio_delete(layer);
            audio_player_reload_layers();
            char ok[32];
            snprintf(ok, sizeof(ok), "OK:AUDIO_DELETE:%d\r\n", layer);
            ble_service_notify_str(ok);
        } else {
            dual_notify_str("AUDIO_ERROR:INVALID_LAYER\r\n");
        }
        break;
    }

    case CMD_GET_AUDIO: {
        /* Report custom audio status: AUDIO_STATUS:idle:low:mid:high:custom
         * Each layer: 1=exists, 0=not; custom: 1=using custom, 0=using built-in */
        char audio_resp[64];
        snprintf(audio_resp, sizeof(audio_resp), "AUDIO_STATUS:%d:%d:%d:%d:%d\r\n",
                 storage_audio_exists(0) ? 1 : 0,
                 storage_audio_exists(1) ? 1 : 0,
                 storage_audio_exists(2) ? 1 : 0,
                 storage_audio_exists(3) ? 1 : 0,
                 audio_player_has_custom_audio() ? 1 : 0);
        dual_notify_str(audio_resp);
        break;
    }

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
        drv_pwm_update();  /* Smooth fan speed ramping */

        /* Feed watchdog — LCD SPI operations can take a while */
        vTaskDelay(pdMS_TO_TICKS(MAIN_TASK_PERIOD_MS));
    }
}

/* ═══════════════════════════════════════════════════════════════ */
void app_main(void)
{
    ESP_LOGI(TAG, "Critical ESP32 started");

    /* 0. NVS flash init (required by Bluedroid) */
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* Production self-test: hold encoder button at power-on to enter */
    if (selftest_check_entry()) {
        selftest_run();  /* Never returns — device must be power-cycled */
    }

    /* 1. AppState init (factory defaults) */
    app_state_init();

    /* OTA rollback self-test — must be early, before any heavy init.
     * If this is first boot after OTA and firmware is bad, we rollback here. */
    ota_service_init();

    /* Phase 8: Load saved settings from NVS */
    storage_init();
    {
        nvs_settings_t saved;
        storage_load_settings(&saved);
        /* Apply saved settings to AppState */
        memcpy(g_app_state.led_colors, saved.led_colors, sizeof(g_app_state.led_colors));
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 3; j++) {
                g_app_state.led_edit[i][j] = g_app_state.led_colors[i][j];
            }
        }
        g_app_state.brightness = saved.brightness;
        g_app_state.volume = saved.volume;
        g_app_state.preset_index = saved.preset_index;
        g_app_state.speed_unit = saved.speed_unit;
        g_app_state.streamlight_active = saved.streamlight;
        g_app_state.breath_mode = saved.breath_mode;
        g_app_state.active_logo_slot = saved.active_logo_slot;
    }

    /* 2. Command queue */
    cmd_queue = xQueueCreate(CMD_QUEUE_DEPTH, sizeof(cmd_msg_t));

    /* Phase 1: LCD init + brand boot logo */
    drv_lcd_init();
    drv_lcd_set_backlight(false);  /* Display OFF — hide random GRAM data */
    drv_lcd_fill_rect(0, 0, 240, 240, 0x0000);
    drv_lcd_blit_rgb565(0, 0, 240, 240, (const uint16_t *)gImage_boot_logo_240);
    drv_lcd_set_backlight(true);   /* Display ON — logo is ready */
    ESP_LOGI(TAG, "Brand boot logo displayed");

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

    /* Phase 7: Audio init */
    drv_audio_init();
    audio_player_init();
    /* WiFi audio re-enabled — PSRAM absorbs WiFi/LWIP buffers,
     * internal SRAM pressure is no longer a concern. */
    audio_engine_init();
    wifi_audio_service_init();
    wifi_comm_service_init();
    audio_engine_set_volume(g_app_state.volume);
    ESP_LOGI(TAG, "Audio pipeline initialized (engine + WiFi audio + WebSocket)");

    /* ═══ WiFi + BLE Boot Sequence (Production) ═══
     * Strategy: WiFi CONNECTING phase has RF contention with BLE (reason=201).
     *           WiFi CONNECTED coexists stably with BLE (confirmed).
     *
     * Boot logic:
     *   - Has NVS credentials → connect WiFi FIRST (blocking 5s, no BLE yet)
     *                         → then start BLE (WiFi already CONNECTED = no contention)
     *   - No credentials     → start BLE immediately (WiFi will be triggered by APP)
     */
    if (wifi_audio_service_has_credentials()) {
        ESP_LOGI(TAG, "NVS has WiFi credentials — connecting WiFi before BLE...");
        wifi_audio_service_auto_connect();  /* Blocking up to 10s */
        ESP_LOGI(TAG, "WiFi phase done, now starting BLE...");
        ble_service_init();
    } else {
        ESP_LOGI(TAG, "No WiFi credentials — starting BLE directly");
        ble_service_init();
    }
    ESP_LOGI(TAG, "BLE initialized (WiFi+BLE coex active)");

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

    /* ── Memory diagnostic ── */
    ESP_LOGI(TAG, "═══ MEMORY REPORT (after all init) ═══");
    ESP_LOGI(TAG, "  Free heap:          %u bytes", (unsigned)esp_get_free_heap_size());
    ESP_LOGI(TAG, "  Min free heap ever: %u bytes", (unsigned)esp_get_minimum_free_heap_size());
    ESP_LOGI(TAG, "  Largest free block: %u bytes", (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
#if CONFIG_SPIRAM
    ESP_LOGI(TAG, "  PSRAM free:         %u bytes", (unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    ESP_LOGI(TAG, "  PSRAM total:        %u bytes", (unsigned)heap_caps_get_total_size(MALLOC_CAP_SPIRAM));
#else
    ESP_LOGW(TAG, "  PSRAM: NOT ENABLED");
#endif
    ESP_LOGI(TAG, "═══════════════════════════════════════");

    /* Boot logo displayed at LCD init — hold for 2 seconds */
    vTaskDelay(pdMS_TO_TICKS(BOOT_LOGO_DURATION_MS));
    /* Transition to UI5 menu */
    ui_manager_set_ui(5);

    /* Start Main_Task IMMEDIATELY so BLE commands are processed */
    xTaskCreatePinnedToCore(main_task, "main_task", 8192, NULL, 5, NULL, 1);
    ESP_LOGI(TAG, "Main task started on Core 1");
}
