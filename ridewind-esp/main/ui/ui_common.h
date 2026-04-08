#pragma once
#include <stdint.h>

/* Shared UI drawing utilities */
void ui_common_draw_progress_bar(uint16_t x, uint16_t y, uint16_t w, uint16_t h, uint8_t percent, uint16_t color);
void ui_common_draw_dot(uint16_t x, uint16_t y, uint16_t color);
void ui_common_clear_encoder_delta(void);
