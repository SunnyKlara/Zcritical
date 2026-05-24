/**
 * @file protocol.h
 * @brief BLE 文本协议命令类型定义 + 解析器接口
 */

#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef enum {
    CMD_NONE = 0,
    CMD_FAN,
    CMD_SPEED,
    CMD_WUHUA,
    CMD_LED,
    CMD_PRESET,
    CMD_BRIGHT,
    CMD_UI,
    CMD_LCD,
    CMD_UNIT,
    CMD_THROTTLE,
    CMD_STREAMLIGHT,
    CMD_LED_GRADIENT,
    CMD_GET_FAN,
    CMD_GET_WUHUA,
    CMD_GET_BRIGHT,
    CMD_GET_STREAMLIGHT,
    CMD_GET_PRESET,
    CMD_GET_ALL,
    CMD_GET_UI,
    CMD_GET_LOGO,
    CMD_LOGO_START,
    CMD_LOGO_DATA,
    CMD_LOGO_END,
    CMD_LOGO_DELETE,
    CMD_OTA_START,
    CMD_OTA_DATA,
    CMD_OTA_END,
    CMD_VOLUME,
    CMD_GET_VOLUME,
    CMD_THROTTLE_FX,    /* THROTTLE_FX:mode (1-6) */
    CMD_WIFI,           /* WIFI:ssid:password */
    CMD_WIFI_SCAN,      /* WIFI_SCAN */
    CMD_AUDIO_START,    /* AUDIO_START:layer:size:crc32 */
    CMD_AUDIO_DATA,     /* AUDIO_DATA:seq:hex */
    CMD_AUDIO_END,      /* AUDIO_END */
    CMD_AUDIO_DELETE,   /* AUDIO_DELETE or AUDIO_DELETE:layer */
    CMD_GET_AUDIO,      /* GET:AUDIO — query custom audio status */
    CMD_OTA_VERSION,    /* OTA_VERSION — query firmware version */
    CMD_SPEED_MAX,      /* SPEED_MAX:xxx — set max speed display value */
    CMD_FAN_RANGE,      /* FAN_RANGE:min,max — set fan PWM range */
    CMD_GET_VERSION,    /* GET:VERSION — query firmware/protocol version */
} cmd_type_t;

typedef struct {
    cmd_type_t type;
    union {
        uint8_t  u8_val;
        int16_t  i16_val;
        struct { uint8_t strip; uint8_t r, g, b; } led;
        struct { uint8_t strip; uint8_t r, g, b; uint8_t speed; } led_gradient;
        struct { uint8_t slot; uint32_t size; uint32_t crc32; } logo_start;
        struct { uint8_t layer; uint32_t size; uint32_t crc32; } audio_start;
        struct { uint8_t *data; uint16_t len; } binary_data;
        uint32_t ota_size;
        struct { char ssid[33]; char password[65]; } wifi;
    } param;
} cmd_msg_t;

bool protocol_parse(const char *raw, uint16_t len, cmd_msg_t *out);
int protocol_format_response(char *buf, uint32_t buf_size, const char *cmd, const char *param);
int protocol_format_report(char *buf, uint32_t buf_size, const char *report_type, const char *data);
int protocol_format_cmd(const cmd_msg_t *cmd, char *buf, uint32_t buf_size);
