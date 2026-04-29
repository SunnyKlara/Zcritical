#pragma once

/* ═══════════════════════════════════════════════════════════════
 *  Critical ESP32-S3 Pin Configuration
 *  All GPIO assignments in one place
 * ═══════════════════════════════════════════════════════════════ */

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

/* MOS Control */
#define PIN_HUMIDIFIER  10     /* GPIO on/off */
#define PIN_FAN         40     /* LEDC PWM */
