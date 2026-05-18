/**
 * @file audio_player.c
 * @brief 5-layer 16-bit variable-rate engine sound synthesizer.
 *
 * 5 layers at different RPM points (gear-based), 2 adjacent layers
 * active at once with crossfade. Variable playback rate (pitch follows RPM).
 * Non-linear RPM inertia. I2S blocking write at 44100Hz is the master clock.
 *
 * Key fix: all audio data is 44100Hz 16-bit, matching the I2S output rate.
 * Previous version used 22050Hz 8-bit data played at 44100Hz = double speed = bad.
 */

#include "audio_player.h"
#include "audio_engine.h"
#include "drv_audio.h"
#include "storage.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

#include "engine_layers_16bit.h"

static const char *TAG = "ENGINE_SND";

/* ── Layer table ── */
#define NUM_LAYERS ENGINE_NUM_LAYERS
typedef struct { const int16_t *data; uint32_t len; uint16_t rpm; } layer_t;

static const layer_t BUILTIN_LAYERS[NUM_LAYERS] = {
    { engine_layer_0, ENGINE_LAYER_0_COUNT, ENGINE_LAYER_0_RPM },
    { engine_layer_1, ENGINE_LAYER_1_COUNT, ENGINE_LAYER_1_RPM },
    { engine_layer_2, ENGINE_LAYER_2_COUNT, ENGINE_LAYER_2_RPM },
    { engine_layer_3, ENGINE_LAYER_3_COUNT, ENGINE_LAYER_3_RPM },
    { engine_layer_4, ENGINE_LAYER_4_COUNT, ENGINE_LAYER_4_RPM },
};

static layer_t s_layers[NUM_LAYERS];

/* ── Tuning ── */
#define RPM_IDLE        1600
#define RPM_MAX         8000
#define BUF_FRAMES      256
#define FADE_IN_BUFS    50
#define FADE_OUT_BUFS   20
#define FP_SHIFT        16
#define FP_ONE          (1u << FP_SHIFT)

/* ── State ── */
static volatile bool     s_playing      = false;
static volatile bool     s_stop_request = false;
static volatile uint16_t s_target_rpm   = RPM_IDLE;
static volatile uint8_t  s_master_vol   = 80;
static TaskHandle_t      s_task         = NULL;

static uint32_t s_pos[NUM_LAYERS];
static uint16_t s_current_rpm;
static int32_t  s_fade;
static bool     s_fading_out;
static int16_t  s_buf[BUF_FRAMES * 2];

/* ── Helpers ── */

static inline int32_t lerp16(const int16_t *d, uint32_t len, uint32_t pos)
{
    uint32_t i = (pos >> FP_SHIFT) % len;
    uint32_t j = (i + 1) % len;
    int32_t  f = pos & (FP_ONE - 1);
    return (int32_t)d[i] + (((int32_t)(d[j] - d[i]) * f) >> FP_SHIFT);
}

static inline uint32_t adv(uint32_t pos, uint32_t step, uint32_t len)
{
    pos += step;
    uint32_t w = len << FP_SHIFT;
    if (pos >= w) pos -= w;
    if (pos >= w) pos %= w;
    return pos;
}

static uint32_t calc_step(uint16_t rpm, uint16_t layer_rpm)
{
    if (layer_rpm == 0) layer_rpm = 1;
    return ((uint32_t)rpm * FP_ONE) / layer_rpm;
}

static void find_blend(uint16_t rpm, int *lo, int *hi, int32_t *mix)
{
    if (rpm <= s_layers[0].rpm) { *lo = *hi = 0; *mix = 0; return; }
    if (rpm >= s_layers[NUM_LAYERS-1].rpm) { *lo = *hi = NUM_LAYERS-1; *mix = 0; return; }
    for (int i = 0; i < NUM_LAYERS - 1; i++) {
        if (rpm < s_layers[i+1].rpm) {
            *lo = i; *hi = i + 1;
            *mix = (int32_t)(rpm - s_layers[i].rpm) * 256 / (s_layers[i+1].rpm - s_layers[i].rpm);
            return;
        }
    }
    *lo = *hi = NUM_LAYERS - 1; *mix = 0;
}

static uint16_t smooth_rpm(uint16_t cur, uint16_t tgt)
{
    if (cur < tgt) {
        int32_t rate = 80 + ((int32_t)(cur - RPM_IDLE) * 120 / (RPM_MAX - RPM_IDLE));
        int32_t d = tgt - cur;
        cur += (d > rate) ? rate : d;
    } else if (cur > tgt) {
        int32_t d = cur - tgt;
        int32_t rate = (d > 1500) ? 150 : 40;
        cur -= (d > rate) ? rate : d;
    }
    if (cur < RPM_IDLE) cur = RPM_IDLE;
    if (cur > RPM_MAX)  cur = RPM_MAX;
    return cur;
}

