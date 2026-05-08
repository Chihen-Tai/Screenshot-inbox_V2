# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ScreenshotInbox` — native macOS 14+ app, built as a Swift Package Manager **executable** target (no Xcode project). SwiftUI app shell with an AppKit-backed grid for the main collection view, plus a menu-bar status item and a floating panel for the lightweight "inbox" surface. SQLite persistence is fully wired (WAL, migrations, multiple repositories); the platform layer (`Platform/macOS/`) holds the concrete OS-facing services. Mock data is no longer the default — it's a fallback if persistence fails to bootstrap.

## Commands

Run from project root.

```bash
swift build                              # build (debug)
swift run ScreenshotInbox                # build + launch the app
swift test                               # run tests (~21 suites under Tests/)
swift test --enable-code-coverage        # with coverage
swift test --filter <SuiteName>/<test>   # single test
swift package clean                      # nuke .build/
```

Release / packaging scripts live in `scripts/` (`build-release.sh`, `package-zip.sh`, `package-dmg.sh`, `verify-release.sh`, `notarize.sh.example`, `remove-quarantine-local.sh`, `check-architecture.sh`). Long-form release notes: `docs/RELEASE.md`.

The app is an SPM executable, not a `.app` bundle. `ScreenshotInboxApp.init()` calls `NSApplication.shared.setActivationPolicy(.regular)` + `activate(...)` to force menu-bar/keyboard-shortcut routing that an SPM exec wouldn't otherwise get. **Don't remove that.** It also installs an `AppDelegate` (see `App/AppWindowRouter.swift`) that re-opens the main window on dock-icon clicks via `AppWindowRouter.shared`.

## Architecture

### Layering

```
App/                SwiftUI entry, AppState, AppCommands, AppDelegate, AppWindowRouter,
                    AppPermissions, AppPrivacyInfo, AppReleaseInfo
UI/                 SwiftUI views, split into:
                      MainWindow/   (split view, toolbar, onboarding, rename/org sheets, toast, root VM)
                      Sidebar/      (sections, items, drop targets, view model)
                      Grid/         (container, item view, filter bar, batch-action bar, view model)
                      Inspector/    (sections: metadata, OCR, detected codes, tags, actions)
                      Preview/      (image, PDF, Quick Look)
                      Settings/     (10+ section views: General, Library, OCR, Import, Privacy, …)
                      Export/       (PDF sheet, options, progress)
                      Debug/        (debug selection bar)
AppKitBridge/       NSCollectionView grid + AppKit controllers (selection, drag, reorder,
                    context menu, shortcuts), MenuBarController, FloatingScreenshotPanel,
                    ScreenshotInboxWindow
Core/               Cross-platform contracts:
                      ServiceProtocols/LibraryProtocols.swift   (LibraryManaging, ScreenshotImporting,
                                                                 ImportConflictResolving, …)
                      ServiceProtocols/PlatformProtocols.swift  (ImageMetadataProvider, ThumbnailGenerating,
                                                                 OCRRecognizing, CodeDetecting,
                                                                 FileOpening, FileTrashManaging,
                                                                 ClipboardProviding, SharingProviding, …)
Models/             Plain value types (Screenshot, ScreenshotItem, Tag, ScreenshotCollection,
                    AppFilter, AppPreferences, ScreenshotInboxPreferences, OrganizationRule,
                    SmartGroup, DuplicateGroup, OCRResult, DetectedCode, ImageHashRecord,
                    Operation, ImportSource, ExportJob, PDFExportOptions)
Persistence/        Real SQLite stack: Database (handle/queue/transactions), MigrationManager,
                    and one repository per domain (Screenshot, Collection, Tag, ImportSource,
                    OCR, DetectedCode, ImageHash, OperationHistory, OrganizationRule,
                    SearchIndex)
Services/           Domain orchestration (platform-neutral):
                      ImportService, AutoImportService, ScreenshotWatcher, FileWatcherService,
                      SourceFolderSyncService, OCRQueueService, OCRService,
                      CodeDetectionService, CodeDetectionQueueService,
                      DuplicateDetectionService, OrganizationRuleService, SmartGroupingService,
                      LibraryService, LibraryIntegrityService, FolderAccessService,
                      SearchService, ThumbnailService, TrashService,
                      PDFExportService, ExportShareService,
                      OperationHistoryService, ScreenshotActionRouter,
                      ScreenshotClipboardService, ScreenshotInboxStore, SettingsService
Platform/macOS/     Concrete macOS implementations of the Core/ServiceProtocols:
                      MacLibraryService, MacImageHashingService, MacImageMetadataReader,
                      MacOCRService (Vision), MacCodeDetectionService (Vision barcode),
                      MacThumbnailService, MacThumbnailProvider, MacFileWatcherService,
                      MacFileActionService, MacFileOpener, MacClipboardService,
                      MacShareService, MacTrashManager, MacPDFExportService,
                      MacImportConflictResolver
Utilities/          Theme, FileHash, AppKitFocusHelper, ErrorPresenter, DateFormatting,
                    FilePathHelpers, ImageMetadataReader, SecurityBookmarkManager, Logger
Resources/          Assets.xcassets, Localizable.strings, PreviewAssets — wired via
                    Package.swift (`.process("Resources")`); `Bundle.module` works at runtime
                    (e.g. `ScreenshotInboxApp.appIconImage()` falls back to it)
```

