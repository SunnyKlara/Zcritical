#include "ui_rgb.h"
#include "ui_common.h"
#include "ui_images.h"
#include "storage.h"
#include "app_state.h"
#include "ui_manager.h"
#include "drv_lcd.h"
#include "drv_led.h"
#include "drv_encoder.h"
#include "led_effects.h"
#include "ble_service.h"
#include <stdio.h>

/* UI3 - 3-Layer RGB Custom
 *
 * F4 rendering model (matched exactly):
 *
 * Three independent update functions, called selectively per state change:
 *
 *   lcd_rgb_update(ch)     — Restore letter ch to NORMAL (white) state
 *   lcd_rgb_cai_update(ch) — Set letter ch to HIGHLIGHTED (colored) state
 *   lcd_rgb_num(ch, val)   — Clear letter+number zone, draw colored number
 *   lcd_name_update(name)  — Clear name zone, draw strip name
 *   lcd_deng(key, name)    — Draw LED indicator (green=0, red=1)
 *
 * State transitions:
 *   Mode 0 rotate: lcd_name_update + lcd_rgb_update(all 3) + lcd_deng(red)
 *   Mode 1 rotate: lcd_rgb_update(all 3) + lcd_rgb_cai_update(active) + lcd_deng(green)
 *   Mode 2 rotate: lcd_rgb_num(active channel, new value) — only touches one zone
 *   Click 0→1:     lcd_rgb_update(all) + lcd_rgb_cai_update(0) + lcd_deng(green)
 *   Click 1→2:     (no visual change, just mode flag)
 *   Click 2→1:     lcd_rgb_update(all) + lcd_rgb_cai_update(active) + redraw all numbers
 */

/* ── Digit lookup tables ── */
static const unsigned char * const s_r_data[10] = {
    gImage_h_0_2425, gImage_h_1_1125, gImage_h_2_2225, gImage_h_3_1925,
    gImage_h_4_2325, gImage_h_5_2125, gImage_h_6_2325, gImage_h_7_2125,
    gImage_h_8_2125, gImage_h_9_2225,
};
static const uint8_t s_r_w[10] = {
    F4_H_0_WIDTH, F4_H_1_WIDTH, F4_H_2_WIDTH, F4_H_3_WIDTH, F4_H_4_WIDTH,
    F4_H_5_WIDTH, F4_H_6_WIDTH, F4_H_7_WIDTH, F4_H_8_WIDTH, F4_H_9_WIDTH,
};
static const unsigned char * const s_g_data[10] = {
    gImage_l_0_2425, gImage_l_1_0925, gImage_l_2_2325, gImage_l_3_2125,
    gImage_l_4_2425, gImage_l_5_2225, gImage_l_6_2325, gImage_l_7_2125,
    gImage_l_8_2325, gImage_l_9_2325,
};
static const uint8_t s_g_w[10] = {
    F4_L_0_WIDTH, F4_L_1_WIDTH, F4_L_2_WIDTH, F4_L_3_WIDTH, F4_L_4_WIDTH,
    F4_L_5_WIDTH, F4_L_6_WIDTH, F4_L_7_WIDTH, F4_L_8_WIDTH, F4_L_9_WIDTH,
};
static const unsigned char * const s_b_data[10] = {
    gImage_b_0_2425, gImage_b_1_0925, gImage_b_2_2125, gImage_b_3_1925,
    gImage_b_4_2325, gImage_b_5_2125, gImage_b_6_2325, gImage_b_7_2125,
    gImage_b_8_2225, gImage_b_9_2325,
};
static const uint8_t s_b_w[10] = {
    F4_B_0_WIDTH, F4_B_1_WIDTH, F4_B_2_WIDTH, F4_B_3_WIDTH, F4_B_4_WIDTH,
    F4_B_5_WIDTH, F4_B_6_WIDTH, F4_B_7_WIDTH, F4_B_8_WIDTH, F4_B_9_WIDTH,
};

typedef struct { const unsigned char *img; uint16_t w, h; } name_info_t;
static const name_info_t s_names[4] = {
    { gImage_RGB_middle_105_27, F4_RGB_MIDDLE_WIDTH, F4_RGB_MIDDLE_HIGH },
    { gImage_RGB_left_5527,     F4_RGB_LEFT_WIDTH,   F4_RGB_LEFT_HIGH },
    { gImage_RGB_right_8033,    F4_RGB_RIGHT_WIDTH,  F4_RGB_RIGHT_HIGH },
    { gImage_RGB_back_7727,     F4_RGB_BACK_WIDTH,   F4_RGB_BACK_HIGH },
};

/* ══════ F4-matching rendering primitives ══════ */

