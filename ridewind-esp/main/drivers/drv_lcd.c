/**
 * @file drv_lcd.c
 * @brief GC9A01 240×240 round LCD driver over SPI with DMA support.
 *
 * Ported from the working ESPtest/main/main.c reference implementation.
 * Uses SPI2_HOST at 40 MHz with DMA for large transfers.
 */

#include "drv_lcd.h"
#include "pin_config.h"
#include "board_config.h"
#include "font_8x16.h"

#include <string.h>
#include <stdio.h>
#include <math.h>

#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_heap_caps.h"
#include "esp_log.h"

/* ── Private state ─────────────────────────────────────────── */

static const char *TAG = "drv_lcd";
static spi_device_handle_t s_spi_dev;

/**
 * DMA-capable buffer for large blitting operations.
 * 240 pixels × 2 bytes = 480 bytes per scanline — we keep a full-row
 * buffer so fill_rect can blast one row at a time.
 */
#define LCD_LINE_BUF_SIZE  (LCD_WIDTH * 2)

/** Static DMA buffer for blit operations (allocated once in init). */
#define DMA_BUF_SIZE       (LCD_WIDTH * LCD_HEIGHT * 2)  /* 115200 bytes max */
static uint8_t *s_dma_buf = NULL;

/* ── Low-level SPI helpers (from working ESPtest code) ───── */

/** Send a single command byte (DC=0). */
static void lcd_cmd(uint8_t cmd)
{
    spi_transaction_t t = {
        .length    = 8,
        .tx_buffer = &cmd,
    };
    gpio_set_level(PIN_LCD_DC, 0);
    spi_device_polling_transmit(s_spi_dev, &t);
}

/** Send a single data byte (DC=1). */
static void lcd_data(uint8_t d)
{
    spi_transaction_t t = {
        .length    = 8,
        .tx_buffer = &d,
    };
    gpio_set_level(PIN_LCD_DC, 1);
    spi_device_polling_transmit(s_spi_dev, &t);
}

/** Send a buffer of data bytes (DC=1). Uses polling for speed. */
static void lcd_data_buf(const uint8_t *buf, int len)
{
    if (len <= 0) return;
    spi_transaction_t t = {
        .length    = len * 8,
        .tx_buffer = buf,
    };
    gpio_set_level(PIN_LCD_DC, 1);
    spi_device_polling_transmit(s_spi_dev, &t);
}

/**
 * Send a large data buffer using the queued (DMA) SPI path.
 * The buffer MUST be in DMA-capable memory.
 */
static void lcd_data_buf_dma(const uint8_t *buf, int len)
{
    if (len <= 0) return;
    spi_transaction_t t = {
        .length    = len * 8,
        .tx_buffer = buf,
    };
    gpio_set_level(PIN_LCD_DC, 1);
    spi_device_transmit(s_spi_dev, &t);
}

/* ── GC9A01 initialisation (proven sequence from ESPtest) ── */

/**
 * Full GC9A01 init command sequence.
 * Copied verbatim from the working ESP32-S3 test firmware.
 */
