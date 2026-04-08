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
    /* [2] Characteristic Value */
    [2] = {
        {ESP_GATT_AUTO_RSP},
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
static void process_rx_data(const uint8_t *data, uint16_t len)
{
    for (uint16_t i = 0; i < len; i++) {
        char c = (char)data[i];

        if (c == '\n' || c == '\r') {
            if (s_rx_len > 0) {
                /* Complete command received — parse and enqueue */
                s_rx_buf[s_rx_len] = '\0';
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
                /* Buffer overflow — discard */
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
    /* Configure advertising data — include FFE0 service UUID so APP can find us */
            static uint8_t svc_uuid_adv[16];
            /* Convert 16-bit UUID 0xFFE0 to 128-bit BLE base UUID */
            /* 0000FFE0-0000-1000-8000-00805F9B34FB in little-endian */
            static const uint8_t ffe0_128[16] = {
                0xFB, 0x34, 0x9B, 0x5F, 0x80, 0x00, 0x00, 0x80,
                0x00, 0x10, 0x00, 0x00, 0xE0, 0xFF, 0x00, 0x00
            };
            memcpy(svc_uuid_adv, ffe0_128, 16);

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
                .service_uuid_len    = 16,
                .p_service_uuid      = svc_uuid_adv,
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
        ESP_LOGI(TAG, "Client connected, conn_id=%d", s_conn_id);
        /* Request higher MTU for better throughput */
        esp_ble_gatt_set_local_mtu(247);
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
        break;

    case ESP_GATTS_MTU_EVT:
        ESP_LOGI(TAG, "MTU updated to %d", param->mtu.mtu);
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

    /* Release Classic BT memory — not needed until Phase 7 A2DP */
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
    esp_ble_gatts_send_indicate(s_gatts_if, s_conn_id, s_char_handle,
                                len, (uint8_t *)data, false);
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
