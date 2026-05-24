# Implementation Plan: Engineering Refactor

## Overview

系统性重构 RideWind Flutter APP (`RideWind/lib/`)，按固定顺序执行五个阶段：(1) 死代码清除 → (2) 接口抽象引入 → (3) 分层架构建立 → (4) 状态管理统一 → (5) 大文件拆分。每个阶段独立可验证，产出单独 commit/tag。质量脚本（层级违规检查、文件长度检查）作为自动化门禁集成到 CI。

## Tasks

- [ ] 1. Set up quality scripts infrastructure and testing framework
  - [ ] 1.1 Add glados dependency and create quality scripts directory structure
    - Add `glados` to `dev_dependencies` in `pubspec.yaml`
    - Create `RideWind/scripts/` directory for quality gate scripts
    - Create `RideWind/test/quality_scripts/` directory for property-based tests
    - _Requirements: 8.1, 8.3_

  - [ ] 1.2 Implement layer violation checker script (`scripts/check_layer_violations.dart`)
    - Implement directory-to-layer mapping (screens/widgets → UI, providers/controllers → Business, services/protocol → Data, models/core/utils/data/configs → Shared)
    - Parse all `.dart` files under `lib/`, extract import statements, determine source and target layers
    - Report violations where UI imports Data, Business imports UI, Data imports UI/Business, Shared imports UI/Business
    - Exempt `main.dart` from all layer restrictions
    - Exclude generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`)
    - Exit code: 0 = no violations, 1 = violations found, 2 = script error
    - Output format: `{file}:{line} — {import} ({source_layer} → {target_layer} is forbidden)`
    - _Requirements: 2.1, 2.2, 2.3, 2.6, 2.7, 8.1_

  - [ ] 1.3 Implement file length checker script (`scripts/check_file_length.dart`)
    - Scan all `.dart` files under `lib/` (excluding generated files)
    - Count total lines per file (including comments and blank lines)
    - Classify: ≤400 = ok, 401-500 = warning, >500 = error
    - Output warnings for 401-500 line files, errors for >500 line files
    - Exit code: 0 = no errors (warnings ok), 1 = has errors, 2 = script error
    - _Requirements: 1.5, 8.3_

  - [ ]* 1.4 Write property test for layer violation checker (Property 6)
    - **Property 6: Layer dependency matrix correctness**
    - Use glados to generate arbitrary (source_path, import_path) pairs
    - Verify checker reports violation iff import target is NOT in allowed-imports set for source layer
    - Verify main.dart exemption holds for all generated import combinations
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.7, 4.6, 8.1**

  - [ ]* 1.5 Write property test for file length checker (Property 10)
    - **Property 10: File length threshold classification**
    - Use glados to generate arbitrary line counts (0..2000)
    - Verify classification: ok if ≤400, warning if 401-500, error if >500
    - Verify exit code is non-zero iff any file classified as error
    - **Validates: Requirements 8.3**

  - [ ]* 1.6 Write property test for generated file exclusion filter (Property 9)
    - **Property 9: Generated file exclusion filter**
    - Use glados to generate arbitrary file path strings
    - Verify filter returns true iff path ends with `.g.dart`, `.freezed.dart`, or `.mocks.dart`
    - Verify partial matches like `my_g.dart` are NOT excluded
    - **Validates: Requirements 3.6**

- [ ] 2. Checkpoint - Verify quality scripts
  - Ensure all tests pass, ask the user if questions arise.
  - Run `flutter test test/quality_scripts/` to verify property tests pass
  - Run `dart run scripts/check_layer_violations.dart` and `dart run scripts/check_file_length.dart` to verify scripts execute correctly

- [ ] 3. Phase 1 — Dead code removal
  - [ ] 3.1 Implement dead code detection utilities (`lib/utils/dead_code_helpers.dart` or as script logic)
    - Detect empty method bodies (methods with only comments or empty blocks) that are not `@override` and not required by interface/abstract class
    - Detect unused imports (imports whose symbols are not referenced in the file)
    - Detect commented-out imports (`// import ...` patterns)
    - Detect unreferenced top-level declarations (variables, functions not used anywhere in non-generated files)
    - Exclude generated files from detection scope
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.6_

  - [ ]* 3.2 Write property test for dead method body detection (Property 7)
    - **Property 7: Dead method body detection**
    - Use glados to generate method declarations with varying body content, annotations, and interface requirements
    - Verify classification as "dead" iff: body is empty/comments-only AND not `@override` AND not required by interface
    - **Validates: Requirements 3.1**

  - [ ]* 3.3 Write property test for commented-import pattern detection (Property 8)
    - **Property 8: Commented-import pattern detection**
    - Use glados to generate lines of Dart source code (comments, imports, regular code)
    - Verify detection identifies `// import ...` patterns but NOT regular comments containing the word "import"
    - **Validates: Requirements 3.3**

  - [ ] 3.4 Execute dead code removal across `RideWind/lib/`
    - Remove all empty/dead method bodies (respecting interface requirements and `@override`)
    - Remove all unused imports
    - Remove all commented-out imports
    - Remove unreferenced declarations (skip if removal would cause compile error, report as skipped)
    - Exclude generated files from modification
    - Run `flutter analyze` after removal — must produce zero errors and zero `unused_import`/`unused_element`/`unused_local_variable` warnings
    - Run `flutter test test/protocol/` — all 51 protocol tests must pass
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 6.1, 6.3, 6.4, 6.6, 8.5_

  - [ ] 3.5 Create Phase 1 commit and verify
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (including 51 protocol tests)
    - Append Phase 1 entry to `CHANGELOG.md` with phase name, files modified/deleted, and description
    - _Requirements: 7.2, 7.4, 7.5_