static void gc9a01_init_seq(void)
{
    lcd_cmd(0xEF);
    lcd_cmd(0xEB); lcd_data(0x14);
    lcd_cmd(0xFE);
    lcd_cmd(0xEF);
    lcd_cmd(0xEB); lcd_data(0x14);
    lcd_cmd(0x84); lcd_data(0x40);
    lcd_cmd(0x85); lcd_data(0xFF);
    lcd_cmd(0x86); lcd_data(0xFF);
    lcd_cmd(0x87); lcd_data(0xFF);
    lcd_cmd(0x88); lcd_data(0x0A);
    lcd_cmd(0x89); lcd_data(0x21);
    lcd_cmd(0x8A); lcd_data(0x00);
    lcd_cmd(0x8B); lcd_data(0x80);
    lcd_cmd(0x8C); lcd_data(0x01);
    lcd_cmd(0x8D); lcd_data(0x01);
    lcd_cmd(0x8E); lcd_data(0xFF);
    lcd_cmd(0x8F); lcd_data(0xFF);

    lcd_cmd(0xB6); lcd_data(0x00); lcd_data(0x00);

    /* Memory Access Control — display rotation
     * 0x48 = 0°, 0x28 = 90°, 0x88 = 180°, 0xE8 = 270°
     * Adjust if display appears rotated on your hardware */
    lcd_cmd(0x36); lcd_data(0x28);

    /* Pixel format: 16-bit RGB565 */
    lcd_cmd(0x3A); lcd_data(0x05);

    lcd_cmd(0x90); lcd_data(0x08); lcd_data(0x08); lcd_data(0x08); lcd_data(0x08);
    lcd_cmd(0xBD); lcd_data(0x06);
    lcd_cmd(0xBC); lcd_data(0x00);
    lcd_cmd(0xFF); lcd_data(0x60); lcd_data(0x01); lcd_data(0x04);
    lcd_cmd(0xC3); lcd_data(0x13);
    lcd_cmd(0xC4); lcd_data(0x13);
    lcd_cmd(0xC9); lcd_data(0x22);
    lcd_cmd(0xBE); lcd_data(0x11);
    lcd_cmd(0xE1); lcd_data(0x10); lcd_data(0x0E);
    lcd_cmd(0xDF); lcd_data(0x21); lcd_data(0x0C); lcd_data(0x02);

    /* Gamma */
    lcd_cmd(0xF0); lcd_data(0x45); lcd_data(0x09); lcd_data(0x08);
                   lcd_data(0x08); lcd_data(0x26); lcd_data(0x2A);
    lcd_cmd(0xF1); lcd_data(0x43); lcd_data(0x70); lcd_data(0x72);
                   lcd_data(0x36); lcd_data(0x37); lcd_data(0x6F);
    lcd_cmd(0xF2); lcd_data(0x45); lcd_data(0x09); lcd_data(0x08);
                   lcd_data(0x08); lcd_data(0x26); lcd_data(0x2A);
    lcd_cmd(0xF3); lcd_data(0x43); lcd_data(0x70); lcd_data(0x72);
                   lcd_data(0x36); lcd_data(0x37); lcd_data(0x6F);

    lcd_cmd(0xED); lcd_data(0x1B); lcd_data(0x0B);
    lcd_cmd(0xAE); lcd_data(0x77);
    lcd_cmd(0xCD); lcd_data(0x63);

    lcd_cmd(0x70); lcd_data(0x07); lcd_data(0x07); lcd_data(0x04); lcd_data(0x0E);
                   lcd_data(0x0F); lcd_data(0x09); lcd_data(0x07); lcd_data(0x08);
                   lcd_data(0x03);

    lcd_cmd(0xE8); lcd_data(0x34);

    lcd_cmd(0x62); lcd_data(0x18); lcd_data(0x0D); lcd_data(0x71); lcd_data(0xED);
                   lcd_data(0x70); lcd_data(0x70); lcd_data(0x18); lcd_data(0x0F);
                   lcd_data(0x71); lcd_data(0xEF); lcd_data(0x70); lcd_data(0x70);

    lcd_cmd(0x63); lcd_data(0x18); lcd_data(0x11); lcd_data(0x71); lcd_data(0xF1);
                   lcd_data(0x70); lcd_data(0x70); lcd_data(0x18); lcd_data(0x13);
                   lcd_data(0x71); lcd_data(0xF3); lcd_data(0x70); lcd_data(0x70);

    lcd_cmd(0x64); lcd_data(0x28); lcd_data(0x29); lcd_data(0xF1); lcd_data(0x01);
                   lcd_data(0xF1); lcd_data(0x00); lcd_data(0x07);

    lcd_cmd(0x66); lcd_data(0x3C); lcd_data(0x00); lcd_data(0xCD); lcd_data(0x67);
                   lcd_data(0x45); lcd_data(0x45); lcd_data(0x10); lcd_data(0x00);
                   lcd_data(0x00); lcd_data(0x00);

    lcd_cmd(0x67); lcd_data(0x00); lcd_data(0x3C); lcd_data(0x00); lcd_data(0x00);
                   lcd_data(0x00); lcd_data(0x01); lcd_data(0x54); lcd_data(0x10);
                   lcd_data(0x32); lcd_data(0x98);

    lcd_cmd(0x74); lcd_data(0x10); lcd_data(0x85); lcd_data(0x80); lcd_data(0x00);
                   lcd_data(0x00); lcd_data(0x4E); lcd_data(0x00);

    lcd_cmd(0x98); lcd_data(0x3E); lcd_data(0x07);

    lcd_cmd(0x35);  /* Tearing effect line ON */
    lcd_cmd(0x21);  /* Display inversion ON */

    /* Sleep out */
    lcd_cmd(0x11);
    vTaskDelay(pdMS_TO_TICKS(50));  /* GC9A01 typically ready in ~50ms */

    /* NOTE: Display ON (0x29) is NOT called here.
     * Caller must clear GRAM first, then call drv_lcd_set_backlight(true)
     * to avoid showing random GRAM data (snow/flicker) on boot. */
}

