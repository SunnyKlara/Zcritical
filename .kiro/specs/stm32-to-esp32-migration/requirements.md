# Requirements Document

## Introduction

RideWind is a smart LED fan control system currently running on STM32F405RGTx with an external JDY-08 BLE module. This project migrates the entire firmware to ESP32-S3, replicating all existing functionality while adding A2DP Bluetooth speaker capability, restructuring the codebase into a clean modular architecture, and replacing external W25Q128 Flash with ESP32-S3 internal Flash (NVS + LittleFS). The target platform is ESP-IDF v5.3.5 with Bluedroid dual-mode Bluetooth stack.

## Glossary

- **System**: The RideWind ESP32-S3 firmware as a whole
- **LCD_Driver**: The GC9A01 240×240 round LCD display driver module (SPI interface)
- **LED_Driver**: The WS2812B addressable LED strip driver module (RMT peripheral)
- **Encoder_Driver**: The EC11 rotary encoder input driver module (PCNT/GPIO)
- **Fan_Controller**: The LEDC PWM fan speed control module
- **Humidifier_Controller**: The GPIO-based humidifier on/off control module
- **BLE_Service**: The Bluedroid GATTS BLE communication service (Service UUID 0xFFE0, Characteristic UUID 0xFFE1)
- **Audio_Service**: The audio pipeline including A2DP Sink, local MP3 decoder, mixer, and I2S output to MAX98357
- **UI_Manager**: The UI state machine managing 8 interfaces (UI0–UI7) with encoder input and LCD rendering
- **Storage_Service**: The persistent storage module using NVS for settings and LittleFS for files
- **OTA_Service**: The ESP-IDF native dual-partition over-the-air firmware update module
- **AppState**: The unified global application state struct protected by a FreeRTOS mutex
- **Protocol_Parser**: The text command parser handling the CMD:PARAM\n protocol format
- **Message_Queue**: The FreeRTOS queue routing BLE commands to the main control task
- **Main_Task**: The primary control loop task running on Core 1 at 50Hz (20ms period)
- **LED_Strip**: A logical grouping of WS2812B LEDs — Left (IO41, 2 LEDs), Main (IO41, 6 LEDs), Right (IO41, 2 LEDs), Tail (IO16, 3 LEDs)
- **Streamlight**: A smooth gradient color cycling effect across 14 presets at 30ms/frame with 100 interpolation steps per transition
- **Breathing_Effect**: A sine-wave brightness modulation effect with 0.6–1.0 range, 3-second period, at 50fps
- **Throttle_Mode**: A special speed control mode where holding the encoder button accelerates (18ms/step) and releasing decelerates (12ms/step)
- **Logo_Slot**: One of 3 storage positions for user-uploaded 240×240 RGB565 images (128KB each with 16-byte header + CRC32)
- **Partition_Table**: The ESP32-S3 8MB flash layout: nvs(24KB), otadata(8KB), phy_init(4KB), ota_0(2.5MB), ota_1(2.5MB), storage/LittleFS(2MB), coredump(64KB)

## Requirements

### Requirement 1: Project Foundation and Partition Layout

**User Story:** As a firmware developer, I want a well-structured ESP-IDF v5.3.5 project skeleton with correct flash partitioning, so that all subsequent modules have a stable foundation to build upon.

#### Acceptance Criteria

1. THE System SHALL use ESP-IDF v5.3.5 as the build framework with CMake project structure and component-based architecture (drivers/, services/, ui/, app/ directories).
2. THE Partition_Table SHALL define the following partitions within 8MB flash: nvs (24KB), otadata (8KB), phy_init (4KB), ota_0 (2.5MB), ota_1 (2.5MB), storage LittleFS (2MB), coredump (64KB).
3. THE System SHALL assign FreeRTOS tasks with Bluedroid stack pinned to Core 0 and Main_Task plus Audio_Service output pinned to Core 1.
4. THE AppState SHALL be a single unified struct containing all application state variables, protected by a FreeRTOS mutex, serving as the sole mutable state for the system.