- [ ] 4. Phase 2 — Interface abstraction
  - [ ] 4.1 Create abstract interface definitions in `lib/core/interfaces/`
    - Create `lib/core/interfaces/ble_interface.dart` — `IBleService` abstract class with all public methods/streams consumed by Business_Layer
    - Create `lib/core/interfaces/ota_interface.dart` — `IOtaService` abstract class
    - Create `lib/core/interfaces/audio_interface.dart` — `IAudioStreamService` abstract class
    - Create `lib/core/interfaces/preference_interface.dart` — `IPreferenceService` abstract class
    - Each interface file includes file-level doc comment with layer name and responsibility
    - _Requirements: 4.1, 4.5, 8.4_

  - [ ] 4.2 Make concrete services implement their abstract interfaces
    - Update `BLEService` to `implements IBleService`
    - Update `OtaUploadService` to `implements IOtaService`
    - Update `AudioStreamService` to `implements IAudioStreamService`
    - Create or update `PreferenceService` to `implements IPreferenceService`
    - Ensure all public methods declared in interfaces are implemented
    - _Requirements: 4.1, 4.3_

  - [ ] 4.3 Update Service Locator to register interfaces
    - Modify `core/service_locator.dart` to register concrete implementations against abstract interface types
    - `sl.registerLazySingleton<IBleService>(() => BLEService())`
    - `sl.registerLazySingleton<IPreferenceService>(() => PreferenceService())`
    - `sl.registerLazySingleton<IAudioStreamService>(() => AudioStreamServiceImpl())`
    - Register `IOtaService` as factory (per-use instance)
    - _Requirements: 4.3_

  - [ ] 4.4 Refactor Business_Layer to depend on interfaces only
    - Update `BluetoothProvider` constructor to accept `IBleService` instead of concrete `BLEService`
    - Update all providers/controllers to reference abstract interface types in constructor parameters and field declarations
    - Remove direct imports of concrete implementation files from Business_Layer files
    - Verify no Business_Layer file imports from `services/` or `protocol/` concrete files (only `core/interfaces/`)
    - _Requirements: 4.2, 4.4, 4.6_

  - [ ] 4.5 Create Phase 2 commit and verify
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (including 51 protocol tests)
    - Run `dart run scripts/check_layer_violations.dart` — note current violations (will be fixed in Phase 3)
    - Append Phase 2 entry to `CHANGELOG.md`
    - _Requirements: 6.1, 6.2, 6.3, 7.2, 7.4, 7.5, 8.5_

- [ ] 5. Checkpoint - Verify Phases 1-2
  - Ensure all tests pass, ask the user if questions arise.
  - Run `flutter analyze` — zero errors
  - Run `flutter test` — all pass

