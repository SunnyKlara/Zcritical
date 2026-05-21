/**
 * @file storage.c
 * @brief NVS persistent storage + LittleFS logo/MP3 file operations
 *
 * NVS: LED colors, brightness, volume, preset, unit, streamlight,
 *       breathing mode, active logo slot.
 * LittleFS: 2MB partition for logo images (3 slots) and engine MP3 files.
 * Logo format: 16-byte logo_header_t (magic 0xAA55, 240×240, data_size, CRC32) + pixel data.
 */

#include "storage.h"
#include "app_state.h"
#include "board_config.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_littlefs.h"
#include "esp_log.h"
#include "esp_crc.h"
#include "esp_heap_caps.h"
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>

static const char *TAG = "STORAGE";
#define NVS_NAMESPACE "ridewind"

static bool s_littlefs_mounted = false;

/* Standard CRC-32 (same as zlib/PNG/Ethernet/APP Dart implementation)
 * esp_crc32_le(0,...) uses init=0 which is NOT standard.
 * Standard CRC-32: init=0xFFFFFFFF, final XOR=0xFFFFFFFF */
uint32_t storage_crc32(const uint8_t *data, uint32_t len)
{
    return esp_crc32_le(~0U, data, len) ^ ~0U;
}

/* ═══════════════════════════════════════════════════════════════
 *  Factory defaults (must match app_state_init)
 * ═══════════════════════════════════════════════════════════════ */
static const nvs_settings_t s_defaults = {
    .led_colors = {
        {255, 255, 255},  /* Main — white */
        {255, 255, 255},  /* Left — white */
        {255, 255, 255},  /* Right — white */
        {255, 255, 255},  /* Tail — white */
    },
    .brightness = 100,
    .volume = 0,          /* Muted — engine audio still in dev */
    .preset_index = 1,
    .speed_unit = 0,
    .streamlight = 0,
    .breath_mode = 0,
    .active_logo_slot = 0,
};

/* ═══════════════════════════════════════════════════════════════
 *  Helper: build logo file path for a slot
 * ═══════════════════════════════════════════════════════════════ */
static void logo_path(uint8_t slot, char *buf, size_t buf_size)
{
    snprintf(buf, buf_size, LITTLEFS_MOUNT_POINT "/logo_%d.bin", slot);
}

/* ═══════════════════════════════════════════════════════════════
 *  Init: NVS + LittleFS mount
 * ═══════════════════════════════════════════════════════════════ */
void storage_init(void)
{
    ESP_LOGI(TAG, "Storage init (NVS namespace: %s)", NVS_NAMESPACE);

    /* Mount LittleFS on the 2MB storage partition */
    esp_vfs_littlefs_conf_t lfs_conf = {
        .base_path = LITTLEFS_MOUNT_POINT,
        .partition_label = LITTLEFS_PARTITION_LABEL,
        .format_if_mount_failed = true,
        .dont_mount = false,
    };

    esp_err_t err = esp_vfs_littlefs_register(&lfs_conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "LittleFS mount failed: %s", esp_err_to_name(err));
    } else {
        s_littlefs_mounted = true;
        size_t total = 0, used = 0;
        esp_littlefs_info(LITTLEFS_PARTITION_LABEL, &total, &used);
        ESP_LOGI(TAG, "LittleFS mounted: total=%u used=%u", (unsigned)total, (unsigned)used);
    }
}

/* ═══════════════════════════════════════════════════════════════
 *  NVS: load / save settings
 * ═══════════════════════════════════════════════════════════════ */
void storage_load_settings(nvs_settings_t *out)
{
    if (!out) return;
    memcpy(out, &s_defaults, sizeof(nvs_settings_t));

    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &h);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "NVS open failed (first boot?), using defaults");
        return;
    }

    size_t len;
    static const char *led_keys[] = {"led_m_rgb", "led_l_rgb", "led_r_rgb", "led_t_rgb"};
    for (int i = 0; i < 4; i++) {
        len = 3;
        nvs_get_blob(h, led_keys[i], out->led_colors[i], &len);
    }

    nvs_get_u8(h, "brightness", &out->brightness);
    nvs_get_u8(h, "volume", &out->volume);
    nvs_get_u8(h, "preset", &out->preset_index);
    nvs_get_u8(h, "speed_unit", &out->speed_unit);
    nvs_get_u8(h, "streamlight", &out->streamlight);
    nvs_get_u8(h, "breath_mode", &out->breath_mode);
    nvs_get_u8(h, "logo_slot", &out->active_logo_slot);

    nvs_close(h);
    ESP_LOGI(TAG, "Settings loaded: bright=%d vol=%d preset=%d",
             out->brightness, out->volume, out->preset_index);
}

