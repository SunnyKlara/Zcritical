# Implementation Plan: STM32-to-ESP32-S3 Migration

## Overview

Migrate the RideWind smart LED fan controller firmware from STM32F405 to ESP32-S3 using ESP-IDF v5.3.5. The implementation follows an 11-phase incremental plan (Phase 0–10), where each phase builds on the previous one and ends with integration verification. All code is C targeting ESP-IDF with Bluedroid dual-mode Bluetooth.

## Tasks

- [x] 1. Phase 0 — Project Skeleton, Partition Table, Config Headers, AppState
  - [x] 1.1 Create ESP-IDF project structure and CMakeLists.txt
    - Create `ridewind-esp/` as an ESP-IDF project with top-level `CMakeLists.txt` and `main/CMakeLists.txt`
    - Register all source directories (drivers/, services/, ui/, app/, config/, resources/) in `main/CMakeLists.txt` SRCS
    - Add `idf_component.yml` with ESP-IDF v5.3.5 dependencies
    - _Requirements: 1.1, 26.1_

  - [x] 1.2 Create custom partition table CSV
    - Create `ridewind-esp/partitions.csv` with: nvs(24KB), otadata(8KB), phy_init(4KB), ota_0(2.5MB), ota_1(2.5MB), storage/LittleFS(2MB), coredump(64KB)
    - Set `CONFIG_PARTITION_TABLE_CUSTOM=y` and `CONFIG_PARTITION_TABLE_CUSTOM_FILENAME` in `sdkconfig.defaults`
    - _Requirements: 1.2_

  - [x] 1.3 Create config headers (pin_config.h, board_config.h, preset_colors.h)
    - Create `main/config/pin_config.h` with all GPIO definitions: LCD(SCL=IO7, SDA=IO6, DC=IO5, CS=IO4), LED(IO41×10, IO16×3), Encoder(A=IO17, B=IO18, KEY=IO8), Fan(IO40), Humidifier(IO10), Audio(DIN=IO13, BCLK=IO12, LRC=IO11)
    - Create `main/config/board_config.h` with all timing constants from design (MAIN_TASK_PERIOD_MS, BUTTON_TIMEOUT_MS, etc.)
    - Create `main/config/preset_colors.h` with the 14 color presets `color_preset_t` array
    - _Requirements: 1.1, 26.1_

  - [x] 1.4 Implement AppState struct and mutex (app_state.c/h)
    - Create `main/app/app_state.h` with the full `app_state_t` struct, extern globals, and lock/unlock macros per design §12
    - Create `main/app/app_state.c` with `app_state_init()` that creates the mutex and sets factory defaults
    - Factory defaults: Main(150,20,0), Left(255,0,0), Right(33,126,222), Tail(255,0,0), brightness=100, volume=50, preset=1, unit=km/h
    - _Requirements: 1.4, 21.3, 24.5_

  - [x] 1.5 Create main.c entry point skeleton
    - Create `main/main.c` with `app_main()` that calls `app_state_init()`, creates `cmd_queue` (32 items), and stubs for phase-by-phase init calls
    - Define the Main_Task function pinned to Core 1 with 20ms period loop (empty body for now)
    - _Requirements: 1.3, 24.2, 24.4_

  - [ ]* 1.6 Write property test for AppState defaults (Property 7: bounded value clamping)
    - **Property 7: Encoder-Adjusted Bounded Value Clamping**
    - Verify that for any current value in [min, max] and any delta, the clamped result stays in [min, max]
    - Create `test/property/test_prop_values.c` with the clamping property test
    - **Validates: Requirements 9.1, 12.1, 15.1, 11.6, 5.2**

- [x] 2. Phase 0 Checkpoint
  - Ensure project compiles with `idf.py build`, partition table is valid, AppState initializes correctly. Ask the user if questions arise.

