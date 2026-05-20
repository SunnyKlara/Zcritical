/**
 * @file wifi_audio_service.c
 * @brief WiFi STA + TCP server for PCM audio streaming
 *
 * Connects ESP32-S3 to a WiFi router (STA mode) and runs a TCP server
 * on port 8080. The Android APP captures system audio via
 * AudioPlaybackCapture and streams raw 44100Hz 16-bit stereo PCM
 * over TCP to this server.
 *
 * WiFi credentials are received via BLE ("WIFI:ssid:password\n"),
 * saved to NVS, and applied at runtime — no reboot needed.
 * On subsequent boots, saved credentials are loaded and WiFi
 * connects automatically before BLE starts.
 *
 * BLE + WiFi coexistence requires CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y
 * in sdkconfig.defaults.
 */

#include "wifi_audio_service.h"
#include "audio_engine.h"
#include "ble_service.h"
#include "wifi_comm_service.h"

#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_log.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "lwip/sockets.h"

#include <string.h>
#include <stdlib.h>

static const char *TAG = "WIFI_AUDIO";

#define TCP_PORT          8080
#define TCP_RX_BUF_SIZE   8192
#define WIFI_CONNECTED_BIT BIT0
#define WIFI_STARTED_BIT   BIT1
#define NVS_NAMESPACE     "wifi_cfg"

static volatile bool s_streaming = false;
static TaskHandle_t  s_server_task = NULL;
static int           s_listen_fd = -1;
static EventGroupHandle_t s_wifi_event_group = NULL;
static bool s_wifi_connected = false;
static bool s_wifi_initialized = false;
static char s_ip_addr[20] = {0};
static int  s_retry_count = 0;
#define WIFI_MAX_RETRY  10

static char s_saved_ssid[33] = {0};
static char s_saved_pass[65] = {0};

/* ═══════════════════════════════════════════════════════════════
 *  NVS helpers
 * ═══════════════════════════════════════════════════════════════ */
static bool nvs_load_wifi(char *ssid, char *pass)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) return false;

    size_t ssid_len = 33;
    size_t pass_len = 65;
    esp_err_t e1 = nvs_get_str(h, "ssid", ssid, &ssid_len);
    esp_err_t e2 = nvs_get_str(h, "pass", pass, &pass_len);
    nvs_close(h);

    return (e1 == ESP_OK && e2 == ESP_OK && ssid[0] != '\0');
}

static void nvs_save_wifi(const char *ssid, const char *pass)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, "ssid", ssid);
    nvs_set_str(h, "pass", pass);
    nvs_commit(h);
    nvs_close(h);
    ESP_LOGI(TAG, "WiFi credentials saved to NVS");
}

/* ═══════════════════════════════════════════════════════════════
 *  WiFi event handler
 * ═══════════════════════════════════════════════════════════════ */
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT) {
        switch (event_id) {
        case WIFI_EVENT_STA_START:
            ESP_LOGI(TAG, "WiFi STA started, connecting...");
            /* Use MIN_MODEM power save — this is REQUIRED for coexistence.
             * WIFI_PS_NONE starves BLE of RF time and causes coex failures.
             * MIN_MODEM lets the coex scheduler properly time-slice between
             * WiFi and BLE while still maintaining good WiFi throughput. */
            esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
            ESP_LOGI(TAG, "WiFi power save set to MIN_MODEM (coex-friendly)");
            xEventGroupSetBits(s_wifi_event_group, WIFI_STARTED_BIT);
            esp_wifi_connect();
            break;

        case WIFI_EVENT_STA_CONNECTED:
            ESP_LOGI(TAG, "WiFi associated with AP, waiting for IP...");
            s_retry_count = 0;
            break;

        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *evt =
                (wifi_event_sta_disconnected_t *)event_data;
            ESP_LOGW(TAG, "WiFi disconnected (reason=%d)", evt->reason);
            s_wifi_connected = false;
            xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);

            /* Stop WebSocket server when WiFi is lost */
            wifi_comm_service_stop();

            if (s_retry_count < WIFI_MAX_RETRY) {
                s_retry_count++;
                ESP_LOGI(TAG, "Retry %d/%d...", s_retry_count, WIFI_MAX_RETRY);
                vTaskDelay(pdMS_TO_TICKS(1000));
                esp_wifi_connect();
            } else {
                ESP_LOGE(TAG, "WiFi connect failed after %d retries", WIFI_MAX_RETRY);
                ble_service_notify_str("WIFI_ERR:CONNECT_FAILED\r\n");
            }
            break;
        }
        default:
            break;
        }
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        snprintf(s_ip_addr, sizeof(s_ip_addr), IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "Got IP: %s", s_ip_addr);
        s_wifi_connected = true;
        s_retry_count = 0;
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);

        /* Notify APP of our IP address */
        char buf[48];
        snprintf(buf, sizeof(buf), "WIFI_IP:%s\r\n", s_ip_addr);
        ble_service_notify_str(buf);

        /* Start WebSocket communication server */
        wifi_comm_service_start();
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  WiFi STA init — call once, then use wifi_do_connect() to
 *  change credentials at runtime without rebooting.
 * ═══════════════════════════════════════════════════════════════ */
