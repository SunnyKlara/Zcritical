/**
 * @file drv_audio.c
 * @brief I2S output driver for MAX98357 DAC
 *
 * 44100 Hz, 16-bit stereo, Philips I2S standard.
 * DIN=IO13, BCLK=IO12, LRC=IO11
 */

#include "drv_audio.h"
#include "pin_config.h"
#include "esp_log.h"
#include "driver/i2s_std.h"
#include "freertos/FreeRTOS.h"

static const char *TAG = "DRV_AUDIO";

static i2s_chan_handle_t s_tx_handle = NULL;
static uint8_t s_volume = 100;  /* 0–100 */

void drv_audio_init(void)
{
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
    /* DMA buffers for smooth audio playback.
     * 6 descriptors × 512 frames × 4 bytes = 12KB total DMA buffer.
     * At 44100Hz stereo this is ~70ms of audio. */
    chan_cfg.dma_desc_num  = 6;
    chan_cfg.dma_frame_num = 512;

    ESP_ERROR_CHECK(i2s_new_channel(&chan_cfg, &s_tx_handle, NULL));

    i2s_std_config_t std_cfg = {
        .clk_cfg  = I2S_STD_CLK_DEFAULT_CONFIG(44100),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT,
                                                         I2S_SLOT_MODE_STEREO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = (gpio_num_t)PIN_I2S_BCLK,
            .ws   = (gpio_num_t)PIN_I2S_LRC,
            .dout = (gpio_num_t)PIN_I2S_DIN,
            .din  = I2S_GPIO_UNUSED,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };

    ESP_ERROR_CHECK(i2s_channel_init_std_mode(s_tx_handle, &std_cfg));
    ESP_ERROR_CHECK(i2s_channel_enable(s_tx_handle));

    ESP_LOGI(TAG, "I2S initialized: 44100Hz 16-bit stereo");
}

void drv_audio_write(const int16_t *samples, uint32_t sample_count)
{
    if (!s_tx_handle || sample_count == 0) return;

    size_t bytes_written = 0;
    /* Each stereo sample = 4 bytes (2 × int16_t) */
    i2s_channel_write(s_tx_handle, samples, sample_count * sizeof(int16_t) * 2,
                      &bytes_written, portMAX_DELAY);
}

void drv_audio_set_volume(uint8_t volume)
{
    if (volume > 100) volume = 100;
    s_volume = volume;
}

uint8_t drv_audio_get_volume(void)
{
    return s_volume;
}

void drv_audio_stop(void)
{
    if (s_tx_handle) {
        i2s_channel_disable(s_tx_handle);
    }
}

void drv_audio_restart(void)
{
    if (s_tx_handle) {
        /* Ignore error if already enabled */
        i2s_channel_enable(s_tx_handle);
    }
}
