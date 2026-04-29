#pragma once
#include <stdint.h>
#include <stdbool.h>

/* Shared UI drawing utilities */
void ui_common_draw_progress_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t percent, uint16_t color);
void ui_common_draw_dot(uint16_t x, uint16_t y, uint16_t color);
void ui_common_clear_encoder_delta(void);

/* ══════ F4-style bitmap rendering helpers ══════ */

/**
 * @brief  Blit an image from F4 取模数组 (RGB565 big-endian byte array).
 *         F4 arrays store pixels as {high_byte, low_byte} pairs.
 *         ESP32 drv_lcd_blit_rgb565 expects native uint16_t (little-endian).
 *         This function handles the byte-swap.
 */
void ui_blit_f4_image(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                      const unsigned char *data);

/**
 * @brief  Draw the full-screen F4 background image (gImage_beijing_240_240).
 */
void ui_draw_f4_background(void);

/**
 * @brief  Draw a large F4-style digit (0-9) at the given position.
 *         Uses the speed_N digit images (height = 53, variable width).
 * @param  x  X position (left edge)
 * @param  y  Y position (top edge)
 * @param  digit  0-9
 */
void ui_draw_large_digit(uint16_t x, uint16_t y, uint8_t digit);

/**
 * @brief  Get the width of a large digit image.
 */
uint8_t ui_large_digit_width(uint8_t digit);

/**
 * @brief  Draw a multi-digit number right-aligned at (right_x, y).
 *         Uses F4's right-aligned layout with signed jianju spacing.
 * @param  right_x   Right edge X coordinate (F4's x_qi or ui4_x_qi)
 * @param  y         Y coordinate
 * @param  num       Number to display (0-999)
 * @param  jianju    Signed spacing (F4 speed uses -2, brightness uses 2)
 */
void ui_draw_large_number_right(uint16_t right_x, uint16_t y,
                                uint16_t num, uint8_t spacing);

/* Internal: signed jianju version matching F4 exactly */
void ui_draw_large_number_right_ex(uint16_t right_x, uint16_t y,
                                    uint16_t num, int8_t jianju);

/**
 * @brief  Draw F4 status indicator LED (12x21 pixel image).
 * @param  x, y   Position
 * @param  state   0=red(off), 1=green(on), 2=orange(throttle)
 */
void ui_draw_f4_led(uint16_t x, uint16_t y, uint8_t state);

/**
 * @brief  Draw a rounded capsule gradient bar (for color presets).
 *         Code-drawn, matching F4's LCD_DrawGradientBar.
 */
void ui_draw_gradient_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                          uint8_t r1, uint8_t g1, uint8_t b1,
                          uint8_t r2, uint8_t g2, uint8_t b2);

/**
 * @brief  Draw a rounded capsule solid color bar.
 */
void ui_draw_solid_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h,
                       uint8_t r, uint8_t g, uint8_t b);
