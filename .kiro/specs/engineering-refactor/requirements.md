# Requirements Document

## Introduction

RideWind Flutter APP 工程化重构规范。项目已有 500+ 用户，当前代码存在大文件（18 个文件超 500 行）、模块边界不清晰、死代码堆积、缺少接口抽象、状态管理散乱等问题。本规范定义系统性重构的目标、约束和验收标准，确保重构过程安全可控，不影响现有用户体验。

重构范围：Flutter APP 端（`RideWind/lib/`），不涉及 ESP32 固件。

## Glossary

- **Refactoring_Engine**: 执行重构操作的开发流程和工具链
- **Architecture_Layer**: 分层架构中的某一层（UI 层、业务逻辑层、数据通信层）
- **UI_Layer**: 负责界面渲染和用户交互的代码层（screens/、widgets/）
- **Business_Layer**: 负责业务逻辑编排的代码层（controllers/、providers/）
- **Data_Layer**: 负责数据获取和底层通信的代码层（services/、protocol/）
- **Interface_Contract**: 抽象类或接口定义，用于隔离模块间的直接依赖
- **Dead_Code**: 已禁用但未删除的代码（空方法体、注释掉的 import、未引用的函数）
- **Service_Locator**: 基于 GetIt 的依赖注入容器（`core/service_locator.dart`）
- **Provider_State**: 基于 Flutter Provider 包的状态管理单元
- **BLE_Service**: 蓝牙低功耗底层通信服务
- **File_Metric**: 文件行数统计指标

## Requirements

### Requirement 1: 大文件拆分

**User Story:** As a developer, I want each Dart source file to stay within 200-400 lines, so that code is easy to navigate, review, and maintain.

#### Acceptance Criteria

1. WHEN a source file in `RideWind/lib/` exceeds 400 total lines (including comments and blank lines), THE Refactoring_Engine SHALL split the file into multiple modules, each containing between 200 and 400 total lines
2. WHEN splitting a file, THE Refactoring_Engine SHALL provide a barrel file (re-exporting all public symbols from the original file path) so that existing callers require zero import changes
3. WHEN splitting a file, THE Refactoring_Engine SHALL place each top-level class, mixin, or enum into its own file, grouping only closely-coupled private helpers with the class they serve
4. IF a split results in circular imports, THEN THE Refactoring_Engine SHALL resolve the cycle by extracting shared types into a `_common.dart` file within the same directory
5. THE Refactoring_Engine SHALL ensure no file in `RideWind/lib/` exceeds 500 total lines after refactoring is complete (500 lines is the hard upper bound; 400 lines is the split trigger)
6. WHEN creating new files from a split, THE Refactoring_Engine SHALL name each file using lowercase_with_underscores matching the primary class or function group it contains, and place it in the same directory as the original file

### Requirement 2: 分层架构建立

**User Story:** As a developer, I want a clear layered architecture (UI → Business Logic → Data/Communication), so that each layer has well-defined responsibilities and dependencies only flow downward.

#### Acceptance Criteria

1. THE Architecture_Layer SHALL enforce that UI_Layer files (in `screens/` and `widgets/`) only import from Business_Layer (`providers/`, `controllers/`) or Shared (`models/`, `core/`, `utils/`, `data/`, `configs/`), not from Data_Layer (`services/`, `protocol/`) directly
2. THE Architecture_Layer SHALL enforce that Business_Layer files may import from Data_Layer and Shared but not from UI_Layer
3. THE Architecture_Layer SHALL enforce that Data_Layer files do not import from UI_Layer or Business_Layer
4. WHEN a screen widget needs BLE data, THE UI_Layer SHALL access the data through a Provider_State or controller in Business_Layer, not by calling BLE_Service directly
5. THE Architecture_Layer SHALL define the following directory-to-layer mapping:
   - UI_Layer: `screens/`, `widgets/`
   - Business_Layer: `providers/`, `controllers/`
   - Data_Layer: `services/`, `protocol/`
   - Shared: `models/`, `core/`, `utils/`, `data/`, `configs/`
6. THE `main.dart` entry point SHALL be exempt from layer import restrictions as it must wire all layers together
7. Shared layer files SHALL NOT import from UI_Layer or Business_Layer; they MAY import from other Shared files and from Data_Layer interface definitions in `core/`

### Requirement 3: 死代码清除

