# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ScreenshotInbox` — native macOS 14+ app, built as a Swift Package Manager **executable** target (no Xcode project). SwiftUI app shell with an AppKit-backed grid for the screenshot collection view. Currently a Phase-4-ish prototype: data is mocked in `Screenshot.mocks`; SQLite/Repository/Service layers exist as stubs (`Database.swift` is a TODO shell).

## Commands

Run from project root.

```bash
swift build                              # build (debug)
swift run ScreenshotInbox                # build + launch the app
swift test                               # run tests (none defined yet)
swift test --enable-code-coverage        # with coverage
swift test --filter <SuiteName>/<test>   # single test
swift package clean                      # nuke .build/
```

The app is an SPM executable, not a `.app` bundle. `ScreenshotInboxApp.init()` calls `NSApplication.shared.setActivationPolicy(.regular)` + `activate(...)` to force menu-bar/keyboard-shortcut routing that an SPM exec wouldn't otherwise get. **Don't remove that.**

## Architecture

### Layering

```
App/                SwiftUI entry, AppState, AppCommands, AppPermissions
UI/                 SwiftUI views (MainWindow, Sidebar, Grid, Inspector, Preview, Settings, Export, Debug)
AppKitBridge/       NSCollectionView grid + AppKit controllers (selection, drag, context menu, shortcuts)
Models/             Plain value types (Screenshot, Tag, ScreenshotCollection, Operation, ...)
Persistence/        Repository protocols (SQLite-backed; Database.swift is a stub)
Services/           Domain services (Import, OCR, Thumbnail, Search, Export, Trash, ...) — mostly skeletons
Utilities/          Theme, FileHash, Logger, AppKitFocusHelper, ErrorPresenter, ...
Resources/          Assets.xcassets, Localizable.strings, PreviewAssets (excluded from SPM build)
```

`Resources/` is `exclude:`d from the executable target in `Package.swift`. If you add code that needs assets at runtime, you'll need to wire them in deliberately (SPM exec resource handling is fiddly).

### State and selection

`AppState` (`@MainActor ObservableObject`) is the single source of truth for sidebar/filter/search/layout-mode and **owns** `SelectionController`. It re-broadcasts the controller's `objectWillChange` so SwiftUI views observing `AppState` re-render on selection changes. Selection mutations should generally go through `AppState.selectAllVisibleScreenshots()` / `clearScreenshotSelection()` so logging + change notification fan out from one place.

`SelectionController` implements Finder-style selection (replace / toggle / shift-range / select-all / prune). Range select uses an `anchorID` pivot; non-shift clicks always re-anchor.

### SwiftUI ↔ AppKit grid bridge

The grid is `NSCollectionView` (AppKit) inside a SwiftUI `NSViewControllerRepresentable`:

- `ScreenshotCollectionViewRepresentable` (SwiftUI) → `ScreenshotCollectionViewController` (AppKit) → `NSCollectionView` + `ScreenshotCollectionViewLayout` + `ScreenshotCollectionViewItem`.
- Click events flow up: AppKit item → controller `onItemClick(id, modifiers)` → `ScreenshotGridContainer.handleClick` → `SelectionController`.
- Selection state flows down: `AppState.selectedScreenshotIDs` → representable → `applyDataIfNeeded` syncs `currentSelectedIDs` and updates visible cells.
- Layout-mode changes (regular/medium/compact) push `Theme.Layout.Grid.ModeParams` into both the flow layout and visible cells via `applyLayoutMode(_:)`.

### Keyboard shortcuts (read this before touching Cmd-A / Escape)

This is the highest-friction area in the codebase. SwiftUI's command system intercepts Cmd-A / Escape **before** the AppKit responder chain, so every "obvious" path got starved. The current solution uses **multiple redundant layers** on purpose:

1. **`AppCommands`** — replaces the standard `.pasteboard` command group. Cmd-A's button checks `AppKitFocusHelper.isTextInputFocused()`; if a text input is focused it forwards `selectAll:` via `NSApp.sendAction`, otherwise it calls `appState.selectAllVisibleScreenshots()`.
2. **`WindowShortcutController`** — installs an `NSEvent.addLocalMonitorForEvents(.keyDown)` monitor for Cmd-A and Escape (keyCode 53 / `\u{1b}`). Defers to text inputs the same way.
3. **`ScreenshotGridContainer.keyboardShortcutSink`** — a hidden zero-size SwiftUI button bound to `.escape` so SwiftUI-routed Escape is captured for the grid context.
4. **`MainWindowView.onExitCommand`** — root-level Escape fallback.

`AppKitFocusHelper.isTextInputFocused()` is the single source of truth for "should this shortcut defer to a text field". `NSTextField` editing actually routes through a shared `NSTextView` field editor, so checking `NSTextView` covers focused text fields too; we also string-match `FieldEditor` for SwiftUI-hosted inputs whose responder isn't a public AppKit class.

If you add a new shortcut path, route it through `AppState`'s wrapper (`selectAllVisibleScreenshots`, `clearScreenshotSelection`) so the existing `print("[Shortcut→AppState] ...")` traces stay coherent.

### Layout modes (responsive 3-column)

`MainSplitView` measures content width via `GeometryReader` (not the window frame) and writes `Theme.LayoutMode` into `AppState`:

- `regular` (≥1100): three-column `NavigationSplitView` (Sidebar / Grid / Inspector).
- `medium` (≥800): two-column (Sidebar + Grid); inspector hidden by default, toolbar can override via `inspectorOverrideVisible`.
- `compact` (<800): grid only; both panes hidden by default, toolbar overrides for each.

Window minimum is 720×560 (set both via SwiftUI `.frame(minWidth:minHeight:)` and AppKit `NSWindow.minSize` from `WindowMinSizeAccessor` — SwiftUI's floor doesn't always propagate). Don't switch `NavigationSplitView` to `.balanced` — it bleeds inspector width into the grid.

Grid item dimensions, spacing, fonts, and checkmark size are all driven by `Theme.Layout.Grid.params(for: mode)` so mode-flip changes are visually consistent in one place.

## Conventions specific to this codebase

- Heavy `print("[Subsystem] ...")` tracing in selection / shortcut / layout-mode paths is intentional debugging scaffolding — keep it consistent when extending those paths. Real logging will replace it later via `Utilities/Logger.swift`.
- `Theme.swift` is the design-token file. Do not hard-code spacing/radius/colors/breakpoints elsewhere; add to `Theme` and reference.
- Selection mutations: prefer `AppState.selection.*` rather than holding your own copy of selected IDs. Read-side, use `appState.selectedScreenshotIDs` / `selectionCount` / `primarySelection` / `selectedScreenshots`.
- After any change that filters the visible set (sidebar, filter chip, search), call `appState.pruneSelectionToVisible()` so counts stay honest.
- Models in `Models/` are value types; persistence stubs in `Persistence/` are protocol-shaped repositories — implement against those rather than against `Database` directly when wiring real data.

## What's mocked / stubbed

- All screenshots come from `Screenshot.mocks` — `LibraryService`, `ImportService`, `ThumbnailService`, etc. are skeleton files.
- `Persistence/Database.swift` has no SQLite wiring yet (just an `init()`).
- No tests exist; `swift test` runs an empty suite.