- [x] 3. Phase 1 — LCD Driver (GC9A01 SPI with DMA)
  - [x] 3.1 Implement drv_lcd.h interface header
    - Create `main/drivers/drv_lcd.h` with all function declarations per design §1: init, fill_rect, draw_circle, draw_line, draw_char, draw_string, draw_number, blit_rgb565, blit_rgb565_dma, set_window, write_data, clear, set_backlight
    - _Requirements: 2.1, 2.3_

  - [x] 3.2 Implement drv_lcd.c SPI initialization and GC9A01 command sequence
    - Configure SPI2_HOST with DMA channel, SCL=IO7, SDA=IO6, DC=IO5, CS=IO4
    - Implement GC9A01 initialization command sequence (sleep out, display on, pixel format RGB565, memory access control)
    - Implement `drv_lcd_set_window()` and `drv_lcd_write_data()` for region-based updates
    - _Requirements: 2.1, 2.2_

  - [x] 3.3 Implement LCD drawing primitives
    - Implement `drv_lcd_fill_rect()`, `drv_lcd_draw_circle()`, `drv_lcd_draw_line()` using set_window + write_data
    - Implement `drv_lcd_draw_char()` and `drv_lcd_draw_string()` using font_8x16.h bitmap font
    - Implement `drv_lcd_draw_number()` for numeric display
    - Implement `drv_lcd_clear()` as full-screen fill_rect
    - _Requirements: 2.3, 2.5_

  - [x] 3.4 Implement DMA-based image blitting
    - Implement `drv_lcd_blit_rgb565()` (blocking) and `drv_lcd_blit_rgb565_dma()` (non-blocking) for full-screen and partial image transfers
    - Ensure full 240×240 frame transfer completes within 50ms
    - _Requirements: 2.4, 2.5_

  - [x] 3.5 Create resource headers (font_8x16.h, default_logo.h, menu_icons.h)
    - Create `main/resources/font_8x16.h` with 8×16 bitmap font array for ASCII printable characters
    - Create `main/resources/default_logo.h` with default boot logo as const RGB565 array (154×154 or 240×240)
    - Create `main/resources/menu_icons.h` with 6 menu page icon arrays (speed, color, RGB, brightness, logo, volume)
    - _Requirements: 2.3, 8.1_

  - [ ]* 3.6 Write unit tests for LCD drawing primitives
    - Test fill_rect boundary conditions (0×0, 240×240, partial regions)
    - Test draw_char with printable ASCII range
    - Test set_window coordinate clamping
    - _Requirements: 2.2, 2.3_

- [x] 4. Phase 1 Checkpoint
  - Ensure LCD initializes, displays a test pattern and the default boot logo. Ask the user if questions arise.

- [x] 5. Phase 2 — WS2812B LED Driver (RMT, 2 strips, 4 logical)
  - [x] 5.1 Implement drv_led.h interface header
    - Create `main/drivers/drv_led.h` with `led_strip_id_t` enum, strip count defines, and all function declarations per design §2
    - _Requirements: 3.1, 3.2_

  - [x] 5.2 Implement drv_led.c with RMT peripheral
    - Initialize two RMT TX channels: channel 0 on IO41 (10 LEDs), channel 1 on IO16 (3 LEDs)
    - Implement `drv_led_set_pixel()` for physical strip/index addressing
    - Implement `drv_led_set_strip_color()` with logical-to-physical mapping: Left→Strip1[0:1], Main→Strip1[2:7], Right→Strip1[8:9], Tail→Strip2[0:2]
    - Implement `drv_led_set_brightness()` and `drv_led_refresh()` with brightness scaling before RMT transmit
    - Ensure complete LED data transmission within 5ms
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ]* 5.3 Write property tests for LED driver (Properties 4, 5)
    - **Property 4: Logical Strip to Physical LED Mapping** — verify correct physical indices for each logical strip
    - **Property 5: Brightness Scaling** — verify `(r × brightness / 100)` stays in [0, 255] for all inputs
    - Create `test/property/test_prop_led.c`
    - **Validates: Requirements 3.2, 3.3**

- [x] 6. Phase 2 Checkpoint
  - Ensure all 13 LEDs light up with correct colors per logical strip. Ask the user if questions arise.