### Requirement 2: LCD Display Driver (GC9A01)

**User Story:** As a user, I want the round LCD to display all UI screens clearly, so that I can see speed, menus, and settings on the device.

#### Acceptance Criteria

1. THE LCD_Driver SHALL initialize the GC9A01 controller over SPI using pins SCL=IO7, SDA=IO6, DC=IO5, CS=IO4 at a clock rate sufficient for full-screen refresh.
2. THE LCD_Driver SHALL support 240×240 pixel rendering in RGB565 color format.
3. THE LCD_Driver SHALL provide functions for drawing filled rectangles, circles, lines, text (multi-size font arrays), and full-screen image blitting from const arrays.
4. WHEN the LCD_Driver receives a framebuffer update request, THE LCD_Driver SHALL complete the SPI transfer for a full 240×240 frame within 50ms.
5. THE LCD_Driver SHALL support partial screen updates to minimize SPI bandwidth when only a portion of the display changes.

### Requirement 3: WS2812B LED Strip Driver

**User Story:** As a user, I want the LED strips to display colors and effects accurately, so that I can customize the lighting on my device.

#### Acceptance Criteria

1. THE LED_Driver SHALL drive two WS2812B data lines using the ESP32-S3 RMT peripheral: IO41 for 10 LEDs (Left 2 + Main 6 + Right 2) and IO16 for 3 LEDs (Tail).
2. THE LED_Driver SHALL support individual pixel RGB color control (0–255 per channel) for all 13 LEDs across 4 logical strips (Main, Left, Right, Tail).
3. THE LED_Driver SHALL apply a global brightness scaling factor (0–100) to all LED output values before transmission.
4. WHEN the LED_Driver receives updated color data, THE LED_Driver SHALL transmit the complete LED data within 5ms to maintain smooth visual effects.

### Requirement 4: Rotary Encoder Driver (EC11)

**User Story:** As a user, I want to navigate menus and adjust values using the rotary knob, so that I can control the device without the phone app.

#### Acceptance Criteria

1. THE Encoder_Driver SHALL read rotation from the EC11 encoder on pins A=IO17, B=IO18 using the ESP32-S3 PCNT peripheral or GPIO interrupt-based decoding.
2. THE Encoder_Driver SHALL detect the encoder button on IO8 (active low) and classify press events as: single click (<400ms press), double click (2 clicks within 400ms), triple click (3 clicks within 400ms), or long press (>800ms hold).
3. THE Encoder_Driver SHALL use a 400ms timeout after the last click to determine the final click count before dispatching the event.
4. THE Encoder_Driver SHALL report rotation delta and button events to the UI_Manager through a dedicated event mechanism.
5. THE Encoder_Driver SHALL debounce both rotation and button inputs to prevent false triggers from mechanical noise.

### Requirement 5: Fan PWM and Humidifier GPIO Control

**User Story:** As a user, I want to control the fan speed and humidifier from the device or app, so that I can adjust airflow and mist output.

#### Acceptance Criteria

1. THE Fan_Controller SHALL generate PWM output on IO40 using the ESP32-S3 LEDC peripheral with a frequency of 1kHz and duty cycle range of 0–100%.
2. WHEN the Fan_Controller receives a speed value (0–100), THE Fan_Controller SHALL update the LEDC duty cycle proportionally within 10ms.
3. THE Humidifier_Controller SHALL control the humidifier via GPIO IO10, where high level activates and low level deactivates the humidifier.
4. WHEN the Humidifier_Controller receives an enable/disable command, THE Humidifier_Controller SHALL set the GPIO output level within 1ms.

### Requirement 6: BLE Communication Service

**User Story:** As a user, I want to connect the Flutter app to the device over BLE, so that I can send commands and receive status updates wirelessly.

#### Acceptance Criteria