static void wifi_ensure_initialized(void)
{
    if (s_wifi_initialized) return;

    ESP_LOGI(TAG, "Initializing WiFi subsystem (first use)...");

    /* esp_netif_init and event loop may already be created by other
     * components. Use _init_check variants or ignore ESP_ERR_INVALID_STATE. */
    esp_err_t err;
    err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_ERROR_CHECK(err);
    }
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_ERROR_CHECK(err);
    }

    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    /* PSRAM enabled + CONFIG_SPIRAM_TRY_ALLOCATE_WIFI_LWIP=y:
     * Dynamic buffers auto-allocate from PSRAM.
     * Static RX buffers MUST be in internal DMA memory — keep at 4
     * to avoid OOM (LCD DMA takes 112KB of internal SRAM). */
    cfg.static_rx_buf_num = 4;     /* must be internal DMA, keep low */
    cfg.dynamic_rx_buf_num = 32;   /* default 32, goes to PSRAM */
    cfg.tx_buf_type = 1;           /* dynamic TX buffers */
    cfg.dynamic_tx_buf_num = 32;   /* default 32, goes to PSRAM */
    cfg.cache_tx_buf_num = 0;
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));

    s_wifi_initialized = true;
    ESP_LOGI(TAG, "WiFi STA subsystem initialized");
}

/**
 * Apply WiFi credentials and connect. Can be called multiple times
 * to switch networks without rebooting.
 */
static void wifi_do_connect(const char *ssid, const char *password)
{
    /* Lazy init — WiFi subsystem only starts when actually needed */
    wifi_ensure_initialized();

    s_retry_count = 0;

    /* If already connected to the SAME network, just re-notify the IP */
    if (s_wifi_connected && s_ip_addr[0] != '\0') {
        wifi_config_t current_cfg = {0};
        esp_wifi_get_config(WIFI_IF_STA, &current_cfg);
        if (strcmp((char *)current_cfg.sta.ssid, ssid) == 0) {
            ESP_LOGI(TAG, "Already connected to \"%s\", re-notifying IP", ssid);
            char buf[48];
            snprintf(buf, sizeof(buf), "WIFI_IP:%s\r\n", s_ip_addr);
            ble_service_notify_str(buf);
            return;
        }
    }

    /* Stop current connection cleanly */
    if (s_wifi_connected) {
        ESP_LOGI(TAG, "Switching WiFi network...");
        s_wifi_connected = false;
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
        esp_wifi_disconnect();
        /* Wait for disconnect event to be processed */
        vTaskDelay(pdMS_TO_TICKS(500));
        /* Reset retry count so disconnect handler doesn't auto-reconnect */
        s_retry_count = WIFI_MAX_RETRY;
        vTaskDelay(pdMS_TO_TICKS(200));
    }

    s_retry_count = 0;

    wifi_config_t wifi_cfg = {0};
    strncpy((char *)wifi_cfg.sta.ssid, ssid, sizeof(wifi_cfg.sta.ssid) - 1);
    strncpy((char *)wifi_cfg.sta.password, password, sizeof(wifi_cfg.sta.password) - 1);
    wifi_cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    wifi_cfg.sta.sort_method = WIFI_CONNECT_AP_BY_SIGNAL;

    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_cfg));

    EventBits_t bits = xEventGroupGetBits(s_wifi_event_group);
    if (!(bits & WIFI_STARTED_BIT)) {
        ESP_LOGI(TAG, "Starting WiFi driver...");
        ESP_ERROR_CHECK(esp_wifi_start());
    } else {
        ESP_LOGI(TAG, "Connecting to \"%s\"...", ssid);
        esp_wifi_connect();
    }
}
/* ═══════════════════════════════════════════════════════════════
 *  TCP server task — waits for WiFi, then accepts audio clients
 * ═══════════════════════════════════════════════════════════════ */
