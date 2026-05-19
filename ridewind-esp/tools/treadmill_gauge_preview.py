"""
跑步机仪表盘 Pygame 预览 v5
- 挡位最高 8（单个数字），字号比上方速度数字小很多
- 大刻度线加粗（3px）
- 上方速度数字大（36px），下方挡位小（14px），明显区分
"""

import pygame
import pygame.gfxdraw
import math
import sys

W, H = 240, 240
SCALE = 3
WIN_W, WIN_H = W * SCALE, H * SCALE

ARC_CX, ARC_CY = 120, 120
ARC_R_OUTER = 108
ARC_R_INNER = 104
ARC_START_DEG = 135
ARC_SWEEP_DEG = 270

TICK_R_OUTER = ARC_R_INNER - 2
TICK_R_INNER_SMALL = TICK_R_OUTER - 5
TICK_R_INNER_BIG = TICK_R_OUTER - 12
LABEL_R = TICK_R_INNER_BIG - 10

NEEDLE_TIP_R = ARC_R_INNER - 3
NEEDLE_BASE_R = 8
NEEDLE_TIP_HALF_W = 0.5
NEEDLE_BASE_HALF_W = 2.5

SPEED_MAX = 20
DISPLAY_MAX = 200
GEAR_MAX = 8

BG_COLOR = (0, 0, 0)
ARC_BG_COLOR = (25, 25, 30)
ARC_BORDER_COLOR = (35, 35, 40)
NEEDLE_COLOR = (255, 50, 30)
CENTER_DOT_COLOR = (60, 60, 65)
TICK_COLOR_DIM = (40, 40, 45)
LABEL_COLOR_DIM = (55, 55, 60)
GEAR_COLOR = (255, 255, 255)
GEAR_LABEL_COLOR = (70, 70, 75)


def arc_gradient_color(pct):
    if pct <= 0.5:
        t = pct * 2
        r = 255
        g = int(255 - (255 - 160) * t)
        b = int(255 - 255 * t)
    else:
        t = (pct - 0.5) * 2
        r = 255
        g = int(160 - (160 - 30) * t)
        b = 0
    return (r, g, b)


def draw_needle_aa(surface, speed):
    pct = speed / SPEED_MAX
    deg = ARC_START_DEG + ARC_SWEEP_DEG * pct
    rad = math.radians(deg)

    cos_n = math.cos(rad)
    sin_n = math.sin(rad)
    perp_cos = math.cos(rad + math.pi / 2)
    perp_sin = math.sin(rad + math.pi / 2)

    tip_x = ARC_CX + NEEDLE_TIP_R * cos_n
    tip_y = ARC_CY + NEEDLE_TIP_R * sin_n

    tip_l = (tip_x + NEEDLE_TIP_HALF_W * perp_cos,
             tip_y + NEEDLE_TIP_HALF_W * perp_sin)
    tip_r = (tip_x - NEEDLE_TIP_HALF_W * perp_cos,
             tip_y - NEEDLE_TIP_HALF_W * perp_sin)

    base_x = ARC_CX + NEEDLE_BASE_R * cos_n
    base_y = ARC_CY + NEEDLE_BASE_R * sin_n
    base_l = (base_x + NEEDLE_BASE_HALF_W * perp_cos,
              base_y + NEEDLE_BASE_HALF_W * perp_sin)
    base_r = (base_x - NEEDLE_BASE_HALF_W * perp_cos,
              base_y - NEEDLE_BASE_HALF_W * perp_sin)

    points = [
        (int(tip_l[0]), int(tip_l[1])),
        (int(tip_r[0]), int(tip_r[1])),
        (int(base_r[0]), int(base_r[1])),
        (int(base_l[0]), int(base_l[1])),
    ]

    pygame.gfxdraw.aapolygon(surface, points, NEEDLE_COLOR)
    pygame.gfxdraw.filled_polygon(surface, points, NEEDLE_COLOR)

    pygame.gfxdraw.aacircle(surface, ARC_CX, ARC_CY, 3, CENTER_DOT_COLOR)
    pygame.gfxdraw.filled_circle(surface, ARC_CX, ARC_CY, 3, CENTER_DOT_COLOR)