1. THE BLE_Service SHALL use the Bluedroid GATTS stack to advertise with device name "T1" and expose Service UUID 0xFFE0 with Characteristic UUID 0xFFE1 supporting write-without-response and notify properties.
2. THE BLE_Service SHALL accept incoming text commands in the format CMD:PARAM\n and route each parsed command through the Message_Queue to the Main_Task.
3. THE BLE_Service SHALL support all existing APP→Hardware commands: FAN, SPEED, WUHUA, LED, PRESET, BRIGHT, UI, LCD, UNIT, THROTTLE, STREAMLIGHT, LED_GRADIENT, GET:xxx, LOGO_START/DATA/END, OTA_START/DATA/END.
4. THE BLE_Service SHALL send all existing Hardware→APP notifications: SPEED_REPORT, KNOB, BTN, THROTTLE_REPORT, UNIT_REPORT, PRESET_REPORT, STATUS, OK/ERR responses via BLE notify on Characteristic 0xFFE1.
5. WHEN the BLE_Service receives data larger than 20 bytes, THE BLE_Service SHALL handle BLE MTU-based fragmentation and reassemble complete commands before parsing.
6. THE BLE_Service SHALL maintain backward compatibility with the existing Flutter RideWind app without requiring app-side protocol changes (except device name changing from "JDY-08" to "T1").


### Requirement 7: Text Protocol Parser

**User Story:** As a firmware developer, I want a robust command parser that handles all BLE protocol messages, so that the device correctly interprets every command from the app.

#### Acceptance Criteria

1. THE Protocol_Parser SHALL parse text commands in the format CMD:PARAM\n where CMD is a string identifier and PARAM is a colon-separated parameter list.
2. THE Protocol_Parser SHALL recognize and dispatch all 20+ command types: FAN:xx, SPEED:xxx, WUHUA:x, LED:s:r:g:b, PRESET:x, BRIGHT:xx, UI:x, LCD:x, UNIT:x, THROTTLE:x, STREAMLIGHT:x, LED_GRADIENT:s:r:g:b:speed, GET:xxx, LOGO_START:slot:size, LOGO_DATA:hex, LOGO_END, OTA_START:size, OTA_DATA:hex, OTA_END.
3. IF the Protocol_Parser receives a malformed or unrecognized command, THEN THE Protocol_Parser SHALL respond with ERR:UNKNOWN_CMD\r\n and discard the invalid input without affecting system state.
4. THE Protocol_Parser SHALL format outgoing responses with \r\n line termination for command acknowledgments (OK:CMD\r\n) and \n line termination for event reports (KNOB:delta\n, BTN:type:action\n).
5. FOR ALL valid command strings, parsing then formatting then parsing the command SHALL produce an equivalent command object (round-trip property).

### Requirement 8: UI State Machine — Boot Logo (UI0)

**User Story:** As a user, I want to see a boot logo when the device powers on, so that I know the device is starting up.

#### Acceptance Criteria

1. WHEN the System completes hardware initialization and NVS settings load, THE UI_Manager SHALL display the active Logo_Slot image (or default embedded logo if no custom logo is set) on the LCD for exactly 2 seconds.
2. WHEN the 2-second boot logo display completes, THE UI_Manager SHALL transition to the menu interface (UI5) without playing engine sound or flashing taillights.
3. THE UI_Manager SHALL read the active Logo_Slot index from NVS during boot to determine which logo to display.

### Requirement 9: UI State Machine — Speed Control (UI1)

**User Story:** As a user, I want to control and display the simulated speed, so that I can see the speed value and switch between km/h and mph.

#### Acceptance Criteria

1. WHILE the UI_Manager is in UI1 normal mode, THE UI_Manager SHALL update the displayed speed value (0–340 km/h or 0–211 mph) in response to encoder rotation.
2. WHEN the user single-clicks the encoder in UI1 normal mode, THE UI_Manager SHALL toggle the speed unit between km/h and mph and send a UNIT_REPORT to the BLE_Service.
3. WHEN the user double-clicks the encoder in UI1, THE UI_Manager SHALL save the current state and return to the menu (UI5).
4. WHEN the user triple-clicks the encoder in UI1, THE UI_Manager SHALL enter Throttle_Mode.
5. WHILE the UI_Manager is in Throttle_Mode, THE UI_Manager SHALL accelerate the speed at 18ms per step while the encoder button is held and decelerate at 12ms per step when the button is released.
6. WHILE the UI_Manager is in Throttle_Mode, THE UI_Manager SHALL exit Throttle_Mode and return to UI1 normal mode when the encoder is rotated.
7. WHILE the UI_Manager is in Throttle_Mode, THE UI_Manager SHALL support remote freeze/unfreeze commands from the BLE_Service to pause and resume speed changes.
8. THE UI_Manager SHALL synchronize the fan PWM output proportionally to the displayed speed value in UI1.