/** Restore letter to normal (white) state — matches F4 lcd_rgb_update */
static void esp_rgb_update(uint8_t ch)
{
    if (ch == 0) {  /* R */
        drv_lcd_fill_rect(F4_RGB_B_R_X - 15, F4_RGB_B_R_Y,
                          F4_RGB_B_G_X - 1 - (F4_RGB_B_R_X - 15), F4_RGB_B_R_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_R_X, F4_RGB_B_R_Y,
                         F4_RGB_B_R_WIDTH, F4_RGB_B_R_HIGH, gImage_RGB_b_r_4853);
    } else if (ch == 1) {  /* G */
        drv_lcd_fill_rect(F4_RGB_B_R_X + F4_RGB_B_R_WIDTH, F4_RGB_B_G_Y,
                          F4_RGB_B_B_X - 1 - (F4_RGB_B_R_X + F4_RGB_B_R_WIDTH), F4_RGB_B_G_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_G_X, F4_RGB_B_G_Y,
                         F4_RGB_B_G_WIDTH, F4_RGB_B_G_HIGH, gImage_RGB_b_g_4853);
    } else {  /* B */
        drv_lcd_fill_rect(F4_RGB_B_G_X + F4_RGB_B_G_WIDTH, F4_RGB_B_B_Y,
                          F4_RGB_B_B_X + F4_RGB_B_B_WIDTH + 10 - (F4_RGB_B_G_X + F4_RGB_B_G_WIDTH),
                          F4_RGB_B_B_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_B_X, F4_RGB_B_B_Y,
                         F4_RGB_B_B_WIDTH, F4_RGB_B_B_HIGH, gImage_RGB_b_b_4753);
    }
}

/** Set letter to highlighted (colored) state — matches F4 lcd_rgb_cai_update */
static void esp_rgb_cai_update(uint8_t ch)
{
    if (ch == 0) {
        drv_lcd_fill_rect(F4_RGB_B_R_X - 15, F4_RGB_B_R_Y,
                          F4_RGB_B_G_X - 1 - (F4_RGB_B_R_X - 15), F4_RGB_B_R_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_R_X, F4_RGB_B_R_Y,
                         F4_RGB_H_R_WIDTH, F4_RGB_H_R_HIGH, gImage_RGB_h_r_4853);
    } else if (ch == 1) {
        drv_lcd_fill_rect(F4_RGB_B_R_X + F4_RGB_B_R_WIDTH, F4_RGB_B_G_Y,
                          F4_RGB_B_B_X - 1 - (F4_RGB_B_R_X + F4_RGB_B_R_WIDTH), F4_RGB_B_G_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_G_X, F4_RGB_B_G_Y,
                         F4_RGB_L_G_WIDTH, F4_RGB_L_G_HIGH, gImage_RGB_l_g_4853);
    } else {
        drv_lcd_fill_rect(F4_RGB_B_G_X + F4_RGB_B_G_WIDTH, F4_RGB_B_B_Y,
                          F4_RGB_B_B_X + F4_RGB_LAN_B_WIDTH + 10 - (F4_RGB_B_G_X + F4_RGB_B_G_WIDTH),
                          F4_RGB_B_B_HIGH, 0x0000);
        ui_blit_f4_image(F4_RGB_B_B_X, F4_RGB_B_B_Y,
                         F4_RGB_LAN_B_WIDTH, F4_RGB_LAN_B_HIGH, gImage_RGB_lan_b_4653);
    }
}

