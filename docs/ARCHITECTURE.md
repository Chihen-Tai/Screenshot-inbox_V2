# Screenshot Inbox Architecture

Screenshot Inbox is currently a native macOS Swift Package Manager executable. Phase 23 keeps the macOS UI intact while making the reusable domain code easier to carry into a future Windows app.

## Layers

### Core

Core code is platform-neutral Swift:

- `ScreenshotInbox/Models/`: value models such as `Screenshot`, `ScreenshotCollection`, `Tag`, `ImportSource`, `OCRResult`, `DetectedCode`, `DuplicateGroup`, `OrganizationRule`, and `AppPreferences`.
- `ScreenshotInbox/Core/ServiceProtocols/`: cross-platform protocols and neutral result/input types.

Core must not import SwiftUI, AppKit, Cocoa, Vision, or QuickLook. It should represent image details as values such as width, height, byte size, format, paths, UUIDs, and timestamps.

### Persistence

`ScreenshotInbox/Persistence/` owns SQLite access:

- `Database` wraps the SQLite connection and statement API.
- `MigrationManager` defines forward-only migrations.
- Repository types own table-specific reads and writes.

Persistence should not depend on SwiftUI or AppKit. Schema changes must be migrations and must be documented in `docs/SCHEMA.md`.

### Services

`ScreenshotInbox/Services/` owns business workflows:

- Import, search, duplicate detection, source sync, organization rules, library integrity, OCR/code queues, export, trash, and action routing.
- Services should depend on repositories and Core protocols rather than concrete AppKit/Vision types.
- Services should return structured results such as `ImportResult`, `LibraryIntegrityReport`, `LibraryMaintenanceResult`, `OriginalExportResult`, and `TextExportResult`; UI decides whether those become alerts, sheets, toasts, or progress views.

Some compatibility services still contain macOS UI dependencies, especially `ExportShareService`, `ScreenshotClipboardService`, and `ScreenshotActionRouter`. These are known migration points, documented in `docs/PLATFORM_BOUNDARIES.md`.

### Platform/macOS

`ScreenshotInbox/Platform/macOS/` owns platform integrations:

- Apple Vision OCR and barcode detection.
- ImageIO thumbnail, metadata, PDF, and image-hash implementations.
- Finder/open-with/system-trash/clipboard/share-sheet behavior.
- Darwin file-system watcher.
- macOS managed-library path defaults.

These classes conform to Core protocols such as `ImageMetadataProvider`, `ThumbnailGenerating`, `OCRRecognizing`, `CodeDetecting`, `FileOpening`, `FileTrashManaging`, `ClipboardProviding`, `SharingProviding`, and `FolderWatching`.

### UI

`ScreenshotInbox/UI/`, `ScreenshotInbox/App/`, and `ScreenshotInbox/AppKitBridge/` are macOS UI:

- SwiftUI shell, sidebar, toolbar, inspector, settings, sheets, toasts, and preview.
- AppKit-backed grid, drag/drop, context menus, shortcut monitors, and collection-view controllers.
- `AppState` composes the current macOS implementation stack and presents service results to the UI.

## Data Flow

1. UI actions call `AppState` or `ScreenshotActionRouter`.
2. `AppState` delegates business work to services.
3. Services call repositories and platform protocols.
4. Platform/macOS implementations perform OS-specific work.
5. Repositories persist durable state in SQLite.
6. `AppState` refreshes published values for SwiftUI/AppKit views.

## Import Pipeline

1. User import, clipboard paste, or source-folder watcher provides file URLs.
2. `ImportService` hashes, checks conflicts, copies into the managed library, reads metadata, writes thumbnails, and inserts repository rows.
3. OCR, code detection, duplicate hashing, and organization rules run after import where applicable.

## Architecture Guard

Run:

```bash
scripts/check-architecture.sh
```

The script scans `ScreenshotInbox/Core` and `ScreenshotInbox/Models` for UI framework imports and common AppKit/SwiftUI type leaks. `CoreArchitectureTests` also checks the same boundary during `swift test`.
