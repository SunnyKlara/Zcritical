#pragma once
#include <stdint.h>
#include <stdbool.h>

/**
 * @file audio_player.h
 * @brief Variable-rate multi-track engine sound synthesizer.
 *
 * Mixes idle + rev + knock PCM samples with variable playback rate
 * (pitch follows RPM) and crossfade (timbre follows RPM).
 * Outputs 16-bit stereo PCM to I2S at 44100 Hz via drv_audio.
 *
 * Inspired by Rc_Engine_Sound_ESP32 (TheDIYGuy999, GPL-3.0).
 */

/** Initialize the engine sound system (call once at startup) */
void audio_player_init(void);

/** Start the engine sound synthesis task */
void audio_player_start_engine(void);

/** Stop the engine sound (with fade-out) */
void audio_player_stop_engine(void);

/** Check if engine sound is currently playing */
bool audio_player_is_playing(void);

/**
 * Set target RPM from speed percentage (0-100).
 * The actual RPM will smoothly interpolate toward this target
 * with configurable acceleration/deceleration inertia.
 */
void audio_player_set_target_rpm(uint8_t speed_percent);

/**
 * Set master volume (0-100).
 * Applied as final gain stage before I2S output.
 */
void audio_player_set_master_volume(uint8_t volume);

/**
 * Legacy API — maps to set_target_rpm for backward compatibility.
 */
void audio_player_set_engine_volume(uint8_t speed_percent);

/** No-op, kept for API compatibility */
void audio_player_pump(void);

/** Reload audio layers from LittleFS (call after custom audio upload) */
void audio_player_reload_layers(void);

/** Check if custom audio is loaded from LittleFS */
bool audio_player_has_custom_audio(void);
