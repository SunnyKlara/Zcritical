/**
 * @file protocol.c
 * @brief BLE text command parser and response formatter
 *
 * Protocol format: CMD:PARAM\n (incoming), OK:CMD\r\n (response), REPORT:data\n (event)
 */

#include "protocol.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ═══════════════════════════════════════════════════════════════
 *  Helper: safe integer parse with range check
 * ═══════════════════════════════════════════════════════════════ */
static bool parse_int(const char *s, int *out)
{
    if (!s || *s == '\0') return false;
    char *end;
    long v = strtol(s, &end, 10);
    if (end == s) return false;          /* no digits consumed */
    *out = (int)v;
    return true;
}

/* Advance past next ':' and return pointer to value, or NULL */
static const char *next_field(const char *p)
{
    const char *c = strchr(p, ':');
    return c ? c + 1 : NULL;
}

/* ═══════════════════════════════════════════════════════════════
 *  protocol_parse — parse raw text command into cmd_msg_t
 * ═══════════════════════════════════════════════════════════════ */
bool protocol_parse(const char *raw, uint16_t len, cmd_msg_t *out)
{
    if (!raw || len == 0 || !out) return false;

    memset(out, 0, sizeof(cmd_msg_t));
    out->type = CMD_NONE;

    /* Work with a null-terminated copy, strip trailing \r\n */
    char buf[256];
    uint16_t copy_len = (len < sizeof(buf) - 1) ? len : (sizeof(buf) - 1);
    memcpy(buf, raw, copy_len);
    buf[copy_len] = '\0';

    /* Strip trailing whitespace / newlines */
    int end = (int)copy_len - 1;
    while (end >= 0 && (buf[end] == '\n' || buf[end] == '\r' || buf[end] == ' ')) {
        buf[end--] = '\0';
    }
    if (buf[0] == '\0') return false;

    int val;
    const char *p;

    /* ── GET commands ── */
    if (strncmp(buf, "GET:", 4) == 0) {
        const char *param = buf + 4;
        if (strcmp(param, "FAN") == 0)         { out->type = CMD_GET_FAN; return true; }
        if (strcmp(param, "WUHUA") == 0)       { out->type = CMD_GET_WUHUA; return true; }
        if (strcmp(param, "BRIGHT") == 0)      { out->type = CMD_GET_BRIGHT; return true; }
        if (strcmp(param, "STREAMLIGHT") == 0) { out->type = CMD_GET_STREAMLIGHT; return true; }
        if (strcmp(param, "PRESET") == 0)      { out->type = CMD_GET_PRESET; return true; }
        if (strcmp(param, "ALL") == 0)         { out->type = CMD_GET_ALL; return true; }
        if (strcmp(param, "UI") == 0)          { out->type = CMD_GET_UI; return true; }
        if (strcmp(param, "LOGO") == 0)        { out->type = CMD_GET_LOGO; return true; }
        if (strcmp(param, "LOGO_SLOTS") == 0) { out->type = CMD_GET_LOGO; return true; }
        if (strcmp(param, "VOL") == 0)         { out->type = CMD_GET_VOLUME; return true; }
        if (strcmp(param, "AUDIO") == 0)       { out->type = CMD_GET_AUDIO; return true; }
        return false;  /* unknown GET */
    }

    /* ── LOGO commands ── */
    if (strncmp(buf, "LOGO_START_BIN:", 15) == 0) {
        /* Binary mode: LOGO_START_BIN:size:crc32 or LOGO_START_BIN:slot:size:crc32
         * Same parsing as LOGO_START but sets binary_mode flag */
        p = buf + 15;
        char *end;
        unsigned long nums[3] = {0};
        int num_count = 0;

        for (int i = 0; i < 3 && p && *p; i++) {
            nums[i] = strtoul(p, &end, 10);
            if (end == p) break;
            num_count++;
            p = (*end == ':') ? end + 1 : NULL;
        }

        out->type = CMD_LOGO_START;
        /* Use bit 7 of slot to signal binary mode to dispatch handler */
        if (num_count == 3) {
            out->param.logo_start.slot = (uint8_t)(nums[0] | 0x80);
            out->param.logo_start.size = (uint32_t)nums[1];
            out->param.logo_start.crc32 = (uint32_t)nums[2];
        } else if (num_count == 2) {
            out->param.logo_start.slot = 0xFF;  /* 0xFF already has bit 7 set = auto + binary */
            out->param.logo_start.size = (uint32_t)nums[0];
            out->param.logo_start.crc32 = (uint32_t)nums[1];
        } else {
            return false;
        }
        if (out->param.logo_start.size == 0) return false;
        return true;
    }
    if (strncmp(buf, "LOGO_START:", 11) == 0) {
        /* Support both formats:
         *   LOGO_START:size:crc32          (2 params, auto-slot)
         *   LOGO_START:slot:size:crc32     (3 params, explicit slot)
         * CRC32 can exceed INT_MAX, so parse with strtoul */
        p = buf + 11;
        char *end;
        unsigned long nums[3] = {0};
        int num_count = 0;

        for (int i = 0; i < 3 && p && *p; i++) {
            nums[i] = strtoul(p, &end, 10);
            if (end == p) break;  /* no digits */
            num_count++;
            p = (*end == ':') ? end + 1 : NULL;
        }

        out->type = CMD_LOGO_START;
        if (num_count == 3) {
            /* LOGO_START:slot:size:crc32 */
            out->param.logo_start.slot = (uint8_t)nums[0];
            out->param.logo_start.size = (uint32_t)nums[1];
            out->param.logo_start.crc32 = (uint32_t)nums[2];
        } else if (num_count == 2) {
            /* LOGO_START:size:crc32 */
            out->param.logo_start.slot = 0xFF;  /* 0xFF = auto-assign */
            out->param.logo_start.size = (uint32_t)nums[0];
            out->param.logo_start.crc32 = (uint32_t)nums[1];
        } else {
            return false;
        }
        if (out->param.logo_start.size == 0) return false;
        return true;
    }
    if (strncmp(buf, "LOGO_DATA:", 10) == 0) {
        /* LOGO_DATA:seq:hex — store pointer to hex data (caller owns buffer) */
        out->type = CMD_LOGO_DATA;
        /* For queue-based dispatch, we'll handle hex data in the BLE layer */
        return true;
    }
    if (strcmp(buf, "LOGO_END") == 0) {
        out->type = CMD_LOGO_END;
        return true;
    }
    if (strncmp(buf, "LOGO_DELETE:", 12) == 0) {
        if (!parse_int(buf + 12, &val)) return false;
        if (val < 0 || val > 2) return false;
        out->type = CMD_LOGO_DELETE;
        out->param.u8_val = (uint8_t)val;
        return true;
    }

    /* ── OTA commands ── */
    if (strncmp(buf, "OTA_START:", 10) == 0) {
        int size;
        if (!parse_int(buf + 10, &size)) return false;
        if (size <= 0) return false;
        out->type = CMD_OTA_START;
        out->param.ota_size = (uint32_t)size;
        return true;
    }
    if (strncmp(buf, "OTA_DATA:", 9) == 0) {
        out->type = CMD_OTA_DATA;
        return true;
    }
    if (strcmp(buf, "OTA_END") == 0) {
        out->type = CMD_OTA_END;
        return true;
    }

    /* ── LED_GRADIENT:s:r:g:b:speed ── */
    if (strncmp(buf, "LED_GRADIENT:", 13) == 0) {
        p = buf + 13;
        int strip, r, g, b, speed = 1;
        if (!parse_int(p, &strip)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &r)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &g)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &b)) return false;
        /* speed is optional */
        const char *sp = next_field(p);
        if (sp) parse_int(sp, &speed);

        if (strip < 1 || strip > 4) return false;
        if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return false;
        if (speed < 0 || speed > 2) speed = 1;

        out->type = CMD_LED_GRADIENT;
        out->param.led_gradient.strip = (uint8_t)strip;
        out->param.led_gradient.r = (uint8_t)r;
        out->param.led_gradient.g = (uint8_t)g;
        out->param.led_gradient.b = (uint8_t)b;
        out->param.led_gradient.speed = (uint8_t)speed;
        return true;
    }

    /* ── LED:s:r:g:b ── */
    if (strncmp(buf, "LED:", 4) == 0) {
        p = buf + 4;
        int strip, r, g, b;
        if (!parse_int(p, &strip)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &r)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &g)) return false;
        p = next_field(p); if (!p) return false;
        if (!parse_int(p, &b)) return false;

        if (strip < 1 || strip > 4) return false;
        if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) return false;

        out->type = CMD_LED;
        out->param.led.strip = (uint8_t)strip;
        out->param.led.r = (uint8_t)r;
        out->param.led.g = (uint8_t)g;
        out->param.led.b = (uint8_t)b;
        return true;
    }

    /* ── STREAMLIGHT:x ── */
    if (strncmp(buf, "STREAMLIGHT:", 12) == 0) {
        if (!parse_int(buf + 12, &val)) return false;
        out->type = CMD_STREAMLIGHT;
        out->param.u8_val = (val != 0) ? 1 : 0;
        return true;
    }

    /* ── SPEED:xxx ── */
    if (strncmp(buf, "SPEED:", 6) == 0) {
        if (!parse_int(buf + 6, &val)) return false;
        if (val < 0) val = 0;
        if (val > 340) val = 340;
        out->type = CMD_SPEED;
        out->param.i16_val = (int16_t)val;
        return true;
    }

    /* ── Simple CMD:val commands ── */
    struct { const char *prefix; uint8_t plen; cmd_type_t type; int min; int max; } simple[] = {
        { "FAN:",       4,  CMD_FAN,        0, 100 },
        { "WUHUA:",     6,  CMD_WUHUA,      0, 1   },
        { "PRESET:",    7,  CMD_PRESET,     1, 14  },
        { "BRIGHT:",    7,  CMD_BRIGHT,     0, 100 },
        { "UI:",        3,  CMD_UI,         0, 7   },
        { "LCD:",       4,  CMD_LCD,        0, 1   },
        { "UNIT:",      5,  CMD_UNIT,       0, 1   },
        { "THROTTLE:",  9,  CMD_THROTTLE,   0, 1   },
        { "VOL:",       4,  CMD_VOLUME,     0, 100 },
    };

    for (int i = 0; i < (int)(sizeof(simple) / sizeof(simple[0])); i++) {
        if (strncmp(buf, simple[i].prefix, simple[i].plen) == 0) {
            if (!parse_int(buf + simple[i].plen, &val)) return false;
            if (val < simple[i].min || val > simple[i].max) return false;
            out->type = simple[i].type;
            out->param.u8_val = (uint8_t)val;
            return true;
        }
    }

    /* ── WIFI_SCAN ── */
    if (strcmp(buf, "WIFI_SCAN") == 0) {
        out->type = CMD_WIFI_SCAN;
        return true;
    }

    /* ── AUDIO upload commands ── */
    if (strncmp(buf, "AUDIO_START_BIN:", 16) == 0) {
        /* AUDIO_START_BIN:layer:size:crc32 — binary mode */
        p = buf + 16;
        char *end;
        unsigned long nums[3] = {0};
        int num_count = 0;
        for (int i = 0; i < 3 && p && *p; i++) {
            nums[i] = strtoul(p, &end, 10);
            if (end == p) break;
            num_count++;
            p = (*end == ':') ? end + 1 : NULL;
        }
        out->type = CMD_AUDIO_START;
        if (num_count == 3) {
            out->param.audio_start.layer = (uint8_t)(nums[0] | 0x80); /* bit7 = binary */
            out->param.audio_start.size = (uint32_t)nums[1];
            out->param.audio_start.crc32 = (uint32_t)nums[2];
        } else {
            return false;
        }
        if (out->param.audio_start.size == 0) return false;
        return true;
    }
    if (strncmp(buf, "AUDIO_START:", 12) == 0) {
        /* AUDIO_START:layer:size:crc32 */
        p = buf + 12;
        char *end;
        unsigned long nums[3] = {0};
        int num_count = 0;
        for (int i = 0; i < 3 && p && *p; i++) {
            nums[i] = strtoul(p, &end, 10);
            if (end == p) break;
            num_count++;
            p = (*end == ':') ? end + 1 : NULL;
        }
        if (num_count != 3) return false;
        out->type = CMD_AUDIO_START;
        out->param.audio_start.layer = (uint8_t)nums[0];
        out->param.audio_start.size = (uint32_t)nums[1];
        out->param.audio_start.crc32 = (uint32_t)nums[2];
        if (out->param.audio_start.size == 0) return false;
        return true;
    }
    if (strncmp(buf, "AUDIO_DATA:", 11) == 0) {
        out->type = CMD_AUDIO_DATA;
        return true;
    }
    if (strcmp(buf, "AUDIO_END") == 0) {
        out->type = CMD_AUDIO_END;
        return true;
    }
    if (strncmp(buf, "AUDIO_DELETE:", 12) == 0) {
        if (!parse_int(buf + 12, &val)) {
            /* AUDIO_DELETE without layer = delete all */
            out->type = CMD_AUDIO_DELETE;
            out->param.u8_val = 0xFF;
            return true;
        }
        if (val < 0 || val > 3) return false;
        out->type = CMD_AUDIO_DELETE;
        out->param.u8_val = (uint8_t)val;
        return true;
    }
    if (strcmp(buf, "AUDIO_DELETE") == 0) {
        out->type = CMD_AUDIO_DELETE;
        out->param.u8_val = 0xFF;  /* delete all */
        return true;
    }

    /* ── WIFI:ssid:password ── */
    if (strncmp(buf, "WIFI:", 5) == 0) {
        const char *ssid_start = buf + 5;
        const char *colon = strchr(ssid_start, ':');
        if (!colon || colon == ssid_start) return false;
        size_t ssid_len = colon - ssid_start;
        const char *pass_start = colon + 1;
        size_t pass_len = strlen(pass_start);
        if (ssid_len >= sizeof(out->param.wifi.ssid)) return false;
        if (pass_len >= sizeof(out->param.wifi.password)) return false;
        out->type = CMD_WIFI;
        memset(out->param.wifi.ssid, 0, sizeof(out->param.wifi.ssid));
        memset(out->param.wifi.password, 0, sizeof(out->param.wifi.password));
        memcpy(out->param.wifi.ssid, ssid_start, ssid_len);
        memcpy(out->param.wifi.password, pass_start, pass_len);
        return true;
    }

    return false;  /* unrecognized command */
}