### Requirement 10: UI State Machine — Color Presets (UI2)

**User Story:** As a user, I want to browse and apply color presets to the LED strips, so that I can quickly change the lighting theme.

#### Acceptance Criteria

1. WHILE the UI_Manager is in UI2, THE UI_Manager SHALL cycle through 14 color presets in response to encoder rotation, applying each preset to the LED strips in real time.
2. WHEN the user single-clicks the encoder in UI2, THE UI_Manager SHALL toggle the Streamlight effect on or off for the current preset.
3. WHEN the user double-clicks the encoder in UI2, THE UI_Manager SHALL save the current preset selection and Streamlight state to NVS and return to the menu (UI5).
4. WHILE Streamlight is active, THE LED_Driver SHALL cycle through preset colors with smooth gradient transitions at 30ms per frame using 100 linear interpolation steps per color transition.
5. WHEN the user rotates the encoder while Streamlight is active, THE UI_Manager SHALL deactivate Streamlight and switch to the newly selected preset in static mode.

### Requirement 11: UI State Machine — RGB Custom (UI3)

**User Story:** As a user, I want to fine-tune the RGB color of each LED strip individually, so that I can create a fully custom lighting setup.

#### Acceptance Criteria

1. THE UI_Manager SHALL implement UI3 as a 3-layer state machine: Layer 0 selects the LED strip (Main/Left/Right/Tail), Layer 1 selects the color channel (R/G/B), Layer 2 adjusts the channel value (0–255).
2. WHILE the UI_Manager is in UI3 Layer 0, THE LCD_Driver SHALL display a red dot indicator on the currently selected strip.
3. WHILE the UI_Manager is in UI3 Layer 1 or Layer 2, THE LCD_Driver SHALL display a green dot indicator on the currently selected channel.
4. WHEN the user single-clicks the encoder in UI3, THE UI_Manager SHALL advance to the next layer (0→1→2), or return from Layer 2 to Layer 1.
5. WHEN the user double-clicks the encoder in UI3 at any layer, THE UI_Manager SHALL save all RGB values to NVS and return to the menu (UI5).
6. WHILE the UI_Manager is in UI3 Layer 2, THE UI_Manager SHALL adjust the selected channel value by ±2 per encoder step and apply the change to the LED strip in real time.
7. WHEN the UI_Manager enters UI3, THE UI_Manager SHALL deactivate Streamlight and Breathing_Effect (RGB custom has highest LED priority).

### Requirement 12: UI State Machine — Brightness (UI4)

**User Story:** As a user, I want to adjust the overall LED brightness and enable a breathing effect, so that I can set the ambient lighting level.

#### Acceptance Criteria

1. WHILE the UI_Manager is in UI4 with Breathing_Effect off, THE UI_Manager SHALL adjust the global brightness (0–100) in response to encoder rotation and apply the value to the LED_Driver in real time.
2. WHEN the user single-clicks the encoder in UI4, THE UI_Manager SHALL toggle the Breathing_Effect on or off.
3. WHEN the user double-clicks the encoder in UI4, THE UI_Manager SHALL save the brightness value and Breathing_Effect state to NVS and return to the menu (UI5).
4. WHILE Breathing_Effect is active, THE LED_Driver SHALL modulate brightness using a sine wave with amplitude range 0.6–1.0, a 3-second period, and 50fps update rate.
5. WHEN the UI_Manager leaves UI4 with Breathing_Effect active, THE Breathing_Effect SHALL continue running in the background across all other UI screens.
6. WHEN the UI_Manager enters UI2 or UI3, THE UI_Manager SHALL deactivate Breathing_Effect (priority: RGB custom > Breathing > Streamlight).

