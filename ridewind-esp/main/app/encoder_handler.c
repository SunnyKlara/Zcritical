/**
 * @file encoder_handler.c
 * @brief EC11 编码器事件处理 — 按键状态机 + BLE 上报
 *
 * 处理原始编码器事件并上报 BLE。具体 UI 响应由各 ui_xxx_update() 处理。
 */

#include "encoder_handler.h"
#include "app_state.h"
#include "ble_service.h"
#include <stdio.h>

void encoder_handler_init(void)
{
    /* Nothing to init — encoder driver handles hardware */
}

void encoder_handler_process(void)
{
    /* Encoder events are now polled directly by each UI screen.
     * This function can be used for global encoder reporting if needed. */
}
