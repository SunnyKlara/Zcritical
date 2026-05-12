#pragma once
#include <stdint.h>
#include <stdbool.h>

void drv_lcd_init(void);
void drv_lcd_fill_rect(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint16_t color);
void drv_lcd_draw_circle(uint16_t cx, uint16_t cy, uint16_t r, uint16_t color, bool filled);
void drv_lcd_draw_line(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1, uint16_t color);
void drv_lcd_draw_char(uint16_t x, uint16_t y, char c, uint16_t fg, uint16_t bg, uint8_t size);
void drv_lcd_draw_string(uint16_t x, uint16_t y, const char *str, uint16_t fg, uint16_t bg, uint8_t size);
void drv_lcd_draw_number(uint16_t x, uint16_t y, int32_t num, uint8_t digits, uint16_t fg, uint16_t bg, uint8_t size);
void drv_lcd_blit_rgb565(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint16_t *data);
void drv_lcd_blit_rgb565_dma(uint16_t x, uint16_t y, uint16_t w, uint16_t h, const uint16_t *data);
void drv_lcd_set_window(uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1);
void drv_lcd_write_data(const uint8_t *data, uint32_t len);
void drv_lcd_clear(uint16_t color);
void drv_lcd_set_backlight(bool on);
