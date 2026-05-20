/**
 * @file ota_service.c
 * @brief BLE OTA firmware update — streaming write to flash
 *
 * Key design decisions:
 * 1. Uses internal SRAM buffer (4KB), NOT PSRAM.
 *    PSRAM is inaccessible during flash erase/write (shares SPI bus).
 * 2. Streams data directly to OTA partition via esp_ota_write().
 * 3. ACKs every ~4KB to pace BLE sender (sliding window).
 * 4. SHA256 computed incrementally during receive.
 * 5. Rollback support: new firmware must call ota_service_init()
 *    at boot to confirm validity, otherwise auto-rollback on crash.
 *
 * References:
 * - ESP-IDF OTA API: esp_ota_ops.h
 * - ESP-IDF v6.0.1 docs: Over The Air Updates (OTA)
 */

#include "ota_service.h"
#include "ble_service.h"
#include "esp_ota_ops.h"
#include "esp_partition.h"
#include "esp_app_format.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"

#include <string.h>
#include <stdio.h>

static const char *TAG = "OTA_SVC";

/* ═══════════════════════════════════════════════════════════════
 *  Internal SRAM buffer — MUST NOT be in PSRAM
 *  4KB aligns with flash sector erase granularity
 * ═══════════════════════════════════════════════════════════════ */
#define OTA_BUF_SIZE        4096
#define OTA_ACK_INTERVAL    (16 * 244)  /* ~3904 bytes, matches BLE window */

static struct {
    bool                active;
    esp_ota_handle_t    handle;
    const esp_partition_t *partition;
    uint32_t            firmware_size;
    uint32_t            received;
    uint32_t            written;
    uint8_t             buf[OTA_BUF_SIZE];  /* Internal SRAM — critical! */
    uint16_t            buf_offset;
    uint32_t            last_ack_at;        /* received count at last ACK */
    char                expected_sha256[65]; /* hex string or empty */
    mbedtls_sha256_context sha_ctx;
    bool                sha_active;
} s_ota = {0};

static bool s_ota_binary_mode = false;

/* ═══════════════════════════════════════════════════════════════
 *  Rollback self-test — called at boot from app_main()
 * ═══════════════════════════════════════════════════════════════ */
void ota_service_init(void)
{
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;

    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
        if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
            ESP_LOGI(TAG, "First boot after OTA — running diagnostics...");

            /* Basic self-test: if we got this far, core systems are OK.
             * More sophisticated checks can be added later (BLE init, LCD, etc.)
             * For now: reaching app_main() without crash = pass. */
            ESP_LOGI(TAG, "Diagnostics PASSED — marking firmware as valid");
            esp_ota_mark_app_valid_cancel_rollback();
        }
    }

    ESP_LOGI(TAG, "Running from: %s (offset 0x%06X)",
             running->label, (unsigned)running->address);
}

/* ═══════════════════════════════════════════════════════════════
 *  Begin OTA session
 * ═══════════════════════════════════════════════════════════════ */
