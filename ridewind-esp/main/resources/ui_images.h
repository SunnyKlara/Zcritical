#pragma once
#include <stdint.h>

/**
 * @file ui_images.h
 * @brief Image resources extracted from F4 STM32 pic.h for sub-UI rendering.
 *        All images are RGB565 format, black background.
 */

/* ══════ Coordinate & Size Defines ══════ */

/* Speed UI1 - Number rendering */
#define F4_SPEED_NUM_HIGH  53
#define F4_JIANJU  -2
#define F4_X_QI  160
#define F4_Y_QI  68

/* Speed UI1 - Wind gauge */
#define F4_FENGSHUBIAO_X  19
#define F4_FENGSHUBIAO_Y  123
#define F4_FENGSHUBIAO_WIDTH  202
#define F4_FENGSHUBIAO_HIGH  43

/* Speed UI1 - Unit labels */
#define F4_SPEED_KMH_X  158
#define F4_SPEED_KMH_Y  135
#define F4_SPEED_KMH_WIDTH  62
#define F4_SPEED_KMH_HIGH  25
#define F4_SPEED_MPH_X  158
#define F4_SPEED_MPH_Y  135
#define F4_SPEED_MPH_WIDTH  52
#define F4_SPEED_MPH_HIGH  25

/* Status LED indicators */
#define F4_H_DENG_WIDTH  12
#define F4_H_DENG_HIGH  21
#define F4_L_DENG_WIDTH  12
#define F4_L_DENG_HIGH  21
#define F4_C_DENG_WIDTH  12
#define F4_C_DENG_HIGH  21

/* Large digit widths (height = speed_num_high = 53) */
#define F4_SPEED_0_WIDTH  51
#define F4_SPEED_1_WIDTH  40
#define F4_SPEED_2_WIDTH  48
#define F4_SPEED_3_WIDTH  43
#define F4_SPEED_4_WIDTH  51
#define F4_SPEED_5_WIDTH  46
#define F4_SPEED_6_WIDTH  49
#define F4_SPEED_7_WIDTH  46
#define F4_SPEED_8_WIDTH  49
#define F4_SPEED_9_WIDTH  49

/* Color Preset UI2 */
#define F4_COLOR_X  15
#define F4_COLOR_Y  75
#define F4_COLOR_WIDTH  183
#define F4_COLOR_HIGH  57
#define F4_COLOR_RIZE_X  150
#define F4_COLOR_RIZE_Y  135
#define F4_COLOR_RIZE_WIDTH  69
#define F4_COLOR_RIZE_HIGH  28
#define F4_PEI_SE_X  25
#define F4_PEI_SE_Y  143

/* RGB UI3 - Number positions */
#define F4_NUM_R_X  54
#define F4_NUM_R_Y  95
#define F4_NUM_G_X  120
#define F4_NUM_G_Y  95
#define F4_NUM_B_X  186
#define F4_NUM_B_Y  95

/* RGB UI3 - Letter backgrounds */
#define F4_RGB_B_R_X  30
#define F4_RGB_B_R_Y  70
#define F4_RGB_B_R_WIDTH  48
#define F4_RGB_B_R_HIGH  53
#define F4_RGB_B_G_X  96
#define F4_RGB_B_G_Y  70
#define F4_RGB_B_G_WIDTH  48
#define F4_RGB_B_G_HIGH  53
#define F4_RGB_B_B_X  162
#define F4_RGB_B_B_Y  70
#define F4_RGB_B_B_WIDTH  47
#define F4_RGB_B_B_HIGH  53
#define F4_RGB_H_R_WIDTH  48
#define F4_RGB_H_R_HIGH  53
#define F4_RGB_L_G_WIDTH  48
#define F4_RGB_L_G_HIGH  53
#define F4_RGB_LAN_B_WIDTH  46
#define F4_RGB_LAN_B_HIGH  53

/* RGB UI3 - Strip names */
#define F4_RGB_LEFT_X  110
#define F4_RGB_LEFT_Y  140
#define F4_RGB_LEFT_WIDTH  55
#define F4_RGB_LEFT_HIGH  27
#define F4_RGB_MIDDLE_WIDTH  105
#define F4_RGB_MIDDLE_HIGH  27
#define F4_RGB_RIGHT_WIDTH  80
#define F4_RGB_RIGHT_HIGH  33
#define F4_RGB_BACK_WIDTH  77
#define F4_RGB_BACK_HIGH  27