### Requirement 13: UI State Machine — Menu (UI5)

**User Story:** As a user, I want a visual menu to navigate between all features, so that I can access any function from a central screen.

#### Acceptance Criteria

1. THE UI_Manager SHALL render UI5 as a full-screen sliding menu with 6 pages corresponding to: Speed (UI1), Color Presets (UI2), RGB Custom (UI3), Brightness (UI4), Logo (UI6), Volume (UI7).
2. WHILE the UI_Manager is in UI5, THE UI_Manager SHALL slide to the next or previous menu page in response to encoder rotation with smooth animation.
3. WHEN the user single-clicks the encoder in UI5, THE UI_Manager SHALL enter the UI corresponding to the currently displayed menu page.
4. THE UI_Manager SHALL clear any residual encoder delta when transitioning between UI screens to prevent unintended input carry-over.

### Requirement 14: UI State Machine — Logo Management (UI6)

**User Story:** As a user, I want to view, select, and delete custom logos, so that I can personalize the boot screen.

#### Acceptance Criteria

1. WHILE the UI_Manager is in UI6, THE UI_Manager SHALL display the currently selected Logo_Slot image on the LCD and allow switching between occupied slots via encoder rotation.
2. WHEN the user single-clicks the encoder in UI6, THE UI_Manager SHALL set the currently viewed Logo_Slot as the active boot logo in NVS.
3. WHEN the user long-presses the encoder for 2 seconds or more in UI6, THE UI_Manager SHALL delete the current Logo_Slot data from LittleFS and display a progress bar during the deletion process.
4. WHEN the user double-clicks the encoder in UI6, THE UI_Manager SHALL return to the menu (UI5).

### Requirement 15: UI State Machine — Volume Control (UI7)

**User Story:** As a user, I want to adjust the audio volume from the device, so that I can control speaker loudness without the app.

#### Acceptance Criteria

1. WHILE the UI_Manager is in UI7, THE UI_Manager SHALL adjust the audio volume (0–100) in response to encoder rotation and apply the value to the Audio_Service in real time.
2. WHEN the user double-clicks the encoder in UI7, THE UI_Manager SHALL save the volume to NVS and return to the menu (UI5).

### Requirement 16: LED Effects Priority System

**User Story:** As a firmware developer, I want a clear LED effect priority system, so that conflicting effects are resolved deterministically.

#### Acceptance Criteria

1. THE LED_Driver SHALL enforce the following effect priority order (highest to lowest): RGB Custom (UI3 active) > Breathing_Effect (UI4 toggle) > Streamlight (UI2 toggle) > Static preset colors.
2. WHEN a higher-priority effect is activated, THE LED_Driver SHALL immediately suppress all lower-priority effects without requiring explicit deactivation commands.
3. WHEN a higher-priority effect is deactivated, THE LED_Driver SHALL resume the highest remaining active effect automatically.

### Requirement 17: LED Gradient Transitions

**User Story:** As a user, I want smooth color transitions when switching presets, so that the lighting changes look fluid.

#### Acceptance Criteria

1. WHEN a color preset change is triggered, THE LED_Driver SHALL perform a linear interpolation transition from the current color to the target color.
2. THE LED_Driver SHALL support three gradient speed modes: fast (0.5 seconds), normal (1.5 seconds), and slow (3.0 seconds).
3. WHILE a gradient transition is in progress and a new target color is set, THE LED_Driver SHALL start the new transition from the current interpolated color value.


### Requirement 18: Audio Pipeline — A2DP Bluetooth Speaker

**User Story:** As a user, I want to stream music from my phone to the device speaker over Bluetooth, so that I can listen to audio while riding.

#### Acceptance Criteria

