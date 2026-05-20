/**
 * @file drv_led.c
 * @brief WS2812B LED 灯带 RMT 驱动 — 双灯带(10+3颗)，亮度缩放
 */

#include "drv_led.h"
#include "pin_config.h"
#include "led_strip.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "drv_led";

/* RMT LED strip handles */
static led_strip_handle_t s_strip1;  /* IO41, 10 LEDs */
static led_strip_handle_t s_strip2;  /* IO16, 3 LEDs */

/* Pixel buffers (raw RGB before brightness scaling) */
static uint8_t s_buf1[LED_STRIP1_COUNT][3];
static uint8_t s_buf2[LED_STRIP2_COUNT][3];

static uint8_t s_brightness = 100;

void drv_led_init(void)
{
    /* Strip 1: IO41, 10 LEDs */
    led_strip_config_t cfg1 = {
        .strip_gpio_num = PIN_LED_STRIP1,
        .max_leds = LED_STRIP1_COUNT,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,
        .led_model = LED_MODEL_WS2812,
    };
    led_strip_rmt_config_t rmt1 = {
        .resolution_hz = 10 * 1000 * 1000,  /* 10 MHz */
        .flags.with_dma = false,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&cfg1, &rmt1, &s_strip1));

    /* Strip 2: IO16, 3 LEDs */
    led_strip_config_t cfg2 = {
        .strip_gpio_num = PIN_LED_STRIP2,
        .max_leds = LED_STRIP2_COUNT,
        .led_pixel_format = LED_PIXEL_FORMAT_GRB,
        .led_model = LED_MODEL_WS2812,
    };
    led_strip_rmt_config_t rmt2 = {
        .resolution_hz = 10 * 1000 * 1000,
        .flags.with_dma = false,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&cfg2, &rmt2, &s_strip2));

    drv_led_clear();
    drv_led_refresh();

    ESP_LOGI(TAG, "LED strips init: strip1=%d LEDs (IO%d), strip2=%d LEDs (IO%d)",
             LED_STRIP1_COUNT, PIN_LED_STRIP1, LED_STRIP2_COUNT, PIN_LED_STRIP2);
}

void drv_led_set_pixel(uint8_t phys_strip, uint16_t index, uint8_t r, uint8_t g, uint8_t b)
{
    if (phys_strip == 0 && index < LED_STRIP1_COUNT) {
        s_buf1[index][0] = r;
        s_buf1[index][1] = g;
        s_buf1[index][2] = b;
    } else if (phys_strip == 1 && index < LED_STRIP2_COUNT) {
        s_buf2[index][0] = r;
        s_buf2[index][1] = g;
        s_buf2[index][2] = b;
    }
}

void drv_led_set_strip_color(led_strip_id_t strip, uint8_t r, uint8_t g, uint8_t b)
{
    switch (strip) {
    case LED_STRIP_LEFT:
        for (int i = LED_LEFT_START; i < LED_LEFT_START + LED_LEFT_COUNT; i++)
            drv_led_set_pixel(0, i, r, g, b);
        break;
    case LED_STRIP_MAIN:
        for (int i = LED_MAIN_START; i < LED_MAIN_START + LED_MAIN_COUNT; i++)
            drv_led_set_pixel(0, i, r, g, b);
        break;
    case LED_STRIP_RIGHT:
        for (int i = LED_RIGHT_START; i < LED_RIGHT_START + LED_RIGHT_COUNT; i++)
            drv_led_set_pixel(0, i, r, g, b);
        break;
    case LED_STRIP_TAIL:
        for (int i = LED_TAIL_START; i < LED_TAIL_START + LED_TAIL_COUNT; i++)
            drv_led_set_pixel(1, i, r, g, b);
        break;
    }
}

void drv_led_set_brightness(uint8_t brightness)
{
    if (brightness > 100) brightness = 100;
    s_brightness = brightness;
}

void drv_led_refresh(void)
{
    /* Apply brightness and push to RMT */
    for (int i = 0; i < LED_STRIP1_COUNT; i++) {
        uint8_t r = (uint8_t)((uint16_t)s_buf1[i][0] * s_brightness / 100);
        uint8_t g = (uint8_t)((uint16_t)s_buf1[i][1] * s_brightness / 100);
        uint8_t b = (uint8_t)((uint16_t)s_buf1[i][2] * s_brightness / 100);
        led_strip_set_pixel(s_strip1, i, r, g, b);
    }
    led_strip_refresh(s_strip1);

    for (int i = 0; i < LED_STRIP2_COUNT; i++) {
        uint8_t r = (uint8_t)((uint16_t)s_buf2[i][0] * s_brightness / 100);
        uint8_t g = (uint8_t)((uint16_t)s_buf2[i][1] * s_brightness / 100);
        uint8_t b = (uint8_t)((uint16_t)s_buf2[i][2] * s_brightness / 100);
        led_strip_set_pixel(s_strip2, i, r, g, b);
    }
    led_strip_refresh(s_strip2);
}

void drv_led_clear(void)
{
    memset(s_buf1, 0, sizeof(s_buf1));
    memset(s_buf2, 0, sizeof(s_buf2));
}