- [x] 7. Phase 3 — Encoder Driver (PCNT + Button State Machine)
  - [x] 7.1 Implement drv_encoder.h interface header
    - Create `main/drivers/drv_encoder.h` with `encoder_event_type_t` enum, `encoder_event_t` struct, and function declarations per design §3
    - _Requirements: 4.1, 4.2_

  - [x] 7.2 Implement drv_encoder.c with PCNT rotation and GPIO button
    - Configure PCNT unit for quadrature decoding on A=IO17, B=IO18 with glitch filter for debounce
    - Implement `drv_encoder_poll()` that reads PCNT counter delta and resets, returning `ENC_EVT_ROTATE` events
    - Implement GPIO input for KEY=IO8 (active low, internal pull-up)
    - _Requirements: 4.1, 4.4, 4.5_

  - [x] 7.3 Implement encoder_handler.c button state machine
    - Create `main/app/encoder_handler.h` and `main/app/encoder_handler.c` per design §14
    - Implement multi-click detection: single click (<400ms), double click (2 within 400ms), triple click (3 within 400ms), long press (>800ms)
    - Use 400ms timeout after last click to determine final click count before dispatching
    - Implement `drv_encoder_button_pressed()` for raw button state (throttle mode)
    - Integrate button events into `drv_encoder_poll()` output
    - _Requirements: 4.2, 4.3, 4.5_

  - [ ]* 7.4 Write property tests for encoder (Properties 6, 8, 9)
    - **Property 6: Button Event Classification** — verify correct classification for random press/release sequences with timestamps
    - **Property 8: Boolean State Toggle** — verify toggle involution (toggle twice = original)
    - **Property 9: Cyclic Index Wrapping** — verify wrap-around for preset (1–14) and menu (1–6) indices
    - Create `test/property/test_prop_encoder.c` and extend `test/property/test_prop_values.c`
    - **Validates: Requirements 4.2, 4.3, 9.2, 10.1, 10.2, 12.2, 13.2**

- [x] 8. Phase 3 Checkpoint
  - Ensure encoder rotation produces correct deltas, button clicks are classified correctly. Ask the user if questions arise.

- [x] 9. Phase 4 — Fan PWM (LEDC) + Humidifier GPIO
  - [x] 9.1 Implement drv_pwm.c/h (Fan LEDC PWM)
    - Create `main/drivers/drv_pwm.h` and `main/drivers/drv_pwm.c` per design §4
    - Configure LEDC timer at 1kHz on IO40
    - Implement `drv_pwm_set_duty(percent)` mapping 0–100 to LEDC duty cycle
    - _Requirements: 5.1, 5.2_

  - [x] 9.2 Implement drv_gpio.c/h (Humidifier GPIO)
    - Create `main/drivers/drv_gpio.h` and `main/drivers/drv_gpio.c` per design §5
    - Configure IO10 as GPIO output, implement `drv_gpio_set_humidifier(enable)` for high/low control
    - _Requirements: 5.3, 5.4_

- [x] 10. Phase 4 Checkpoint
  - Ensure fan speed responds to duty cycle changes, humidifier toggles on/off. Ask the user if questions arise.