/* ── Public API ────────────────────────────────────────────── */

void drv_lcd_init(void)
{
    /* Configure DC pin as GPIO output */
    gpio_set_direction(PIN_LCD_DC, GPIO_MODE_OUTPUT);
    gpio_set_direction(PIN_LCD_CS, GPIO_MODE_OUTPUT);
    gpio_set_level(PIN_LCD_CS, 1);

    /* Optional hardware reset (RST pin not connected on this board) */
    if (PIN_LCD_RST >= 0) {
        gpio_set_direction(PIN_LCD_RST, GPIO_MODE_OUTPUT);
        gpio_set_level(PIN_LCD_RST, 0);
        vTaskDelay(pdMS_TO_TICKS(10));
        gpio_set_level(PIN_LCD_RST, 1);
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    /* SPI bus configuration */
    spi_bus_config_t bus_cfg = {
        .mosi_io_num   = PIN_LCD_SDA,
        .miso_io_num   = -1,
        .sclk_io_num   = PIN_LCD_SCL,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = LCD_WIDTH * LCD_HEIGHT * 2,
    };

    spi_device_interface_config_t dev_cfg = {
        .clock_speed_hz = LCD_SPI_FREQ_HZ,
        .mode           = 0,
        .spics_io_num   = PIN_LCD_CS,
        .queue_size     = 7,
    };

    ESP_ERROR_CHECK(spi_bus_initialize(LCD_SPI_HOST, &bus_cfg, SPI_DMA_CH_AUTO));
    ESP_ERROR_CHECK(spi_bus_add_device(LCD_SPI_HOST, &dev_cfg, &s_spi_dev));

    /* Allocate DMA-capable buffer for large transfers */
    s_dma_buf = (uint8_t *)heap_caps_malloc(DMA_BUF_SIZE, MALLOC_CAP_DMA);
    if (!s_dma_buf) {
        ESP_LOGE(TAG, "Failed to allocate DMA buffer (%d bytes)", DMA_BUF_SIZE);
    }

    /* Run the proven GC9A01 init sequence */
    gc9a01_init_seq();

    /* Clear screen to black to avoid snow */
    drv_lcd_clear(0x0000);

    ESP_LOGI(TAG, "GC9A01 LCD initialised (%dx%d, %d MHz SPI)",
             LCD_WIDTH, LCD_HEIGHT, LCD_SPI_FREQ_HZ / 1000000);
}

void drv_lcd_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1)
{
    lcd_cmd(0x2A);  /* Column address set */
    lcd_data(x0 >> 8); lcd_data(x0 & 0xFF);
    lcd_data(x1 >> 8); lcd_data(x1 & 0xFF);

    lcd_cmd(0x2B);  /* Row address set */
    lcd_data(y0 >> 8); lcd_data(y0 & 0xFF);
    lcd_data(y1 >> 8); lcd_data(y1 & 0xFF);

    lcd_cmd(0x2C);  /* Memory write */
}

void drv_lcd_write_data(const uint8_t *data, uint32_t len)
{
    if (!data || len == 0) return;

    /* For small transfers use polling; for large use DMA path */
    if (len <= 32) {
        lcd_data_buf(data, (int)len);
    } else {
        lcd_data_buf_dma(data, (int)len);
    }
}

void drv_lcd_set_backlight(bool on)
{
    /* No dedicated backlight pin on this board — GC9A01 display-on/off */
    if (on) {
        lcd_cmd(0x29);  /* Display ON */
    } else {
        lcd_cmd(0x28);  /* Display OFF */
    }
}

/* ── Drawing primitives (Task 3.3) ─────────────────────────── */

void drv_lcd_clear(uint16_t color)
{
    drv_lcd_fill_rect(0, 0, LCD_WIDTH, LCD_HEIGHT, color);
}

void drv_lcd_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t color)
{
    if (w == 0 || h == 0) return;
    if (x >= LCD_WIDTH || y >= LCD_HEIGHT) return;

    /* Clamp to screen bounds */
    if (x + w > LCD_WIDTH)  w = LCD_WIDTH  - x;
    if (y + h > LCD_HEIGHT) h = LCD_HEIGHT - y;

    drv_lcd_set_window(x, y, x + w - 1, y + h - 1);

    uint8_t hi = color >> 8;
    uint8_t lo = color & 0xFF;

    /* Build one scanline in a stack buffer (max 480 bytes) */
    uint8_t line[LCD_LINE_BUF_SIZE];
    for (uint16_t i = 0; i < w; i++) {
        line[i * 2]     = hi;
        line[i * 2 + 1] = lo;
    }

    /* Blast row by row */
    for (uint16_t r = 0; r < h; r++) {
        lcd_data_buf(line, w * 2);
    }
}