External docs of record: `docs/ARCHITECTURE.md`, `docs/LIBRARY_FORMAT.md`, `docs/SCHEMA.md`, `docs/PLATFORM_BOUNDARIES.md`, `docs/WINDOWS_PORTABILITY.md`. Update those alongside structural changes.

### Library on disk (managed library)

Default root: `~/Pictures/Screenshot Inbox Library/` (`MacLibraryService.defaultRootURL`). Layout:

```
Screenshot Inbox Library/
  screenshot-inbox.sqlite                # WAL-mode SQLite, owned by Database
  Originals/<YYYY>/<MM>/<uuid>.<ext>     # canonical per-screenshot file
  Thumbnails/small/<uuid>.jpg            # ~256px thumb (NSCollectionView cells)
  Thumbnails/large/<uuid>.jpg            # large thumb (Quick Look / inspector)
  Exports/PDFs/                          # PDF export output
```

Tests/previews can inject a different root via `MacLibraryService(rootURL:)`. Don't hard-code the path elsewhere — go through `LibraryManaging`.

### Persistence (Phase 6 stack)

`Database` (`Persistence/Database.swift`) is a thin wrapper around `sqlite3_*` C APIs:

- Single connection, single serial `DispatchQueue` (`ScreenshotInbox.Database.serial`); reads and writes both run on it.
- WAL journal mode, `synchronous=NORMAL`, `foreign_keys=ON` set at open.
- `Statement` is an RAII wrapper around `sqlite3_stmt` (auto-finalizes); use `bind`/`step`/`columnX` helpers, not the C calls directly.
- `transaction { ... }` runs `BEGIN IMMEDIATE … COMMIT`, rolls back on throw.
- Bind text/blob with `SQLITE_TRANSIENT_BRIDGE` (Swift string lifetimes are scoped to the call).

Migrations are forward-only and idempotent (`MigrationManager.runPending(on:)`), tracked in `schema_migrations`. Add a new schema version by registering a `Migration(version:up:)` rather than mutating an existing one. Schema details: `docs/SCHEMA.md`.

Repositories in `Persistence/` are the only legitimate consumers of `Database`. Service code talks to repositories, not to `Database` directly. When persistence bootstrap fails, `AppState.database` is `nil`, `isUsingMockData = true`, and repository writes degrade to no-ops — services should treat `nil` `database` as a soft failure mode, not crash.

### Platform layer

`Core/ServiceProtocols/` defines the protocols (`LibraryManaging`, `ScreenshotImporting`, `OCRRecognizing`, `CodeDetecting`, `FileOpening`, `FileTrashManaging`, `ClipboardProviding`, `SharingProviding`, `FolderWatching`, `ImageMetadataProvider`, `ThumbnailGenerating`, `ImageHashingService`, …). `Platform/macOS/Mac*` files are the concrete implementations. Anything talking to AppKit, Vision, ImageIO, NSPasteboard, or NSWorkspace lives in `Platform/macOS/` — service code in `Services/` should depend on the protocol, not the concrete `Mac*` type. Cross-platform expectations: `docs/PLATFORM_BOUNDARIES.md`, `docs/WINDOWS_PORTABILITY.md`.

