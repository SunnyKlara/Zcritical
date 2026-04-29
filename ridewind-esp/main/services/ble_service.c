/**
 * @file ble_service.c
 * @brief Bluedroid BLE GATTS — Service 0xFFE0, Characteristic 0xFFE1
 *
 * Receives text commands via write-without-response, reassembles MTU fragments
 * until '\n', parses via protocol_parse(), and enqueues cmd_msg_t to cmd_queue.
 * Sends responses/reports via notifications.
 */

#include "ble_service.h"
#include "protocol.h"
#include "board_config.h"
#include "esp_heap_caps.h"

#include "esp_bt.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_gatt_common_api.h"
#include "esp_bt_defs.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include <string.h>

static const char *TAG = "BLE_SVC";

/* ── External command queue (created in main.c) ── */
extern QueueHandle_t cmd_queue;

/* ── GATT profile state ── */
#define GATTS_APP_ID        0
#define SVC_UUID            0xFFE0
#define CHAR_UUID           0xFFE1
#define GATTS_CHAR_VAL_LEN  512

static uint16_t s_gatts_if    = ESP_GATT_IF_NONE;
static uint16_t s_conn_id     = 0;
static bool     s_connected   = false;
static uint16_t s_char_handle = 0;
static uint16_t s_svc_handle  = 0;

/* ── MTU fragment reassembly buffer ── */
#define RX_BUF_SIZE  512
static char    s_rx_buf[RX_BUF_SIZE];
static uint16_t s_rx_len = 0;

/* ── Advertising data ── */
static esp_ble_adv_params_t s_adv_params = {
    .adv_int_min       = 0x20,   /* 20ms */
    .adv_int_max       = 0x40,   /* 40ms */
    .adv_type          = ADV_TYPE_IND,
    .own_addr_type     = BLE_ADDR_TYPE_PUBLIC,
    .channel_map       = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

/* ── Service / Characteristic UUIDs ── */
static const uint16_t primary_svc_uuid   = ESP_GATT_UUID_PRI_SERVICE;
static const uint16_t char_decl_uuid     = ESP_GATT_UUID_CHAR_DECLARE;
static const uint16_t char_ccc_uuid      = ESP_GATT_UUID_CHAR_CLIENT_CONFIG;
static const uint8_t  char_prop          = ESP_GATT_CHAR_PROP_BIT_WRITE_NR
                                         | ESP_GATT_CHAR_PROP_BIT_NOTIFY;
static const uint16_t svc_uuid_val       = SVC_UUID;
static const uint16_t char_uuid_val      = CHAR_UUID;
static uint8_t  char_ccc_val[2]          = {0x00, 0x00};
static uint8_t  char_value[GATTS_CHAR_VAL_LEN] = {0};

/* GATT database: Service + Characteristic + CCC descriptor */
static const esp_gatts_attr_db_t s_gatt_db[] = {
    /* [0] Service Declaration */
    [0] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16, (uint8_t *)&primary_svc_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint16_t), sizeof(svc_uuid_val), (uint8_t *)&svc_uuid_val
        }
    },
    /* [1] Characteristic Declaration */
    [1] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16, (uint8_t *)&char_decl_uuid,
            ESP_GATT_PERM_READ,
            sizeof(uint8_t), sizeof(char_prop), (uint8_t *)&char_prop
        }
    },
    /* [2] Characteristic Value — use RSP_BY_APP to prevent echo on write */
    [2] = {
        {ESP_GATT_RSP_BY_APP},
        {
            ESP_UUID_LEN_16, (uint8_t *)&char_uuid_val,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            GATTS_CHAR_VAL_LEN, 0, char_value
        }
    },
    /* [3] Client Characteristic Configuration (CCC) */
    [3] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16, (uint8_t *)&char_ccc_uuid,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            sizeof(char_ccc_val), sizeof(char_ccc_val), char_ccc_val
        }
    },
};

#define GATT_DB_NUM  (sizeof(s_gatt_db) / sizeof(s_gatt_db[0]))

/* ═══════════════════════════════════════════════════════════════
 *  Process received data: reassemble fragments, parse on '\n'
 * ═══════════════════════════════════════════════════════════════ */

