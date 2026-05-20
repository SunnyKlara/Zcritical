/**
 * @file wifi_comm_service.c
 * @brief WiFi WebSocket server — primary APP ↔ ESP32 communication channel
 *
 * Architecture:
 * - Uses ESP-IDF's esp_http_server with WebSocket support
 * - Listens on port 81 (port 80 reserved for future HTTP API, 8080 for audio)
 * - Text frames: parsed as protocol commands (same as BLE text commands)
 * - Binary frames: routed to OTA/Logo handlers (same as BLE binary mode)
 * - mDNS: registers "critical-t1" so APP can find device as "critical-t1.local"
 *
 * Thread safety:
 * - WebSocket handler runs in the httpd task context
 * - Commands are enqueued to cmd_queue (same as BLE path)
 * - Notifications use httpd_ws_send_frame (thread-safe with httpd handle)
 */

#include "wifi_comm_service.h"
#include "protocol.h"
#include "ble_service.h"

#include "esp_http_server.h"
#include "esp_log.h"
#include "mdns.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include <string.h>

static const char *TAG = "WIFI_COMM";

#define WS_PORT  81
#define WS_MAX_FRAME_SIZE  4096  /* Max single frame size (for OTA chunks) */

/* External command queue (created in main.c) */
extern QueueHandle_t cmd_queue;

/* External OTA/Logo binary handlers */
extern void ota_service_feed_data(const uint8_t *data, uint16_t len);
extern bool ota_is_binary_mode(void);
extern void logo_upload_feed_binary(const uint8_t *data, uint16_t len);
extern bool logo_is_binary_mode(void);

static httpd_handle_t s_server = NULL;
static int s_ws_fd = -1;  /* File descriptor of connected WebSocket client */
static bool s_mdns_initialized = false;

/* ═══════════════════════════════════════════════════════════════
 *  mDNS registration
 * ═══════════════════════════════════════════════════════════════ */
static void mdns_register(void)
{
    if (s_mdns_initialized) return;

    esp_err_t err = mdns_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "mDNS init failed: %s", esp_err_to_name(err));
        return;
    }

    mdns_hostname_set("critical-t1");
    mdns_instance_name_set("Critical T1 Wind Tunnel");

    /* Register WebSocket service for discovery */
    mdns_service_add("Critical-T1-WS", "_ws", "_tcp", WS_PORT, NULL, 0);

    /* Also register HTTP service */
    mdns_service_add("Critical-T1-HTTP", "_http", "_tcp", WS_PORT, NULL, 0);

    s_mdns_initialized = true;
    ESP_LOGI(TAG, "mDNS registered: critical-t1.local:%d", WS_PORT);
}

/* ═══════════════════════════════════════════════════════════════
 *  WebSocket handler — receives frames from APP
 * ═══════════════════════════════════════════════════════════════ */
static esp_err_t ws_handler(httpd_req_t *req)
{
    /* Handle new WebSocket connection (upgrade request) */
    if (req->method == HTTP_GET) {
        s_ws_fd = httpd_req_to_sockfd(req);
        ESP_LOGI(TAG, "WebSocket client connected (fd=%d)", s_ws_fd);
        return ESP_OK;
    }

    /* Receive WebSocket frame */
    httpd_ws_frame_t ws_pkt = {0};
    ws_pkt.type = HTTPD_WS_TYPE_TEXT;

    /* First call with len=0 to get frame info */
    esp_err_t ret = httpd_ws_recv_frame(req, &ws_pkt, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "httpd_ws_recv_frame (info) failed: %s", esp_err_to_name(ret));
        return ret;
    }

    if (ws_pkt.len == 0) {
        /* Empty frame or control frame (ping/pong/close) */
        if (ws_pkt.type == HTTPD_WS_TYPE_CLOSE) {
            ESP_LOGI(TAG, "WebSocket client disconnected");
            s_ws_fd = -1;
        }
        return ESP_OK;
    }

    if (ws_pkt.len > WS_MAX_FRAME_SIZE) {
        ESP_LOGW(TAG, "Frame too large: %d bytes (max %d)", ws_pkt.len, WS_MAX_FRAME_SIZE);
        return ESP_ERR_INVALID_SIZE;
    }

    /* Allocate buffer and receive payload */
    uint8_t *buf = malloc(ws_pkt.len + 1);
    if (!buf) {
        ESP_LOGE(TAG, "Failed to allocate %d bytes for WS frame", ws_pkt.len);
        return ESP_ERR_NO_MEM;
    }

    ws_pkt.payload = buf;
    ret = httpd_ws_recv_frame(req, &ws_pkt, ws_pkt.len);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "httpd_ws_recv_frame (data) failed: %s", esp_err_to_name(ret));
        free(buf);
        return ret;
    }

    /* Route based on frame type */
    if (ws_pkt.type == HTTPD_WS_TYPE_TEXT) {
        /* Text frame = protocol command */
        buf[ws_pkt.len] = '\0';  /* Null-terminate */

        /* Strip trailing \r\n if present */
        int cmd_len = (int)ws_pkt.len;
        while (cmd_len > 0 && (buf[cmd_len - 1] == '\r' || buf[cmd_len - 1] == '\n')) {
            buf[--cmd_len] = '\0';
        }

        if (cmd_len > 0) {
            cmd_msg_t msg;
            if (protocol_parse((const char *)buf, (uint16_t)cmd_len, &msg)) {
                if (cmd_queue) {
                    xQueueSend(cmd_queue, &msg, pdMS_TO_TICKS(10));
                }
            } else {
                ESP_LOGW(TAG, "Parse fail: %s", buf);
            }
        }
    } else if (ws_pkt.type == HTTPD_WS_TYPE_BINARY) {
        /* Binary frame = OTA data or Logo data */
        if (ota_is_binary_mode()) {
            ota_service_feed_data(buf, (uint16_t)ws_pkt.len);
        } else if (logo_is_binary_mode()) {
            logo_upload_feed_binary(buf, (uint16_t)ws_pkt.len);
        } else {
            ESP_LOGW(TAG, "Binary frame received but no binary mode active (%d bytes)",
                     ws_pkt.len);
        }
    }

    free(buf);
    return ESP_OK;
}