static void tcp_server_task(void *arg)
{
    static uint8_t rx_buf[TCP_RX_BUF_SIZE];

    for (;;) {
        /* Wait until WiFi is connected */
        ESP_LOGI(TAG, "TCP server waiting for WiFi connection...");
        xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT,
                            pdFALSE, pdFALSE, portMAX_DELAY);

        /* Create listening socket */
        s_listen_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (s_listen_fd < 0) {
            ESP_LOGE(TAG, "Socket create failed");
            vTaskDelay(pdMS_TO_TICKS(3000));
            continue;
        }

        int opt = 1;
        setsockopt(s_listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in server_addr = {
            .sin_family = AF_INET,
            .sin_port = htons(TCP_PORT),
            .sin_addr.s_addr = htonl(INADDR_ANY),
        };

        if (bind(s_listen_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) != 0) {
            ESP_LOGE(TAG, "Bind failed");
            close(s_listen_fd); s_listen_fd = -1;
            vTaskDelay(pdMS_TO_TICKS(3000));
            continue;
        }

        if (listen(s_listen_fd, 1) != 0) {
            ESP_LOGE(TAG, "Listen failed");
            close(s_listen_fd); s_listen_fd = -1;
            vTaskDelay(pdMS_TO_TICKS(3000));
            continue;
        }

        ESP_LOGI(TAG, "TCP server listening on %s:%d", s_ip_addr, TCP_PORT);

        /* Notify APP that audio server is ready */
        char buf[64];
        snprintf(buf, sizeof(buf), "AUDIO_READY:%s:%d\r\n", s_ip_addr, TCP_PORT);
        ble_service_notify_str(buf);

        /* Accept loop — breaks if WiFi disconnects */
        while (s_wifi_connected) {
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);

            /* Use select() with timeout so we can check wifi_connected */
            fd_set read_fds;
            FD_ZERO(&read_fds);
            FD_SET(s_listen_fd, &read_fds);
            struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };

            int sel = select(s_listen_fd + 1, &read_fds, NULL, NULL, &tv);
            if (sel <= 0) continue;  /* timeout or error, re-check wifi */

            int client_fd = accept(s_listen_fd, (struct sockaddr *)&client_addr, &addr_len);
            if (client_fd < 0) continue;

            ESP_LOGI(TAG, "Audio client connected");
            s_streaming = true;

            int nd = 1;
            setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &nd, sizeof(nd));

            /* Lazy-start audio engine output task on first WiFi audio connection */
            audio_engine_start_task();

            /* Receive PCM data and feed to audio engine.
             * CRITICAL: TCP recv can return odd byte counts. PCM is 16-bit
             * stereo (4 bytes per frame). If we feed misaligned data, L/R
             * channels swap → crackling/popping noise.
             * Solution: carry over trailing odd byte(s) to next recv. */
            int carry = 0;  /* bytes carried from previous recv (0 or 1) */
            while (s_wifi_connected) {
                int len = recv(client_fd, rx_buf + carry,
                               TCP_RX_BUF_SIZE - carry, 0);
                if (len <= 0) break;
                len += carry;

                /* Frame-align: must be multiple of 4 (one stereo sample) */
                int aligned = len & ~3;
                carry = len - aligned;

                if (aligned > 0) {
                    audio_engine_feed_a2dp_pcm((const int16_t *)rx_buf,
                                               aligned / (int)sizeof(int16_t));
                }

                /* Move trailing bytes to start of buffer for next recv */
                if (carry > 0) {
                    memmove(rx_buf, rx_buf + aligned, carry);
                }
            }

            s_streaming = false;
            close(client_fd);
            ESP_LOGI(TAG, "Audio client disconnected");
        }

        /* WiFi lost — close server socket, loop back to wait */
        close(s_listen_fd);
        s_listen_fd = -1;
        ESP_LOGW(TAG, "WiFi lost, TCP server stopped");
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════ */

