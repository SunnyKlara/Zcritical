/**
 * @file board_config.h
 * @brief 板级硬件常量 — LED 数量/逻辑分区/时序参数/队列深度
 */

#pragma once

#include "driver/ledc.h"
#include "driver/spi_master.h"

/* ═══════════════════════════════════════════════════════════════
 *  Critical Hardware & Timing Constants
 * ═══════════════════════════════════════════════════════════════ */

/* ── Version & Compatibility ── */
#define PROTOCOL_VERSION        1       /* Increment on breaking protocol changes */
#define HW_MODEL                "T1"    /* Hardware model identifier */
#define MIN_APP_VERSION         "1.2.0" /* Minimum compatible APP version */

/* ── Capability Bitmap (each bit = one feature the firmware supports) ── */
#define CAP_SPEED_CONTROL       (1 << 0)   /* Speed/fan control */
#define CAP_LED_PRESET          (1 << 1)   /* LED preset colors */
#define CAP_LED_RGB             (1 << 2)   /* LED individual RGB control */
#define CAP_ATOMIZER            (1 << 3)   /* Atomizer on/off */
#define CAP_FAN_CONTROL         (1 << 4)   /* Fan PWM control */
#define CAP_OTA                 (1 << 5)   /* OTA firmware upgrade */
#define CAP_WIFI_PROVISION      (1 << 6)   /* WiFi provisioning */
#define CAP_LOGO_UPLOAD         (1 << 7)   /* Logo upload to LCD */
#define CAP_AUDIO_ENGINE        (1 << 8)   /* Engine sound playback */
#define CAP_SPEED_MAX_CONFIG    (1 << 9)   /* SPEED_MAX command */
#define CAP_FAN_RANGE_CONFIG    (1 << 10)  /* FAN_RANGE command */
#define CAP_VOLUME_CONTROL      (1 << 11)  /* VOL command */
#define CAP_THROTTLE_MODE       (1 << 12)  /* THROTTLE command */
#define CAP_THROTTLE_FX         (1 << 13)  /* THROTTLE_FX command */
#define CAP_STREAMLIGHT         (1 << 14)  /* STREAMLIGHT command */
#define CAP_AUDIO_UPLOAD        (1 << 15)  /* Custom audio upload */
#define CAP_WIFI_AUDIO          (1 << 16)  /* WiFi audio streaming */
#define CAP_LED_GRADIENT        (1 << 17)  /* LED gradient effect */

/* Current device capabilities — OR together all supported features */
#define DEVICE_CAPABILITIES ( \
    CAP_SPEED_CONTROL | CAP_LED_PRESET | CAP_LED_RGB | CAP_ATOMIZER | \
    CAP_FAN_CONTROL | CAP_OTA | CAP_WIFI_PROVISION | CAP_LOGO_UPLOAD | \
    CAP_AUDIO_ENGINE | CAP_SPEED_MAX_CONFIG | CAP_FAN_RANGE_CONFIG | \
    CAP_VOLUME_CONTROL | CAP_THROTTLE_MODE | CAP_THROTTLE_FX | \
    CAP_STREAMLIGHT | CAP_AUDIO_UPLOAD | CAP_WIFI_AUDIO | CAP_LED_GRADIENT \
)

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
#define BUTTON_TIMEOUT_MS           250
#define LONG_PRESS_MS               600

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
#define BOOT_LOGO_DURATION_MS       3000

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