- [ ] 6. Phase 3 — Layer enforcement
  - [ ] 6.1 Fix UI_Layer violations (screens/ and widgets/ importing from services/protocol/)
    - Identify all direct imports from `services/` or `protocol/` in `screens/` and `widgets/` files
    - For each violation: route data access through the appropriate Provider or Controller in Business_Layer
    - Where a screen directly calls `BLEService`, refactor to use `BluetoothProvider` or a new controller
    - Ensure UI files only import from `providers/`, `controllers/`, `models/`, `core/`, `utils/`, `data/`, `configs/`
    - _Requirements: 2.1, 2.4, 6.2, 6.3_

  - [ ] 6.2 Fix Business_Layer violations (providers/controllers importing from screens/widgets/)
    - Identify any imports from `screens/` or `widgets/` in `providers/` or `controllers/` files
    - Extract shared types/callbacks to `models/` or `core/` if needed
    - _Requirements: 2.2_

  - [ ] 6.3 Fix Data_Layer violations (services/protocol importing from UI or Business)
    - Identify any imports from `screens/`, `widgets/`, `providers/`, or `controllers/` in `services/` or `protocol/` files
    - Refactor to use callbacks, streams, or shared models instead
    - _Requirements: 2.3_

  - [ ] 6.4 Fix Shared layer violations
    - Ensure `models/`, `core/`, `utils/`, `data/`, `configs/` files do not import from UI or Business layers
    - Shared files may import from other Shared files and from `core/` interface definitions
    - _Requirements: 2.7_

  - [ ] 6.5 Verify layer enforcement with quality script
    - Run `dart run scripts/check_layer_violations.dart` — must exit with code 0 (zero violations)
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (including 51 protocol tests)
    - _Requirements: 8.1, 8.2, 8.5_

  - [ ] 6.6 Create Phase 3 commit and verify
    - Run full validation suite
    - Append Phase 3 entry to `CHANGELOG.md`
    - _Requirements: 7.2, 7.4, 7.5_

- [ ] 7. Phase 4 — State consolidation
  - [ ] 7.1 Audit current state management patterns
    - Identify all widgets that cache BLE state in local `State` fields (violating single-source-of-truth)
    - Identify all `setState()` calls that duplicate Provider-managed state
    - Identify providers that manage multiple domains (candidates for splitting)
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ] 7.2 Split BluetoothProvider into single-responsibility providers
    - Extract LED/color logic into `LedProvider` (color presets, RGB values, flow effects)
    - Extract audio logic into `AudioProvider` (WiFi state, audio stream state, volume)
    - Keep `BluetoothProvider` focused on BLE connection + protocol communication + speed/sensor data
    - Each new provider gets a doc comment stating its responsibility boundary
    - Register new providers in Service Locator and `main.dart` MultiProvider
    - _Requirements: 5.4_

  - [ ] 7.3 Refactor widgets to use Provider as single source of truth
    - Remove all local `State` fields that duplicate BLE connection status — use `Consumer<BluetoothProvider>` instead
    - Remove all local caching of speed/sensor data — read from Provider at render time
    - Replace direct stream subscriptions in widgets with Provider-exposed properties
    - Ensure `Provider.of<T>(context)` without `listen: false` only appears inside `Consumer` or `Selector` when multiple providers are accessed
    - _Requirements: 5.1, 5.2, 5.3, 5.5_

  - [ ] 7.4 Create Phase 4 commit and verify
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (including 51 protocol tests)
    - Run `dart run scripts/check_layer_violations.dart` — zero violations
    - Append Phase 4 entry to `CHANGELOG.md`
    - _Requirements: 6.1, 6.2, 6.3, 7.2, 7.4, 7.5, 8.5_

- [ ] 8. Checkpoint - Verify Phases 3-4
  - Ensure all tests pass, ask the user if questions arise.
  - Run full validation: `flutter analyze`, `flutter test`, layer violation check

