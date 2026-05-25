/**
 * @file ui_digit_roller.c
 * @brief 小米 HUD 风格数字滚轮动画实现
 *
 * 核心原理：
 *   每个数字位独立做垂直像素偏移动画。绘制时对数字位图做行级裁剪(clip)，
 *   只 blit 可见区域内的像素行，实现平滑的上下滚动过渡效果。
 *
 * 性能：
 *   - 数字区域约 140×53 像素 = ~15KB/帧
 *   - 40MHz SPI 下单帧传输 <1ms
 *   - 目标 30fps，每 33ms tick 一次
 */

#include "ui_digit_roller.h"
#include "ui_common.h"
#include "ui_images.h"
#include "drv_lcd.h"
#include "colored_digits.h"
#include <string.h>

/* ── 数字位图数据引用 (同 ui_common.c) ── */

static const unsigned char * const s_digit_data[10] = {
    gImage_speed_0_5153, gImage_speed_1_1553, gImage_speed_2_4853,
    gImage_speed_3_4353, gImage_speed_4_5153, gImage_speed_5_4653,
    gImage_speed_6_4953, gImage_speed_7_4653, gImage_speed_8_4953,
    gImage_speed_9_4953,
};

static const uint8_t s_digit_width[10] = {
    F4_SPEED_0_WIDTH, F4_SPEED_1_WIDTH, F4_SPEED_2_WIDTH, F4_SPEED_3_WIDTH,
    F4_SPEED_4_WIDTH, F4_SPEED_5_WIDTH, F4_SPEED_6_WIDTH, F4_SPEED_7_WIDTH,
    F4_SPEED_8_WIDTH, F4_SPEED_9_WIDTH,
};

/* 彩色数字位图数据 (同 ui_common.c 中的 s_colored_digit_data 布局) */
static const unsigned char * const s_colored_data[COLORED_DIGIT_STEPS][10] = {
    { gImage_speed_0_c0, gImage_speed_1_c0, gImage_speed_2_c0, gImage_speed_3_c0, gImage_speed_4_c0, gImage_speed_5_c0, gImage_speed_6_c0, gImage_speed_7_c0, gImage_speed_8_c0, gImage_speed_9_c0 },
    { gImage_speed_0_c1, gImage_speed_1_c1, gImage_speed_2_c1, gImage_speed_3_c1, gImage_speed_4_c1, gImage_speed_5_c1, gImage_speed_6_c1, gImage_speed_7_c1, gImage_speed_8_c1, gImage_speed_9_c1 },
    { gImage_speed_0_c2, gImage_speed_1_c2, gImage_speed_2_c2, gImage_speed_3_c2, gImage_speed_4_c2, gImage_speed_5_c2, gImage_speed_6_c2, gImage_speed_7_c2, gImage_speed_8_c2, gImage_speed_9_c2 },
    { gImage_speed_0_c3, gImage_speed_1_c3, gImage_speed_2_c3, gImage_speed_3_c3, gImage_speed_4_c3, gImage_speed_5_c3, gImage_speed_6_c3, gImage_speed_7_c3, gImage_speed_8_c3, gImage_speed_9_c3 },
    { gImage_speed_0_c4, gImage_speed_1_c4, gImage_speed_2_c4, gImage_speed_3_c4, gImage_speed_4_c4, gImage_speed_5_c4, gImage_speed_6_c4, gImage_speed_7_c4, gImage_speed_8_c4, gImage_speed_9_c4 },
    { gImage_speed_0_c5, gImage_speed_1_c5, gImage_speed_2_c5, gImage_speed_3_c5, gImage_speed_4_c5, gImage_speed_5_c5, gImage_speed_6_c5, gImage_speed_7_c5, gImage_speed_8_c5, gImage_speed_9_c5 },
    { gImage_speed_0_c6, gImage_speed_1_c6, gImage_speed_2_c6, gImage_speed_3_c6, gImage_speed_4_c6, gImage_speed_5_c6, gImage_speed_6_c6, gImage_speed_7_c6, gImage_speed_8_c6, gImage_speed_9_c6 },
    { gImage_speed_0_c7, gImage_speed_1_c7, gImage_speed_2_c7, gImage_speed_3_c7, gImage_speed_4_c7, gImage_speed_5_c7, gImage_speed_6_c7, gImage_speed_7_c7, gImage_speed_8_c7, gImage_speed_9_c7 },
    { gImage_speed_0_c8, gImage_speed_1_c8, gImage_speed_2_c8, gImage_speed_3_c8, gImage_speed_4_c8, gImage_speed_5_c8, gImage_speed_6_c8, gImage_speed_7_c8, gImage_speed_8_c8, gImage_speed_9_c8 },
    { gImage_speed_0_c9, gImage_speed_1_c9, gImage_speed_2_c9, gImage_speed_3_c9, gImage_speed_4_c9, gImage_speed_5_c9, gImage_speed_6_c9, gImage_speed_7_c9, gImage_speed_8_c9, gImage_speed_9_c9 },
    { gImage_speed_0_c10, gImage_speed_1_c10, gImage_speed_2_c10, gImage_speed_3_c10, gImage_speed_4_c10, gImage_speed_5_c10, gImage_speed_6_c10, gImage_speed_7_c10, gImage_speed_8_c10, gImage_speed_9_c10 },
};

