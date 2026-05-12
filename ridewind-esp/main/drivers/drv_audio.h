#pragma once
#include <stdint.h>
#include <stdbool.h>

/* I2S config: 44100Hz, 16-bit stereo, DIN=IO13, BCLK=IO12, LRC=IO11 */
void drv_audio_init(void);
void drv_audio_write(const int16_t *samples, uint32_t sample_count);
void drv_audio_set_volume(uint8_t volume);  /* 0–100 master volume */
void drv_audio_stop(void);
void drv_audio_restart(void);  /* Re-enable I2S after stop */