- [ ] 9. Phase 5 — File splitting
  - [ ] 9.1 Implement file splitting utilities
    - Create naming convention function: PascalCase class name → `lowercase_with_underscores.dart`
    - Implement splitting logic: identify top-level declarations, group private helpers with their class
    - Implement barrel file generation: re-export all public symbols from original path
    - Implement circular import resolution: extract shared types to `_common.dart`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6_

  - [ ]* 9.2 Write property test for file split size bounds (Property 1)
    - **Property 1: File split size bounds**
    - Use glados to generate file content with N lines (N > 400)
    - Verify each chunk is between 200-400 lines and sum equals N
    - **Validates: Requirements 1.1, 1.5**

  - [ ]* 9.3 Write property test for barrel file symbol preservation (Property 2)
    - **Property 2: Barrel file symbol preservation**
    - Use glados to generate sets of public symbols
    - Verify barrel file re-exports every symbol (superset property)
    - **Validates: Requirements 1.2**

  - [ ]* 9.4 Write property test for one-declaration-per-file splitting (Property 3)
    - **Property 3: One-declaration-per-file splitting**
    - Use glados to generate files with multiple top-level declarations
    - Verify each output file has exactly one primary declaration, no duplicates across files
    - **Validates: Requirements 1.3**

  - [ ]* 9.5 Write property test for cycle resolution (Property 4)
    - **Property 4: Cycle resolution produces DAG**
    - Use glados to generate dependency graphs with cycles
    - Verify after resolution the graph is a DAG (no cycles)
    - **Validates: Requirements 1.4**

  - [ ]* 9.6 Write property test for class-to-filename conversion (Property 5)
    - **Property 5: Class-to-filename conversion**
    - Use glados to generate valid PascalCase class names
    - Verify output is lowercase_with_underscores ending in `.dart`
    - Verify round-trip: filename → PascalCase yields original name
    - **Validates: Requirements 1.6**

  - [ ] 9.7 Split large files (>400 lines) into modules
    - Split `running_mode_widget.dart` (~1560 lines) → config, controls, display + barrel
    - Split `bluetooth_provider.dart` (~800+ lines) → core connection/state (already partially done in Phase 4 with LedProvider/AudioProvider extraction)
    - Split all remaining files exceeding 400 lines using one-class-per-file principle
    - Generate barrel files for each split to maintain backward compatibility (zero import changes for callers)
    - Resolve any circular imports by extracting shared types to `_common.dart`
    - Each new file gets a file-level doc comment with layer name and responsibility
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 8.4_

  - [ ] 9.8 Verify file splitting results
    - Run `dart run scripts/check_file_length.dart` — must exit with code 0 (no file >500 lines)
    - Verify no file exceeds 500 lines (hard upper bound)
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (including 51 protocol tests)
    - Run `dart run scripts/check_layer_violations.dart` — zero violations
    - _Requirements: 1.5, 8.2, 8.3, 8.5_

  - [ ] 9.9 Create Phase 5 commit and verify
    - Run full validation suite
    - Append Phase 5 entry to `CHANGELOG.md`
    - _Requirements: 7.2, 7.4, 7.5_

- [ ] 10. CI integration and final validation
  - [ ] 10.1 Add quality gate steps to CI workflow
    - Add `dart run scripts/check_layer_violations.dart` step to `analyze` job in `.github/workflows/multi-platform-build.yml`
    - Add `dart run scripts/check_file_length.dart` step to `analyze` job
    - Place these steps after `flutter analyze` and `flutter test`
    - Ensure non-zero exit code from either script fails the CI job and blocks the build
    - _Requirements: 8.6_

  - [ ] 10.2 Final full validation run
    - Run `flutter analyze` — zero errors
    - Run `flutter test` — all tests pass (51 protocol tests + new property tests)
    - Run `dart run scripts/check_layer_violations.dart` — zero violations
    - Run `dart run scripts/check_file_length.dart` — zero errors
    - Verify all file-level doc comments are present on new files
    - _Requirements: 6.3, 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 11. Final checkpoint - Complete refactoring validation
  - Ensure all tests pass, ask the user if questions arise.
  - Verify all 5 phase tags exist in version control
  - Verify CHANGELOG.md has entries for all 5 phases
  - Confirm no file in `ridewind-esp/` was modified

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation between major phases
- Property tests validate universal correctness properties from the design document using the `glados` library
- Unit tests validate specific examples and edge cases
- The fixed refactoring order (Dead code → Interfaces → Layers → State → Splitting) is critical — each phase builds on the previous
- All 51 existing protocol tests must pass after every commit
- ESP32 firmware (`ridewind-esp/`) is completely out of scope — no modifications allowed
- BLE protocol command formats and UUID constants must remain unchanged throughout

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["1.4", "1.5", "1.6"] },
    { "id": 3, "tasks": ["3.1"] },
    { "id": 4, "tasks": ["3.2", "3.3"] },
    { "id": 5, "tasks": ["3.4"] },
    { "id": 6, "tasks": ["3.5"] },
    { "id": 7, "tasks": ["4.1"] },
    { "id": 8, "tasks": ["4.2"] },
    { "id": 9, "tasks": ["4.3", "4.4"] },
    { "id": 10, "tasks": ["4.5"] },
    { "id": 11, "tasks": ["6.1", "6.2", "6.3", "6.4"] },
    { "id": 12, "tasks": ["6.5"] },
    { "id": 13, "tasks": ["6.6"] },
    { "id": 14, "tasks": ["7.1"] },
    { "id": 15, "tasks": ["7.2"] },
    { "id": 16, "tasks": ["7.3"] },
    { "id": 17, "tasks": ["7.4"] },
    { "id": 18, "tasks": ["9.1"] },
    { "id": 19, "tasks": ["9.2", "9.3", "9.4", "9.5", "9.6"] },
    { "id": 20, "tasks": ["9.7"] },
    { "id": 21, "tasks": ["9.8"] },
    { "id": 22, "tasks": ["9.9"] },
    { "id": 23, "tasks": ["10.1", "10.2"] }
  ]
}
```