void storage_save_settings(const nvs_settings_t *settings)
{
    if (!settings) return;

    nvs_handle_t h;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "NVS open for write failed: %s", esp_err_to_name(err));
        return;
    }

    static const char *led_keys[] = {"led_m_rgb", "led_l_rgb", "led_r_rgb", "led_t_rgb"};
    for (int i = 0; i < 4; i++) {
        nvs_set_blob(h, led_keys[i], settings->led_colors[i], 3);
    }

    nvs_set_u8(h, "brightness", settings->brightness);
    nvs_set_u8(h, "volume", settings->volume);
    nvs_set_u8(h, "preset", settings->preset_index);
    nvs_set_u8(h, "speed_unit", settings->speed_unit);
    nvs_set_u8(h, "streamlight", settings->streamlight);
    nvs_set_u8(h, "breath_mode", settings->breath_mode);
    nvs_set_u8(h, "logo_slot", settings->active_logo_slot);

    err = nvs_commit(h);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "NVS commit failed: %s", esp_err_to_name(err));
    }
    nvs_close(h);
    ESP_LOGI(TAG, "Settings saved");
}

void storage_save_current(void)
{
    extern app_state_t g_app_state;

    nvs_settings_t s;
    memcpy(s.led_colors, g_app_state.led_colors, sizeof(s.led_colors));
    s.brightness = (uint8_t)g_app_state.brightness;
    s.volume = g_app_state.volume;
    s.preset_index = g_app_state.preset_index;
    s.speed_unit = g_app_state.speed_unit;
    s.streamlight = g_app_state.streamlight_active;
    s.breath_mode = g_app_state.breath_mode;
    s.active_logo_slot = g_app_state.active_logo_slot;
    storage_save_settings(&s);
}

/* ═══════════════════════════════════════════════════════════════
 *  LittleFS: Logo file operations
 * ═══════════════════════════════════════════════════════════════ */
bool storage_logo_exists(uint8_t slot)
{
    if (!s_littlefs_mounted || slot >= MAX_LOGO_SLOTS) return false;

    char path[48];
    logo_path(slot, path, sizeof(path));

    struct stat st;
    return (stat(path, &st) == 0 && st.st_size > (off_t)sizeof(logo_header_t));
}

bool storage_logo_read(uint8_t slot, uint8_t *buf, uint32_t buf_size, uint32_t *out_size)
{
    if (!s_littlefs_mounted || slot >= MAX_LOGO_SLOTS || !buf) return false;

    char path[48];
    logo_path(slot, path, sizeof(path));

    FILE *f = fopen(path, "rb");
    if (!f) {
        ESP_LOGW(TAG, "Logo slot %d: file not found", slot);
        return false;
    }

    /* Read and validate header */
    logo_header_t hdr;
    if (fread(&hdr, 1, sizeof(hdr), f) != sizeof(hdr)) {
        fclose(f);
        return false;
    }

    if (hdr.magic != LOGO_MAGIC || hdr.width != LOGO_WIDTH || hdr.height != LOGO_HEIGHT) {
        ESP_LOGW(TAG, "Logo slot %d: invalid header (magic=0x%04X)", slot, hdr.magic);
        fclose(f);
        return false;
    }

    if (hdr.data_size > buf_size) {
        ESP_LOGW(TAG, "Logo slot %d: data too large (%u > %u)",
                 slot, (unsigned)hdr.data_size, (unsigned)buf_size);
        fclose(f);
        return false;
    }

    /* Read pixel data */
    size_t read_bytes = fread(buf, 1, hdr.data_size, f);
    fclose(f);

    if (read_bytes != hdr.data_size) {
        ESP_LOGW(TAG, "Logo slot %d: short read (%u/%u)",
                 slot, (unsigned)read_bytes, (unsigned)hdr.data_size);
        return false;
    }

    /* Validate CRC32 */
    uint32_t calc_crc = storage_crc32(buf, hdr.data_size);
    if (calc_crc != hdr.crc32) {
        ESP_LOGW(TAG, "Logo slot %d: CRC mismatch (stored=0x%08X calc=0x%08X)",
                 slot, (unsigned)hdr.crc32, (unsigned)calc_crc);
        return false;
    }

    if (out_size) *out_size = hdr.data_size;
    ESP_LOGI(TAG, "Logo slot %d: read OK (%u bytes)", slot, (unsigned)hdr.data_size);
    return true;
}

