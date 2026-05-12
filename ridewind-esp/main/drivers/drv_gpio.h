#pragma once

#include <stdbool.h>

void drv_gpio_init(void);
void drv_gpio_set_humidifier(bool enable);
bool drv_gpio_get_humidifier(void);