### State and selection

`AppState` (`@MainActor ObservableObject`, ~3700 lines) is the single source of truth and the dependency-injection hub. It owns:

- Sidebar selection, filter chip, search query, layout-mode overrides.
- The full `AppPreferences` and `ScreenshotInboxPreferences` (persisted via `SettingsService` / `ScreenshotInboxPreferencesService`); didSet-handlers fan out side effects.
- The persistence stack: `Database`, all repositories, `MacLibraryService`, and every domain service (Import, AutoImport, OCRQueue, CodeDetectionQueue, DuplicateDetection, OrganizationRule, Search, PDFExport, ExportShare, LibraryIntegrity, FolderAccess, SourceFolderSync, …).
- Selection (`SelectionController`, Finder-style: replace / toggle / shift-range / select-all / prune; range select uses an `anchorID` pivot, non-shift clicks re-anchor).
- Window/keyboard shortcuts (`WindowShortcutController`) and the `ScreenshotActionRouter`.
- Sheet/overlay state: rename, tag editor, collection picker/rename/delete, permanent-delete confirm, empty-trash confirm, PDF export sheet, OCR text viewer, Quick Look preview, toast.
- Phase 0 floating-inbox state: `screenshotInboxStore`, `screenshotWatcher`, `menuBarController`, `phase1ScreenshotFolderURL`.
- The app-level undo log (`OperationHistoryService` instance for screenshot ops, distinct from `NSText.undo`).

`AppState` re-broadcasts `SelectionController`'s `objectWillChange`, so views observing `AppState` re-render on selection changes. Selection mutations should generally go through `AppState` wrappers (`selectAllVisibleScreenshots()`, `clearScreenshotSelection()`, etc.) so logging + change notification fan out from one place. **Read selection** via `appState.selectedScreenshotIDs` / `selectionCount` / `primarySelection` / `selectedScreenshots`, never via your own copy.

### SwiftUI ↔ AppKit grid bridge

The grid is `NSCollectionView` (AppKit) inside a SwiftUI `NSViewControllerRepresentable`:

