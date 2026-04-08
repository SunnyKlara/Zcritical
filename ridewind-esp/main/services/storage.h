#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t led_colors[4][3];
    uint8_t brightness;
    uint8_t volume;
    uint8_t preset_index;
    uint8_t speed_unit;
    uint8_t streamlight;
    uint8_t breath_mode;
    uint8_t active_logo_slot;
} nvs_settings_t;

void storage_init(void);
void storage_load_settings(nvs_settings_t *out);
void storage_save_settings(const nvs_settings_t *settings);
bool storage_logo_exists(uint8_t slot);
bool storage_logo_read(uint8_t slot, uint8_t *buf, uint32_t buf_size, uint32_t *out_size);
bool storage_logo_write(uint8_t slot, const uint8_t *data, uint32_t size, uint32_t crc32);
bool storage_logo_delete(uint8_t slot);
uint8_t storage_logo_count_valid(void);
uint8_t storage_logo_find_empty(void);
bool storage_mp3_read(const char *filename, uint8_t **out_data, uint32_t *out_size);
