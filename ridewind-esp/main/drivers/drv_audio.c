#include "drv_audio.h"

void drv_audio_init(void) {}
void drv_audio_write(const int16_t *samples, uint32_t sample_count) { (void)samples; (void)sample_count; }
void drv_audio_set_volume(uint8_t volume) { (void)volume; }
void drv_audio_stop(void) {}
