"""Fix ui_treadmill.c v8: performance + visual"""
import os

path = r"c:\Users\Klara\Desktop\4.8\ridewind-esp\main\ui\ui_treadmill.c"
with open(path, "r", encoding="utf-8") as f:
    c = f.read()

# 1. Replace ui_treadmill_update - only redraw on actual change
old_start = c.find("void ui_treadmill_update(void)")
new_update = """void ui_treadmill_update(void)
{
    if (s_need_full_redraw) {
        draw_full_screen();
        s_need_full_redraw = 0;
        return;
    }

    encoder_event_t evt;
    while (drv_encoder_poll(&evt)) {
        if (evt.type == ENC_EVT_DOUBLE_CLICK) {
            ui_manager_set_ui(5);
            return;
        }
        if (evt.type == ENC_EVT_ROTATE) {
            s_cruise_speed += evt.delta;
            if (s_cruise_speed < 0) s_cruise_speed = 0;
            if (s_cruise_speed > TREAD_MAX_SPEED) s_cruise_speed = TREAD_MAX_SPEED;
            if (!drv_encoder_button_pressed()) {
                s_treadmill_speed = s_cruise_speed;
                char buf[32];
                snprintf(buf, sizeof(buf), "TREAD_SPEED:%d\\n", s_treadmill_speed);
                ble_service_notify_str(buf);
            }
        }
    }

    speed_process();

    float target = (float)s_treadmill_speed;
    if (fabsf(s_display_speed - target) > 0.05f) {
        s_display_speed += (target - s_display_speed) * SMOOTH_FACTOR;
    } else {
        s_display_speed = target;
    }

    /* ONLY redraw when integer speed changes - prevents WDT and lag */
    int16_t visual_speed = (int16_t)(s_display_speed + 0.5f);
    if (visual_speed == s_last_drawn_speed) return;

    uint8_t new_pct = (uint8_t)((uint32_t)visual_speed * 100 / TREAD_MAX_SPEED);
    if (new_pct > 100) new_pct = 100;

    if (new_pct != s_last_drawn_pct) {
        update_arc_fast(s_last_drawn_pct, new_pct);
        draw_ticks(new_pct);
        s_last_drawn_pct = new_pct;
    }

    update_needle_smooth();
    draw_speed_number();
    draw_gear_blocks();
    s_last_drawn_speed = visual_speed;
}
"""
c = c[:old_start] + new_update
print("1. Replaced ui_treadmill_update")

# 2. Remove center circle border ring (the "杂碎圆点")
c = c.replace(
    "    drv_lcd_draw_circle(ARC_CX, ARC_CY, 6, COLOR_ARC_BORDER, false);\n", "")
print("2. Removed circle border ring")

# 3. Replace gear_color with pure red gradient (light to dark)
old_gear_color_start = c.find("static uint16_t gear_color(int idx)")
old_gear_color_end = c.find("\nstatic void draw_gear_blocks", old_gear_color_start)

new_gear_color = """static uint16_t gear_color(int idx)
{
    /* Pure red: light pink(1) -> deep red(8) */
    uint8_t t = (uint8_t)((idx - 1) * 100 / (GEAR_MAX - 1));
    uint8_t r = (uint8_t)(120 + 135 * t / 100);  /* 120 -> 255 */
    uint8_t g = (uint8_t)(60 - 60 * t / 100);    /* 60 -> 0 */
    uint8_t b = (uint8_t)(60 - 60 * t / 100);    /* 60 -> 0 */
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}
"""
c = c[:old_gear_color_start] + new_gear_color + c[old_gear_color_end:]
print("3. Replaced gear_color with red gradient")

# 4. Replace gear blocks: equal width, progressive HEIGHT (tall rectangles)
old_gear_fn_start = c.find("static void draw_gear_blocks(void)")
old_gear_fn_end = c.find("\n/* ====== Full Screen", old_gear_fn_start)

new_gear_fn = """static void draw_gear_blocks(void)
{
    int gear = 0;
    if (s_treadmill_speed >= 1) {
        gear = (s_treadmill_speed * GEAR_MAX + TREAD_MAX_SPEED / 2) / TREAD_MAX_SPEED;
        if (gear < 1) gear = 1;
        if (gear > GEAR_MAX) gear = GEAR_MAX;
    }

    /* Equal width (6px), progressive height: 4,6,8,10,12,14,16,18 */
    #define GEAR_W  6
    uint16_t total_w = GEAR_MAX * GEAR_W + (GEAR_MAX - 1) * GEAR_BLOCK_GAP;
    uint16_t start_x = ARC_CX - total_w / 2;
    uint16_t base_y = GEAR_CENTER_Y + 18;  /* bottom-aligned */

    /* Clear gear area */
    drv_lcd_fill_rect(start_x - 2, GEAR_CENTER_Y - 2, total_w + 4, 22, COLOR_BG);

    for (int i = 1; i <= GEAR_MAX; i++) {
        uint8_t h = 4 + (uint8_t)((i - 1) * 2);  /* height: 4,6,8,10,12,14,16,18 */
        uint16_t bx = start_x + (i - 1) * (GEAR_W + GEAR_BLOCK_GAP);
        uint16_t by = base_y - h;  /* bottom-aligned */
        uint16_t color = (i <= gear) ? gear_color(i) : COLOR_GEAR_DIM;
        drv_lcd_fill_rect(bx, by, GEAR_W, h, color);
    }
    #undef GEAR_W
}
"""
c = c[:old_gear_fn_start] + new_gear_fn + c[old_gear_fn_end:]
print("4. Replaced gear blocks: equal width, progressive height, bottom-aligned")

# 5. Remove the unused GEAR_BLOCK_H define if still there
c = c.replace("#define GEAR_BLOCK_H        5\n", "")
c = c.replace("#define GEAR_BLOCK_H        4\n", "")

with open(path, "w", encoding="utf-8") as f:
    f.write(c)

print(f"\nDone! File: {len(c)} chars, {c.count(chr(10))} lines")