void drv_lcd_draw_line(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t color)
{
    /* Bresenham's line algorithm */
    int dx = (int)x1 - (int)x0;
    int dy = (int)y1 - (int)y0;
    int sx = (dx >= 0) ? 1 : -1;
    int sy = (dy >= 0) ? 1 : -1;
    dx = (dx >= 0) ? dx : -dx;
    dy = (dy >= 0) ? dy : -dy;

    int err = dx - dy;
    int cx = (int)x0, cy = (int)y0;

    for (;;) {
        if (cx >= 0 && cx < LCD_WIDTH && cy >= 0 && cy < LCD_HEIGHT) {
            drv_lcd_fill_rect((uint16_t)cx, (uint16_t)cy, 1, 1, color);
        }
        if (cx == (int)x1 && cy == (int)y1) break;
        int e2 = 2 * err;
        if (e2 > -dy) { err -= dy; cx += sx; }
        if (e2 <  dx) { err += dx; cy += sy; }
    }
}

void drv_lcd_draw_circle(uint16_t cx, uint16_t cy, uint16_t r, uint16_t color, bool filled)
{
    if (r == 0) {
        drv_lcd_fill_rect(cx, cy, 1, 1, color);
        return;
    }

    if (filled) {
        /* Filled circle: draw horizontal spans using midpoint algorithm */
        int x = 0, y = (int)r;
        int d = 1 - (int)r;

        while (x <= y) {
            /* Draw horizontal lines for each octant pair */
            int y0_top = (int)cy - y;
            int y0_bot = (int)cy + y;
            int y1_top = (int)cy - x;
            int y1_bot = (int)cy + x;
            int x_left  = (int)cx - x;
            int x_right = (int)cx + x;
            int x_left2 = (int)cx - y;
            int x_right2= (int)cx + y;

            /* Clamp and draw */
            if (y0_top >= 0 && y0_top < LCD_HEIGHT && x_left >= 0 && x_right < LCD_WIDTH)
                drv_lcd_fill_rect((uint16_t)x_left, (uint16_t)y0_top, (uint16_t)(x_right - x_left + 1), 1, color);
            if (y0_bot >= 0 && y0_bot < LCD_HEIGHT && x_left >= 0 && x_right < LCD_WIDTH)
                drv_lcd_fill_rect((uint16_t)x_left, (uint16_t)y0_bot, (uint16_t)(x_right - x_left + 1), 1, color);
            if (y1_top >= 0 && y1_top < LCD_HEIGHT && x_left2 >= 0 && x_right2 < LCD_WIDTH)
                drv_lcd_fill_rect((uint16_t)x_left2, (uint16_t)y1_top, (uint16_t)(x_right2 - x_left2 + 1), 1, color);
            if (y1_bot >= 0 && y1_bot < LCD_HEIGHT && x_left2 >= 0 && x_right2 < LCD_WIDTH)
                drv_lcd_fill_rect((uint16_t)x_left2, (uint16_t)y1_bot, (uint16_t)(x_right2 - x_left2 + 1), 1, color);

            if (d < 0) {
                d += 2 * x + 3;
            } else {
                d += 2 * (x - y) + 5;
                y--;
            }
            x++;
        }
    } else {
        /* Outline circle: midpoint algorithm, plot individual pixels */
        int x = 0, y = (int)r;
        int d = 1 - (int)r;

        while (x <= y) {
            /* 8-way symmetry */
            drv_lcd_fill_rect(cx + x, cy + y, 1, 1, color);
            drv_lcd_fill_rect(cx - x, cy + y, 1, 1, color);
            drv_lcd_fill_rect(cx + x, cy - y, 1, 1, color);
            drv_lcd_fill_rect(cx - x, cy - y, 1, 1, color);
            drv_lcd_fill_rect(cx + y, cy + x, 1, 1, color);
            drv_lcd_fill_rect(cx - y, cy + x, 1, 1, color);
            drv_lcd_fill_rect(cx + y, cy - x, 1, 1, color);
            drv_lcd_fill_rect(cx - y, cy - x, 1, 1, color);

            if (d < 0) {
                d += 2 * x + 3;
            } else {
                d += 2 * (x - y) + 5;
                y--;
            }
            x++;
        }
    }
}