/* ═══════════════════════════════════════════════════════════════
 *  protocol_format_response — format acknowledgment (ends with \r\n)
 * ═══════════════════════════════════════════════════════════════ */
int protocol_format_response(char *buf, uint32_t buf_size, const char *cmd, const char *param)
{
    if (!buf || buf_size < 8) return 0;
    int n;
    if (param && param[0] != '\0') {
        n = snprintf(buf, buf_size, "OK:%s:%s\r\n", cmd, param);
    } else {
        n = snprintf(buf, buf_size, "OK:%s\r\n", cmd);
    }
    return (n > 0 && (uint32_t)n < buf_size) ? n : 0;
}

/* ═══════════════════════════════════════════════════════════════
 *  protocol_format_report — format event report (ends with \n)
 * ═══════════════════════════════════════════════════════════════ */
int protocol_format_report(char *buf, uint32_t buf_size, const char *report_type, const char *data)
{
    if (!buf || buf_size < 8) return 0;
    int n;
    if (data && data[0] != '\0') {
        n = snprintf(buf, buf_size, "%s:%s\n", report_type, data);
    } else {
        n = snprintf(buf, buf_size, "%s\n", report_type);
    }
    return (n > 0 && (uint32_t)n < buf_size) ? n : 0;
}

/* ═══════════════════════════════════════════════════════════════
 *  protocol_format_cmd — format cmd_msg_t back to text (round-trip)
 * ═══════════════════════════════════════════════════════════════ */