#define DIGIT_HEIGHT  F4_SPEED_NUM_HIGH  /* 53 pixels */

/* 滚动速度配置 */
#define ROLLER_BASE_SPEED    4   /* 基础每 tick 像素数 */
#define ROLLER_FAST_SPEED    8   /* 快速滚动 (大跨度变化) */
#define ROLLER_ACCEL_THRESH  3   /* 超过这个差值用快速 */

/* ── 内部工具函数 ── */

/** 分解数字为各位 */
static void decompose_number(uint16_t num, uint8_t *hundreds, uint8_t *tens, uint8_t *ones, uint8_t *count)
{
    if (num >= 100) {
        *hundreds = num / 100;
        *tens = (num % 100) / 10;
        *ones = num % 10;
        *count = 3;
    } else if (num >= 10) {
        *hundreds = 0;
        *tens = num / 10;
        *ones = num % 10;
        *count = 2;
    } else {
        *hundreds = 0;
        *tens = 0;
        *ones = num;
        *count = 1;
    }
}

/** 计算两个数字之间的最短滚动方向 (考虑 9→0 的环绕) */
static int8_t calc_direction(uint8_t from, uint8_t to)
{
    if (from == to) return 0;

    /* 向上滚动的步数 (0→1→2→...→9→0) */
    uint8_t up_steps = (to >= from) ? (to - from) : (10 - from + to);
    /* 向下滚动的步数 */
    uint8_t down_steps = 10 - up_steps;

    /* 选择步数少的方向 */
    if (up_steps <= down_steps) return 1;   /* 向上 */
    return -1;  /* 向下 */
}

/**
 * @brief  裁剪绘制单个数字位图的部分行
 *
 * 将数字位图的 [src_row_start, src_row_start+visible_rows) 行
 * 绘制到屏幕的 (x, dst_y) 位置。
 *
 * @param x             屏幕 X 坐标
 * @param dst_y         屏幕 Y 坐标 (绘制起始行)
 * @param digit         数字 0-9
 * @param src_row_start 位图中的起始行 (0-based)
 * @param visible_rows  要绘制的行数
 * @param use_colored   是否用彩色
 * @param color_index   颜色索引
 */
static void draw_digit_clipped(uint16_t x, uint16_t dst_y, uint8_t digit,
                                uint16_t src_row_start, uint16_t visible_rows,
                                bool use_colored, uint8_t color_index)
{
    if (digit > 9 || visible_rows == 0) return;
    if (src_row_start >= DIGIT_HEIGHT) return;
    if (src_row_start + visible_rows > DIGIT_HEIGHT)
        visible_rows = DIGIT_HEIGHT - src_row_start;

    uint8_t w = s_digit_width[digit];
    if (w == 0) return;

    /* 获取位图数据指针 */
    const unsigned char *img_data;
    if (use_colored && color_index < COLORED_DIGIT_STEPS) {
        img_data = s_colored_data[color_index][digit];
    } else {
        img_data = s_digit_data[digit];
    }

    /* 计算位图中对应行的偏移 (每像素 2 bytes, RGB565) */
    uint32_t row_bytes = (uint32_t)w * 2;
    const unsigned char *src = img_data + (uint32_t)src_row_start * row_bytes;

    /* 直接 blit 裁剪后的区域 */
    drv_lcd_set_window(x, dst_y, x + w - 1, dst_y + visible_rows - 1);

    /* 逐行发送 (数据在 flash 中，用 polling 方式) */
    uint32_t total = row_bytes * visible_rows;
    const uint8_t *p = (const uint8_t *)src;

    /* 使用 drv_lcd_write_data 发送 (它内部会根据大小选择 polling/DMA) */
    drv_lcd_write_data(p, total);
}

/* ── 公开 API ── */