bool ota_service_begin(uint32_t firmware_size, const char *sha256_hex)
{
    if (s_ota.active) {
        ESP_LOGW(TAG, "OTA already active, aborting previous");
        ota_service_abort();
    }

    /* Find next update partition (A/B toggle) */
    s_ota.partition = esp_ota_get_next_update_partition(NULL);
    if (!s_ota.partition) {
        ESP_LOGE(TAG, "No OTA partition found!");
        ble_service_notify_str("OTA_FAIL:NO_PARTITION\r\n");
        return false;
    }

    /* Size check */
    if (firmware_size > s_ota.partition->size) {
        ESP_LOGE(TAG, "Firmware %u > partition %u",
                 (unsigned)firmware_size, (unsigned)s_ota.partition->size);
        char err[64];
        snprintf(err, sizeof(err), "OTA_FAIL:TOO_BIG:%u:%u\r\n",
                 (unsigned)firmware_size, (unsigned)s_ota.partition->size);
        ble_service_notify_str(err);
        return false;
    }

    ESP_LOGI(TAG, "OTA begin: size=%u, target=%s (0x%06X, %uKB)",
             (unsigned)firmware_size, s_ota.partition->label,
             (unsigned)s_ota.partition->address,
             (unsigned)(s_ota.partition->size / 1024));

    /* Begin OTA — this erases the partition (takes 3-5 seconds for 3MB) */
    esp_err_t err = esp_ota_begin(s_ota.partition, firmware_size, &s_ota.handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_begin failed: %s", esp_err_to_name(err));
        char fail[48];
        snprintf(fail, sizeof(fail), "OTA_FAIL:BEGIN:%s\r\n", esp_err_to_name(err));
        ble_service_notify_str(fail);
        return false;
    }

    /* Initialize state */
    s_ota.firmware_size = firmware_size;
    s_ota.received = 0;
    s_ota.written = 0;
    s_ota.buf_offset = 0;
    s_ota.last_ack_at = 0;
    s_ota.active = true;

    /* SHA256 setup */
    if (sha256_hex && strlen(sha256_hex) == 64) {
        strncpy(s_ota.expected_sha256, sha256_hex, 64);
        s_ota.expected_sha256[64] = '\0';
        mbedtls_sha256_init(&s_ota.sha_ctx);
        mbedtls_sha256_starts(&s_ota.sha_ctx, 0);  /* 0 = SHA-256 (not 224) */
        s_ota.sha_active = true;
    } else {
        s_ota.expected_sha256[0] = '\0';
        s_ota.sha_active = false;
    }

    /* Enter binary mode */
    s_ota_binary_mode = true;

    /* Notify App — ready to receive data */
    char ready[48];
    snprintf(ready, sizeof(ready), "OTA_READY:%u\r\n",
             (unsigned)s_ota.partition->size);
    ble_service_notify_str(ready);

    ESP_LOGI(TAG, "OTA partition erased, ready for data");
    return true;
}

/* ═══════════════════════════════════════════════════════════════
 *  Flush internal buffer to flash
 * ═══════════════════════════════════════════════════════════════ */
static bool flush_buffer(void)
{
    if (s_ota.buf_offset == 0) return true;

    esp_err_t err = esp_ota_write(s_ota.handle, s_ota.buf, s_ota.buf_offset);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_write failed at offset %u: %s",
                 (unsigned)s_ota.written, esp_err_to_name(err));
        return false;
    }

    s_ota.written += s_ota.buf_offset;
    s_ota.buf_offset = 0;
    return true;
}

/* ═══════════════════════════════════════════════════════════════
 *  Feed data — called from BLE callback (Core 0)
 *  Buffers in internal SRAM, flushes to flash every 4KB
 * ═══════════════════════════════════════════════════════════════ */
