/**
 * @file audio_player.c
 * @brief 4-layer variable-rate engine sound synthesizer.
 *
 * 4 layers at different RPM points, only 2 adjacent layers active at once.
 * Variable playback rate (pitch follows RPM), crossfade between layers.
 * Non-linear RPM inertia. I2S blocking write is the master clock.
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

#include "engine_idle.h"
#include "engine_low.h"
#include "engine_mid.h"
#include "engine_high.h"

static const char *TAG = "ENGINE_SND";

/* ── Layer table ── */
#define NUM_LAYERS 4
typedef struct { const int8_t *data; uint32_t len; uint16_t rpm; } layer_t;

/* Built-in (flash) layers — used as fallback */
static const layer_t BUILTIN_LAYERS[NUM_LAYERS] = {
    { engine_idle_samples, ENGINE_IDLE_SAMPLE_COUNT, 800  },
    { engine_low_samples,  ENGINE_LOW_SAMPLE_COUNT,  2000 },
    { engine_mid_samples,  ENGINE_MID_SAMPLE_COUNT,  4000 },
    { engine_high_samples, ENGINE_HIGH_SAMPLE_COUNT, 7000 },
};

/* Active layers — points to either built-in or PSRAM-loaded custom audio */
static layer_t s_layers[NUM_LAYERS];

/* PSRAM buffers for custom audio (freed on reload) */
static int8_t *s_custom_buf[NUM_LAYERS] = {NULL, NULL, NULL, NULL};
static bool s_custom_loaded = false;

/* ── Tuning ── */
#define RPM_IDLE        800
#define RPM_MAX         8000
#define BUF_FRAMES      512
#define FADE_IN_BUFS    70
#define FADE_OUT_BUFS   30
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

static inline int32_t lerp(const int8_t *d, uint32_t len, uint32_t pos)
{
    uint32_t i = (pos >> FP_SHIFT) % len;
    uint32_t j = (i + 1) % len;
    int32_t  f = pos & (FP_ONE - 1);
    return d[i] + (((int32_t)(d[j] - d[i]) * f) >> FP_SHIFT);
}

static inline uint32_t adv(uint32_t pos, uint32_t step, uint32_t len)
{
    pos += step;
    uint32_t w = len << FP_SHIFT;
    if (pos >= w) pos -= w;
    if (pos >= w) pos %= w;
    return pos;
}

/* RPM → step for a given layer. Native pitch when rpm == layer_rpm. */
static uint32_t calc_step(uint16_t rpm, uint16_t layer_rpm)
{
    if (layer_rpm == 0) layer_rpm = 1;
    /* At native pitch: step = 22050/44100 = 0.5 in FP */
    return ((uint32_t)rpm * (FP_ONE / 2)) / layer_rpm;
}

/* Find which 2 layers to blend, return blend 0-256 */
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

/* Non-linear RPM smoothing */
static uint16_t smooth_rpm(uint16_t cur, uint16_t tgt)
{
    if (cur < tgt) {
        /* Accel: faster at higher RPM */
        int32_t rate = 100 + ((int32_t)(cur - RPM_IDLE) * 100 / (RPM_MAX - RPM_IDLE));
        int32_t d = tgt - cur;
        cur += (d > rate) ? rate : d;
    } else if (cur > tgt) {
        /* Decel: slow flywheel decay */
        int32_t d = cur - tgt;
        int32_t rate = (d > 1500) ? 200 : 50;
        cur -= (d > rate) ? rate : d;
    }
    if (cur < RPM_IDLE) cur = RPM_IDLE;
    if (cur > RPM_MAX)  cur = RPM_MAX;
    return cur;
}