**User Story:** As a developer, I want all dead code removed from the codebase, so that files are shorter, intent is clear, and no one wastes time reading unused code.

#### Acceptance Criteria

1. WHEN a method body is empty or contains only comments, and the method is not required by an interface, abstract class, mixin, or annotated with `@override`, THE Refactoring_Engine SHALL delete the method entirely
2. WHEN an import statement references a symbol that is not used in executable or declaration code within the same file, THE Refactoring_Engine SHALL remove the import
3. WHEN a commented-out import exists (e.g., `// import ...`), THE Refactoring_Engine SHALL remove the comment
4. WHEN a variable or function is declared but never referenced in any non-generated Dart file within the project (excluding files matching `*.g.dart`, `*.freezed.dart`, and `*.mocks.dart`), and the symbol is not a `main()` entry point, THE Refactoring_Engine SHALL delete the declaration
5. THE Refactoring_Engine SHALL run `flutter analyze` after dead code removal and produce zero errors and zero warnings of type `unused_import`, `unused_element`, or `unused_local_variable` that were not already present before the removal operation
6. THE Refactoring_Engine SHALL exclude generated files (matching patterns `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`) from all dead code detection and removal operations
7. IF removing a declaration would introduce a new compile error (e.g., the symbol is referenced via a `part`/`part of` relationship or exported through a library barrel file), THEN THE Refactoring_Engine SHALL retain the declaration and report it as a skipped item in the operation summary

### Requirement 4: 接口抽象引入

**User Story:** As a developer, I want modules to depend on abstract interfaces rather than concrete implementations, so that I can swap libraries or mock dependencies without cascading changes.

#### Acceptance Criteria

1. THE Data_Layer SHALL define an abstract class for each of the following external-facing services: BLE communication, OTA upload, audio streaming, and preference storage, where each abstract class declares all public methods and streams that Business_Layer classes consume from that service
2. WHEN a Business_Layer class depends on a Data_Layer service, THE Business_Layer class SHALL reference only the abstract interface type in its constructor parameters, field declarations, and method signatures, and SHALL NOT import the concrete implementation file
3. THE Service_Locator SHALL register each concrete implementation against its abstract interface type so that replacing an implementation requires modifying only the Service_Locator registration call and no Business_Layer source file
4. WHEN a new Data_Layer service is added, THE service SHALL implement an existing abstract interface or define a new abstract interface in the designated interface directory before any Business_Layer file imports or references the service
5. THE abstract interface files SHALL reside in `core/` or a dedicated `interfaces/` directory, separate from the concrete implementation files located in `services/` or `data/`
6. IF a Business_Layer source file contains a direct import of a concrete Data_Layer implementation file, THEN THE static analysis check SHALL report a violation identifying the offending import and the Business_Layer file

### Requirement 5: 状态管理统一

**User Story:** As a developer, I want a single, consistent state management pattern across the app, so that state flows are predictable and debuggable.

#### Acceptance Criteria

1. THE App SHALL use Provider (ChangeNotifier) as the sole state management mechanism for reactive UI state, where reactive UI state is defined as any value that originates from device communication, persisted preferences, or cross-screen shared data — excluding ephemeral widget-local state such as animation controllers, form field focus, and scroll position
2. WHEN BLE connection state changes, THE BluetoothProvider SHALL be the single source of truth, and no widget SHALL cache or duplicate the connection status in its own State fields — widgets SHALL read connection state exclusively via `Provider.of<BluetoothProvider>` or `Consumer<BluetoothProvider>` at render time
3. WHEN speed or sensor data arrives from the device, THE data SHALL flow through BluetoothProvider (either as a notified property or an exposed stream from ResponseRouter) rather than being stored in widget local state — widgets SHALL subscribe via Provider or the provider's public stream getters
4. THE App SHALL organize state into providers with single-responsibility scope such that each provider class exposes no more than one domain (e.g., BLE communication, color/LED settings, user preferences) and each provider class includes a doc comment stating its responsibility boundary
5. IF a widget needs to combine state from multiple providers, THEN THE widget SHALL use `Consumer` or `Selector` to subscribe to only the needed properties, and SHALL NOT trigger a rebuild of the entire subtree — verified by confirming that no `Provider.of<T>(context)` call without `listen: false` appears outside of a `Consumer` or `Selector` when multiple providers are accessed in the same widget

