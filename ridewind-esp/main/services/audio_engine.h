/**
 * @file audio_engine.h
 * @brief 音频混合器接口 — WiFi PCM 接收 + 音量控制 + I2S 输出任务
 */

#pragma once
#include <stdint.h>
#include <stdbool.h>

void audio_engine_init(void);
void audio_engine_start_task(void);  /* Create audio output FreeRTOS task */

/* Engine sound control (Phase 7 — stubs for now, engine sound not priority) */
void audio_engine_play_start_sound(void);
void audio_engine_start_throttle(void);
void audio_engine_stop_throttle(void);

/* Mixer configuration */
void audio_engine_set_throttle_mode(bool active);

/* Volume 0–100 */
void audio_engine_set_volume(uint8_t volume);

/* Pause/resume the WiFi audio output task (used when engine sound is playing) */
void audio_engine_pause(void);
void audio_engine_resume(void);

/* A2DP PCM input (called from A2DP callback on Core 0) */
void audio_engine_feed_a2dp_pcm(const int16_t *samples, uint32_t count);