bool storage_logo_write(uint8_t slot, const uint8_t *data, uint32_t size, uint32_t crc32)
{
    if (!s_littlefs_mounted || slot >= MAX_LOGO_SLOTS || !data || size == 0) return false;

    /* Validate CRC32 before writing */
    uint32_t calc_crc = storage_crc32(data, size);
    if (calc_crc != crc32) {
        ESP_LOGE(TAG, "Logo slot %d: CRC mismatch on write (expected=0x%08X calc=0x%08X)",
                 slot, (unsigned)crc32, (unsigned)calc_crc);
        return false;
    }

    char path[48];
    logo_path(slot, path, sizeof(path));

    FILE *f = fopen(path, "wb");
    if (!f) {
        ESP_LOGE(TAG, "Logo slot %d: cannot open for write", slot);
        return false;
    }

    /* Write header */
    logo_header_t hdr = {
        .magic = LOGO_MAGIC,
        .width = LOGO_WIDTH,
        .height = LOGO_HEIGHT,
        .reserved = 0,
        .data_size = size,
        .crc32 = crc32,
    };

    bool ok = true;
    if (fwrite(&hdr, 1, sizeof(hdr), f) != sizeof(hdr)) {
        ok = false;
    }

    /* Write pixel data */
    if (ok && fwrite(data, 1, size, f) != size) {
        ok = false;
    }

    fclose(f);

    if (!ok) {
        ESP_LOGE(TAG, "Logo slot %d: write failed, removing partial file", slot);
        remove(path);
        return false;
    }

    ESP_LOGI(TAG, "Logo slot %d: written OK (%u bytes, CRC=0x%08X)",
             slot, (unsigned)size, (unsigned)crc32);
    return true;
}

bool storage_logo_delete(uint8_t slot)
{
    if (!s_littlefs_mounted || slot >= MAX_LOGO_SLOTS) return false;

    char path[48];
    logo_path(slot, path, sizeof(path));

    if (remove(path) == 0) {
        ESP_LOGI(TAG, "Logo slot %d: deleted", slot);
        return true;
    }
    ESP_LOGW(TAG, "Logo slot %d: delete failed (not found?)", slot);
    return false;
}

uint8_t storage_logo_count_valid(void)
{
    uint8_t count = 0;
    for (uint8_t i = 0; i < MAX_LOGO_SLOTS; i++) {
        if (storage_logo_exists(i)) count++;
    }
    return count;
}

uint8_t storage_logo_find_empty(void)
{
    for (uint8_t i = 0; i < MAX_LOGO_SLOTS; i++) {
        if (!storage_logo_exists(i)) return i;
    }
    return MAX_LOGO_SLOTS;  /* all full */
}

/* ═══════════════════════════════════════════════════════════════
 *  LittleFS: MP3 file access (Task 19.2)
 * ═══════════════════════════════════════════════════════════════ */
bool storage_mp3_read(const char *filename, uint8_t **out_data, uint32_t *out_size)
{
    if (!s_littlefs_mounted || !filename || !out_data || !out_size) return false;

    char path[64];
    snprintf(path, sizeof(path), LITTLEFS_MOUNT_POINT "/%s", filename);

    FILE *f = fopen(path, "rb");
    if (!f) {
        ESP_LOGW(TAG, "MP3 file not found: %s", path);
        return false;
    }

    /* Get file size */
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (fsize <= 0 || fsize > 512 * 1024) {  /* max 512KB per MP3 */
        ESP_LOGW(TAG, "MP3 file invalid size: %ld", fsize);
        fclose(f);
        return false;
    }

    uint8_t *buf = malloc((size_t)fsize);
    if (!buf) {
        ESP_LOGE(TAG, "MP3 malloc failed (%ld bytes)", fsize);
        fclose(f);
        return false;
    }

    size_t read_bytes = fread(buf, 1, (size_t)fsize, f);
    fclose(f);

    if (read_bytes != (size_t)fsize) {
        ESP_LOGW(TAG, "MP3 short read: %u/%ld", (unsigned)read_bytes, fsize);
        free(buf);
        return false;
    }

    *out_data = buf;
    *out_size = (uint32_t)fsize;
    ESP_LOGI(TAG, "MP3 loaded: %s (%u bytes)", filename, (unsigned)fsize);
    return true;
}


/* ═══════════════════════════════════════════════════════════════
 *  LittleFS: Custom engine audio PCM file operations
 *
 *  Files: /storage/engine_idle.pcm, engine_low.pcm, engine_mid.pcm, engine_high.pcm
 *  Format: raw signed 8-bit PCM, 22050 Hz, mono
 *  No header — just raw samples. Size = sample count.
 * ═══════════════════════════════════════════════════════════════ */

