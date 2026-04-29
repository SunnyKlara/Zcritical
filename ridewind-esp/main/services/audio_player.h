#pragma once
#include <stdint.h>
#include <stdbool.h>

/**
 * @file audio_player.h
 * @brief Local MP3 file player using minimp3 decoder.
 *
 * Decodes embedded MP3 data (engine.mp3) and outputs PCM to I2S.
 * Supports looping playback and volume control tied to speed.
 */

/** Initialize the audio player (call once at startup) */
void audio_player_init(void);

/** Start playing the embedded engine sound in a loop */
void audio_player_start_engine(void);

/** Stop engine sound playback */
void audio_player_stop_engine(void);

/** Check if engine sound is currently playing */
bool audio_player_is_playing(void);

/**
 * Set engine volume based on speed (0-100).
 * 0 = quiet idle, 100 = full roar.
 */
void audio_player_set_engine_volume(uint8_t speed_percent);

/** Set master volume (0-100), applied on top of speed volume */
void audio_player_set_master_volume(uint8_t volume);

/**
 * Decode and play one MP3 frame. Call from main loop (~20ms period).
 * Non-blocking decode, blocking I2S write (~26ms per frame).
 */
void audio_player_pump(void);