int protocol_format_cmd(const cmd_msg_t *cmd, char *buf, uint32_t buf_size)
{
    if (!cmd || !buf || buf_size < 16) return 0;
    int n = 0;

    switch (cmd->type) {
    case CMD_FAN:
        n = snprintf(buf, buf_size, "FAN:%d\n", cmd->param.u8_val);
        break;
    case CMD_SPEED:
        n = snprintf(buf, buf_size, "SPEED:%d\n", cmd->param.i16_val);
        break;
    case CMD_WUHUA:
        n = snprintf(buf, buf_size, "WUHUA:%d\n", cmd->param.u8_val);
        break;
    case CMD_LED:
        n = snprintf(buf, buf_size, "LED:%d:%d:%d:%d\n",
                     cmd->param.led.strip, cmd->param.led.r,
                     cmd->param.led.g, cmd->param.led.b);
        break;
    case CMD_PRESET:
        n = snprintf(buf, buf_size, "PRESET:%d\n", cmd->param.u8_val);
        break;
    case CMD_BRIGHT:
        n = snprintf(buf, buf_size, "BRIGHT:%d\n", cmd->param.u8_val);
        break;
    case CMD_UI:
        n = snprintf(buf, buf_size, "UI:%d\n", cmd->param.u8_val);
        break;
    case CMD_LCD:
        n = snprintf(buf, buf_size, "LCD:%d\n", cmd->param.u8_val);
        break;
    case CMD_UNIT:
        n = snprintf(buf, buf_size, "UNIT:%d\n", cmd->param.u8_val);
        break;
    case CMD_THROTTLE:
        n = snprintf(buf, buf_size, "THROTTLE:%d\n", cmd->param.u8_val);
        break;
    case CMD_STREAMLIGHT:
        n = snprintf(buf, buf_size, "STREAMLIGHT:%d\n", cmd->param.u8_val);
        break;
    case CMD_LED_GRADIENT:
        n = snprintf(buf, buf_size, "LED_GRADIENT:%d:%d:%d:%d:%d\n",
                     cmd->param.led_gradient.strip,
                     cmd->param.led_gradient.r,
                     cmd->param.led_gradient.g,
                     cmd->param.led_gradient.b,
                     cmd->param.led_gradient.speed);
        break;
    case CMD_VOLUME:
        n = snprintf(buf, buf_size, "VOL:%d\n", cmd->param.u8_val);
        break;
    case CMD_GET_FAN:         n = snprintf(buf, buf_size, "GET:FAN\n"); break;
    case CMD_GET_WUHUA:       n = snprintf(buf, buf_size, "GET:WUHUA\n"); break;
    case CMD_GET_BRIGHT:      n = snprintf(buf, buf_size, "GET:BRIGHT\n"); break;
    case CMD_GET_STREAMLIGHT: n = snprintf(buf, buf_size, "GET:STREAMLIGHT\n"); break;
    case CMD_GET_PRESET:      n = snprintf(buf, buf_size, "GET:PRESET\n"); break;
    case CMD_GET_ALL:         n = snprintf(buf, buf_size, "GET:ALL\n"); break;
    case CMD_GET_UI:          n = snprintf(buf, buf_size, "GET:UI\n"); break;
    case CMD_GET_LOGO:        n = snprintf(buf, buf_size, "GET:LOGO\n"); break;
    case CMD_GET_VOLUME:      n = snprintf(buf, buf_size, "GET:VOL\n"); break;
    case CMD_GET_AUDIO:       n = snprintf(buf, buf_size, "GET:AUDIO\n"); break;
    case CMD_AUDIO_START:
        n = snprintf(buf, buf_size, "AUDIO_START:%d:%u:%u\n",
                     cmd->param.audio_start.layer,
                     (unsigned)cmd->param.audio_start.size,
                     (unsigned)cmd->param.audio_start.crc32);
        break;
    case CMD_AUDIO_DATA:      n = snprintf(buf, buf_size, "AUDIO_DATA:\n"); break;
    case CMD_AUDIO_END:       n = snprintf(buf, buf_size, "AUDIO_END\n"); break;
    case CMD_AUDIO_DELETE:
        n = snprintf(buf, buf_size, "AUDIO_DELETE:%d\n", cmd->param.u8_val);
        break;
    case CMD_LOGO_START:
        n = snprintf(buf, buf_size, "LOGO_START:%d:%u\n",
                     cmd->param.logo_start.slot, (unsigned)cmd->param.logo_start.size);
        break;
    case CMD_LOGO_DATA:       n = snprintf(buf, buf_size, "LOGO_DATA:\n"); break;
    case CMD_LOGO_END:        n = snprintf(buf, buf_size, "LOGO_END\n"); break;
    case CMD_LOGO_DELETE:
        n = snprintf(buf, buf_size, "LOGO_DELETE:%d\n", cmd->param.u8_val);
        break;
    case CMD_OTA_START:
        n = snprintf(buf, buf_size, "OTA_START:%u\n", (unsigned)cmd->param.ota_size);
        break;
    case CMD_OTA_DATA:        n = snprintf(buf, buf_size, "OTA_DATA:\n"); break;
    case CMD_OTA_END:         n = snprintf(buf, buf_size, "OTA_END\n"); break;
    default:
        return 0;
    }

    return (n > 0 && (uint32_t)n < buf_size) ? n : 0;
}
