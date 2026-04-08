#pragma once
#include <stdint.h>
#include <stdbool.h>

void audio_engine_init(void);
void audio_engine_start_task(void);
void audio_engine_play_start_sound(void);
void audio_engine_start_throttle(void);
void audio_engine_stop_throttle(void);
void audio_engine_set_throttle_mode(bool active);
void audio_engine_set_volume(uint8_t volume);
void audio_engine_feed_a2dp_pcm(const int16_t *samples, uint32_t count);
