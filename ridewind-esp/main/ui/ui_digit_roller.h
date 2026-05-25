/**
 * @file ui_digit_roller.h
 * @brief 小米 HUD 风格数字滚轮动画 — 数字变化时垂直滚动过渡
 *
 * 效果：数字增大时旧数字向上滑出、新数字从下方滑入（里程表/老虎机感）
 *       数字减小时反向滚动（向下滑出、从上方滑入）
 *
 * 用法：
 *   1. ui_roller_init() 初始化
 *   2. ui_roller_set_target() 设置目标数字
 *   3. 每帧调用 ui_roller_tick() 推进动画
 *   4. ui_roller_draw() 绘制当前帧
 */

#pragma once
#include <stdint.h>
#include <stdbool.h>

/* 最多支持 3 位数字 (0-999) */
#define ROLLER_MAX_DIGITS  3

/* 单个数字位的滚轮状态 */
typedef struct {
    uint8_t  current;       /* 当前显示的数字 0-9 */
    uint8_t  target;        /* 目标数字 0-9 */
    int16_t  offset_y;      /* 当前垂直偏移像素 (正=向上滚, 负=向下滚) */
    int8_t   direction;     /* 滚动方向: +1=向上(数字增大), -1=向下(数字减小), 0=静止 */
    uint8_t  speed;         /* 每 tick 滚动像素数 (越大越快) */
} digit_roller_t;

/* 整个数字显示的滚轮组 */
typedef struct {
    digit_roller_t digits[ROLLER_MAX_DIGITS];  /* [0]=百位, [1]=十位, [2]=个位 */
    uint16_t       target_num;                  /* 目标数值 */
    uint16_t       display_num;                 /* 当前逻辑显示数值 */
    uint8_t        digit_count;                 /* 当前显示位数 (1-3) */
    uint8_t        color_index;                 /* 颜色索引 (0=白色普通, 1-10=油门渐变) */
    bool           use_colored;                 /* 是否使用彩色数字 */
    bool           animating;                   /* 是否有动画在进行 */
} number_roller_t;

/**
 * @brief  初始化滚轮组，设置初始数值
 * @param  roller  滚轮组指针
 * @param  initial_num  初始数值 (0-999)
 */
void ui_roller_init(number_roller_t *roller, uint16_t initial_num);

/**
 * @brief  设置目标数值，触发滚动动画
 * @param  roller  滚轮组指针
 * @param  target  目标数值 (0-999)
 */
void ui_roller_set_target(number_roller_t *roller, uint16_t target);

/**
 * @brief  设置颜色模式
 * @param  roller       滚轮组指针
 * @param  use_colored  是否使用彩色数字
 * @param  color_index  颜色索引 (0-10, 用于油门模式渐变)
 */
void ui_roller_set_color(number_roller_t *roller, bool use_colored, uint8_t color_index);

/**
 * @brief  推进一帧动画
 * @param  roller  滚轮组指针
 * @return true 如果有像素变化需要重绘
 */
bool ui_roller_tick(number_roller_t *roller);

/**
 * @brief  绘制当前帧（带裁剪的垂直滚动效果）
 * @param  roller   滚轮组指针
 * @param  right_x  右对齐 X 坐标 (同 F4 的 x_qi)
 * @param  y        Y 坐标
 * @param  jianju   字间距 (同 F4 的 jianju)
 */
void ui_roller_draw(number_roller_t *roller, uint16_t right_x, uint16_t y, int8_t jianju);

/**
 * @brief  检查是否还在动画中
 */
bool ui_roller_is_animating(number_roller_t *roller);

/**
 * @brief  立即跳到目标值（无动画）
 */
void ui_roller_snap(number_roller_t *roller, uint16_t num);