- `ScreenshotCollectionViewRepresentable` (SwiftUI) → `ScreenshotCollectionViewController` (AppKit) → `NSCollectionView` + `ScreenshotCollectionViewLayout` + `ScreenshotCollectionViewItem`.
- Click events flow up: AppKit item → controller `onItemClick(id, modifiers)` → `ScreenshotGridContainer.handleClick` → `SelectionController`.
- Selection state flows down: `AppState.selectedScreenshotIDs` → representable → `applyDataIfNeeded` syncs `currentSelectedIDs` and updates visible cells.
- Layout-mode changes (regular/medium/compact) push `Theme.Layout.Grid.ModeParams` into both the flow layout and visible cells via `applyLayoutMode(_:)`.
- Drag/drop: a small constellation in `AppKitBridge/` — `DragDropController` (external file drop in), `DragSelectionController` (rubber-band/marquee), `DragReorderController` + `InternalCollectionDrag` / `InternalScreenshotDrag` / `DragPasteboardTypes` (intra-grid reorder + collection assignment via the sidebar's `SidebarDropTargetView`).

### Floating inbox / menu bar (Phase 0 surface)

Separate from the main window, the app exposes a lightweight inbox driven by `ScreenshotWatcher`:

- `ScreenshotWatcher` watches the user's screenshot folder (default `~/Desktop`, configurable via `phase1ScreenshotFolderURL`) and pushes new files into `ScreenshotInboxStore` (in-memory, `@MainActor`).
- `MenuBarController` installs an `NSStatusItem` with a badge (count of new items), a menu (Open Inbox / Show Floating Preview / Settings / Quit), and toggles via `ScreenshotInboxPreferences.menuBarBadgeEnabled`.
- `FloatingInboxPanelController` (`AppKitBridge/FloatingScreenshotPanel.swift`) hosts a fixed-size `NSPanel` (620×380 pt, min 520×260) with a unified list layout for all item counts (0/1/2+). Reasons for showing it (`FloatingPreviewShowReason`) are logged for traceability. Three AppKit gotchas to keep in mind:
  1. **Window drag**: `isMovableByWindowBackground = false` on the panel; only the header is draggable via `WindowDragArea: NSViewRepresentable` (overrides `mouseDownCanMoveWindow`). Do not apply that background to rows or thumbnails or they will drag the window instead of starting file drags.
  2. **Click/double-click**: Use `.onTapGesture { }.simultaneousGesture(TapGesture(count: 2).onEnded { })`. Stacking `onTapGesture(count:2)` before `onTapGesture(count:1)` creates SwiftUI's exclusive-gesture relationship and delays single-click ~350 ms.
  3. **Panel collapse**: When `contentViewController` is replaced, `NSHostingController` auto-resizes the panel to the root view's intrinsic content size. `ScrollView { LazyVStack }` reports near-zero intrinsic height, collapsing the panel. Fix: add `.frame(width: 620, height: 380)` to the root `VStack` in `FloatingInboxPanelView.body` AND call `panel.setContentSize(Self.contentSize())` after every `contentViewController` assignment.
- `AppWindowRouter.shared` is the cross-cutting "open the main inbox window" callback — registered by `MainWindowView`, called from menu bar, floating panel, and dock-click (`AppDelegate.applicationShouldHandleReopen`).
- `ScreenshotInboxStore` is currently in-memory only; persistence is intentionally deferred (see TODO at top of the file).

### Keyboard shortcuts (read this before touching Cmd-A / Escape / Cmd-C/V/X)

This is the highest-friction area in the codebase. SwiftUI's command system intercepts Cmd-shortcuts **before** the AppKit responder chain, so every "obvious" path got starved. The current solution uses **multiple redundant layers** on purpose:

1. **`AppCommands`** — replaces the standard `.pasteboard`, `.undoRedo`, `.appSettings`, `.appInfo`, and `.newItem` command groups. Cmd-A / Cmd-C / Cmd-V / Cmd-X / Cmd-Z buttons each check `AppKitFocusHelper.isTextInputFocused()`; if a text input is focused they forward via `NSApp.sendAction` to the standard selectors (`selectAll:`, `cut:`, `copy:`, `paste:`, `undo:`); otherwise they call into `appState` (`selectAllVisibleScreenshots`, `cutSelectedScreenshotsToPasteboard`, `copySelectedScreenshotsToPasteboard`, `pasteClipboardIntoInbox`, `performAppUndo`). A separate `CommandGroup(after: .pasteboard)` adds Cmd-R (Reveal in Finder), Cmd-E (Export Original — `NSSavePanel` for single, `NSOpenPanel` folder picker for multi), and Cmd-Shift-E (Combine into PDF / Export as PDF — label changes dynamically with selection count).
2. **`WindowShortcutController`** — installs an `NSEvent.addLocalMonitorForEvents(.keyDown)` monitor for Cmd-A and Escape (keyCode 53 / `\u{1b}`). Defers to text inputs the same way.
3. **`ScreenshotGridContainer.keyboardShortcutSink`** — a hidden zero-size SwiftUI button bound to `.escape` so SwiftUI-routed Escape is captured for the grid context.
4. **`MainWindowView.onExitCommand`** — root-level Escape fallback.

`AppKitFocusHelper.isTextInputFocused()` is the single source of truth for "should this shortcut defer to a text field". `NSTextField` editing actually routes through a shared `NSTextView` field editor, so checking `NSTextView` covers focused text fields too; we also string-match `FieldEditor` for SwiftUI-hosted inputs whose responder isn't a public AppKit class.

If you add a new shortcut path, route it through `AppState`'s wrapper so the existing `print("[Shortcut→AppState] ...")` and `print("[AppCommands] ...")` traces stay coherent. The clipboard wrapper is `ScreenshotClipboardService` — don't bypass it.

### Layout modes (responsive 3-column)

`MainSplitView` measures content width via `GeometryReader` (not the window frame) and writes `Theme.LayoutMode` into `AppState`:

- `regular` (≥1100): three-column `NavigationSplitView` (Sidebar / Grid / Inspector).
- `medium` (≥800): two-column (Sidebar + Grid); inspector hidden by default, toolbar can override via `inspectorOverrideVisible`.
- `compact` (<800): grid only; both panes hidden by default, toolbar overrides for each.

Window minimum is 720×560 (set both via SwiftUI `.frame(minWidth:minHeight:)` and AppKit `NSWindow.minSize` from `WindowMinSizeAccessor` — SwiftUI's floor doesn't always propagate). Don't switch `NavigationSplitView` to `.balanced` — it bleeds inspector width into the grid.

Grid item dimensions, spacing, fonts, and checkmark size are all driven by `Theme.Layout.Grid.params(for: mode)` so mode-flip changes are visually consistent in one place.

### Settings

Settings open as a separate `Settings` scene (Cmd-,) wired in `ScreenshotInboxApp.body`. `SettingsView` is a `TabView` over a stack of section views in `UI/Settings/` (General, Appearance, Library, Screenshot, Import sources, OCR, Organization rules, Quick filters, Privacy, Advanced). All preference changes flow through `AppState.preferences` (persisted via `SettingsService`) or `AppState.screenshotInboxPreferences` (persisted via `ScreenshotInboxPreferencesService`); `didSet` handlers on `AppState` apply side effects (e.g. restarting the auto-import watcher).

## Tests

`Tests/ScreenshotInboxTests/` contains ~21 suites covering: import conflict resolution, library integrity, release readiness, privacy readiness, search service, smart grouping, organization rules, screenshot watcher, source folder sync, duplicate detection, export/share, screenshot clipboard, repository CRUD/trash, image hash repo, collection management, inbox preferences, inbox store, screenshot inbox window, selection controller, layout decisions, inspector/toolbar menu, quick-filter prefs. Run a single suite/test with `swift test --filter <SuiteName>/<test>`.

## Conventions specific to this codebase

- **Logging**: heavy `print("[Subsystem] ...")` tracing in selection / shortcut / layout-mode / floating-panel / persistence-bootstrap paths is intentional debugging scaffolding — keep the tag-prefix style consistent when extending those paths. `Utilities/Logger.swift` exists as the eventual home for structured logging; don't replace existing prints in bulk without a deliberate migration.
- **Theme tokens**: `Theme.swift` is the design-token file. Do not hard-code spacing/radius/colors/breakpoints/grid params elsewhere; add to `Theme` and reference.
- **Selection mutations**: prefer `AppState` wrappers over poking `SelectionController` directly. Read-side, use `appState.selectedScreenshotIDs` / `selectionCount` / `primarySelection` / `selectedScreenshots`.
- **Pruning**: after any change that filters the visible set (sidebar, filter chip, search), call `appState.pruneSelectionToVisible()` so counts stay honest.
- **Models in `Models/` are value types**; persistence goes through repositories in `Persistence/`, not through `Database` directly.
- **Platform boundary**: AppKit/Vision/ImageIO/NSWorkspace/NSPasteboard usage stays in `Platform/macOS/` (or `AppKitBridge/` for grid-specific UI bridging). Services in `Services/` depend on `Core/ServiceProtocols/` protocols, not concrete `Mac*` types.
- **Preferences are the single config source**: `AppPreferences` (general) and `ScreenshotInboxPreferences` (Phase 0 inbox). Don't introduce ad-hoc `UserDefaults` reads — extend the relevant preferences struct + service.
- **Undo for screenshot ops** flows through `OperationHistoryService` (`appState.appUndoService`), not `NSText`'s undo manager. Cmd-Z in `AppCommands` forwards to text first, falls back to `appState.performAppUndo()`.
- **Fallback / mock-only mode**: when `AppState.database` is `nil`, repository writes no-op and the app still runs. New code should not crash on `nil` `database`; it should degrade gracefully and surface a single toast/error rather than spamming.

## What's deferred

- `ScreenshotInboxStore` is in-memory only (see TODO comment) — Phase 1 inbox state is not persisted across launches yet.
- Several services have skeletons or partial implementations; check `docs/ARCHITECTURE.md` and `ROADMAP.md` for the current state of each phase before assuming a method is fully wired.
- Real structured logging via `Utilities/Logger.swift` hasn't replaced the `print(...)` traces yet — that migration is intentional and incremental.