1. THE Audio_Service SHALL register as an A2DP Sink using the Bluedroid stack with device name "T1", accepting SBC audio streams from paired phones.
2. WHEN a phone pairs and streams A2DP audio, THE Audio_Service SHALL decode the incoming SBC data to PCM and route the samples to the I2S output (DIN=IO13, BCLK=IO12, LRC=IO11) connected to the MAX98357 amplifier.
3. THE Audio_Service SHALL support simultaneous BLE control connection and A2DP audio streaming using Bluedroid dual-mode (Classic BT + BLE).
4. WHEN the A2DP connection is established, THE Audio_Service SHALL apply the current volume setting (0–100) from AppState to the audio output.

### Requirement 19: Audio Pipeline — Local MP3 Engine Effects

**User Story:** As a user, I want engine sound effects during throttle mode, so that the experience feels more immersive.

#### Acceptance Criteria

1. THE Audio_Service SHALL decode local MP3 files stored in LittleFS: engine start sound (~40KB) and engine acceleration loop (~193KB).
2. WHEN Throttle_Mode is activated, THE Audio_Service SHALL play the engine start sound followed by the acceleration loop synchronized to the speed value.
3. WHEN Throttle_Mode is deactivated, THE Audio_Service SHALL stop the engine sound effect and restore normal audio routing.

### Requirement 20: Audio Pipeline — Mixer and Volume Control

**User Story:** As a firmware developer, I want a software audio mixer, so that engine effects and Bluetooth music can play simultaneously with configurable balance.

#### Acceptance Criteria

1. THE Audio_Service SHALL mix A2DP PCM audio and local MP3 decoded PCM audio into a single output stream before sending to I2S.
2. WHILE Throttle_Mode is active, THE Audio_Service SHALL mix audio with engine sound at 100% volume and Bluetooth music at 20% volume.
3. WHILE Throttle_Mode is inactive, THE Audio_Service SHALL output Bluetooth music at 100% volume with no engine sound.
4. THE Audio_Service SHALL apply a master volume control (0–100 from AppState) to the final mixed output before I2S transmission.
5. THE Audio_Service SHALL prevent audio clipping by clamping mixed sample values to the valid 16-bit PCM range (-32768 to 32767).

### Requirement 21: NVS Persistent Storage

**User Story:** As a user, I want my settings to persist across power cycles, so that I do not have to reconfigure the device every time.

#### Acceptance Criteria

1. THE Storage_Service SHALL store user settings in NVS including: 4× LED strip RGB colors (12 bytes), global brightness (1 byte), Streamlight flag (1 byte), volume (1 byte), active preset index (1 byte), speed unit preference (1 byte), Breathing_Effect state (1 byte), and active Logo_Slot index (1 byte).
2. WHEN the System boots, THE Storage_Service SHALL read all stored settings from NVS and populate the AppState struct before any UI rendering begins.
3. IF NVS contains no previously stored settings (first boot), THEN THE Storage_Service SHALL initialize AppState with factory default values: Main LED RGB(150,20,0), Left LED RGB(255,0,0), Right LED RGB(33,126,222), Tail LED RGB(255,0,0), brightness 100, volume 50, preset 1, unit km/h, Streamlight off, Breathing off.
4. THE Storage_Service SHALL write settings to NVS only when the user explicitly saves (double-click to exit a UI screen), avoiding unnecessary write cycles.

### Requirement 22: LittleFS File Storage

**User Story:** As a user, I want to upload custom logos and have engine sound files stored on the device, so that I can personalize the boot screen and have audio effects available.

#### Acceptance Criteria

1. THE Storage_Service SHALL mount a LittleFS filesystem on the 2MB storage partition for storing Logo images and MP3 audio files.
2. THE Storage_Service SHALL support 3 Logo_Slot files, each containing a 240×240 RGB565 image with a 16-byte header and CRC32 checksum, totaling up to 128KB per slot.
3. WHEN a LOGO_START command is received via BLE, THE Storage_Service SHALL begin receiving logo data packets (LOGO_DATA), validate the CRC32 on LOGO_END, and write the complete image to the specified Logo_Slot in LittleFS.
4. IF the CRC32 validation fails during logo upload, THEN THE Storage_Service SHALL discard the incomplete data, respond with ERR:CRC\r\n, and leave the target Logo_Slot unchanged.
5. THE Storage_Service SHALL store MP3 engine sound files (start ~40KB, acceleration ~193KB) in LittleFS, accessible by the Audio_Service.