/* External logo data handler — defined in main.c (Phase 9) */
extern void logo_upload_feed_hex(const char *hex_str, uint16_t len);
extern void logo_upload_feed_binary(const uint8_t *data, uint16_t len);
extern bool logo_is_binary_mode(void);

static void process_rx_data(const uint8_t *data, uint16_t len)
{
    /* Binary logo mode: all incoming data is raw pixel bytes, no text framing.
     * Exception: if we see "LOGO_END" text, exit binary mode. */
    if (logo_is_binary_mode()) {
        /* Check if this is the LOGO_END command (text, ends with \n) */
        if (len >= 8 && len <= 10) {
            /* Small packet might be LOGO_END\n or LOGO_END\r\n */
            char tmp[16];
            uint16_t copy_len = (len < sizeof(tmp) - 1) ? len : sizeof(tmp) - 1;
            memcpy(tmp, data, copy_len);
            tmp[copy_len] = '\0';
            /* Strip trailing \r\n */
            for (int i = copy_len - 1; i >= 0 && (tmp[i] == '\r' || tmp[i] == '\n'); i--) {
                tmp[i] = '\0';
            }
            if (strcmp(tmp, "LOGO_END") == 0) {
                /* Route to command parser */
                cmd_msg_t msg;
                if (protocol_parse(tmp, (uint16_t)strlen(tmp), &msg)) {
                    if (cmd_queue) xQueueSend(cmd_queue, &msg, 0);
                }
                return;
            }
        }
        /* Raw binary data — feed directly to PSRAM buffer */
        logo_upload_feed_binary(data, len);
        return;
    }

    for (uint16_t i = 0; i < len; i++) {
        char c = (char)data[i];

        if (c == '\n' || c == '\r') {
            if (s_rx_len > 0) {
                s_rx_buf[s_rx_len] = '\0';

                /* Fast path for LOGO_DATA — decode hex directly without queue */
                if (s_rx_len > 10 && strncmp(s_rx_buf, "LOGO_DATA:", 10) == 0) {
                    logo_upload_feed_hex(s_rx_buf + 10, s_rx_len - 10);
                    s_rx_len = 0;
                    continue;
                }

                cmd_msg_t msg;
                if (protocol_parse(s_rx_buf, s_rx_len, &msg)) {
                    if (cmd_queue) {
                        xQueueSend(cmd_queue, &msg, 0);
                    }
                } else {
                    ESP_LOGW(TAG, "Parse fail: %s", s_rx_buf);
                }
                s_rx_len = 0;
            }
        } else {
            if (s_rx_len < RX_BUF_SIZE - 1) {
                s_rx_buf[s_rx_len++] = c;
            } else {
                ESP_LOGW(TAG, "RX buffer overflow, discarding");
                s_rx_len = 0;
            }
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  GAP event handler
 * ═══════════════════════════════════════════════════════════════ */
static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param)
{
    switch (event) {
    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
        esp_ble_gap_start_advertising(&s_adv_params);
        break;
    case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
        if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
            ESP_LOGI(TAG, "Advertising started");
        }
        break;
    default:
        break;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  GATTS event handler
 * ═══════════════════════════════════════════════════════════════ */
static void gatts_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if,
                                esp_ble_gatts_cb_param_t *param)
{
    switch (event) {
    case ESP_GATTS_REG_EVT:
        if (param->reg.status == ESP_GATT_OK) {
            s_gatts_if = gatts_if;
            /* Set device name */
            esp_ble_gap_set_device_name(BLE_DEVICE_NAME);
            /* Configure advertising data — device name only.
             * APP side filters by device name "T1" and verifies FFE0 service
             * after connection, so we don't need UUID in the adv packet. */
            esp_ble_adv_data_t adv_data = {
                .set_scan_rsp        = false,
                .include_name        = true,
                .include_txpower     = false,
                .min_interval        = 0x0006,
                .max_interval        = 0x0010,
                .appearance          = 0x00,
                .manufacturer_len    = 0,
                .p_manufacturer_data = NULL,
                .service_data_len    = 0,
                .p_service_data      = NULL,
                .service_uuid_len    = 0,
                .p_service_uuid      = NULL,
                .flag                = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
            };
            esp_ble_gap_config_adv_data(&adv_data);
            /* Create attribute table */
            esp_ble_gatts_create_attr_tab(s_gatt_db, gatts_if, GATT_DB_NUM, 0);
        }
        break;

    case ESP_GATTS_CREAT_ATTR_TAB_EVT:
        if (param->add_attr_tab.status == ESP_GATT_OK && param->add_attr_tab.num_handle == GATT_DB_NUM) {
            s_svc_handle  = param->add_attr_tab.handles[0];
            s_char_handle = param->add_attr_tab.handles[2];
            esp_ble_gatts_start_service(s_svc_handle);
            ESP_LOGI(TAG, "Service started, char_handle=%d", s_char_handle);
        }
        break;

    case ESP_GATTS_CONNECT_EVT:
        s_conn_id   = param->connect.conn_id;
        s_connected = true;
        s_rx_len    = 0;  /* Reset reassembly buffer */
        ESP_LOGI(TAG, "Client connected, conn_id=%d (free heap: %u, largest block: %u)",
                 s_conn_id,
                 (unsigned)esp_get_free_heap_size(),
                 (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
        /* Request higher MTU for better throughput */
        esp_ble_gatt_set_local_mtu(247);
        /* Notify WiFi status after a short delay (let MTU negotiate first) */
        break;

    case ESP_GATTS_DISCONNECT_EVT:
        s_connected = false;
        s_rx_len    = 0;
        ESP_LOGI(TAG, "Client disconnected, restarting advertising");
        esp_ble_gap_start_advertising(&s_adv_params);
        break;

    case ESP_GATTS_WRITE_EVT:
        if (param->write.handle == s_char_handle && param->write.len > 0) {
            process_rx_data(param->write.value, param->write.len);
        }
        /* Send write response manually (RSP_BY_APP mode) */
        if (param->write.need_rsp) {
            esp_ble_gatts_send_response(gatts_if, param->write.conn_id,
                param->write.trans_id, ESP_GATT_OK, NULL);
        }
        break;

    case ESP_GATTS_MTU_EVT:
        ESP_LOGI(TAG, "MTU updated to %d", param->mtu.mtu);
        /* Only notify WiFi status if already connected — do NOT auto-connect.
         * WiFi auto-connect was causing RF contention that killed BLE.
         * APP should send WIFI:ssid:pass explicitly when it needs audio. */
        {
            extern void wifi_audio_service_notify_status(void);
            wifi_audio_service_notify_status();
        }
        break;

    default:
        break;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════ */
void ble_service_init(void)
{
    ESP_LOGI(TAG, "Initializing BLE GATTS");

    /* BLE-only mode (ESP32-S3 does not support Classic BT) */
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&bt_cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BLE));

    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());

    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(gatts_event_handler));
    ESP_ERROR_CHECK(esp_ble_gap_register_callback(gap_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(GATTS_APP_ID));

    ESP_LOGI(TAG, "BLE GATTS initialized");
}

void ble_service_start(void)
{
    esp_ble_gap_start_advertising(&s_adv_params);
}

void ble_service_stop(void)
{
    esp_ble_gap_stop_advertising();
}

void ble_service_notify(const char *data, uint16_t len)
{
    if (!s_connected || s_gatts_if == ESP_GATT_IF_NONE || s_char_handle == 0) return;

    /* Retry on congestion — BLE TX buffer can be full during high-throughput
     * operations like logo upload. Without retry, ACK packets get silently
     * dropped, causing the APP to timeout waiting for them. */
    for (int retry = 0; retry < 10; retry++) {
        esp_err_t err = esp_ble_gatts_send_indicate(s_gatts_if, s_conn_id, s_char_handle,
                                                     len, (uint8_t *)data, false);
        if (err == ESP_OK) return;

        if (err == ESP_ERR_NO_MEM || err == ESP_GATT_CONGESTED) {
            vTaskDelay(pdMS_TO_TICKS(20));  /* wait for TX buffer to drain */
            continue;
        }
        ESP_LOGW(TAG, "Notify failed: %s", esp_err_to_name(err));
        return;
    }
    ESP_LOGW(TAG, "Notify failed after 10 retries (congestion)");
}

void ble_service_notify_str(const char *str)
{
    if (!str) return;
    ble_service_notify(str, (uint16_t)strlen(str));
}

bool ble_service_is_connected(void)
{
    return s_connected;
}
