# Requirements Document

## Introduction

Redesign the ridewind-esp main menu screen (UI5) from the current text-only scanline compositing approach to a full-screen single-page menu with bitmap icon + text blit and slide transition animation, targeting the 240×240 round GC9A01 LCD. The design reuses the F4 STM32 project's existing icon and text bitmap arrays (12 arrays: 6 icons + 6 text labels), with the same layout parameters (icon center Y=90, text Y=155, dots Y=205), adding a smooth slide-in/slide-out transition animation that the F4 version lacks.

## Glossary

- **Menu_Renderer**: The UI5 menu rendering module (`ui_menu.c`) responsible for drawing icons, text labels, navigation dots, and slide animations on the LCD.
- **Icon_Bitmap**: A const RGB565 bitmap array for a menu page icon graphic (e.g., `gImage_fengsu_68_58` for Speed, sizes vary per icon: 68×58, 74×74, 65×68, 72×72, 68×68, 73×58).
- **Text_Bitmap**: A const RGB565 bitmap array for a menu page text label (e.g., `gImage_speed_99_33` for "Speed", sizes vary per label: 99×33, 88×31, 72×27, 103×33, 79×33, 90×27).
- **Menu_Page**: One of the 6 selectable menu entries: Speed (→UI1), Color (→UI2), RGB (→UI3), Bright (→UI4), Logo (→UI6), Volume (→UI7).
- **Slide_Animation**: The animated transition between menu pages where the current icon+text slides out horizontally while the new icon+text slides in from the opposite side, using 8 frames at 12ms intervals (~96ms total).
- **Navigation_Dots**: A row of 6 indicator dots at Y=205 showing which Menu_Page is currently selected.
- **Encoder_Accumulator**: The mechanism that sums rotary encoder deltas and triggers a page switch when the accumulated value reaches ±2 with at least 150ms since the last switch.
- **GC9A01_LCD**: The 240×240 round SPI LCD display with an effective visible diameter of approximately 200 pixels.

## Requirements

### Requirement 1: Static Page Rendering

**User Story:** As a user, I want to see a centered icon and text label on the menu screen, so that I can identify the current menu selection clearly.

#### Acceptance Criteria

1. THE Menu_Renderer SHALL display the current Menu_Page by blitting the Icon_Bitmap horizontally centered at icon center Y=90 and the Text_Bitmap horizontally centered at text Y=155.
2. THE Menu_Renderer SHALL use `drv_lcd_blit_rgb565` to draw each bitmap directly from the const Flash array without copying to RAM.
3. THE Menu_Renderer SHALL support 6 Menu_Pages with varying icon sizes (68×58, 74×74, 65×68, 72×72, 68×68, 73×58) and text sizes (99×33, 88×31, 72×27, 103×33, 79×33, 90×27), centering each individually.
4. WHEN the menu screen is entered, THE Menu_Renderer SHALL clear the full screen to black and draw the static page for the currently selected Menu_Page.

### Requirement 2: Slide Transition Animation

**User Story:** As a user, I want a smooth sliding animation when I rotate the encoder, so that the menu transition feels responsive and polished rather than an abrupt page swap.

#### Acceptance Criteria

1. WHEN a page switch is triggered, THE Menu_Renderer SHALL animate the transition using 8 frames with 12ms delay between frames, completing in approximately 96ms.
2. THE Menu_Renderer SHALL slide the outgoing icon+text horizontally off-screen in the scroll direction while simultaneously sliding the incoming icon+text in from the opposite side.
3. FOR each animation frame, THE Menu_Renderer SHALL clear the icon zone (Y=50 to Y=190) with `drv_lcd_fill_rect` then blit both the outgoing and incoming icon+text at their interpolated X positions.
4. THE Menu_Renderer SHALL use linear interpolation to calculate horizontal positions across the 8 animation frames, with a total displacement of 240 pixels (full screen width).
5. WHEN the Slide_Animation completes, THE Menu_Renderer SHALL render the final static page with the new icon+text centered.

### Requirement 3: Navigation Dots

