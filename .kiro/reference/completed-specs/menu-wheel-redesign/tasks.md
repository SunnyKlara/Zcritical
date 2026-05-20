# Implementation Plan: Menu Wheel Redesign

## Overview

Replace the text-only scanline compositing menu (UI5) with a bitmap-based menu using F4 icon/text arrays and slide transition animation. Implementation proceeds in 4 phases: board constants, bitmap data integration, ui_menu.c rewrite, and final wiring/verification.

## Tasks

- [x] 1. Add menu layout constants to board_config.h
  - Add `MENU_ICON_CENTER_Y` (90), `MENU_TEXT_Y` (155), `MENU_DOT_Y` (205), `MENU_DOT_SPACING` (15), `MENU_DOT_RADIUS` (3)
  - Add `MENU_DOT_ACTIVE_COLOR` (0xFFFF), `MENU_DOT_INACTIVE_COLOR` (0x4208)
  - Add `MENU_ANIM_FRAMES` (8), `MENU_ANIM_FRAME_DELAY` (12)
  - Add `MENU_ANIM_ZONE_TOP` (50), `MENU_ANIM_ZONE_BOTTOM` (190)
  - Add `MENU_PAGE_COUNT` (6)
  - Keep existing `MENU_SWITCH_DEBOUNCE_MS` (150) and `MENU_DELTA_THRESHOLD` (2) unchanged
  - _Requirements: 8.1, 8.2_

- [x] 2. Create bitmap data and lookup table
  - [x] 2.1 Create `ridewind-esp/main/resources/menu_icons.c` — include all 12 F4 bitmap array `.c` files from `ridewind-esp/取模数组/` directory
    - Include: `fengsu_68_58.c`, `tiaosepan_74_74.c`, `rgbtubiao.c`, `brighttubiao.c`, `logotubiao.c`, `voicetubiao.c` (6 icons)
    - Include: `speed_99_33.c`, `new_color.c`, `rgb.c`, `bright.c`, `logo.c`, `voice.c` (6 text labels)
    - Define the `menu_pages[MENU_PAGE_COUNT]` lookup table with icon/text pointers (cast `const unsigned char*` to `const uint16_t*`), dimensions, and `target_ui` values
    - _Requirements: 7.1, 7.2, 7.3_

  - [x] 2.2 Populate `ridewind-esp/main/resources/menu_icons.h` with extern declarations
    - Declare all 12 bitmap arrays as `extern const unsigned char[]`
    - Define `menu_page_info_t` struct with icon/text pointers, dimensions, and `target_ui`
    - Declare `extern const menu_page_info_t menu_pages[MENU_PAGE_COUNT]`
    - _Requirements: 7.1, 7.2_

  - [x] 2.3 Add `resources/menu_icons.c` to `CMakeLists.txt` SRCS list
    - _Requirements: 7.1_

- [x] 3. Checkpoint — Verify bitmap data compiles
  - Ensure the project compiles with the new bitmap data and lookup table, ask the user if questions arise.

