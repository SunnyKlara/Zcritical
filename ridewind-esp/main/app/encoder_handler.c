#include "encoder_handler.h"
#include "app_state.h"
#include "ble_service.h"
#include <stdio.h>

/* Encoder handler: processes raw encoder events and reports to BLE.
 * The actual UI-specific handling is done in each ui_xxx_update(). */

void encoder_handler_init(void)
{
    /* Nothing to init — encoder driver handles hardware */
}

void encoder_handler_process(void)
{
    /* Encoder events are now polled directly by each UI screen.
     * This function can be used for global encoder reporting if needed. */
}