### Requirement 23: OTA Firmware Update

**User Story:** As a user, I want to update the device firmware over BLE from the app, so that I can receive new features and bug fixes without physical access.

#### Acceptance Criteria

1. THE OTA_Service SHALL use ESP-IDF native dual-partition OTA with ota_0 and ota_1 partitions (2.5MB each).
2. WHEN an OTA_START command is received via BLE with the firmware size parameter, THE OTA_Service SHALL begin an OTA session, writing incoming OTA_DATA packets to the inactive OTA partition.
3. WHEN an OTA_END command is received, THE OTA_Service SHALL validate the written firmware image, mark the new partition as bootable, and trigger a system restart.
4. IF the OTA firmware validation fails, THEN THE OTA_Service SHALL abort the OTA session, respond with ERR:OTA_VERIFY\r\n, and retain the current firmware without modification.
5. IF the System fails to boot from a newly written OTA partition, THEN THE OTA_Service SHALL automatically roll back to the previous working partition on the next boot.

### Requirement 24: FreeRTOS Task Architecture

**User Story:** As a firmware developer, I want a well-defined task architecture, so that real-time audio and UI responsiveness are maintained without race conditions.

#### Acceptance Criteria

1. THE System SHALL run the Bluedroid stack (BLE + A2DP) on Core 0 with sufficient stack size for Bluetooth operations.
2. THE Main_Task SHALL run on Core 1 with a 20ms period (50Hz), processing encoder input, UI state machine updates, LED effect calculations, and BLE command dispatch from the Message_Queue.
3. THE Audio_Service output task SHALL run on Core 1, reading mixed PCM samples and writing to the I2S DMA buffer.
4. THE System SHALL use the Message_Queue (FreeRTOS xQueue) to route all BLE commands from the BLE_Service (Core 0) to the Main_Task (Core 1), ensuring the Main_Task is the single modifier of AppState.
5. THE AppState mutex SHALL be held only during read or write operations on shared state fields, with a maximum hold time of 1ms to prevent priority inversion.

### Requirement 25: Boot Sequence

**User Story:** As a user, I want the device to start up reliably and quickly, so that it is ready to use within a few seconds of powering on.

#### Acceptance Criteria

1. THE System SHALL execute the boot sequence in the following order: hardware peripheral initialization → NVS settings load → Logo display for 2 seconds → transition to menu (UI5).
2. THE System SHALL complete hardware initialization and NVS load within 1 second of power-on.
3. WHILE the boot logo is displayed, THE System SHALL initialize the Bluedroid stack and begin BLE advertising in the background so that the device is connectable by the time the menu appears.
4. THE System SHALL suppress engine sound playback and taillight flash effects during the boot sequence.

### Requirement 26: Code Architecture and Modularity

**User Story:** As a firmware developer, I want a clean modular codebase, so that individual components can be developed, tested, and maintained independently.

#### Acceptance Criteria

1. THE System SHALL organize source code into four layers: drivers/ (hardware abstraction for LCD, LED, encoder, PWM, GPIO, I2S), services/ (business logic for BLE, audio, storage, OTA, protocol), ui/ (display rendering and UI state machine), and app/ (AppState management and main task orchestration).
2. THE System SHALL define hardware abstraction interfaces in drivers/ that isolate all ESP-IDF peripheral API calls from the business logic in services/ and ui/.
3. THE System SHALL ensure that no module in services/ or ui/ directly calls ESP-IDF peripheral APIs — all hardware access goes through drivers/ interfaces.
4. THE System SHALL use the AppState struct as the single source of truth for all mutable application state, with no global variables outside of AppState.