- [x] 11. Phase 5 — BLE Communication + Protocol Parser + Message Queue
  - [x] 11.1 Implement protocol.c/h command parser and formatter
    - Create `main/services/protocol.h` with `cmd_type_t` enum, `cmd_msg_t` struct, and function declarations per design §9
    - Implement `protocol_parse()` for all 20+ command types: FAN, SPEED, WUHUA, LED, PRESET, BRIGHT, UI, LCD, UNIT, THROTTLE, STREAMLIGHT, LED_GRADIENT, VOL, GET:xxx, LOGO_START/DATA/END, OTA_START/DATA/END
    - Implement `protocol_format_response()` with `\r\n` termination for acknowledgments
    - Implement `protocol_format_report()` with `\n` termination for event reports
    - Implement `protocol_format_cmd()` for round-trip testing
    - Handle malformed commands: return false with CMD_NONE, no side effects
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [ ]* 11.2 Write property tests for protocol parser (Properties 1, 2, 3)
    - **Property 1: Protocol Round-Trip** — parse → format → parse produces equivalent cmd_msg_t
    - **Property 2: Malformed Command Rejection** — random byte strings that don't match valid formats return false/CMD_NONE
    - **Property 3: Response Line Termination** — acknowledgments end with `\r\n`, reports end with `\n`
    - Create `test/property/test_prop_protocol.c`
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**

  - [x] 11.3 Implement ble_service.c/h (Bluedroid GATTS)
    - Create `main/services/ble_service.h` and `main/services/ble_service.c` per design §7
    - Initialize Bluedroid controller and enable BLE mode
    - Register GATTS application with Service UUID 0xFFE0, Characteristic UUID 0xFFE1 (write-without-response + notify)
    - Implement advertising with device name "T1"
    - Implement write callback: receive data, handle MTU fragmentation (reassemble until `\n`), call `protocol_parse()`, send `cmd_msg_t` to `cmd_queue` via `xQueueSend()`
    - Implement `ble_service_notify()` and `ble_service_notify_str()` for sending responses/reports
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 11.4 Implement BLE command dispatch in Main_Task
    - In `main.c` Main_Task loop, dequeue `cmd_msg_t` from `cmd_queue` with `xQueueReceive()`
    - Implement command dispatch switch: apply each command type to AppState (FAN→drv_pwm, SPEED→speed, WUHUA→humidifier, LED→led_colors, PRESET→preset, BRIGHT→brightness, UI→ui_manager, etc.)
    - Send appropriate OK/ERR responses via `ble_service_notify_str()`
    - Implement GET:xxx handlers that read AppState and send formatted responses
    - _Requirements: 6.2, 6.3, 6.4, 24.4_

  - [ ]* 11.5 Write property test for BLE fragmentation (Property 19)
    - **Property 19: BLE Fragmentation Reassembly** — verify that any valid command split at arbitrary 20-byte boundaries reassembles correctly
    - Create `test/property/test_prop_ble.c`
    - **Validates: Requirements 6.5**

- [x] 12. Phase 5 Checkpoint
  - Ensure BLE advertising works with name "T1", app can connect, send commands (FAN, LED, PRESET, BRIGHT), and receive OK responses. Ask the user if questions arise.