static const char *s_audio_filenames[AUDIO_LAYER_COUNT] = {
    "engine_idle.pcm",
    "engine_low.pcm",
    "engine_mid.pcm",
    "engine_high.pcm",
};

static void audio_path(uint8_t layer, char *buf, size_t buf_size)
{
    snprintf(buf, buf_size, LITTLEFS_MOUNT_POINT "/%s", s_audio_filenames[layer]);
}

bool storage_audio_exists(uint8_t layer)
{
    if (!s_littlefs_mounted || layer >= AUDIO_LAYER_COUNT) return false;
    char path[64];
    audio_path(layer, path, sizeof(path));
    struct stat st;
    return (stat(path, &st) == 0 && st.st_size > 0);
}

bool storage_audio_write(uint8_t layer, const uint8_t *data, uint32_t size, uint32_t crc32)
{
    if (!s_littlefs_mounted || layer >= AUDIO_LAYER_COUNT || !data || size == 0) return false;
    if (size > AUDIO_MAX_PCM_SIZE) {
        ESP_LOGE(TAG, "Audio layer %d: too large (%u > %u)", layer, (unsigned)size, AUDIO_MAX_PCM_SIZE);
        return false;
    }

    /* Validate CRC32 */
    uint32_t calc_crc = storage_crc32(data, size);
    if (crc32 != 0 && calc_crc != crc32) {
        ESP_LOGE(TAG, "Audio layer %d: CRC mismatch (expected=0x%08X calc=0x%08X)",
                 layer, (unsigned)crc32, (unsigned)calc_crc);
        return false;
    }

    char path[64];
    audio_path(layer, path, sizeof(path));

    FILE *f = fopen(path, "wb");
    if (!f) {
        ESP_LOGE(TAG, "Audio layer %d: cannot open for write", layer);
        return false;
    }

    bool ok = (fwrite(data, 1, size, f) == size);
    fclose(f);

    if (!ok) {
        ESP_LOGE(TAG, "Audio layer %d: write failed, removing partial", layer);
        remove(path);
        return false;
    }

    ESP_LOGI(TAG, "Audio layer %d: written OK (%u bytes, CRC=0x%08X)",
             layer, (unsigned)size, (unsigned)calc_crc);
    return true;
}

bool storage_audio_read(uint8_t layer, int8_t **out_data, uint32_t *out_size)
{
    if (!s_littlefs_mounted || layer >= AUDIO_LAYER_COUNT || !out_data || !out_size) return false;

    char path[64];
    audio_path(layer, path, sizeof(path));

    FILE *f = fopen(path, "rb");
    if (!f) return false;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (fsize <= 0 || fsize > AUDIO_MAX_PCM_SIZE) {
        fclose(f);
        return false;
    }

    /* Allocate in PSRAM for large audio buffers */
    int8_t *buf = (int8_t *)heap_caps_malloc((size_t)fsize, MALLOC_CAP_SPIRAM);
    if (!buf) {
        ESP_LOGE(TAG, "Audio layer %d: PSRAM alloc failed (%ld bytes)", layer, fsize);
        fclose(f);
        return false;
    }

    size_t read_bytes = fread(buf, 1, (size_t)fsize, f);
    fclose(f);

    if (read_bytes != (size_t)fsize) {
        free(buf);
        return false;
    }

    *out_data = buf;
    *out_size = (uint32_t)fsize;
    ESP_LOGI(TAG, "Audio layer %d: loaded from LittleFS (%u samples)", layer, (unsigned)fsize);
    return true;
}

bool storage_audio_delete(uint8_t layer)
{
    if (!s_littlefs_mounted || layer >= AUDIO_LAYER_COUNT) return false;
    char path[64];
    audio_path(layer, path, sizeof(path));
    if (remove(path) == 0) {
        ESP_LOGI(TAG, "Audio layer %d: deleted", layer);
        return true;
    }
    return false;
}

void storage_audio_delete_all(void)
{
    for (uint8_t i = 0; i < AUDIO_LAYER_COUNT; i++) {
        storage_audio_delete(i);
    }
    ESP_LOGI(TAG, "All custom audio deleted");
}

uint8_t storage_audio_count(void)
{
    uint8_t count = 0;
    for (uint8_t i = 0; i < AUDIO_LAYER_COUNT; i++) {
        if (storage_audio_exists(i)) count++;
    }
    return count;
}