void wifi_audio_service_init(void)
{
    s_wifi_event_group = xEventGroupCreate();

    /* DON'T initialize WiFi subsystem here — it consumes ~40KB heap
     * and can interfere with BLE. WiFi will be lazily initialized
     * when wifi_do_connect() is first called. */

    /* Check for saved WiFi credentials — but DON'T auto-connect at boot.
     * WiFi will only connect when APP explicitly sends WIFI command via BLE.
     * This prevents WiFi from interfering with BLE connection. */
    char ssid[33] = {0}, pass[65] = {0};
    if (nvs_load_wifi(ssid, pass)) {
        ESP_LOGI(TAG, "Found saved WiFi: \"%s\" — waiting for APP to trigger connect", ssid);
        strncpy(s_saved_ssid, ssid, sizeof(s_saved_ssid) - 1);
        strncpy(s_saved_pass, pass, sizeof(s_saved_pass) - 1);
        /* NOT auto-connecting. APP will send WIFI command or call
         * wifi_audio_service_auto_connect() after BLE is stable. */
    } else {
        ESP_LOGI(TAG, "No saved WiFi credentials — send WIFI:ssid:pass via BLE");
    }

    /* Start TCP server task (will wait for WiFi connection) */
    xTaskCreatePinnedToCore(tcp_server_task, "tcp_audio", 4096, NULL, 4,
                            &s_server_task, 0);
}

void wifi_audio_service_connect(const char *ssid, const char *password)
{
    ESP_LOGI(TAG, "New WiFi config: \"%s\"", ssid);
    nvs_save_wifi(ssid, password);
    wifi_do_connect(ssid, password);
}

void wifi_audio_service_auto_connect(void)
{
    if (s_saved_ssid[0] != '\0') {
        ESP_LOGI(TAG, "Auto-connecting to saved WiFi: \"%s\" (blocking, max 10s)", s_saved_ssid);
        wifi_do_connect(s_saved_ssid, s_saved_pass);

        /* Block until connected or timeout (10 seconds).
         * This is called at boot BEFORE BLE starts, so blocking is safe.
         * Ensures WiFi is fully connected before BLE init to avoid RF contention. */
        EventBits_t bits = xEventGroupWaitBits(
            s_wifi_event_group, WIFI_CONNECTED_BIT,
            pdFALSE, pdFALSE, pdMS_TO_TICKS(10000));

        if (bits & WIFI_CONNECTED_BIT) {
            ESP_LOGI(TAG, "WiFi auto-connect SUCCESS: %s", s_ip_addr);
        } else {
            ESP_LOGW(TAG, "WiFi auto-connect TIMEOUT (10s) — will retry in background");
        }
    } else {
        ESP_LOGI(TAG, "No saved WiFi to auto-connect");
    }
}

void wifi_audio_service_scan(void)
{
    /* WiFi scan is done on the phone side (Android WifiManager).
     * ESP32 just tells the APP to use its own scanner. */
    ble_service_notify_str("WIFI_SCAN:USE_PHONE\r\n");
}

bool wifi_audio_service_is_streaming(void) { return s_streaming; }
bool wifi_audio_service_is_connected(void) { return s_wifi_connected; }
const char *wifi_audio_service_get_ip(void) { return s_ip_addr; }

void wifi_audio_service_stop(void)
{
    s_streaming = false;
    if (s_listen_fd >= 0) {
        close(s_listen_fd);
        s_listen_fd = -1;
    }
}

void wifi_audio_service_clear_credentials(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) == ESP_OK) {
        nvs_erase_key(h, "ssid");
        nvs_erase_key(h, "pass");
        nvs_commit(h);
        nvs_close(h);
        ESP_LOGI(TAG, "WiFi credentials cleared from NVS");
    }
}