### Requirement 6: 重构安全保障

**User Story:** As a developer, I want the refactoring process to be safe and reversible, so that 500+ existing users are never impacted by internal code reorganization.

#### Acceptance Criteria

1. THE Refactoring_Engine SHALL preserve all BLE protocol command formats (command strings sent via CommandSender) and UUID constants (service UUID 0xFFE0, characteristic UUID 0xFFE1) unchanged during refactoring
2. THE Refactoring_Engine SHALL preserve all public API signatures of BluetoothProvider — including public method signatures, getter return types, Stream type declarations, and constructor parameters — so that screen-level code requires zero modifications per refactoring step
3. WHEN a refactoring step is complete, THE project SHALL pass `flutter analyze` with zero errors and `flutter test` SHALL complete with all existing tests passing
4. THE Refactoring_Engine SHALL execute refactoring in incremental steps, where each step produces a state that passes `flutter analyze` with zero errors and can execute `flutter test` without compilation failures
5. IF a refactoring step introduces a regression detected by test failure or analysis error, THEN THE Refactoring_Engine SHALL revert the step and attempt an alternative approach, with a maximum of 3 alternative attempts per step before escalating to the developer
6. THE Refactoring_Engine SHALL not modify any file in `ridewind-esp/` as part of this refactoring effort

### Requirement 7: 重构执行顺序

**User Story:** As a developer, I want a defined execution order for refactoring tasks, so that each step builds on a stable foundation and risk is minimized.

#### Acceptance Criteria

1. THE Refactoring_Engine SHALL execute refactoring phases in the following fixed order: (1) Dead code removal → (2) Interface abstraction → (3) Layer enforcement → (4) State consolidation → (5) File splitting
2. WHEN starting a new phase, THE Refactoring_Engine SHALL verify that the previous phase passes all of the following validation criteria before proceeding: `flutter analyze` reports zero errors, and all existing automated tests pass with zero failures
3. IF the previous phase fails any validation criterion, THEN THE Refactoring_Engine SHALL halt execution, report which specific validation check failed, and not proceed to the next phase until all validation criteria pass
4. THE Refactoring_Engine SHALL produce a separate version-control commit and version tag for each completed phase, with each tag corresponding to exactly one phase's changes and no other unrelated modifications
5. WHEN a phase is complete, THE Refactoring_Engine SHALL append an entry to CHANGELOG.md containing: the phase name, the version tag, a list of files added/modified/deleted, and a one-sentence description of the structural change performed

### Requirement 8: 代码质量验证

**User Story:** As a developer, I want automated quality checks that enforce the new architecture rules, so that the codebase does not regress after refactoring.

#### Acceptance Criteria

1. THE Refactoring_Engine SHALL provide an analysis script that scans all .dart files under lib/ and detects forbidden cross-layer imports: files in lib/screens/ or lib/widgets/ (UI layer) SHALL NOT directly import files from lib/services/ or lib/protocol/ (Data layer); WHEN one or more violations are detected, THE script SHALL exit with a non-zero exit code and output each violation as a line containing the violating file path and the forbidden import statement
2. WHEN `flutter analyze` is run on the RideWind project, THE project SHALL produce zero analysis errors (exit code 0); warnings and info-level lints are permitted
3. THE Refactoring_Engine SHALL provide a script that counts total lines in all .dart files under lib/ (excluding generated files matching *.g.dart and *.freezed.dart), reports files exceeding 400 lines as warnings and files exceeding 500 lines as errors, and exits with a non-zero exit code if any file exceeds 500 lines
4. WHEN a new .dart file is created under lib/, THE file SHALL include a file-level doc comment (/// comment block before the first declaration) containing: the layer name (one of: screens, widgets, services, providers, models, core) and a one-sentence description of the file's responsibility not exceeding 120 characters
5. THE Refactoring_Engine SHALL run `flutter test test/protocol/` after each refactoring commit and verify that all 51 existing protocol tests pass (exit code 0); IF any protocol test fails, THEN THE Refactoring_Engine SHALL revert the refactoring step and report the failing test names
6. WHEN the CI pipeline executes a build triggered by a pull request or tag push, THE CI pipeline SHALL run the layer-violation analysis script and the file-length check script as gate steps before the build step; IF either script exits with a non-zero code, THEN THE CI pipeline SHALL mark the job as failed and block the build
