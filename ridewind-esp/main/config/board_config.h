#pragma once

#include "driver/ledc.h"
#include "driver/spi_master.h"

/* ═══════════════════════════════════════════════════════════════
 *  Critical Hardware & Timing Constants
 * ═══════════════════════════════════════════════════════════════ */

/* LED strip physical counts */
#define LED_STRIP1_COUNT        10
#define LED_STRIP2_COUNT        3
#define LED_TOTAL_COUNT         (LED_STRIP1_COUNT + LED_STRIP2_COUNT)

/* Logical strip index ranges on physical strip 1 (IO41, 10 LEDs) */
#define LED_LEFT_START          0
#define LED_LEFT_COUNT          2
#define LED_MAIN_START          2
#define LED_MAIN_COUNT          6
#define LED_RIGHT_START         8
#define LED_RIGHT_COUNT         2

/* Logical strip on physical strip 2 (IO16, 3 LEDs) */
#define LED_TAIL_START          0
#define LED_TAIL_COUNT          3

/* LCD */
#define LCD_WIDTH               240
#define LCD_HEIGHT              240
#define LCD_SPI_HOST            SPI2_HOST
#define LCD_SPI_FREQ_HZ         (40 * 1000 * 1000)  /* 40 MHz */

/* Fan PWM */
#define FAN_PWM_FREQ_HZ         1000
#define FAN_LEDC_TIMER          LEDC_TIMER_0
#define FAN_LEDC_CHANNEL        LEDC_CHANNEL_0
#define FAN_LEDC_RESOLUTION     LEDC_TIMER_10_BIT   /* 0-1023 */

/* Task timing (milliseconds) */
#define MAIN_TASK_PERIOD_MS         20
#define LCD_REFRESH_PERIOD_MS       50
#define PWM_UPDATE_PERIOD_MS        100
#define ENCODER_POLL_PERIOD_MS      20

/* Button detection */
#define BUTTON_TIMEOUT_MS           400
#define LONG_PRESS_MS               800

/* LED effects */
#define LED_GRADIENT_PERIOD_MS      20
#define STREAMLIGHT_PERIOD_MS       30
#define BREATHING_PERIOD_MS         20

/* Gradient speed modes (steps at 50fps) */
#define GRADIENT_SPEED_FAST         25      /* 0.5s */
#define GRADIENT_SPEED_NORMAL       75      /* 1.5s */
#define GRADIENT_SPEED_SLOW         150     /* 3.0s */

/* Streamlight */
#define STREAMLIGHT_INTERP_STEPS    100

/* Breathing effect */
#define BREATHING_PERIOD_SEC        3.0f
#define BREATHING_MIN_SCALE         0.6f
#define BREATHING_MAX_SCALE         1.0f

/* BLE */
#define BLE_RX_TIMEOUT_MS           50
#define BLE_DEVICE_NAME             "T1"

/* Throttle mode */
#define THROTTLE_ACCEL_MS           18
#define THROTTLE_DECEL_MS           12
#define REMOTE_FREEZE_WINDOW_MS     500

/* Menu */
#define MENU_SWITCH_DEBOUNCE_MS     150
#define MENU_DELTA_THRESHOLD        1
#define MENU_PAGE_COUNT             7

/* Menu layout (matching F4 parameters) */
#define MENU_ICON_CENTER_Y          90
#define MENU_TEXT_Y                 155
#define MENU_DOT_Y                  205
#define MENU_DOT_SPACING            15
#define MENU_DOT_RADIUS             3
#define MENU_DOT_ACTIVE_COLOR       0xFFFF   /* White */
#define MENU_DOT_INACTIVE_COLOR     0x4208   /* Dark gray */

/* Menu animation */
#define MENU_ANIM_FRAMES            8
#define MENU_ANIM_FRAME_DELAY       12       /* ms */
#define MENU_ANIM_ZONE_TOP          50
#define MENU_ANIM_ZONE_BOTTOM       190

/* Boot */
#define BOOT_LOGO_DURATION_MS       2000

/* Message queue */
#define CMD_QUEUE_DEPTH             32

/* Speed */
#define SPEED_MAX_KMH               340
#define SPEED_MAX_MPH               211
#define FAN_SPEED_MAX               100

/* Preset count */
#define COLOR_PRESET_COUNT          14

/* Logo storage */
#define MAX_LOGO_SLOTS              3
#define LOGO_WIDTH                  240
#define LOGO_HEIGHT                 240
#define LOGO_PIXEL_BYTES            (LOGO_WIDTH * LOGO_HEIGHT * 2)  /* RGB565 */
#define LOGO_MAGIC                  0xAA55
#define LITTLEFS_MOUNT_POINT        "/storage"
#define LITTLEFS_PARTITION_LABEL    "storage"
