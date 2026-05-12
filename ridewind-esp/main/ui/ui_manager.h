#pragma once
#include <stdint.h>

void ui_manager_init(void);
void ui_manager_update(void);
void ui_manager_set_ui(uint8_t target_ui);
uint8_t ui_manager_get_ui(void);