- [x] 13. Phase 6 — UI State Machine + LED Effects
  - [x] 13.1 Implement ui_common.c/h shared drawing utilities
    - Create `main/ui/ui_common.h` and `main/ui/ui_common.c`
    - Implement shared helpers: progress bar drawing, dot indicator (red/green), slider bar, value display with units
    - Implement screen clear and transition helpers (clear encoder delta on UI switch per Property 12)
    - _Requirements: 13.4, 26.2_

  - [x] 13.2 Implement ui_manager.c/h state machine dispatcher
    - Create `main/ui/ui_manager.h` and `main/ui/ui_manager.c` per design §15
    - Implement `ui_manager_init()`, `ui_manager_update()` (called every 20ms), `ui_manager_set_ui()`, `ui_manager_get_ui()`
    - Dispatch to per-screen update functions based on `g_app_state.ui`
    - Clear encoder_delta on every UI transition
    - _Requirements: 13.4, 24.2_

  - [x] 13.3 Implement ui_menu.c/h (UI5 — Sliding Menu)
    - Implement 6-page sliding menu with icons: Speed(UI1), Presets(UI2), RGB(UI3), Brightness(UI4), Logo(UI6), Volume(UI7)
    - Implement smooth slide animation on encoder rotation with debounce (MENU_SWITCH_DEBOUNCE_MS=150, MENU_DELTA_THRESHOLD=2)
    - Single-click enters the selected UI: menu_selected 1→UI1, 2→UI2, 3→UI3, 4→UI4, 5→UI6, 6→UI7
    - _Requirements: 13.1, 13.2, 13.3_

  - [ ]* 13.4 Write property test for menu dispatch (Property 11)
    - **Property 11: Menu Click Dispatches Correct UI** — for any menu_selected in {1..6}, click transitions to correct UI
    - Extend `test/property/test_prop_ui.c`
    - **Validates: Requirements 13.3**

  - [x] 13.5 Implement ui_speed.c/h (UI1 — Speed Control + Throttle Mode)
    - Implement speed display (0–340 km/h or 0–211 mph) with large number rendering
    - Encoder rotation adjusts speed, single-click toggles unit (km/h↔mph) and sends UNIT_REPORT
    - Double-click saves and returns to UI5
    - Triple-click enters Throttle_Mode: hold button accelerates (18ms/step), release decelerates (12ms/step), rotate exits throttle
    - Synchronize fan PWM proportionally to displayed speed via `drv_pwm_set_duty()`
    - Support remote freeze/unfreeze from BLE THROTTLE command
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8_

  - [x] 13.6 Implement ui_preset.c/h (UI2 — Color Presets + Streamlight)
    - Implement preset cycling (1–14) on encoder rotation, applying colors to LED strips in real time
    - Single-click toggles Streamlight effect on/off
    - Double-click saves preset + streamlight state to NVS and returns to UI5
    - Rotation while Streamlight active: deactivate Streamlight, switch to new preset in static mode
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [x] 13.7 Implement ui_rgb.c/h (UI3 — 3-Layer RGB Custom)
    - Implement 3-layer state machine: Layer 0 (select strip 0–3), Layer 1 (select channel R/G/B), Layer 2 (adjust value 0–255 by ±2/step)
    - Layer 0: red dot indicator on selected strip; Layer 1/2: green dot on selected channel
    - Single-click advances layer (0→1→1→2→1); double-click at any layer saves all RGB to NVS and returns to UI5
    - On enter: deactivate Streamlight and Breathing_Effect (RGB custom has highest priority)
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_

  - [ ]* 13.8 Write property test for UI3 state machine (Property 10)
    - **Property 10: UI3 State Machine Transitions** — verify click transitions (0→1, 1→2, 2→1) and rotation behavior per layer
    - Extend `test/property/test_prop_ui.c`
    - **Validates: Requirements 11.1, 11.4**

  - [x] 13.9 Implement ui_bright.c/h (UI4 — Brightness + Breathing Effect)
    - Implement brightness adjustment (0–100) on encoder rotation when Breathing off
    - Single-click toggles Breathing_Effect on/off
    - Double-click saves brightness + breath state to NVS and returns to UI5
    - Breathing continues in background after leaving UI4 (until entering UI2 or UI3)
    - _Requirements: 12.1, 12.2, 12.3, 12.5, 12.6_

  - [x] 13.10 Implement ui_logo.c/h (UI6 — Logo Management)
    - Display currently selected Logo_Slot image, encoder rotation switches between occupied slots
    - Single-click sets current slot as active boot logo in NVS
    - Long-press (≥2s) deletes current slot from LittleFS with progress bar
    - Double-click returns to UI5
    - _Requirements: 14.1, 14.2, 14.3, 14.4_

  - [x] 13.11 Implement ui_volume.c/h (UI7 — Volume Control)
    - Implement volume adjustment (0–100) on encoder rotation, apply to Audio_Service in real time
    - Double-click saves volume to NVS and returns to UI5
    - _Requirements: 15.1, 15.2_

  - [x] 13.12 Implement led_effects.c/h (Gradient, Streamlight, Breathing, Priority)
    - Create `main/app/led_effects.h` and `main/app/led_effects.c` per design §13
    - Implement `led_effects_process()` called every 20ms from Main_Task
    - Implement gradient transition: linear interpolation with 3 speed modes (fast=25 steps/0.5s, normal=75/1.5s, slow=150/3.0s)
    - Implement gradient restart from current interpolated color (Property 15)
    - Implement Streamlight: cycle through 14 presets at 30ms/frame with 100 interpolation steps per transition
    - Implement Breathing: sine wave brightness modulation, range 0.6–1.0, 3-second period, 50fps
    - Implement priority resolution: RGB Custom > Breathing > Streamlight > Static
    - _Requirements: 16.1, 16.2, 16.3, 17.1, 17.2, 17.3, 10.4, 12.4_

  - [ ]* 13.13 Write property tests for LED effects (Properties 13, 14, 15, 20, 21)
    - **Property 13: LED Effect Priority Resolution** — verify correct priority for all combinations of active effects
    - **Property 14: Linear Color Interpolation** — verify interpolation formula and boundary conditions (step 0 = start, step N = target)
    - **Property 15: Gradient Restart from Current Color** — verify new gradient starts from current interpolated color
    - **Property 20: Breathing Effect Sine Wave Range** — verify scale factor always in [0.6, 1.0]
    - **Property 21: Streamlight Interpolation Completeness** — verify exactly 100 steps between consecutive presets
    - Extend `test/property/test_prop_led.c`
    - **Validates: Requirements 16.1, 16.2, 16.3, 17.1, 17.3, 12.4, 10.4**

  - [x] 13.14 Implement UI0 boot logo display
    - In `ui_manager_init()` or `main.c` boot sequence: read active Logo_Slot from NVS, display logo (or default) for 2 seconds, then transition to UI5
    - Suppress engine sound and taillight flash during boot
    - _Requirements: 8.1, 8.2, 8.3, 25.1, 25.4_

  - [ ]* 13.15 Write property test for encoder delta clear (Property 12)
    - **Property 12: Encoder Delta Cleared on UI Transition** — verify encoder_delta is 0 after any UI transition
    - Extend `test/property/test_prop_ui.c`
    - **Validates: Requirements 13.4**