void ota_service_feed_data(const uint8_t *data, uint16_t len)
{
    if (!s_ota.active || !data || len == 0) return;

    /* Don't accept more than expected */
    uint32_t remaining = s_ota.firmware_size - s_ota.received;
    if (len > remaining) len = (uint16_t)remaining;

    /* Update SHA256 incrementally (operates on input data in SRAM stack) */
    if (s_ota.sha_active) {
        mbedtls_sha256_update(&s_ota.sha_ctx, data, len);
    }

    s_ota.received += len;

    /* Fill internal buffer, flush when full */
    const uint8_t *src = data;
    uint16_t left = len;
    while (left > 0) {
        uint16_t space = OTA_BUF_SIZE - s_ota.buf_offset;
        uint16_t copy = (left < space) ? left : space;

        memcpy(s_ota.buf + s_ota.buf_offset, src, copy);
        s_ota.buf_offset += copy;
        src += copy;
        left -= copy;

        if (s_ota.buf_offset >= OTA_BUF_SIZE) {
            if (!flush_buffer()) {
                /* Flash write failed — abort */
                ble_service_notify_str("OTA_FAIL:FLASH_WRITE\r\n");
                ota_service_abort();
                return;
            }
        }
    }

    /* ACK every ~4KB to pace the sender */
    uint32_t since_last = s_ota.received - s_ota.last_ack_at;
    if (since_last >= OTA_ACK_INTERVAL || s_ota.received >= s_ota.firmware_size) {
        char ack[32];
        snprintf(ack, sizeof(ack), "OTA_ACK:%u\r\n", (unsigned)s_ota.received);
        ble_service_notify_str(ack);
        s_ota.last_ack_at = s_ota.received;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  End OTA — validate and set boot partition
 * ═══════════════════════════════════════════════════════════════ */
void ota_service_end(void)
{
    if (!s_ota.active) {
        ble_service_notify_str("OTA_FAIL:NO_SESSION\r\n");
        return;
    }

    /* Exit binary mode first */
    s_ota_binary_mode = false;

    ESP_LOGI(TAG, "OTA end: received=%u expected=%u written=%u buf_remaining=%u",
             (unsigned)s_ota.received, (unsigned)s_ota.firmware_size,
             (unsigned)s_ota.written, (unsigned)s_ota.buf_offset);

    /* Size check */
    if (s_ota.received != s_ota.firmware_size) {
        char fail[64];
        snprintf(fail, sizeof(fail), "OTA_FAIL:SIZE:%u/%u\r\n",
                 (unsigned)s_ota.received, (unsigned)s_ota.firmware_size);
        ble_service_notify_str(fail);
        ota_service_abort();
        return;
    }

    /* Flush remaining buffer */
    if (!flush_buffer()) {
        ble_service_notify_str("OTA_FAIL:FLUSH\r\n");
        ota_service_abort();
        return;
    }

    /* SHA256 verification (if provided) */
    if (s_ota.sha_active) {
        uint8_t sha_result[32];
        mbedtls_sha256_finish(&s_ota.sha_ctx, sha_result);
        mbedtls_sha256_free(&s_ota.sha_ctx);
        s_ota.sha_active = false;

        /* Convert to hex for comparison */
        char calc_hex[65];
        for (int i = 0; i < 32; i++) {
            snprintf(calc_hex + i * 2, 3, "%02x", sha_result[i]);
        }
        calc_hex[64] = '\0';

        if (strcmp(calc_hex, s_ota.expected_sha256) != 0) {
            ESP_LOGE(TAG, "SHA256 mismatch!");
            ESP_LOGE(TAG, "  Expected: %s", s_ota.expected_sha256);
            ESP_LOGE(TAG, "  Computed: %s", calc_hex);
            ble_service_notify_str("OTA_FAIL:SHA256\r\n");
            esp_ota_abort(s_ota.handle);
            s_ota.active = false;
            return;
        }
        ESP_LOGI(TAG, "SHA256 verified OK");
    }

    /* Finalize OTA — validates image header, magic bytes, etc. */
    esp_err_t err = esp_ota_end(s_ota.handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_end failed: %s", esp_err_to_name(err));
        char fail[48];
        snprintf(fail, sizeof(fail), "OTA_FAIL:VALIDATE:%s\r\n", esp_err_to_name(err));
        ble_service_notify_str(fail);
        s_ota.active = false;
        return;
    }

    /* Set new boot partition */
    err = esp_ota_set_boot_partition(s_ota.partition);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_ota_set_boot_partition failed: %s", esp_err_to_name(err));
        char fail[48];
        snprintf(fail, sizeof(fail), "OTA_FAIL:SET_BOOT:%s\r\n", esp_err_to_name(err));
        ble_service_notify_str(fail);
        s_ota.active = false;
        return;
    }

    /* Success! */
    s_ota.active = false;
    ESP_LOGI(TAG, "OTA SUCCESS! New firmware at %s, rebooting in 500ms...",
             s_ota.partition->label);

    /* Read new firmware version from partition */
    esp_app_desc_t new_desc;
    if (esp_ota_get_partition_description(s_ota.partition, &new_desc) == ESP_OK) {
        char ok[64];
        snprintf(ok, sizeof(ok), "OTA_OK:%s\r\n", new_desc.version);
        ble_service_notify_str(ok);
    } else {
        ble_service_notify_str("OTA_OK:unknown\r\n");
    }

    /* Delay to let BLE notification reach the App, then restart */
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

/* ═══════════════════════════════════════════════════════════════
 *  Abort OTA
 * ═══════════════════════════════════════════════════════════════ */
void ota_service_abort(void)
{
    if (s_ota.active) {
        esp_ota_abort(s_ota.handle);
        if (s_ota.sha_active) {
            mbedtls_sha256_free(&s_ota.sha_ctx);
            s_ota.sha_active = false;
        }
        s_ota.active = false;
        ESP_LOGW(TAG, "OTA aborted");
    }
    s_ota_binary_mode = false;
}

/* ═══════════════════════════════════════════════════════════════
 *  Binary mode query
 * ═══════════════════════════════════════════════════════════════ */
bool ota_is_binary_mode(void)
{
    return s_ota_binary_mode;
}