void ui_roller_init(number_roller_t *roller, uint16_t initial_num)
{
    memset(roller, 0, sizeof(*roller));
    roller->target_num = initial_num;
    roller->display_num = initial_num;

    uint8_t h, t, o, cnt;
    decompose_number(initial_num, &h, &t, &o, &cnt);

    roller->digits[0].current = h;
    roller->digits[0].target = h;
    roller->digits[1].current = t;
    roller->digits[1].target = t;
    roller->digits[2].current = o;
    roller->digits[2].target = o;
    roller->digit_count = cnt;

    for (int i = 0; i < ROLLER_MAX_DIGITS; i++) {
        roller->digits[i].offset_y = 0;
        roller->digits[i].direction = 0;
        roller->digits[i].speed = ROLLER_BASE_SPEED;
    }

    roller->animating = false;
    roller->use_colored = false;
    roller->color_index = 0;
}

void ui_roller_set_target(number_roller_t *roller, uint16_t target)
{
    if (target > 999) target = 999;
    if (target == roller->target_num && !roller->animating) return;

    roller->target_num = target;

    uint8_t h, t, o, cnt;
    decompose_number(target, &h, &t, &o, &cnt);

    /* 设置每位的目标和方向 */
    uint8_t targets[3] = { h, t, o };

    for (int i = 0; i < ROLLER_MAX_DIGITS; i++) {
        digit_roller_t *d = &roller->digits[i];
        d->target = targets[i];

        if (d->current != d->target) {
            d->direction = calc_direction(d->current, d->target);

            /* 根据差距决定速度 */
            uint8_t diff = (d->direction > 0)
                ? ((d->target >= d->current) ? (d->target - d->current) : (10 - d->current + d->target))
                : ((d->current >= d->target) ? (d->current - d->target) : (10 - d->target + d->current));

            d->speed = (diff > ROLLER_ACCEL_THRESH) ? ROLLER_FAST_SPEED : ROLLER_BASE_SPEED;
            roller->animating = true;
        }
    }

    roller->digit_count = cnt;
}

void ui_roller_set_color(number_roller_t *roller, bool use_colored, uint8_t color_index)
{
    roller->use_colored = use_colored;
    roller->color_index = color_index;
}

bool ui_roller_tick(number_roller_t *roller)
{
    if (!roller->animating) return false;

    bool any_moving = false;
    bool changed = false;

    for (int i = 0; i < ROLLER_MAX_DIGITS; i++) {
        digit_roller_t *d = &roller->digits[i];

        if (d->direction == 0) continue;
        if (d->current == d->target && d->offset_y == 0) {
            d->direction = 0;
            continue;
        }

        any_moving = true;
        changed = true;

        /* 推进偏移 */
        d->offset_y += d->direction * d->speed;

        /* 检查是否滚过一个完整数字高度 */
        if (d->offset_y >= DIGIT_HEIGHT) {
            /* 向上滚完一位 */
            d->current = (d->current + 1) % 10;
            d->offset_y -= DIGIT_HEIGHT;

            /* 到达目标？ */
            if (d->current == d->target) {
                d->offset_y = 0;
                d->direction = 0;
            }
        } else if (d->offset_y <= -DIGIT_HEIGHT) {
            /* 向下滚完一位 */
            d->current = (d->current == 0) ? 9 : (d->current - 1);
            d->offset_y += DIGIT_HEIGHT;

            if (d->current == d->target) {
                d->offset_y = 0;
                d->direction = 0;
            }
        }
    }

    if (!any_moving) {
        roller->animating = false;
        /* 同步 display_num */
        roller->display_num = roller->target_num;
    }

    return changed;
}

/**
 * @brief  绘制单个数字位的滚动帧
 *
 * 当 offset_y != 0 时，绘制两个数字的部分：
 *   - 当前数字被偏移（部分可见）
 *   - 下一个数字从另一侧进入（部分可见）
 */