void drv_lcd_draw_char(uint16_t x, uint16_t y, char c, uint16_t fg, uint16_t bg, uint8_t size)
{
    if (c < 32 || c > 126) c = '?';
    if (size == 0) size = 1;

    const uint8_t *glyph = font_8x16[c - 32];
    uint16_t cw = 8 * size;
    uint16_t ch = 16 * size;

    if (x + cw > LCD_WIDTH || y + ch > LCD_HEIGHT) return;

    /* Row buffer: max 8*size pixels × 2 bytes */
    uint8_t rb[LCD_LINE_BUF_SIZE];

    for (uint8_t row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        /* Build one scaled row */
        for (uint8_t col = 0; col < 8; col++) {
            uint16_t clr = (bits & (0x80 >> col)) ? fg : bg;
            for (uint8_t sx = 0; sx < size; sx++) {
                int idx = (col * size + sx) * 2;
                rb[idx]     = clr >> 8;
                rb[idx + 1] = clr & 0xFF;
            }
        }
        /* Write the row 'size' times for vertical scaling */
        drv_lcd_set_window(x, y + row * size, x + cw - 1, y + row * size + size - 1);
        for (uint8_t sy = 0; sy < size; sy++) {
            lcd_data_buf(rb, cw * 2);
        }
    }
}

void drv_lcd_draw_string(uint16_t x, uint16_t y, const char *str, uint16_t fg, uint16_t bg, uint8_t size)
{
    if (!str) return;
    if (size == 0) size = 1;

    while (*str) {
        if (x + 8 * size > LCD_WIDTH) break;  /* Stop at right edge */
        drv_lcd_draw_char(x, y, *str, fg, bg, size);
        x += 8 * size;
        str++;
    }
}

void drv_lcd_draw_number(uint16_t x, uint16_t y, int32_t num, uint8_t digits, uint16_t fg, uint16_t bg, uint8_t size)
{
    char buf[16];
    if (digits > 0 && digits < sizeof(buf)) {
        snprintf(buf, sizeof(buf), "%*ld", (int)digits, (long)num);
    } else {
        snprintf(buf, sizeof(buf), "%ld", (long)num);
    }
    drv_lcd_draw_string(x, y, buf, fg, bg, size);
}

/* ── Image blitting (Task 3.4) ─────────────────────────────── */

void drv_lcd_blit_rgb565(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint16_t *data)
{
    if (!data || w == 0 || h == 0) return;
    if (x >= LCD_WIDTH || y >= LCD_HEIGHT) return;
    if (x + w > LCD_WIDTH)  w = LCD_WIDTH  - x;
    if (y + h > LCD_HEIGHT) h = LCD_HEIGHT - y;

    drv_lcd_set_window(x, y, x + w - 1, y + h - 1);

    uint32_t total_bytes = (uint32_t)w * h * 2;

    /* Use polling transmit — data may be in flash (const), send in chunks */
    const uint8_t *src = (const uint8_t *)data;
    while (total_bytes > 0) {
        int chunk = (total_bytes > LCD_LINE_BUF_SIZE) ? LCD_LINE_BUF_SIZE : (int)total_bytes;
        lcd_data_buf(src, chunk);
        src += chunk;
        total_bytes -= chunk;
    }
}

void drv_lcd_blit_rgb565_dma(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint16_t *data)
{
    if (!data || w == 0 || h == 0) return;
    if (x >= LCD_WIDTH || y >= LCD_HEIGHT) return;
    if (x + w > LCD_WIDTH)  w = LCD_WIDTH  - x;
    if (y + h > LCD_HEIGHT) h = LCD_HEIGHT - y;

    drv_lcd_set_window(x, y, x + w - 1, y + h - 1);

    uint32_t total_bytes = (uint32_t)w * h * 2;
    const uint8_t *src = (const uint8_t *)data;

    if (!s_dma_buf) {
        /* Fallback to non-DMA path if allocation failed */
        drv_lcd_blit_rgb565(x, y, w, h, data);
        return;
    }

    /*
     * Copy into DMA-capable buffer in chunks and send via DMA.
     * Max chunk = DMA_BUF_SIZE (full frame fits).
     */
    while (total_bytes > 0) {
        uint32_t chunk = (total_bytes > DMA_BUF_SIZE) ? DMA_BUF_SIZE : total_bytes;
        memcpy(s_dma_buf, src, chunk);
        lcd_data_buf_dma(s_dma_buf, (int)chunk);
        src += chunk;
        total_bytes -= chunk;
    }
}
