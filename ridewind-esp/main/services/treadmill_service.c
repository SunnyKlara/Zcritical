/**
 * @file treadmill_service.c
 * @brief 跑步机业务层 — 把 UI 档位 (0..TREAD_UI_MAX) 映射成 driver 占空比 (0..100)
 */

#include "treadmill_service.h"
#include "drv_treadmill.h"
#include "ble_service.h"
#include "esp_log.h"
#include <stdio.h>

static const char *TAG = "tread_svc";

/* ── Treadmill response curve (mirrors drv_pwm.c fan_curve idea) ──
 *
 * Bench observation: belt motor barely twitches below ~90% duty, so
 * we skip the dead zone and land gear-1 right at the "just moves"
 * threshold so user sees motion the instant they leave 0.
 *
 * Curve shape (UI gear 0..20 → PWM 0..100%):
 *   gear 0       = 0%      stopped
 *   gear 1       = 70%     definite motion (kick over the static friction)
 *   gear 1..6    = 70→85%  fast ramp — every click feels noticeable
 *   gear 6..14   = 85→95%  slow middle — comfortable cruise range
 *   gear 14..20  = 95→100% top-end fine control
 *
 * If the belt fails to start at gear 1, raise TREAD_DUTY_MIN.
 * If gear 1 is already too aggressive, lower it. */
#define TREAD_DUTY_MIN      70   /* Static-friction kick — gear 1 lands here */
#define TREAD_DUTY_MID_LO   85   /* Knee 1: end of fast ramp */
#define TREAD_DUTY_MID_HI   95   /* Knee 2: end of cruise band */
#define TREAD_DUTY_MAX      100

#define TREAD_GEAR_KNEE_1   6    /* Up to here: low gears, fast climb */
#define TREAD_GEAR_KNEE_2   14   /* Up to here: cruise band, gentle climb */

static uint8_t s_ui_speed = 0;

/* Piecewise map UI gear (1..TREAD_UI_MAX) → PWM duty.
 * 0 stays 0. Each segment is linear; the segment slopes differ so the
 * lower gears feel responsive while higher gears allow fine tuning. */
static uint8_t map_ui_to_duty(uint8_t ui)
{
    if (ui == 0) return 0;
    if (ui > TREAD_UI_MAX) ui = TREAD_UI_MAX;

    if (ui <= TREAD_GEAR_KNEE_1) {
        /* gear 1..6 → MIN..MID_LO */
        uint16_t span = TREAD_DUTY_MID_LO - TREAD_DUTY_MIN;
        return (uint8_t)(TREAD_DUTY_MIN +
            ((uint16_t)(ui - 1) * span) / (TREAD_GEAR_KNEE_1 - 1));
    } else if (ui <= TREAD_GEAR_KNEE_2) {
        /* gear 7..14 → MID_LO..MID_HI */
        uint16_t span = TREAD_DUTY_MID_HI - TREAD_DUTY_MID_LO;
        return (uint8_t)(TREAD_DUTY_MID_LO +
            ((uint16_t)(ui - TREAD_GEAR_KNEE_1) * span) /
            (TREAD_GEAR_KNEE_2 - TREAD_GEAR_KNEE_1));
    } else {
        /* gear 15..20 → MID_HI..MAX */
        uint16_t span = TREAD_DUTY_MAX - TREAD_DUTY_MID_HI;
        return (uint8_t)(TREAD_DUTY_MID_HI +
            ((uint16_t)(ui - TREAD_GEAR_KNEE_2) * span) /
            (TREAD_UI_MAX - TREAD_GEAR_KNEE_2));
    }
}

void treadmill_service_init(void)
{
    s_ui_speed = 0;
    ESP_LOGI(TAG, "Treadmill service init, UI max=%d", TREAD_UI_MAX);
}

void treadmill_service_set_speed(uint8_t ui_speed)
{
    if (ui_speed > TREAD_UI_MAX) ui_speed = TREAD_UI_MAX;
    if (ui_speed == s_ui_speed) return;
    s_ui_speed = ui_speed;

    uint8_t duty = map_ui_to_duty(ui_speed);
    drv_treadmill_set_duty(duty);

    /* Notify APP for UI mirror — keeps existing TREAD_SPEED:N protocol. */
    char buf[32];
    snprintf(buf, sizeof(buf), "TREAD_SPEED:%u\n", (unsigned)ui_speed);
    ble_service_notify_str(buf);
}

uint8_t treadmill_service_get_speed(void) { return s_ui_speed; }

void treadmill_service_stop(void)
{
    s_ui_speed = 0;
    drv_treadmill_set_duty(0);
    ble_service_notify_str("TREAD_SPEED:0\n");
}