/** Draw colored number — matches F4 lcd_rgb_num. Clears the FULL letter+number zone first. */
static void esp_rgb_num(uint8_t ch, uint8_t val)
{
    const unsigned char * const *dd;
    const uint8_t *dw;
    uint16_t cx, cy;  /* center x, top y for number */
    uint16_t clr_x, clr_y, clr_w, clr_h;  /* clear region (matches F4 LCD_Fill) */

    if (ch == 0) {
        dd = s_r_data; dw = s_r_w;
        cx = F4_NUM_R_X; cy = F4_NUM_R_Y;
        clr_x = F4_RGB_B_R_X - 10; clr_y = F4_RGB_B_R_Y;
        clr_w = F4_RGB_B_G_X - 1 - clr_x; clr_h = F4_RGB_B_R_HIGH;
    } else if (ch == 1) {
        dd = s_g_data; dw = s_g_w;
        cx = F4_NUM_G_X; cy = F4_NUM_G_Y;
        clr_x = F4_RGB_B_G_X - 10; clr_y = F4_RGB_B_G_Y;
        clr_w = F4_RGB_B_B_X - 1 - clr_x; clr_h = F4_RGB_B_G_HIGH;
    } else {
        dd = s_b_data; dw = s_b_w;
        cx = F4_NUM_B_X; cy = F4_NUM_B_Y;
        clr_x = F4_RGB_B_B_X - 10; clr_y = F4_RGB_B_B_Y;
        clr_w = F4_RGB_B_B_WIDTH + 20; clr_h = F4_RGB_B_B_HIGH;
    }

    /* Clear entire letter+number zone (same as F4) */
    drv_lcd_fill_rect(clr_x, clr_y, clr_w, clr_h, 0x0000);

    /* Draw number digits centered at (cx, cy) */
    uint8_t d_a = 0, d_b = 0, d_c = 0, cnt;
    if (val >= 100) { d_a = val/100; d_b = (val%100)/10; d_c = val%10; cnt = 3; }
    else if (val >= 10) { d_b = val/10; d_c = val%10; cnt = 2; }
    else { d_c = val; cnt = 1; }

    uint8_t wa = dw[d_a], wb = dw[d_b], wc = dw[d_c];

    if (cnt == 3) {
        ui_blit_f4_image(cx - wb/2 - wa, cy, wa, F4_RGB_HIGH, dd[d_a]);
        ui_blit_f4_image(cx - wb/2,      cy, wb, F4_RGB_HIGH, dd[d_b]);
        ui_blit_f4_image(cx + wb/2,      cy, wc, F4_RGB_HIGH, dd[d_c]);
    } else if (cnt == 2) {
        ui_blit_f4_image(cx - wb, cy, wb, F4_RGB_HIGH, dd[d_b]);
        ui_blit_f4_image(cx,     cy, wc, F4_RGB_HIGH, dd[d_c]);
    } else {
        ui_blit_f4_image(cx - wc/2, cy, wc, F4_RGB_HIGH, dd[d_c]);
    }
}

/** Draw strip name + LED — matches F4 lcd_name_update + lcd_deng */
static void esp_name_update(uint8_t name_idx)
{
    drv_lcd_fill_rect(F4_RGB_LEFT_X, F4_RGB_LEFT_Y,
                      F4_RGB_MIDDLE_WIDTH + F4_H_DENG_WIDTH,
                      F4_RGB_RIGHT_HIGH, 0x0000);
    const name_info_t *n = &s_names[name_idx];
    ui_blit_f4_image(F4_RGB_LEFT_X, F4_RGB_LEFT_Y, n->w, n->h, n->img);
}

static void esp_deng(uint8_t key_num, uint8_t name_idx)
{
    /* key_num: 0=green, nonzero=red (matches F4 lcd_deng) */
    const name_info_t *n = &s_names[name_idx];
    uint8_t state = (key_num == 0) ? 1 : 0;  /* 0=red, 1=green in our ui_draw_f4_led */
    ui_draw_f4_led(F4_RGB_LEFT_X + n->w, F4_RGB_LEFT_Y + 5, state);
}

/* ══════ State machine ══════ */

static uint8_t s_inited = 0;

void ui_rgb_enter(void)
{
    s_inited = 0;
    g_app_state.ui3_mode = 0;
    g_app_state.ui3_channel = 0;
    g_app_state.ui3_strip = 0;

    if (g_app_state.streamlight_active) {
        g_app_state.streamlight_active = 0;
        led_effects_streamlight_stop();
    }
    if (g_app_state.breath_mode) {
        g_app_state.breath_mode = 0;
        led_effects_breathing_stop();
    }

    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 3; j++)
            g_app_state.led_edit[i][j] = g_app_state.led_colors[i][j];
}

