# Architecture

Screenshot Inbox is a native macOS Swift Package Manager executable. The app uses SwiftUI for the main shell and AppKit where macOS collection-view behavior is needed.

## High-Level Architecture

The app is organized around `AppState`, a `@MainActor ObservableObject` that owns user-visible state, selection, services, repositories, and workflow routing. SwiftUI views observe `AppState`; AppKit bridge controllers report selection, drag/drop, context menu, and shortcut events back into it.

## Core Models

Core value types live in `ScreenshotInbox/Models/`. Important models include screenshots, tags, collections, OCR results, detected codes, duplicate groups, export options, import sources, and organization rules.

## Services

Domain workflows live in `ScreenshotInbox/Services/`.

- `ImportService` imports image files into the managed library.
- `OCRQueueService` and `CodeDetectionQueueService` schedule processing.
- `SearchService` parses and applies local search filters.
- `PDFExportService` exports selected screenshots as PDF.
- `ExportShareService` exports, copies, and shares originals or OCR text.
- `LibraryIntegrityService` checks and repairs managed-library state.
- `ScreenshotActionRouter` centralizes UI action dispatch.

## Persistence

Persistence lives in `ScreenshotInbox/Persistence/`. The app uses SQLite through repository types and `MigrationManager`. UI code should use `AppState`, services, or repository abstractions rather than talking directly to SQLite.

## Platform/macOS Layer

macOS-specific implementations live in `ScreenshotInbox/Platform/macOS/`. This layer handles Apple Vision OCR and QR detection, thumbnail generation, file watching, PDF rendering, image hashing, metadata reading, Finder actions, and managed library paths.

## UI Layer

SwiftUI views live in `ScreenshotInbox/UI/`.

- `MainWindow` contains the split layout, toolbar, sheets, and toasts.
- `Sidebar` contains library navigation, collections, smart groups, and settings entry.
- `Grid` hosts the screenshot grid and filter bar.
- `Inspector` shows preview, actions, metadata, OCR, detected codes, and tags.
- `Settings` contains preferences, watched folders, OCR, rules, and maintenance tools.

The grid itself is backed by AppKit in `ScreenshotInbox/AppKitBridge/` for `NSCollectionView`, drag/drop, context menus, and keyboard behavior.

## Managed Library Folder

By default, the managed library is stored under the user's Pictures folder:

```text
~/Pictures/Screenshot Inbox Library/
```

The library contains managed originals, thumbnails, exports, and the SQLite database.

## SQLite Database

The SQLite database stores screenshot metadata, collections, tags, OCR records, detected codes, import sources, image hashes, organization rules, and related state. Migrations are versioned in `MigrationManager`.

## Import Pipeline

1. A user imports files manually or a watched folder reports new files.
2. `ImportService` validates supported image formats.
3. The app copies files into the managed library.
4. Thumbnails and metadata are generated.
5. Repository rows are inserted or updated.
6. OCR, QR detection, duplicate hashing, and organization rules can run afterward.

## OCR, QR, and Search Pipeline

OCR and QR detection run locally through Apple frameworks. Results are stored in repositories and reflected back into `Screenshot` values through `AppState`. Search combines text terms and structured filters across filenames, OCR text, tags, collections, source apps, formats, and detected codes.

## Export Pipeline

PDF export resolves selected screenshots to managed originals, renders pages according to `PDFExportOptions`, and writes a PDF to the chosen output path. Original export and OCR text export use `ExportShareService`.