/* ═══════════════════════════════════════════════════════════════
 *  HTTP server setup
 * ═══════════════════════════════════════════════════════════════ */
static const httpd_uri_t ws_uri = {
    .uri       = "/ws",
    .method    = HTTP_GET,
    .handler   = ws_handler,
    .user_ctx  = NULL,
    .is_websocket = true,
    .handle_ws_control_frames = true,
};

/* ═══════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════ */
void wifi_comm_service_init(void)
{
    ESP_LOGI(TAG, "WiFi comm service initialized (port %d)", WS_PORT);
    /* Server will be started when wifi_comm_service_start() is called */
}

void wifi_comm_service_start(void)
{
    if (s_server) {
        ESP_LOGW(TAG, "Server already running");
        return;
    }

    /* Register mDNS */
    mdns_register();

    /* Start HTTP server with WebSocket support */
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = WS_PORT;
    config.ctrl_port = WS_PORT + 1;  /* Control port (internal) */
    config.max_open_sockets = 2;     /* 1 WebSocket + 1 spare */
    config.stack_size = 8192;        /* Larger stack for WS frame processing */

    esp_err_t err = httpd_start(&s_server, &config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start httpd: %s", esp_err_to_name(err));
        return;
    }

    httpd_register_uri_handler(s_server, &ws_uri);

    ESP_LOGI(TAG, "WebSocket server started on port %d (ws://critical-t1.local:%d/ws)",
             WS_PORT, WS_PORT);

    /* Notify via BLE that WebSocket is ready (for transition period) */
    char buf[64];
    snprintf(buf, sizeof(buf), "WS_READY:%d\r\n", WS_PORT);
    ble_service_notify_str(buf);
}

void wifi_comm_service_stop(void)
{
    if (s_server) {
        httpd_stop(s_server);
        s_server = NULL;
        s_ws_fd = -1;
        ESP_LOGI(TAG, "WebSocket server stopped");
    }
}

void wifi_comm_service_notify_str(const char *str)
{
    if (!s_server || s_ws_fd < 0 || !str) return;

    httpd_ws_frame_t ws_pkt = {
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *)str,
        .len = strlen(str),
        .final = true,
    };

    esp_err_t err = httpd_ws_send_frame_async(s_server, s_ws_fd, &ws_pkt);
    if (err != ESP_OK) {
        if (err == ESP_ERR_INVALID_ARG) {
            /* Client disconnected */
            ESP_LOGW(TAG, "WS client gone, clearing fd");
            s_ws_fd = -1;
        } else {
            ESP_LOGW(TAG, "WS send failed: %s", esp_err_to_name(err));
        }
    }
}

void wifi_comm_service_notify_bin(const uint8_t *data, uint16_t len)
{
    if (!s_server || s_ws_fd < 0 || !data || len == 0) return;

    httpd_ws_frame_t ws_pkt = {
        .type = HTTPD_WS_TYPE_BINARY,
        .payload = (uint8_t *)data,
        .len = len,
        .final = true,
    };

    esp_err_t err = httpd_ws_send_frame_async(s_server, s_ws_fd, &ws_pkt);
    if (err != ESP_OK) {
        if (err == ESP_ERR_INVALID_ARG) {
            s_ws_fd = -1;
        } else {
            ESP_LOGW(TAG, "WS bin send failed: %s", esp_err_to_name(err));
        }
    }
}

bool wifi_comm_service_is_connected(void)
{
    return (s_server != NULL && s_ws_fd >= 0);
}

uint16_t wifi_comm_service_get_port(void)
{
    return WS_PORT;
}