/* RGB UI3 - Colored digit sizes (height = rgb_high) */
#define F4_RGB_HIGH  25
#define F4_H_0_WIDTH  24
#define F4_H_1_WIDTH  11
#define F4_H_2_WIDTH  22
#define F4_H_3_WIDTH  19
#define F4_H_4_WIDTH  23
#define F4_H_5_WIDTH  21
#define F4_H_6_WIDTH  23
#define F4_H_7_WIDTH  21
#define F4_H_8_WIDTH  21
#define F4_H_9_WIDTH  22
#define F4_L_0_WIDTH  24
#define F4_L_1_WIDTH  9
#define F4_L_2_WIDTH  23
#define F4_L_3_WIDTH  21
#define F4_L_4_WIDTH  24
#define F4_L_5_WIDTH  22
#define F4_L_6_WIDTH  23
#define F4_L_7_WIDTH  21
#define F4_L_8_WIDTH  23
#define F4_L_9_WIDTH  23
#define F4_B_0_WIDTH  24
#define F4_B_1_WIDTH  9
#define F4_B_2_WIDTH  21
#define F4_B_3_WIDTH  19
#define F4_B_4_WIDTH  23
#define F4_B_5_WIDTH  21
#define F4_B_6_WIDTH  23
#define F4_B_7_WIDTH  21
#define F4_B_8_WIDTH  22
#define F4_B_9_WIDTH  23

/* Brightness UI4 */
#define F4_UI4_JIANJU  2
#define F4_UI4_X_QI  155
#define F4_UI4_Y_QI  85
#define F4_BRT_X  140
#define F4_BRT_Y  150
#define F4_BRT_WIDTH  69
#define F4_BRT_HIGH  23

/* ══════ Image Array Declarations ══════ */

/* Full-screen background (240x240) */
extern const unsigned char gImage_beijing_240_240[115200];

/* Speed UI1 */
extern const unsigned char gImage_fengshubiao_202_43[17372];
extern const unsigned char gImage_speed_kmh_6225[3100];
extern const unsigned char gImage_speed_mph_5225[2600];

/* Status LED indicators (12x21) */
extern const unsigned char gImage_h_deng_1221[504];
extern const unsigned char gImage_l_deng_1221[504];
extern const unsigned char gImage_c_deng_1221[504];

/* Large digits 0-9 (height=53, variable width) */
extern const unsigned char gImage_speed_0_5153[5406];
extern const unsigned char gImage_speed_1_1553[4240];
extern const unsigned char gImage_speed_2_4853[5088];
extern const unsigned char gImage_speed_3_4353[4558];
extern const unsigned char gImage_speed_4_5153[5406];
extern const unsigned char gImage_speed_5_4653[4876];
extern const unsigned char gImage_speed_6_4953[5194];
extern const unsigned char gImage_speed_7_4653[4876];
extern const unsigned char gImage_speed_8_4953[5194];
extern const unsigned char gImage_speed_9_4953[5194];

/* Color Preset UI2 */
extern const unsigned char gImage_color_183_57[20862];
extern const unsigned char gImage_color_rize_69_28[3864];

/* RGB UI3 - Letter backgrounds */
extern const unsigned char gImage_RGB_b_r_4853[5088];
extern const unsigned char gImage_RGB_b_g_4853[5088];
extern const unsigned char gImage_RGB_b_b_4753[4982];
extern const unsigned char gImage_RGB_h_r_4853[5088];
extern const unsigned char gImage_RGB_l_g_4853[5088];
extern const unsigned char gImage_RGB_lan_b_4653[4876];

/* RGB UI3 - Strip names */
extern const unsigned char gImage_RGB_middle_105_27[5670];
extern const unsigned char gImage_RGB_left_5527[2970];
extern const unsigned char gImage_RGB_right_8033[5280];
extern const unsigned char gImage_RGB_back_7727[4158];

/* RGB UI3 - Red digits */
extern const unsigned char gImage_h_0_2425[1200];
extern const unsigned char gImage_h_1_1125[550];
extern const unsigned char gImage_h_2_2225[1100];
extern const unsigned char gImage_h_3_1925[950];
extern const unsigned char gImage_h_4_2325[1150];
extern const unsigned char gImage_h_5_2125[1050];
extern const unsigned char gImage_h_6_2325[1150];
extern const unsigned char gImage_h_7_2125[1050];
extern const unsigned char gImage_h_8_2125[1050];
extern const unsigned char gImage_h_9_2225[1100];

/* RGB UI3 - Green digits */
extern const unsigned char gImage_l_0_2425[1200];
extern const unsigned char gImage_l_1_0925[450];
extern const unsigned char gImage_l_2_2325[1150];
extern const unsigned char gImage_l_3_2125[1050];
extern const unsigned char gImage_l_4_2425[1200];
extern const unsigned char gImage_l_5_2225[1100];
extern const unsigned char gImage_l_6_2325[1150];
extern const unsigned char gImage_l_7_2125[1050];
extern const unsigned char gImage_l_8_2325[1150];
extern const unsigned char gImage_l_9_2325[1150];

/* RGB UI3 - Blue digits */
extern const unsigned char gImage_b_0_2425[1200];
extern const unsigned char gImage_b_1_0925[450];
extern const unsigned char gImage_b_2_2125[1050];
extern const unsigned char gImage_b_3_1925[950];
extern const unsigned char gImage_b_4_2325[1150];
extern const unsigned char gImage_b_5_2125[1050];
extern const unsigned char gImage_b_6_2325[1150];
extern const unsigned char gImage_b_7_2125[1050];
extern const unsigned char gImage_b_8_2225[1100];
extern const unsigned char gImage_b_9_2325[1150];

/* Brightness UI4 */
extern const unsigned char gImage_brt_6923[3174];