- [x] 14. Phase 6 Checkpoint
  - Ensure all 8 UI screens render correctly, encoder navigation works, LED effects (gradient, streamlight, breathing) function, and priority system resolves correctly. Ask the user if questions arise.

- [x] 15. Phase 7 — Audio Pipeline (A2DP Sink + MP3 Decode + Mixer + I2S)
  - [x] 15.1 Implement drv_audio.c/h (I2S output to MAX98357)
    - Create `main/drivers/drv_audio.h` and `main/drivers/drv_audio.c` per design §6
    - Configure I2S with 44100Hz, 16-bit stereo on DIN=IO13, BCLK=IO12, LRC=IO11
    - Implement `drv_audio_write()` for blocking DMA write, `drv_audio_set_volume()`, `drv_audio_stop()`
    - _Requirements: 18.2, 20.4_

  - [x] 15.2 Implement wifi_audio_service.c/h (WiFi SoftAP + TCP PCM streaming)
    - Create `main/services/wifi_audio_service.h` and `main/services/wifi_audio_service.c`
    - ESP32-S3 does NOT support Classic BT (no A2DP). Use WiFi audio instead.
    - Initialize SoftAP "T1_Audio" (pw "12345678"), TCP server on port 8080
    - Accept client connections, receive raw 44100Hz 16-bit stereo PCM
    - Feed received PCM to `audio_engine_feed_a2dp_pcm()` ring buffer
    - Android APP captures system audio via AudioPlaybackCapture and streams via TCP
    - _Requirements: 18.1, 18.2, 18.3, 18.4_

  - [x] 15.3 Implement audio_engine.c/h (MP3 decode + ring buffers + mixer)
    - Create `main/services/audio_engine.h` and `main/services/audio_engine.c` per design §11
    - Implement A2DP PCM ring buffer and engine PCM ring buffer
    - Implement software MP3 decoder for local engine sound files (engine_start.mp3, engine_accel.mp3)
    - Implement `audio_engine_play_start_sound()` and `audio_engine_start_throttle()` / `audio_engine_stop_throttle()`
    - Implement mixer: throttle mode = engine×1.0 + BT×0.2; normal mode = BT×1.0
    - Apply master volume (0–100) and clamp to [-32768, 32767] to prevent clipping
    - Implement `audio_engine_start_task()` to create Audio_Output_Task on Core 1 (priority 6)
    - _Requirements: 19.1, 19.2, 19.3, 20.1, 20.2, 20.3, 20.4, 20.5_

  - [ ]* 15.4 Write property test for audio mixer (Property 16)
    - **Property 16: Audio Mixer Weighted Sum with Clipping Prevention** — verify mixer output formula and clamping for random PCM samples, throttle flag, and volume
    - Create `test/property/test_prop_audio.c`
    - **Validates: Requirements 20.1, 20.2, 20.3, 20.4, 20.5**

  - [x] 15.5 Wire audio into Main_Task and Throttle_Mode
    - Connect Throttle_Mode activation/deactivation in ui_speed.c to `audio_engine_set_throttle_mode()`
    - Connect volume changes in ui_volume.c to `audio_engine_set_volume()`
    - Connect BLE VOL command dispatch to `audio_engine_set_volume()`
    - _Requirements: 19.2, 19.3, 20.2, 20.3_