void ui_rgb_update(void)
{
    uint8_t strip = g_app_state.ui3_strip;

    /* First frame: full init (matches F4 LCD_ui3) */
    if (!s_inited) {
        ui_draw_f4_background();
        /* Draw all 3 letters in normal state */
        ui_blit_f4_image(F4_RGB_B_R_X, F4_RGB_B_R_Y,
                         F4_RGB_B_R_WIDTH, F4_RGB_B_R_HIGH, gImage_RGB_b_r_4853);
        ui_blit_f4_image(F4_RGB_B_G_X, F4_RGB_B_G_Y,
                         F4_RGB_B_G_WIDTH, F4_RGB_B_G_HIGH, gImage_RGB_b_g_4853);
        ui_blit_f4_image(F4_RGB_B_B_X, F4_RGB_B_B_Y,
                         F4_RGB_B_B_WIDTH, F4_RGB_B_B_HIGH, gImage_RGB_b_b_4753);
        /* Strip name + LED (mode 0 = red dot) */
        esp_name_update(strip);
        esp_deng(1, strip);  /* 1 = red */
        /* Draw initial name label */
        ui_blit_f4_image(F4_RGB_LEFT_X, F4_RGB_LEFT_Y,
                         F4_RGB_MIDDLE_WIDTH, F4_RGB_MIDDLE_HIGH,
                         gImage_RGB_middle_105_27);
        s_inited = 1;
        return;
    }

    /* Process encoder events */
    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        uint8_t mode = g_app_state.ui3_mode;

        switch (evt.type) {
        case ENC_EVT_ROTATE: {
            int16_t delta = evt.delta;

            if (mode == 0) {
                /* ── Mode 0: select strip ── */
                int8_t s = g_app_state.ui3_strip + (delta > 0 ? 1 : -1);
                if (s < 0) s = 3;
                if (s > 3) s = 0;
                g_app_state.ui3_strip = s;
                strip = s;

                /* F4: lcd_name_update + lcd_rgb_update(all) + lcd_deng(red) */
                esp_name_update(strip);
                esp_rgb_update(0);
                esp_rgb_update(1);
                esp_rgb_update(2);
                esp_deng(1, strip);

            } else if (mode == 1) {
                /* ── Mode 1: select channel ── */
                int8_t c = g_app_state.ui3_channel + (delta > 0 ? 1 : -1);
                if (c < 0) c = 2;
                if (c > 2) c = 0;
                g_app_state.ui3_channel = c;

                /* F4: lcd_rgb_update(all) + lcd_rgb_cai_update(active) + lcd_deng(green) */
                esp_rgb_update(0);
                esp_rgb_update(1);
                esp_rgb_update(2);
                esp_rgb_cai_update(c);
                esp_deng(0, strip);

            } else {
                /* ── Mode 2: adjust value ── */
                uint8_t chan = g_app_state.ui3_channel;
                int16_t val = g_app_state.led_edit[strip][chan];
                val += delta * 2;
                if (val < 0) val = 0;
                if (val > 255) val = 255;
                g_app_state.led_edit[strip][chan] = val;

                drv_led_set_strip_color((led_strip_id_t)strip,
                    (uint8_t)g_app_state.led_edit[strip][0],
                    (uint8_t)g_app_state.led_edit[strip][1],
                    (uint8_t)g_app_state.led_edit[strip][2]);
                drv_led_refresh();

                /* F4: lcd_rgb_num(channel, value) — only updates one zone */
                esp_rgb_num(chan, (uint8_t)val);
            }
            break;
        }

        /* ═══════════════════════════════════════════════════════════
         *  Drill-down / Pop-back 导航模式
         *  旋转 = 选择/调整，单击 = 确认进入或确认返回
         *
         *  Mode 0 (灯带选择): 单击 → 进入 Mode 1
         *  Mode 1 (通道选择): 单击 → 进入 Mode 2
         *  Mode 2 (数值调整): 单击 → 确认数值，弹回 Mode 0（保持当前灯带）
         * ═══════════════════════════════════════════════════════════ */
        case ENC_EVT_CLICK:
            if (g_app_state.ui3_mode == 0) {
                /* Mode 0 → Mode 1: 进入通道选择 */
                g_app_state.ui3_mode = 1;
                g_app_state.ui3_channel = 0;
                esp_rgb_update(0);
                esp_rgb_update(1);
                esp_rgb_update(2);
                esp_rgb_cai_update(0);
                esp_deng(0, strip);

            } else if (g_app_state.ui3_mode == 1) {
                /* Mode 1 → Mode 2: 进入数值调整 */
                g_app_state.ui3_mode = 2;
                /* 显示当前通道的数值 */
                esp_rgb_num(g_app_state.ui3_channel,
                    (uint8_t)g_app_state.led_edit[strip][g_app_state.ui3_channel]);

            } else {
                /* Mode 2 → Mode 0: 确认数值，弹回灯带选择 */
                /* 应用编辑的颜色到实际颜色 */
                for (int j = 0; j < 3; j++) {
                    g_app_state.led_colors[strip][j] =
                        (uint8_t)g_app_state.led_edit[strip][j];
                }
                /* 通知 APP 颜色已更新 */
                {
                    char buf[48];
                    snprintf(buf, sizeof(buf), "LED_UPDATE:%d:%d:%d:%d\r\n",
                             strip + 1,
                             g_app_state.led_colors[strip][0],
                             g_app_state.led_colors[strip][1],
                             g_app_state.led_colors[strip][2]);
                    ble_service_notify_str(buf);
                }
                /* 弹回 Mode 0，保持当前灯带 */
                g_app_state.ui3_mode = 0;
                esp_name_update(strip);
                esp_rgb_update(0);
                esp_rgb_update(1);
                esp_rgb_update(2);
                esp_deng(1, strip);  /* 红点 = 灯带选择模式 */
            }
            break;

        case ENC_EVT_DOUBLE_CLICK:
            for (int i = 0; i < 4; i++)
                for (int j = 0; j < 3; j++)
                    g_app_state.led_colors[i][j] = (uint8_t)g_app_state.led_edit[i][j];
            storage_save_current();
            ui_manager_set_ui(5);
            return;

        default: break;
        }
    }
}