void wifi_audio_service_notify_status(void)
{
    if (s_wifi_connected && s_ip_addr[0] != '\0') {
        char buf[48];
        snprintf(buf, sizeof(buf), "WIFI_IP:%s\r\n", s_ip_addr);
        ble_service_notify_str(buf);

        /* Also re-send AUDIO_READY if TCP server is listening */
        if (s_listen_fd >= 0) {
            char buf2[64];
            snprintf(buf2, sizeof(buf2), "AUDIO_READY:%s:%d\r\n", s_ip_addr, TCP_PORT);
            ble_service_notify_str(buf2);
        }
    }
}

bool wifi_audio_service_has_credentials(void)
{
    char ssid[33] = {0}, pass[65] = {0};
    return nvs_load_wifi(ssid, pass);
}

/* ═══════════════════════════════════════════════════════════════
 *  WiFi Provisioning Task — async BLE-coordinated WiFi connect
 *
 *  Flow: stop BLE advertising → disconnect BLE → connect WiFi
 *        → success: restart BLE advertising + notify WIFI_IP
 *        → failure: restart BLE advertising + notify error
 *
 *  This avoids RF contention during WiFi CONNECTING phase.
 *  Once WiFi is CONNECTED, coexistence with BLE is stable.
 * ═══════════════════════════════════════════════════════════════ */
typedef struct {
    char ssid[33];
    char password[65];
} wifi_provision_params_t;

static void wifi_provision_task(void *arg)
{
    wifi_provision_params_t *params = (wifi_provision_params_t *)arg;

    ESP_LOGI(TAG, "Provisioning: stopping BLE to avoid RF contention...");

    /* Step 1: Stop BLE advertising and disconnect client.
     * This eliminates RF competition during WiFi CONNECTING phase. */
    ble_service_stop();
    vTaskDelay(pdMS_TO_TICKS(200));  /* Let BLE stack settle */

    /* Step 2: Connect WiFi (blocking wait up to 10s) */
    ESP_LOGI(TAG, "Provisioning: connecting to \"%s\"...", params->ssid);
    nvs_save_wifi(params->ssid, params->password);
    wifi_do_connect(params->ssid, params->password);

    /* Wait for connection result */
    EventBits_t bits = xEventGroupWaitBits(
        s_wifi_event_group, WIFI_CONNECTED_BIT,
        pdFALSE, pdFALSE, pdMS_TO_TICKS(10000));

    /* Step 3: Restart BLE regardless of WiFi result.
     * WiFi CONNECTED state coexists stably with BLE (confirmed). */
    ESP_LOGI(TAG, "Provisioning: restarting BLE advertising...");
    ble_service_start();

    if (bits & WIFI_CONNECTED_BIT) {
        ESP_LOGI(TAG, "Provisioning SUCCESS: IP=%s", s_ip_addr);
        /* APP will receive WIFI_IP notification when it reconnects via BLE.
         * The event handler already sends WIFI_IP on got_ip event.
         * But APP may not be connected yet — it will get status on reconnect
         * via wifi_audio_service_notify_status() in MTU event. */
    } else {
        ESP_LOGW(TAG, "Provisioning FAILED: WiFi connect timeout (10s)");
        /* BLE is back up — APP will reconnect and we notify failure.
         * Use a small delay to let BLE advertising restart, then notify. */
        vTaskDelay(pdMS_TO_TICKS(500));
        ble_service_notify_str("WIFI_ERR:CONNECT_FAILED\r\n");
    }

    free(params);
    vTaskDelete(NULL);
}

void wifi_audio_service_provision(const char *ssid, const char *password)
{
    /* Allocate params on heap — task will free them */
    wifi_provision_params_t *params = malloc(sizeof(wifi_provision_params_t));
    if (!params) {
        ESP_LOGE(TAG, "Provision: malloc failed");
        ble_service_notify_str("WIFI_ERR:MEM\r\n");
        return;
    }
    strncpy(params->ssid, ssid, sizeof(params->ssid) - 1);
    params->ssid[sizeof(params->ssid) - 1] = '\0';
    strncpy(params->password, password, sizeof(params->password) - 1);
    params->password[sizeof(params->password) - 1] = '\0';

    /* Spawn provisioning task — runs async so BLE command handler returns immediately */
    xTaskCreatePinnedToCore(wifi_provision_task, "wifi_prov", 4096, params, 5, NULL, 0);
}