def draw_gauge(surface, speed):
    surface.fill(BG_COLOR)
    pct = speed / SPEED_MAX
    fill_angle = ARC_START_DEG + ARC_SWEEP_DEG * pct

    # 弧线外圈边框
    for deg_10 in range(ARC_START_DEG * 10, (ARC_START_DEG + ARC_SWEEP_DEG) * 10 + 1, 3):
        deg = deg_10 / 10.0
        rad = math.radians(deg)
        x = int(ARC_CX + (ARC_R_OUTER + 1) * math.cos(rad))
        y = int(ARC_CY + (ARC_R_OUTER + 1) * math.sin(rad))
        if 0 <= x < W and 0 <= y < H:
            surface.set_at((x, y), ARC_BORDER_COLOR)

    # 弧线
    for deg_10 in range(ARC_START_DEG * 10, (ARC_START_DEG + ARC_SWEEP_DEG) * 10 + 1):
        deg = deg_10 / 10.0
        rad = math.radians(deg)
        arc_pct = (deg - ARC_START_DEG) / ARC_SWEEP_DEG
        color = arc_gradient_color(arc_pct) if deg <= fill_angle else ARC_BG_COLOR
        for r in range(ARC_R_INNER, ARC_R_OUTER + 1):
            x = int(ARC_CX + r * math.cos(rad))
            y = int(ARC_CY + r * math.sin(rad))
            if 0 <= x < W and 0 <= y < H:
                surface.set_at((x, y), color)

    # 刻度线（大刻度 3px 粗）
    for i in range(DISPLAY_MAX // 10 + 1):
        val = i * 10
        t = val / DISPLAY_MAX
        if t > 1.0:
            break
        deg = ARC_START_DEG + ARC_SWEEP_DEG * t
        rad = math.radians(deg)

        is_big = (val % 50 == 0)
        r_inner = TICK_R_INNER_BIG if is_big else TICK_R_INNER_SMALL
        thickness = 3 if is_big else 1

        if t <= pct:
            base = arc_gradient_color(t)
            tick_color = (int(base[0] * 0.6), int(base[1] * 0.6), int(base[2] * 0.6))
        else:
            tick_color = TICK_COLOR_DIM

        x0 = int(ARC_CX + TICK_R_OUTER * math.cos(rad))
        y0 = int(ARC_CY + TICK_R_OUTER * math.sin(rad))
        x1 = int(ARC_CX + r_inner * math.cos(rad))
        y1 = int(ARC_CY + r_inner * math.sin(rad))
        pygame.draw.line(surface, tick_color, (x0, y0), (x1, y1), thickness)

    # 刻度数字
    font_small = pygame.font.SysFont('Arial', 8)
    for val in [0, 50, 100, 150, 200]:
        t = val / DISPLAY_MAX
        deg = ARC_START_DEG + ARC_SWEEP_DEG * t
        rad = math.radians(deg)
        lx = int(ARC_CX + LABEL_R * math.cos(rad))
        ly = int(ARC_CY + LABEL_R * math.sin(rad))
        if t <= pct:
            base = arc_gradient_color(t)
            label_color = (int(base[0] * 0.45), int(base[1] * 0.45), int(base[2] * 0.45))
        else:
            label_color = LABEL_COLOR_DIM
        text_surf = font_small.render(str(val), True, label_color)
        text_rect = text_surf.get_rect(center=(lx, ly))
        surface.blit(text_surf, text_rect)

    # 指针
    draw_needle_aa(surface, speed)

    # 中心速度数字（大，30px bold）
    display_spd = int(speed * 10)
    font_big = pygame.font.SysFont('Arial', 30, bold=True)
    text_surf = font_big.render(str(display_spd), True, (255, 255, 255))
    text_rect = text_surf.get_rect(center=(ARC_CX, ARC_CY + 26))
    surface.blit(text_surf, text_rect)

    # 底部缺口：挡位（18px，单个数字 1-8，无标签）
    gear = max(1, min(GEAR_MAX, int(speed * GEAR_MAX / SPEED_MAX + 0.5)))
    if speed < 0.5:
        gear_text = "N"
    else:
        gear_text = str(gear)
    font_gear = pygame.font.SysFont('Arial', 18, bold=True)
    gear_surf = font_gear.render(gear_text, True, GEAR_COLOR)
    gear_rect = gear_surf.get_rect(center=(ARC_CX, ARC_CY + 62))
    surface.blit(gear_surf, gear_rect)

    # 圆形遮罩
    mask = pygame.Surface((W, H), pygame.SRCALPHA)
    mask.fill((0, 0, 0, 255))
    pygame.draw.circle(mask, (0, 0, 0, 0), (W // 2, H // 2), W // 2)
    surface.blit(mask, (0, 0))


def main():
    pygame.init()
    screen = pygame.display.set_mode((WIN_W, WIN_H))
    pygame.display.set_caption("Treadmill Gauge v5 (240x240)")
    clock = pygame.time.Clock()
    canvas = pygame.Surface((W, H))
    speed = 0.0
    running = True

    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False

        mouse_pressed = pygame.mouse.get_pressed()[0]
        if mouse_pressed:
            speed += 0.12
            if speed > SPEED_MAX:
                speed = SPEED_MAX
        else:
            speed -= 0.08
            if speed < 0:
                speed = 0

        draw_gauge(canvas, speed)
        scaled = pygame.transform.scale(canvas, (WIN_W, WIN_H))
        screen.blit(scaled, (0, 0))
        pygame.display.flip()
        clock.tick(60)

    pygame.quit()
    sys.exit()


if __name__ == '__main__':
    main()
