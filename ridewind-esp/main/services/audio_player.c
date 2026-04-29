/**
 * @file audio_player.c
 * @brief Engine sound — dual-task pipeline for gapless playback.
 *
 * Memory budget (PSRAM enabled, WiFi audio active):
 *   PSRAM handles: WiFi/LWIP buffers, BT allocations, audio ring buffers
 *   Decode task: 18KB stack (internal SRAM)
 *   Ring buffer: 32KB (may go to PSRAM via malloc)
 *   Output task: 3KB stack
 */

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_NO_STDIO
#define MINIMP3_ONLY_MP3
#define MINIMP3_NO_SIMD
#include "minimp3.h"

#include "audio_player.h"
#include "drv_audio.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/ringbuf.h"
#include <string.h>

static const char *TAG = "AUDIO_PLAY";

extern const uint8_t engine_mp3_start[] asm("_binary_engine_mp3_start");
extern const uint8_t engine_mp3_end[]   asm("_binary_engine_mp3_end");

static mp3dec_t s_mp3dec;
static volatile bool s_playing = false;
static volatile bool s_stop_request = false;
static volatile uint8_t s_master_vol = 80;
static volatile uint8_t s_speed_pct = 0;
static TaskHandle_t s_decode_task = NULL;
static TaskHandle_t s_output_task = NULL;
static RingbufHandle_t s_ringbuf = NULL;

static int16_t s_pcm[1152 * 2];  /* static decode buffer */

/* ══════ Output Task — reads ring buffer, writes I2S ══════ */
static void output_task(void *arg)
{
    ESP_LOGI(TAG, "Output task running");
    vTaskDelay(pdMS_TO_TICKS(80));  /* pre-fill delay */

    while (!s_stop_request) {
        size_t sz = 0;
        void *data = xRingbufferReceiveUpTo(s_ringbuf, &sz, pdMS_TO_TICKS(50),
                                            1024);
        if (data && sz >= 4) {
            sz &= ~3u;
            drv_audio_write((const int16_t *)data, sz / 4);
            vRingbufferReturnItem(s_ringbuf, data);
        } else {
            if (data) vRingbufferReturnItem(s_ringbuf, data);
        }
    }

    /* Silence + stop I2S */
    int16_t silence[256] = {0};
    drv_audio_write(silence, 128);
    drv_audio_stop();

    s_output_task = NULL;
    ESP_LOGI(TAG, "Output task stopped");
    vTaskDelete(NULL);
}

/* ══════ Decode Task — decodes MP3, fills ring buffer ══════ */
static void decode_task(void *arg)
{
    const uint8_t *mp3 = engine_mp3_start;
    size_t mp3_size = (size_t)(engine_mp3_end - engine_mp3_start);

    ESP_LOGI(TAG, "Decode task running, MP3=%u bytes, heap=%lu",
             (unsigned)mp3_size, (unsigned long)esp_get_free_heap_size());

    mp3dec_init(&s_mp3dec);

    while (!s_stop_request) {
        const uint8_t *pos = mp3;
        size_t rem = mp3_size;

        while (rem > 0 && !s_stop_request) {
            mp3dec_frame_info_t info;
            int samples = mp3dec_decode_frame(&s_mp3dec, pos, (int)rem,
                                              s_pcm, &info);
            if (info.frame_bytes == 0) {
                if (rem > 1) { pos++; rem--; continue; }
                break;
            }
            pos += info.frame_bytes;
            rem -= info.frame_bytes;
            if (samples <= 0) continue;

            /* Volume */
            uint8_t spd = s_speed_pct;
            int total = samples * info.channels;
            if (spd == 0) {
                memset(s_pcm, 0, total * sizeof(int16_t));
            } else {
                uint32_t sv = 20 + ((uint32_t)spd * 80) / 100;
                uint32_t vol = (uint32_t)s_master_vol * sv;
                for (int i = 0; i < total; i++) {
                    int32_t s = ((int32_t)s_pcm[i] * (int32_t)vol) / 10000;
                    s_pcm[i] = (s > 32767) ? 32767 : (s < -32768) ? -32768 : (int16_t)s;
                }
            }

            /* Mono → stereo */
            if (info.channels == 1) {
                for (int i = samples - 1; i >= 0; i--) {
                    s_pcm[i*2+1] = s_pcm[i];
                    s_pcm[i*2]   = s_pcm[i];
                }
                total = samples * 2;
            }

            /* Push to ring buffer — blocks if full */
            size_t bytes = total * sizeof(int16_t);
            while (!s_stop_request) {
                if (xRingbufferSend(s_ringbuf, s_pcm, bytes, pdMS_TO_TICKS(10)))
                    break;
            }
        }
        /* Loop — don't reinit decoder for seamless transition */
    }

    s_decode_task = NULL;
    ESP_LOGI(TAG, "Decode task stopped");
    vTaskDelete(NULL);
}

/* ══════ Public API ══════ */

void audio_player_init(void)
{
    ESP_LOGI(TAG, "Init — engine.mp3 = %u bytes",
             (unsigned)(engine_mp3_end - engine_mp3_start));
}

void audio_player_start_engine(void)
{
    if (s_playing) return;

    s_ringbuf = xRingbufferCreate(32768, RINGBUF_TYPE_BYTEBUF);
    if (!s_ringbuf) {
        ESP_LOGE(TAG, "Ring buffer alloc failed, heap=%lu",
                 (unsigned long)esp_get_free_heap_size());
        return;
    }

    drv_audio_restart();
    s_stop_request = false;
    s_playing = true;

    BaseType_t r1 = xTaskCreatePinnedToCore(decode_task, "eng_dec", 18432,
                                            NULL, 5, &s_decode_task, 1);
    BaseType_t r2 = xTaskCreatePinnedToCore(output_task, "eng_out", 3072,
                                            NULL, 6, &s_output_task, 1);
    if (r1 != pdPASS || r2 != pdPASS) {
        ESP_LOGE(TAG, "Task create failed! r1=%d r2=%d heap=%lu",
                 r1, r2, (unsigned long)esp_get_free_heap_size());
        s_stop_request = true; s_playing = false;
        if (s_decode_task) { vTaskDelete(s_decode_task); s_decode_task = NULL; }
        if (s_output_task) { vTaskDelete(s_output_task); s_output_task = NULL; }
        vRingbufferDelete(s_ringbuf); s_ringbuf = NULL;
        return;
    }

    ESP_LOGI(TAG, "Engine started, heap=%lu",
             (unsigned long)esp_get_free_heap_size());
}

void audio_player_stop_engine(void)
{
    if (!s_playing) return;
    s_stop_request = true;

    for (int i = 0; i < 300 && (s_decode_task || s_output_task); i++)
        vTaskDelay(pdMS_TO_TICKS(5));

    if (s_decode_task) { vTaskDelete(s_decode_task); s_decode_task = NULL; }
    if (s_output_task) { vTaskDelete(s_output_task); s_output_task = NULL; drv_audio_stop(); }
    if (s_ringbuf) { vRingbufferDelete(s_ringbuf); s_ringbuf = NULL; }

    s_playing = false;
    ESP_LOGI(TAG, "Engine stopped");
}

bool audio_player_is_playing(void) { return s_playing; }

void audio_player_set_engine_volume(uint8_t speed_percent)
{
    if (speed_percent > 100) speed_percent = 100;
    s_speed_pct = speed_percent;
}

void audio_player_set_master_volume(uint8_t volume)
{
    if (volume > 100) volume = 100;
    s_master_vol = volume;
}

void audio_player_pump(void) { }
