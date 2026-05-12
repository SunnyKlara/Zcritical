#include "drv_gpio.h"
#include "pin_config.h"
#include "driver/gpio.h"
#include "esp_log.h"

static const char *TAG = "drv_gpio";
static bool s_humidifier;

void drv_gpio_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = (1ULL << PIN_HUMIDIFIER),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&cfg);
    gpio_set_level(PIN_HUMIDIFIER, 0);
    s_humidifier = false;
    ESP_LOGI(TAG, "Humidifier GPIO init: IO%d", PIN_HUMIDIFIER);
}

void drv_gpio_set_humidifier(bool enable)
{
    s_humidifier = enable;
    gpio_set_level(PIN_HUMIDIFIER, enable ? 1 : 0);
}

bool drv_gpio_get_humidifier(void) { return s_humidifier; }