/* ── Synth task ── */
static void synth_task(void *arg)
{
    ESP_LOGI(TAG, "4-layer synth started");

    for (int i = 0; i < NUM_LAYERS; i++) s_pos[i] = 0;
    s_current_rpm = RPM_IDLE;
    s_fade = 0;
    s_fading_out = false;

    const int32_t fade_in_step  = (256 + FADE_IN_BUFS  - 1) / FADE_IN_BUFS;
    const int32_t fade_out_step = (256 + FADE_OUT_BUFS - 1) / FADE_OUT_BUFS;

    while (1) {
        /* RPM */
        s_current_rpm = smooth_rpm(s_current_rpm, s_target_rpm);

        /* Fade */
        if (s_stop_request && !s_fading_out) s_fading_out = true;
        if (s_fading_out) {
            s_fade -= fade_out_step;
            if (s_fade <= 0) { s_fade = 0; break; }
        } else if (s_fade < 256) {
            s_fade += fade_in_step;
            if (s_fade > 256) s_fade = 256;
        }

        /* Layer blend */
        int lo, hi;
        int32_t blend;
        find_blend(s_current_rpm, &lo, &hi, &blend);

        uint32_t step_lo = calc_step(s_current_rpm, s_layers[lo].rpm);
        uint32_t step_hi = calc_step(s_current_rpm, s_layers[hi].rpm);

        /* Pre-compute gains: all in 0-256 range.
         * Final multiply chain: sample(-128..127) * layer_gain(0..256) / 256
         *   → still -128..127 range, then << 8 → 16-bit, then * vol_gain / 256.
         * This avoids overflow: max intermediate = 127 * 256 = 32512, fits int16. */
        int32_t lo_gain = 256 - blend;
        int32_t hi_gain = blend;
        int32_t vol_gain = (s_fade * ((int32_t)s_master_vol * 256 / 100)) >> 8;

        /* Fill buffer */
        for (int i = 0; i < BUF_FRAMES; i++) {
            int32_t s_lo = lerp(s_layers[lo].data, s_layers[lo].len, s_pos[lo]);
            int32_t s_hi = (lo != hi)
                ? lerp(s_layers[hi].data, s_layers[hi].len, s_pos[hi])
                : s_lo;

            /* Crossfade: result is -128..127 */
            int32_t mix = (s_lo * lo_gain + s_hi * hi_gain) >> 8;

            /* To 16-bit: -32768..32512 */
            int32_t out = mix << 8;

            /* Apply volume (fade × master): 0-256 */
            out = (out * vol_gain) >> 8;

            /* Clamp */
            if (out >  32767) out =  32767;
            if (out < -32768) out = -32768;

            s_buf[i * 2]     = (int16_t)out;
            s_buf[i * 2 + 1] = (int16_t)out;

            s_pos[lo] = adv(s_pos[lo], step_lo, s_layers[lo].len);
            if (lo != hi)
                s_pos[hi] = adv(s_pos[hi], step_hi, s_layers[hi].len);
        }

        drv_audio_write(s_buf, BUF_FRAMES);
    }

    /* Silence flush */
    memset(s_buf, 0, sizeof(s_buf));
    for (int i = 0; i < 4; i++) drv_audio_write(s_buf, BUF_FRAMES);
    drv_audio_stop();

    s_playing = false;
    s_task = NULL;
    ESP_LOGI(TAG, "Synth stopped");
    vTaskDelete(NULL);
}

/* ── Public API ── */

/**
 * Load audio layers: try LittleFS custom audio first, fall back to built-in.
 * Custom audio must have all 4 layers present to be used.
 */
static void load_audio_layers(void)
{
    /* Free any previously loaded custom buffers */
    for (int i = 0; i < NUM_LAYERS; i++) {
        if (s_custom_buf[i]) {
            free(s_custom_buf[i]);
            s_custom_buf[i] = NULL;
        }
    }
    s_custom_loaded = false;

    /* Check if all 4 custom layers exist in LittleFS */
    uint8_t custom_count = storage_audio_count();
    if (custom_count == AUDIO_LAYER_COUNT) {
        bool all_ok = true;
        int8_t *bufs[NUM_LAYERS] = {NULL};
        uint32_t sizes[NUM_LAYERS] = {0};

        for (int i = 0; i < NUM_LAYERS; i++) {
            if (!storage_audio_read(i, &bufs[i], &sizes[i])) {
                all_ok = false;
                break;
            }
        }

        if (all_ok) {
            for (int i = 0; i < NUM_LAYERS; i++) {
                s_custom_buf[i] = bufs[i];
                s_layers[i].data = bufs[i];
                s_layers[i].len = sizes[i];
                s_layers[i].rpm = BUILTIN_LAYERS[i].rpm;
            }
            s_custom_loaded = true;
            ESP_LOGI(TAG, "Custom audio loaded from LittleFS (%d layers)", NUM_LAYERS);
            return;
        }

        /* Cleanup partial loads */
        for (int i = 0; i < NUM_LAYERS; i++) {
            if (bufs[i]) free(bufs[i]);
        }
        ESP_LOGW(TAG, "Custom audio incomplete, using built-in");
    } else if (custom_count > 0) {
        ESP_LOGW(TAG, "Only %d/%d custom layers found, using built-in", custom_count, AUDIO_LAYER_COUNT);
    }

    /* Use built-in layers */
    for (int i = 0; i < NUM_LAYERS; i++) {
        s_layers[i].data = BUILTIN_LAYERS[i].data;
        s_layers[i].len = BUILTIN_LAYERS[i].len;
        s_layers[i].rpm = BUILTIN_LAYERS[i].rpm;
    }
}

void audio_player_init(void)
{
    ESP_LOGI(TAG, "Init — %d layers", NUM_LAYERS);
    load_audio_layers();
}

void audio_player_reload_layers(void)
{
    bool was_playing = s_playing;
    if (was_playing) {
        audio_player_stop_engine();
    }
    load_audio_layers();
    ESP_LOGI(TAG, "Layers reloaded (custom=%d)", s_custom_loaded);
    if (was_playing) {
        audio_player_start_engine();
    }
}

bool audio_player_has_custom_audio(void)
{
    return s_custom_loaded;
}

void audio_player_start_engine(void)
{
    if (s_playing) return;
    audio_engine_pause();
    drv_audio_restart();

    /* Flush DMA to prevent startup pop */
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
