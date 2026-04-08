#pragma once
#include "drv_encoder.h"

typedef enum {
    BTN_ACTION_NONE = 0,
    BTN_ACTION_CLICK,
    BTN_ACTION_DOUBLE_CLICK,
    BTN_ACTION_TRIPLE_CLICK,
    BTN_ACTION_LONG_PRESS,
} btn_action_t;

void encoder_handler_init(void);
void encoder_handler_process(void);
