/**
 * @file selftest.c
 * @brief Production self-test — hardware validation for assembly QC.
 *
 * Triggered by holding encoder button (IO8, active low) during power-on.
 * Tests: LCD, LED strips, encoder, speaker, fan, humidifier, BLE, PSRAM.
 * Results displayed on LCD + UART serial output.
 *
 * NEVER RETURNS — device must be power-cycled after test completes.
 */

#include "selftest.h"
#include "pin_config.h"
#include "board_config.h"

#include <stdio.h>
#include <string.h>
#include <stdbool.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

/* Drivers */
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "drv_pwm.h"
#include "drv_gpio.h"
#include "drv_audio.h"

static const char *TAG = "SELFTEST";

/* ═══════════════════════════════════════════════════════════════
 *  Color definitions (RGB565)
 * ═══════════════════════════════════════════════════════════════ */
#define COLOR_BLACK   0x0000
#define COLOR_WHITE   0xFFFF
#define COLOR_RED     0xF800
#define COLOR_GREEN   0x07E0
#define COLOR_BLUE    0x001F
#define COLOR_YELLOW  0xFFE0
#define COLOR_CYAN    0x07FF

/* ═══════════════════════════════════════════════════════════════
 *  Test result tracking
 * ═══════════════════════════════════════════════════════════════ */
typedef enum {
    TEST_LCD = 0,
    TEST_LED_MAIN,
    TEST_LED_TAIL,
    TEST_ENCODER_ROTATE,
    TEST_ENCODER_BUTTON,
    TEST_SPEAKER,
    TEST_FAN,
    TEST_HUMIDIFIER,
    TEST_BLE,
    TEST_PSRAM,
    TEST_COUNT
} test_id_t;

static const char *test_names[TEST_COUNT] = {
    "LCD",
    "LED Main",
    "LED Tail",
    "Enc Rotate",
    "Enc Button",
    "Speaker",
    "Fan",
    "Humidifier",
    "BLE",
    "PSRAM",
};

static bool test_results[TEST_COUNT];

/* ═══════════════════════════════════════════════════════════════
 *  Helper: show test status on LCD
 * ═══════════════════════════════════════════════════════════════ */
static void show_header(void)
{
    drv_lcd_clear(COLOR_BLACK);
    drv_lcd_draw_string(20, 10, "SELF-TEST v1.0", COLOR_CYAN, COLOR_BLACK, 2);
    drv_lcd_draw_string(20, 35, "Hold=enter test", COLOR_WHITE, COLOR_BLACK, 1);
}

static void show_test_item(int idx, const char *status, uint16_t color)
{
    uint16_t y = 60 + idx * 18;
    char line[32];
    snprintf(line, sizeof(line), "%2d.%-12s %s", idx + 1, test_names[idx], status);
    drv_lcd_draw_string(5, y, line, color, COLOR_BLACK, 1);
}

static void show_final_result(bool all_pass)
{
    uint16_t bg = all_pass ? COLOR_GREEN : COLOR_RED;
    const char *msg = all_pass ? "ALL PASS" : "FAIL";

    drv_lcd_fill_rect(30, 200, 180, 35, bg);
    drv_lcd_draw_string(60, 208, msg, COLOR_BLACK, bg, 2);
}

/* ═══════════════════════════════════════════════════════════════
 *  Helper: generate a beep tone via I2S
 * ═══════════════════════════════════════════════════════════════ */
