#include "storage.h"
#include <string.h>

void storage_init(void) {}
void storage_load_settings(nvs_settings_t *out) { (void)out; }
void storage_save_settings(const nvs_settings_t *settings) { (void)settings; }
bool storage_logo_exists(uint8_t slot) { (void)slot; return false; }
bool storage_logo_read(uint8_t slot, uint8_t *buf, uint32_t buf_size, uint32_t *out_size) { (void)slot; (void)buf; (void)buf_size; (void)out_size; return false; }
bool storage_logo_write(uint8_t slot, const uint8_t *data, uint32_t size, uint32_t crc32) { (void)slot; (void)data; (void)size; (void)crc32; return false; }
bool storage_logo_delete(uint8_t slot) { (void)slot; return false; }
uint8_t storage_logo_count_valid(void) { return 0; }
uint8_t storage_logo_find_empty(void) { return 0; }
bool storage_mp3_read(const char *filename, uint8_t **out_data, uint32_t *out_size) { (void)filename; (void)out_data; (void)out_size; return false; }
