/**
 * @file audio_engine.c
 * @brief Audio mixer + ring buffer + I2S output task
 *
 * Receives PCM from WiFi audio service via ring buffer.
 * Applies volume control and outputs to I2S via drv_audio.
 */

#include "audio_engine.h"
#include "drv_audio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/ringbuf.h"

#include <string.h>

static const char *TAG = "AUDIO_ENG";

/* ── Ring buffer for WiFi PCM data ── */
/* 64KB — ~180ms of 44100Hz stereo 16-bit audio buffer.
 * Large enough to absorb WiFi/BLE coexistence jitter.
 * Allocated from PSRAM via heap_caps if available. */
#define PCM_RINGBUF_SIZE  (64 * 1024)
static RingbufHandle_t s_pcm_ringbuf = NULL;

/* ── Mixer state ── */
static volatile uint8_t s_volume = 100;
static volatile bool    s_throttle_mode = false;
static volatile bool    s_paused = false;

/* ── Output buffer ── */
/* Process 128 stereo frames (512 bytes) per chunk.
 * At 44100Hz this is ~2.9ms of audio per write. */
#define OUTPUT_FRAMES     128
#define OUTPUT_SAMPLES    (OUTPUT_FRAMES * 2)  /* L+R interleaved */
#define OUTPUT_BYTES      (OUTPUT_SAMPLES * sizeof(int16_t))
static int16_t s_out_buf[OUTPUT_SAMPLES];

/* ── Audio output task handle ── */
static TaskHandle_t s_audio_task = NULL;

/* Forward declaration */
static void ensure_ringbuf(void);

/* ═══════════════════════════════════════════════════════════════
 *  Audio output task — reads ring buffer, applies volume, writes I2S
 * ═══════════════════════════════════════════════════════════════ */
static void audio_output_task(void *arg)
{
    ESP_LOGI(TAG, "Audio output task started");

    for (;;) {
        if (!s_pcm_ringbuf || s_paused) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        size_t item_size = 0;

        /* Read exactly frame-aligned data from ring buffer.
         * CRITICAL: must be multiple of 4 bytes (one stereo frame = 2×int16).
         * Misalignment causes L/R channel swap → crackling noise. */
        int16_t *data = (int16_t *)xRingbufferReceiveUpTo(
            s_pcm_ringbuf, &item_size, pdMS_TO_TICKS(50), OUTPUT_BYTES);

        if (data && item_size >= 4) {
            /* Force frame alignment — drop trailing odd bytes */
            item_size &= ~3u;  /* round down to multiple of 4 */

            uint32_t num_samples = item_size / sizeof(int16_t);
            uint8_t vol = s_volume;

            /* Apply volume scaling */
            for (uint32_t i = 0; i < num_samples; i++) {
                int32_t sample = (int32_t)data[i];

                if (s_throttle_mode) {
                    sample = (sample * 20) / 100;
                }

                sample = (sample * vol) / 100;

                if (sample > 32767) sample = 32767;
                if (sample < -32768) sample = -32768;

                s_out_buf[i] = (int16_t)sample;
            }

            /* Return ring buffer item BEFORE blocking I2S write */
            vRingbufferReturnItem(s_pcm_ringbuf, data);

            /* Write to I2S — num_samples/2 = stereo frame count */
            drv_audio_write(s_out_buf, num_samples / 2);
        } else {
            if (data) vRingbufferReturnItem(s_pcm_ringbuf, data);
            /* Underrun — write silence to keep I2S clock running.
             * Without this, I2S DMA stalls and causes pops on resume. */
            memset(s_out_buf, 0, OUTPUT_BYTES);
            drv_audio_write(s_out_buf, OUTPUT_FRAMES);
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  Public API
 * ═══════════════════════════════════════════════════════════════ */
void audio_engine_init(void)
{
    /* Eagerly create ring buffer — PSRAM available, no need to defer.
     * This avoids latency on first WiFi audio connection. */
    ensure_ringbuf();
    ESP_LOGI(TAG, "Audio engine initialized (ringbuf pre-allocated)");
}

static void ensure_ringbuf(void)
{
    if (s_pcm_ringbuf) return;
    s_pcm_ringbuf = xRingbufferCreate(PCM_RINGBUF_SIZE, RINGBUF_TYPE_BYTEBUF);
    if (!s_pcm_ringbuf) {
        ESP_LOGE(TAG, "Failed to create PCM ring buffer");
        return;
    }
    ESP_LOGI(TAG, "PCM ring buffer created (%d bytes)", PCM_RINGBUF_SIZE);
}

void audio_engine_start_task(void)
{
    if (s_audio_task) return;
    ensure_ringbuf();
    xTaskCreatePinnedToCore(audio_output_task, "audio_out", 4096, NULL, 6, &s_audio_task, 1);
    ESP_LOGI(TAG, "Audio output task created on Core 1, priority 6");
}

void audio_engine_feed_a2dp_pcm(const int16_t *samples, uint32_t count)
{
    if (!samples || count == 0) return;

    /* Lazy init ring buffer on first feed */
    ensure_ringbuf();
    if (!s_pcm_ringbuf) return;

    /* Ensure we only feed frame-aligned data (multiple of 2 samples = 4 bytes) */
    count &= ~1u;  /* round down to even number of int16_t */
    if (count == 0) return;

    size_t bytes = count * sizeof(int16_t);
    /* Block up to 50ms if buffer full — provides TCP backpressure.
     * This prevents data loss and audio dropouts. If buffer stays full
     * for >50ms, drop the data to avoid blocking TCP recv indefinitely. */
    xRingbufferSend(s_pcm_ringbuf, samples, bytes, pdMS_TO_TICKS(50));
}

void audio_engine_set_volume(uint8_t volume)
{
    if (volume > 100) volume = 100;
    s_volume = volume;
    drv_audio_set_volume(volume);
}

void audio_engine_set_throttle_mode(bool active)
{
    s_throttle_mode = active;
}

void audio_engine_pause(void)
{
    s_paused = true;
}

void audio_engine_resume(void)
{
    s_paused = false;
}

/* Engine sound — delegate to audio_player */
#include "audio_player.h"

void audio_engine_play_start_sound(void)
{
    audio_player_start_engine();
}

void audio_engine_start_throttle(void)
{
    audio_player_start_engine();
}

void audio_engine_stop_throttle(void)
{
    audio_player_stop_engine();
}