static void draw_roller_digit(digit_roller_t *d, uint16_t x, uint16_t y,
                               bool use_colored, uint8_t color_index)
{
    uint8_t w = s_digit_width[d->current];

    if (d->offset_y == 0 && d->direction == 0) {
        /* 静止状态：直接画完整数字 */
        if (use_colored) {
            ui_draw_large_digit_colored(x, y, d->current, color_index);
        } else {
            ui_draw_large_digit(x, y, d->current);
        }
        return;
    }

    /* 动画状态：裁剪绘制 */
    int16_t off = d->offset_y;  /* 正=向上, 负=向下 */
    uint8_t next_digit;

    if (off > 0) {
        /* 向上滚动：当前数字向上移出，下一个数字从底部进入 */
        next_digit = (d->current + 1) % 10;

        /* 当前数字：显示 [off, DIGIT_HEIGHT) 行，画在 y 位置 */
        uint16_t visible_current = DIGIT_HEIGHT - (uint16_t)off;
        if (visible_current > 0) {
            draw_digit_clipped(x, y, d->current,
                               (uint16_t)off, visible_current,
                               use_colored, color_index);
        }

        /* 下一个数字：显示 [0, off) 行，画在 y + visible_current 位置 */
        if (off > 0) {
            /* 先清除下方即将被新数字覆盖的区域（处理宽度差异） */
            uint8_t next_w = s_digit_width[next_digit];
            uint8_t max_w = (w > next_w) ? w : next_w;
            drv_lcd_fill_rect(x, y + visible_current, max_w, (uint16_t)off, 0x0000);

            draw_digit_clipped(x, y + visible_current, next_digit,
                               0, (uint16_t)off,
                               use_colored, color_index);
        }
    } else {
        /* 向下滚动：当前数字向下移出，上一个数字从顶部进入 */
        uint16_t abs_off = (uint16_t)(-off);
        next_digit = (d->current == 0) ? 9 : (d->current - 1);

        /* 上一个数字：显示 [DIGIT_HEIGHT - abs_off, DIGIT_HEIGHT) 行，画在 y 位置 */
        if (abs_off > 0) {
            uint8_t next_w = s_digit_width[next_digit];
            uint8_t max_w = (w > next_w) ? w : next_w;
            drv_lcd_fill_rect(x, y, max_w, abs_off, 0x0000);

            draw_digit_clipped(x, y, next_digit,
                               DIGIT_HEIGHT - abs_off, abs_off,
                               use_colored, color_index);
        }

        /* 当前数字：显示 [0, DIGIT_HEIGHT - abs_off) 行，画在 y + abs_off 位置 */
        uint16_t visible_current = DIGIT_HEIGHT - abs_off;
        if (visible_current > 0) {
            draw_digit_clipped(x, y + abs_off, d->current,
                               0, visible_current,
                               use_colored, color_index);
        }
    }
}

void ui_roller_draw(number_roller_t *roller, uint16_t right_x, uint16_t y, int8_t jianju)
{
    /* 计算各位数字的 X 坐标 (右对齐，同 F4 布局) */
    uint8_t count = roller->digit_count;

    /* 使用目标数字的宽度来计算布局（保持位置稳定） */
    uint8_t d_a = roller->digits[0].current;
    uint8_t d_b = roller->digits[1].current;
    uint8_t d_c = roller->digits[2].current;

    uint8_t w_a = s_digit_width[d_a];
    uint8_t w_b = s_digit_width[d_b];
    uint8_t w_c = s_digit_width[d_c];

    if (count == 3) {
        int16_t x3 = (int16_t)right_x - w_a - w_b - w_c - jianju * 3;
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;

        draw_roller_digit(&roller->digits[0], (uint16_t)x3, y,
                          roller->use_colored, roller->color_index);
        draw_roller_digit(&roller->digits[1], (uint16_t)x2, y,
                          roller->use_colored, roller->color_index);
        draw_roller_digit(&roller->digits[2], (uint16_t)x1, y,
                          roller->use_colored, roller->color_index);
    } else if (count == 2) {
        int16_t x2 = (int16_t)right_x - w_b - w_c - jianju * 2;
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;

        draw_roller_digit(&roller->digits[1], (uint16_t)x2, y,
                          roller->use_colored, roller->color_index);
        draw_roller_digit(&roller->digits[2], (uint16_t)x1, y,
                          roller->use_colored, roller->color_index);
    } else {
        int16_t x1 = (int16_t)right_x - w_c - jianju * 1;

        draw_roller_digit(&roller->digits[2], (uint16_t)x1, y,
                          roller->use_colored, roller->color_index);
    }
}

bool ui_roller_is_animating(number_roller_t *roller)
{
    return roller->animating;
}

void ui_roller_snap(number_roller_t *roller, uint16_t num)
{
    if (num > 999) num = 999;
    roller->target_num = num;
    roller->display_num = num;
    roller->animating = false;

    uint8_t h, t, o, cnt;
    decompose_number(num, &h, &t, &o, &cnt);

    roller->digits[0].current = h;
    roller->digits[0].target = h;
    roller->digits[0].offset_y = 0;
    roller->digits[0].direction = 0;

    roller->digits[1].current = t;
    roller->digits[1].target = t;
    roller->digits[1].offset_y = 0;
    roller->digits[1].direction = 0;

    roller->digits[2].current = o;
    roller->digits[2].target = o;
    roller->digits[2].offset_y = 0;
    roller->digits[2].direction = 0;

    roller->digit_count = cnt;
}
