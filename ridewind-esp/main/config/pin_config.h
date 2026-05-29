/**
 * @file pin_config.h
 * @brief ESP32-S3 GPIO 引脚定义 — 所有硬件引脚分配集中管理
 */

#pragma once

/* GC9A01 Round LCD (SPI) */
#define PIN_LCD_SCL     7
#define PIN_LCD_SDA     6
#define PIN_LCD_DC      5
#define PIN_LCD_CS      4
#define PIN_LCD_RST     (-1)   /* Not connected */

/* MAX98357 I2S Audio */
#define PIN_I2S_DIN     13
#define PIN_I2S_BCLK    12
#define PIN_I2S_LRC     11

/* WS2812B LED Strips */
#define PIN_LED_STRIP1  41     /* 10 LEDs: Left(2) + Main(6) + Right(2) */
#define PIN_LED_STRIP2  16     /* 3 LEDs: Tail */

/* EC11 Rotary Encoder */
#define PIN_ENC_A       17
#define PIN_ENC_B       18
#define PIN_ENC_KEY     8      /* Active low */

/* MOS Control
 * ⚠️ 重要：硬件文档标注 IO10=雾化器、IO40=风扇，但实测确认是反的！
 * 实际接线：IO10 = 风扇PWM调速（MOS管控制风扇），IO40 = 雾化器开关
 */
#define PIN_HUMIDIFIER  40     /* GPIO on/off — 超声波雾化器开关 */
#define PIN_FAN         10     /* LEDC PWM — 风扇调速 */
#define PIN_TREADMILL   14     /* LEDC PWM — 跑步机（车模传送带）调速 */