- [x] 16. Phase 7 Checkpoint
  - Ensure A2DP streaming works from phone, engine sounds play during throttle mode, mixer blends correctly, volume control works. Ask the user if questions arise.

- [x] 17. Phase 8 — NVS Persistent Storage
  - [x] 17.1 Implement storage.c/h NVS operations
    - Create `main/services/storage.h` and `main/services/storage.c` per design §10
    - Implement `storage_init()` to mount NVS partition
    - Implement `storage_load_settings()` to read all NVS keys (led_m_rgb, led_l_rgb, led_r_rgb, led_t_rgb, brightness, volume, preset, speed_unit, streamlight, breath_mode, logo_slot) into `nvs_settings_t`
    - If keys don't exist (first boot), return factory defaults per Requirement 21.3
    - Implement `storage_save_settings()` to write all settings to NVS
    - _Requirements: 21.1, 21.2, 21.3, 21.4_

  - [x] 17.2 Wire NVS into boot sequence and UI save points
    - In `main.c` boot: call `storage_load_settings()` and populate AppState before UI rendering
    - In each UI double-click exit handler (UI1–UI4, UI6, UI7): call `storage_save_settings()` with current AppState values
    - _Requirements: 21.2, 21.4, 25.1, 25.2_

  - [ ]* 17.3 Write property test for NVS round-trip (Property 17)
    - **Property 17: NVS Settings Round-Trip** — verify save then load produces identical `nvs_settings_t` for any valid settings
    - Create `test/property/test_prop_storage.c`
    - **Validates: Requirements 21.1**

- [x] 18. Phase 8 Checkpoint
  - Ensure settings persist across simulated power cycles: change LED color, brightness, volume, reboot, verify values restored. Ask the user if questions arise.

- [x] 19. Phase 9 — LittleFS + Logo Upload/Display
  - [x] 19.1 Implement storage.c LittleFS mount and logo file operations
    - Extend `main/services/storage.c` to mount LittleFS on the 2MB `storage` partition
    - Implement `storage_logo_exists()`, `storage_logo_read()`, `storage_logo_write()`, `storage_logo_delete()`
    - Implement logo file format: 16-byte `logo_header_t` (magic 0xAA55, 240×240, data_size, CRC32) + pixel data
    - Validate CRC32 on write; reject and leave slot unchanged if CRC mismatch
    - Implement `storage_logo_count_valid()` and `storage_logo_find_empty()`
    - _Requirements: 22.1, 22.2, 22.3, 22.4_

  - [x] 19.2 Implement storage.c MP3 file access
    - Implement `storage_mp3_read()` to load engine_start.mp3 and engine_accel.mp3 from LittleFS into memory
    - _Requirements: 22.5_

  - [x] 19.3 Implement BLE logo upload protocol in command dispatch
    - Handle LOGO_START: begin receiving, allocate buffer for incoming data
    - Handle LOGO_DATA: accumulate hex-decoded data packets
    - Handle LOGO_END: validate CRC32, write to slot via `storage_logo_write()`, respond OK or ERR:CRC
    - Handle LOGO_DELETE: delete slot via `storage_logo_delete()`
    - _Requirements: 22.3, 22.4_

  - [x] 19.4 Wire logo display into UI0 boot and UI6 management
    - Update UI0 boot: read active logo slot from NVS, load from LittleFS, display via `drv_lcd_blit_rgb565()`; fall back to default_logo.h if no custom logo
    - Update UI6: load and display logo images from LittleFS slots, support slot switching, deletion with progress bar
    - _Requirements: 8.1, 8.3, 14.1, 14.2, 14.3_

  - [ ]* 19.5 Write property test for logo storage (Property 18)
    - **Property 18: Logo Storage Round-Trip with CRC Validation** — verify write then read returns identical data; corrupted CRC is rejected
    - Extend `test/property/test_prop_storage.c`
    - **Validates: Requirements 22.2, 22.3, 22.4**