/* ── Synth task ── */
static void synth_task(void *arg)
{
    ESP_LOGI(TAG, "5-layer 16-bit synth started (44100Hz)");

    for (int i = 0; i < NUM_LAYERS; i++) s_pos[i] = 0;
    s_current_rpm = RPM_IDLE;
    s_fade = 0;
    s_fading_out = false;

    const int32_t fade_in_step  = (256 + FADE_IN_BUFS  - 1) / FADE_IN_BUFS;
    const int32_t fade_out_step = (256 + FADE_OUT_BUFS - 1) / FADE_OUT_BUFS;

    while (1) {
        s_current_rpm = smooth_rpm(s_current_rpm, s_target_rpm);

        if (s_stop_request && !s_fading_out) s_fading_out = true;
        if (s_fading_out) {
            s_fade -= fade_out_step;
            if (s_fade <= 0) { s_fade = 0; break; }
        } else if (s_fade < 256) {
            s_fade += fade_in_step;
            if (s_fade > 256) s_fade = 256;
        }

        int lo, hi;
        int32_t blend;
        find_blend(s_current_rpm, &lo, &hi, &blend);

        uint32_t step_lo = calc_step(s_current_rpm, s_layers[lo].rpm);
        uint32_t step_hi = calc_step(s_current_rpm, s_layers[hi].rpm);

        int32_t lo_gain = 256 - blend;
        int32_t hi_gain = blend;
        int32_t vol_gain = (s_fade * ((int32_t)s_master_vol * 256 / 100)) >> 8;

        for (int i = 0; i < BUF_FRAMES; i++) {
            int32_t s_lo = lerp16(s_layers[lo].data, s_layers[lo].len, s_pos[lo]);
            int32_t s_hi = (lo != hi)
                ? lerp16(s_layers[hi].data, s_layers[hi].len, s_pos[hi])
                : s_lo;

            int32_t mix = (s_lo * lo_gain + s_hi * hi_gain) >> 8;
            int32_t out = (mix * vol_gain) >> 8;

            if (out > 32767) out = 32767;
            if (out < -32768) out = -32768;

            s_buf[i * 2]     = (int16_t)out;
            s_buf[i * 2 + 1] = (int16_t)out;

            s_pos[lo] = adv(s_pos[lo], step_lo, s_layers[lo].len);
            if (lo != hi)
                s_pos[hi] = adv(s_pos[hi], step_hi, s_layers[hi].len);
        }

        drv_audio_write(s_buf, BUF_FRAMES);
    }

    memset(s_buf, 0, sizeof(s_buf));
    for (int i = 0; i < 4; i++) drv_audio_write(s_buf, BUF_FRAMES);
    drv_audio_stop();

    s_playing = false;
    s_task = NULL;
    ESP_LOGI(TAG, "Synth stopped");
    vTaskDelete(NULL);
}

/* ── Public API ── */

void audio_player_init(void)
{
    ESP_LOGI(TAG, "Init — %d layers, 16-bit 44100Hz", NUM_LAYERS);

    if (storage_audio_count() > 0) {
        ESP_LOGW(TAG, "Clearing stale custom audio from LittleFS");
        storage_audio_delete_all();
    }

    for (int i = 0; i < NUM_LAYERS; i++) {
        s_layers[i] = BUILTIN_LAYERS[i];
        ESP_LOGI(TAG, "  Layer %d: %u samples, rpm=%u",
                 i, (unsigned)s_layers[i].len, s_layers[i].rpm);
    }
}

void audio_player_reload_layers(void) { audio_player_init(); }
bool audio_player_has_custom_audio(void) { return false; }

void audio_player_start_engine(void)
{
    if (s_playing) return;
    ESP_LOGI(TAG, "Starting engine (5-layer 16-bit)");
    audio_engine_pause();
    drv_audio_restart();

    memset(s_buf, 0, sizeof(s_buf));
    for (int i = 0; i < 4; i++) drv_audio_write(s_buf, BUF_FRAMES);

    s_stop_request = false;
    s_playing = true;
    s_target_rpm = RPM_IDLE;

    if (xTaskCreatePinnedToCore(synth_task, "eng_synth", 8192, NULL, 6, &s_task, 1) != pdPASS) {
        ESP_LOGE(TAG, "Task create failed");
        s_playing = false;
        audio_engine_resume();
    }
}

void audio_player_stop_engine(void)
{
    if (!s_playing) return;
    s_stop_request = true;
    for (int i = 0; i < 200 && s_task; i++) vTaskDelay(pdMS_TO_TICKS(10));
    if (s_task) { vTaskDelete(s_task); s_task = NULL; s_playing = false; drv_audio_stop(); }
    audio_engine_resume();
}

bool audio_player_is_playing(void) { return s_playing; }

void audio_player_set_target_rpm(uint8_t pct)
{
    if (pct > 100) pct = 100;
    s_target_rpm = RPM_IDLE + ((uint32_t)pct * (RPM_MAX - RPM_IDLE)) / 100;
}

void audio_player_set_master_volume(uint8_t v)
{
    if (v > 100) v = 100;
    s_master_vol = v;
}

void audio_player_set_engine_volume(uint8_t pct) { audio_player_set_target_rpm(pct); }
void audio_player_pump(void) { }