- [x] 4. Rewrite ui_menu.c — static rendering and navigation
  - [x] 4.1 Implement `draw_static_page(uint8_t page_idx)` — look up `menu_pages[]`, compute centered icon X = `(240 - icon_w) / 2`, icon Y = `MENU_ICON_CENTER_Y - icon_h / 2`, blit icon via `drv_lcd_blit_rgb565()`, compute centered text X = `(240 - text_w) / 2`, blit text at `MENU_TEXT_Y`, then call `draw_nav_dots()`
    - Remove all old scanline compositing code (slot_t, composite_scanline, render_item_zone, build_slots_at, calc_scale_fp, calc_color, font_8x16 include)
    - Replace `#include "font_8x16.h"` with `#include "menu_icons.h"`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 4.2 Implement `draw_nav_dots(uint8_t active_idx)` — clear dot row, compute start X to center 6 dots with `MENU_DOT_SPACING`, draw active dot as filled white circle (radius `MENU_DOT_RADIUS`, color `MENU_DOT_ACTIVE_COLOR`), inactive dots as filled dark gray (`MENU_DOT_INACTIVE_COLOR`)
    - _Requirements: 3.1, 3.2, 3.3_

  - [x] 4.3 Implement `wrap_page(int8_t idx)` helper for circular menu navigation
    - _Requirements: 4.4_

  - [x] 4.4 Implement `ui_menu_enter()` — reset `s_accum = 0`, set `s_need_redraw = 1`
    - _Requirements: 1.4_

  - [x] 4.5 Implement `ui_menu_update()` — check `auto_enter` flag first (clear flag, transition to sub-UI), then handle `s_need_redraw` (clear screen + draw static page), then poll encoder events: `ENC_EVT_ROTATE` accumulates delta with threshold + debounce triggering slide, `ENC_EVT_CLICK` enters sub-UI via `ui_manager_set_ui(menu_pages[sel].target_ui)`, drain encoder queue after page switch
    - _Requirements: 4.1, 4.2, 4.3, 5.1, 5.2, 6.1, 6.2_

  - [ ]* 4.6 Write property test for circular page wrap (Property 4)
    - **Property 4: Circular page wrap**
    - For any integer i, `wrap_page(i)` returns a value in [0, MENU_PAGE_COUNT-1] and `wrap_page(i + MENU_PAGE_COUNT) == wrap_page(i)`
    - **Validates: Requirements 4.4**

  - [ ]* 4.7 Write property test for bitmap centering computation (Property 1)
    - **Property 1: Bitmap centering computation**
    - For any valid bitmap width w in [1, 240], `(240 - w) / 2` produces X such that the bitmap midpoint is within 1 pixel of screen center (120)
    - **Validates: Requirements 1.1, 1.3**

- [x] 5. Checkpoint — Verify static rendering works
  - Ensure the project compiles and static page rendering is correct, ask the user if questions arise.

- [x] 6. Implement slide transition animation
  - [x] 6.1 Implement `blit_clipped(const uint16_t *data, uint16_t w, uint16_t h, int16_t x, uint16_t y)` — handle partial off-screen blitting: skip if fully off-screen (`x + w <= 0` or `x >= 240`), compute `src_x_offset`, `dst_x`, `visible_w`, blit row-by-row via `drv_lcd_blit_rgb565()`
    - _Requirements: 2.2, 2.3_

  - [x] 6.2 Implement `do_slide_animation(uint8_t cur_page, int8_t direction)` — compute new page via `wrap_page()`, update dots immediately, run 8-frame loop: compute linear progress `frame * 240 / (MENU_ANIM_FRAMES - 1)`, clear animation zone with `drv_lcd_fill_rect()`, blit outgoing + incoming icon+text at interpolated X positions using `blit_clipped()`, delay `MENU_ANIM_FRAME_DELAY` ms per frame, draw final static page, return new page index
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.4_

  - [x] 6.3 Wire `do_slide_animation()` into `ui_menu_update()` encoder rotation handler — when threshold + debounce met, call `do_slide_animation()`, update `g_app_state.menu_selected`, drain encoder queue, reset accumulator and timestamp
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ]* 6.4 Write property test for animation position interpolation (Property 2)
    - **Property 2: Animation position interpolation**
    - For any frame f in [0, 7] and direction d in {-1, +1}, displacement = `f * 240 / 7`, outgoing moves away from center, incoming moves toward center, frame 0 starts at origin, frame 7 ends centered
    - **Validates: Requirements 2.2, 2.4**

  - [ ]* 6.5 Write property test for encoder trigger condition (Property 3)
    - **Property 3: Encoder trigger condition**
    - For any accumulator value a and time delta t, page switch triggers iff `|a| >= MENU_DELTA_THRESHOLD` AND `t >= MENU_SWITCH_DEBOUNCE_MS`
    - **Validates: Requirements 4.1**

- [x] 7. Final checkpoint — Ensure all tests pass
  - Ensure the project compiles cleanly with all changes, verify no linker errors with 12 bitmap arrays, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The F4 bitmap arrays are `const unsigned char[]` — cast to `const uint16_t*` in the lookup table
- All layout magic numbers come from `board_config.h` constants
- `ui_menu.h` and `ui_manager.c` remain unchanged — the public API (`ui_menu_enter`/`ui_menu_update`) is preserved
- Property tests validate universal correctness properties from the design document