- [ ] 20. Phase 9 Checkpoint
  - Ensure logo upload via BLE works, logos display on boot and in UI6, CRC validation rejects corrupted data, MP3 files load from LittleFS. Ask the user if questions arise.

- [ ] 21. Phase 10 — OTA Firmware Upgrade
  - [ ] 21.1 Implement OTA service in command dispatch
    - Extend BLE command dispatch in `main.c` to handle OTA_START, OTA_DATA, OTA_END
    - On OTA_START: begin ESP-IDF OTA session with `esp_ota_begin()` targeting the inactive partition
    - On OTA_DATA: write hex-decoded data to OTA partition with `esp_ota_write()`
    - On OTA_END: validate with `esp_ota_end()`, set boot partition with `esp_ota_set_boot_partition()`, restart
    - On validation failure: abort session, respond ERR:OTA_VERIFY, retain current firmware
    - _Requirements: 23.1, 23.2, 23.3, 23.4_

  - [ ] 21.2 Configure OTA rollback support
    - Enable `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` in `sdkconfig.defaults`
    - After successful boot from new OTA partition, call `esp_ota_mark_app_valid_cancel_rollback()`
    - If boot fails, ESP-IDF automatically rolls back to previous partition
    - _Requirements: 23.5_

  - [ ]* 21.3 Write unit tests for OTA state machine
    - Test OTA session lifecycle: START → DATA × N → END (success path)
    - Test OTA abort on verify failure
    - Test OTA timeout handling
    - _Requirements: 23.2, 23.3, 23.4_

- [ ] 22. Phase 10 Checkpoint
  - Ensure OTA upload via BLE writes to inactive partition, device reboots to new firmware, rollback works if new firmware is invalid. Ask the user if questions arise.

- [ ] 23. Final Integration and Boot Sequence Verification
  - [ ] 23.1 Wire complete boot sequence in main.c
    - Implement full boot order: hardware peripheral init (GPIO, SPI, I2S, RMT, LEDC, PCNT) → NVS load → LCD init → boot logo display (2s) → Bluedroid init + BLE advertising (parallel during logo) → transition to UI5 → Main_Task loop begins
    - Ensure hardware init + NVS load completes within 1 second
    - Suppress engine sound and taillight flash during boot
    - _Requirements: 25.1, 25.2, 25.3, 25.4_

  - [ ] 23.2 Verify task architecture and core pinning
    - Confirm Bluedroid stack runs on Core 0, Main_Task on Core 1 (priority 5), Audio_Output_Task on Core 1 (priority 6)
    - Confirm cmd_queue routes all BLE commands from Core 0 to Main_Task on Core 1
    - Confirm AppState mutex hold time stays under 1ms
    - _Requirements: 24.1, 24.2, 24.3, 24.4, 24.5_

  - [ ] 23.3 Verify code architecture compliance
    - Confirm all source organized into drivers/, services/, ui/, app/ layers
    - Confirm no ESP-IDF peripheral API calls in services/ or ui/ (all go through drivers/)
    - Confirm no global mutable variables outside AppState
    - _Requirements: 26.1, 26.2, 26.3, 26.4_

- [ ] 24. Final Checkpoint
  - Ensure all tests pass, full boot sequence works, BLE + A2DP dual-mode operates correctly, all 8 UI screens function, LED effects run, NVS persists settings, logo upload/display works, OTA succeeds. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each phase
- Property tests validate universal correctness properties from the design document
- All code is C targeting ESP-IDF v5.3.5 with Bluedroid dual-mode Bluetooth
- Phase 6 (UI + LED effects) is the largest phase, broken into per-screen sub-tasks
- The design document component interfaces (§1–§15) define the exact function signatures to implement