**User Story:** As a user, I want to see indicator dots showing which page is selected out of the total, so that I know my position in the menu.

#### Acceptance Criteria

1. THE Menu_Renderer SHALL display 6 Navigation_Dots at Y=205 with 15 pixels horizontal spacing, centered on the screen (matching F4's MENU_DOT_SPACING).
2. THE Menu_Renderer SHALL render the active dot as a filled white (0xFFFF) circle with radius 3 pixels.
3. THE Menu_Renderer SHALL render inactive dots as filled dark gray (0x4208) circles with radius 3 pixels (matching F4's MENU_DOT_INACTIVE color).
4. WHEN a page switch is triggered, THE Menu_Renderer SHALL update the Navigation_Dots to reflect the new selection before the Slide_Animation begins.

### Requirement 4: Encoder Navigation

**User Story:** As a user, I want to rotate the encoder to scroll through menu pages, so that I can navigate to the desired setting.

#### Acceptance Criteria

1. WHEN the Encoder_Accumulator reaches a magnitude of 2 or greater AND at least 150ms have elapsed since the last page switch, THE Menu_Renderer SHALL trigger a page switch in the accumulated direction.
2. WHEN a page switch is triggered, THE Menu_Renderer SHALL reset the Encoder_Accumulator to zero and record the current timestamp.
3. WHEN a page switch is triggered, THE Menu_Renderer SHALL drain all pending encoder events from the queue to prevent over-scrolling.
4. THE Menu_Renderer SHALL wrap menu navigation circularly so that scrolling past page 6 returns to page 1, and scrolling before page 1 goes to page 6.

### Requirement 5: Menu Item Selection via Click

**User Story:** As a user, I want to click the encoder button to enter the selected sub-UI, so that I can access the corresponding settings screen.

#### Acceptance Criteria

1. WHEN an `ENC_EVT_CLICK` event is received, THE Menu_Renderer SHALL transition to the sub-UI corresponding to the currently selected Menu_Page.
2. THE Menu_Renderer SHALL map the 6 Menu_Pages to target UIs as follows: Speed→UI1, Color→UI2, RGB→UI3, Bright→UI4, Logo→UI6, Volume→UI7.

### Requirement 6: BLE Auto-Enter

**User Story:** As a user, I want BLE commands to automatically enter a specific sub-UI from the menu, so that the companion app can navigate the device remotely.

#### Acceptance Criteria

1. WHEN the `auto_enter` flag in AppState is set, THE Menu_Renderer SHALL immediately transition to the sub-UI corresponding to the current `menu_selected` value and clear the `auto_enter` flag.
2. THE Menu_Renderer SHALL check the `auto_enter` flag before processing encoder input on each update cycle.

### Requirement 7: Icon and Text Data from F4 Bitmap Arrays

**User Story:** As a developer, I want to reuse the existing F4 STM32 bitmap arrays for menu icons and text, so that no new artwork needs to be created.

#### Acceptance Criteria

1. THE Menu_Renderer SHALL include the 12 existing F4 bitmap arrays (6 icons + 6 text labels) from the `ridewind-esp/取模数组/` directory as const data in `menu_icons.h`.
2. THE Menu_Renderer SHALL store a lookup table mapping each Menu_Page index to its icon array, icon width, icon height, text array, text width, and text height.
3. THE total Flash footprint for all 12 bitmap arrays SHALL be approximately 50-60KB.

### Requirement 8: Board Configuration Constants

**User Story:** As a developer, I want all menu layout constants defined in board_config.h, so that layout parameters are centralized and easy to tune.

#### Acceptance Criteria

1. THE board configuration SHALL define constants for: icon center Y (90), text Y (155), dot Y (205), dot spacing (15), dot radius (3), dot active color (0xFFFF), dot inactive color (0x4208), animation frame count (8), animation frame delay (12ms), encoder accumulation threshold (2), and encoder debounce interval (150ms).
2. THE Menu_Renderer SHALL use the board configuration constants instead of hardcoded magic numbers for all layout and timing parameters.