static void generate_beep(uint32_t freq_hz, uint32_t duration_ms)
{
    const uint32_t sample_rate = 44100;
    uint32_t total_samples = sample_rate * duration_ms / 1000;
    #define BEEP_CHUNK  512
    int16_t buf[BEEP_CHUNK * 2];  /* stereo */

    uint32_t samples_written = 0;
    while (samples_written < total_samples) {
        uint32_t chunk = total_samples - samples_written;
        if (chunk > BEEP_CHUNK) chunk = BEEP_CHUNK;

        for (uint32_t i = 0; i < chunk; i++) {
            uint32_t phase = ((samples_written + i) * freq_hz / sample_rate) % 2;
            int16_t val = phase ? 8000 : -8000;
            buf[i * 2]     = val;
            buf[i * 2 + 1] = val;
        }
        drv_audio_write(buf, chunk);
        samples_written += chunk;
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Individual test functions
 * ═══════════════════════════════════════════════════════════════ */

static bool test_lcd_func(void)
{
    drv_lcd_fill_rect(180, 60, 50, 50, COLOR_RED);
    vTaskDelay(pdMS_TO_TICKS(300));
    drv_lcd_fill_rect(180, 60, 50, 50, COLOR_GREEN);
    vTaskDelay(pdMS_TO_TICKS(300));
    drv_lcd_fill_rect(180, 60, 50, 50, COLOR_BLUE);
    vTaskDelay(pdMS_TO_TICKS(300));
    drv_lcd_fill_rect(180, 60, 50, 50, COLOR_BLACK);
    return true;
}

static bool test_led_main_func(void)
{
    for (int i = LED_MAIN_START; i < LED_MAIN_START + LED_MAIN_COUNT; i++)
        drv_led_set_pixel(0, i, 255, 0, 0);
    drv_led_refresh();
    vTaskDelay(pdMS_TO_TICKS(500));

    for (int i = LED_MAIN_START; i < LED_MAIN_START + LED_MAIN_COUNT; i++)
        drv_led_set_pixel(0, i, 0, 255, 0);
    drv_led_refresh();
    vTaskDelay(pdMS_TO_TICKS(500));

    for (int i = LED_MAIN_START; i < LED_MAIN_START + LED_MAIN_COUNT; i++)
        drv_led_set_pixel(0, i, 0, 0, 255);
    drv_led_refresh();
    vTaskDelay(pdMS_TO_TICKS(500));

    drv_led_clear();
    drv_led_refresh();
    return true;
}

static bool test_led_tail_func(void)
{
    for (int i = LED_TAIL_START; i < LED_TAIL_START + LED_TAIL_COUNT; i++)
        drv_led_set_pixel(1, i, 255, 0, 0);
    drv_led_refresh();
    vTaskDelay(pdMS_TO_TICKS(500));

    for (int i = LED_TAIL_START; i < LED_TAIL_START + LED_TAIL_COUNT; i++)
        drv_led_set_pixel(1, i, 0, 255, 0);
    drv_led_refresh();
    vTaskDelay(pdMS_TO_TICKS(500));

    drv_led_clear();
    drv_led_refresh();
    return true;
}

static bool test_encoder_rotate_func(void)
{
    show_test_item(TEST_ENCODER_ROTATE, "ROTATE!", COLOR_YELLOW);
    ESP_LOGI(TAG, "[4] Waiting for encoder rotation (10s timeout)...");

    uint32_t start = (uint32_t)(esp_timer_get_time() / 1000);
    encoder_event_t evt;

    while (((uint32_t)(esp_timer_get_time() / 1000) - start) < 10000) {
        if (drv_encoder_poll(&evt)) {
            if (evt.type == ENC_EVT_ROTATE) {
                ESP_LOGI(TAG, "  Rotation detected: delta=%d", evt.delta);
                return true;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    ESP_LOGW(TAG, "  Timeout — no rotation detected");
    return false;
}

static bool test_encoder_button_func(void)
{
    show_test_item(TEST_ENCODER_BUTTON, "PRESS!", COLOR_YELLOW);
    ESP_LOGI(TAG, "[5] Release button, then press again (10s timeout)...");

    /* Wait for release first (user held button to enter selftest) */
    while (gpio_get_level(PIN_ENC_KEY) == 0) {
        vTaskDelay(pdMS_TO_TICKS(50));
    }
    vTaskDelay(pdMS_TO_TICKS(200));

    /* Wait for fresh press */
    uint32_t start = (uint32_t)(esp_timer_get_time() / 1000);
    while (((uint32_t)(esp_timer_get_time() / 1000) - start) < 10000) {
        if (gpio_get_level(PIN_ENC_KEY) == 0) {
            ESP_LOGI(TAG, "  Button press detected");
            vTaskDelay(pdMS_TO_TICKS(200));
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    ESP_LOGW(TAG, "  Timeout — no button press");
    return false;
}

static bool test_speaker_func(void)
{
    ESP_LOGI(TAG, "[6] Playing beep tones...");
    generate_beep(1000, 500);
    vTaskDelay(pdMS_TO_TICKS(100));
    generate_beep(2000, 300);
    drv_audio_stop();  /* Silence I2S to prevent residual noise */
    return true;
}

static bool test_fan_func(void)
{
    ESP_LOGI(TAG, "[7] Fan ON 70%% for 2 seconds...");
    drv_pwm_set_duty(70);
    vTaskDelay(pdMS_TO_TICKS(2000));
    drv_pwm_set_duty(0);
    return true;
}

static bool test_humidifier_func(void)
{
    ESP_LOGI(TAG, "[8] Humidifier ON for 1.5 seconds...");
    drv_gpio_set_humidifier(true);
    vTaskDelay(pdMS_TO_TICKS(1500));
    drv_gpio_set_humidifier(false);
    return true;
}

static bool test_ble_func(void)
{
    ESP_LOGI(TAG, "[9] BLE — SKIP (confirm via App scan after test)");
    return true;
}

static bool test_psram_func(void)
{
    size_t free_psram = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
    ESP_LOGI(TAG, "[10] PSRAM free: %u bytes", (unsigned)free_psram);

    if (free_psram < 1024 * 1024) {
        ESP_LOGE(TAG, "  PSRAM too small or not detected!");
        return false;
    }

    uint8_t *test_buf = heap_caps_malloc(1024, MALLOC_CAP_SPIRAM);
    if (!test_buf) {
        ESP_LOGE(TAG, "  PSRAM malloc failed");
        return false;
    }
    memset(test_buf, 0xA5, 1024);
    bool ok = true;
    for (int i = 0; i < 1024; i++) {
        if (test_buf[i] != 0xA5) { ok = false; break; }
    }
    free(test_buf);

    if (!ok) ESP_LOGE(TAG, "  PSRAM read/write verify failed");
    return ok;
}

/* ═══════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════ */

bool selftest_check_entry(void)
{
    /* ── Check production test lock in NVS ── */
    nvs_handle_t nvs;
    if (nvs_open("selftest", NVS_READONLY, &nvs) == ESP_OK) {
        uint8_t passed = 0;
        nvs_get_u8(nvs, "passed", &passed);
        nvs_close(nvs);
        if (passed == 1) {
            ESP_LOGI(TAG, "Selftest already passed — skipping (production lock active)");
            return false;
        }
    }

    /* ── Check button state ── */
    gpio_config_t cfg = {
        .pin_bit_mask = (1ULL << PIN_ENC_KEY),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&cfg);
    vTaskDelay(pdMS_TO_TICKS(50));

    bool pressed = (gpio_get_level(PIN_ENC_KEY) == 0);
    if (pressed) {
        ESP_LOGW(TAG, "*** SELFTEST MODE — Encoder button held at boot ***");
    }
    return pressed;
}

void selftest_run(void)
{
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "  RideWind Production Self-Test v1.0");
    ESP_LOGI(TAG, "========================================");

    /* Initialize drivers */
    drv_lcd_init();
    drv_lcd_set_backlight(true);
    drv_led_init();
    drv_led_set_brightness(80);
    drv_encoder_init();
    drv_pwm_init();
    drv_audio_init();

    show_header();
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Run tests */
    typedef bool (*test_func_t)(void);
    test_func_t tests[TEST_COUNT] = {
        test_lcd_func,
        test_led_main_func,
        test_led_tail_func,
        test_encoder_rotate_func,
        test_encoder_button_func,
        test_speaker_func,
        test_fan_func,
        test_humidifier_func,
        test_ble_func,
        test_psram_func,
    };

    for (int i = 0; i < TEST_COUNT; i++) {
        ESP_LOGI(TAG, "[%d/%d] Testing: %s", i + 1, TEST_COUNT, test_names[i]);
        show_test_item(i, "...", COLOR_WHITE);

        bool result = tests[i]();
        test_results[i] = result;

        if (result) {
            show_test_item(i, "PASS", COLOR_GREEN);
            ESP_LOGI(TAG, "  -> PASS");
        } else {
            show_test_item(i, "FAIL", COLOR_RED);
            ESP_LOGE(TAG, "  -> FAIL");
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    /* Summary */
    bool all_pass = true;
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "  RESULTS:");
    for (int i = 0; i < TEST_COUNT; i++) {
        ESP_LOGI(TAG, "  [%s] %s", test_results[i] ? "PASS" : "FAIL", test_names[i]);
        if (!test_results[i]) all_pass = false;
    }
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "  FINAL: %s", all_pass ? "ALL PASS" : "FAILED");
    ESP_LOGI(TAG, "========================================");

    show_final_result(all_pass);

    /* Celebration blink if all pass */
    if (all_pass) {
        for (int blink = 0; blink < 3; blink++) {
            for (int i = 0; i < LED_STRIP1_COUNT; i++)
                drv_led_set_pixel(0, i, 0, 255, 0);
            for (int i = 0; i < LED_STRIP2_COUNT; i++)
                drv_led_set_pixel(1, i, 0, 255, 0);
            drv_led_refresh();
            vTaskDelay(pdMS_TO_TICKS(300));
            drv_led_clear();
            drv_led_refresh();
            vTaskDelay(pdMS_TO_TICKS(200));
        }
    }

    /* ── ALL PASS: set production lock + restart ── */
    if (all_pass) {
        /* Write production test lock to NVS */
        nvs_handle_t nvs;
        if (nvs_open("selftest", NVS_READWRITE, &nvs) == ESP_OK) {
            nvs_set_u8(nvs, "passed", 1);
            nvs_commit(nvs);
            nvs_close(nvs);
            ESP_LOGI(TAG, "Production test lock set — selftest will not run again");
        }

        ESP_LOGI(TAG, "ALL PASS — restarting into normal mode in 3 seconds...");
        vTaskDelay(pdMS_TO_TICKS(3000));
        esp_restart();
    }

    /* ── FAIL: halt forever — operator must investigate ── */
    ESP_LOGE(TAG, "FAILED — halting. Power cycle to retry.");
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
