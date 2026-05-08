# Platform Boundaries

Phase 23 prepares Screenshot Inbox for a possible Windows version without building that app now. The main rule is: Core and business services communicate through neutral protocols; OS-specific code stays in `Platform/<platform>`.

## 1. Shared Core

Shared code can include:

- Models in `ScreenshotInbox/Models`.
- Platform protocols and neutral result/input types in `ScreenshotInbox/Core/ServiceProtocols`.
- Repository protocols and SQLite-backed persistence where the SQLite C binding or replacement binding is available.
- Business services that depend on repositories and protocols, such as import, search, duplicate detection, source sync, organization rules, and library integrity.

Shared code should avoid SwiftUI, AppKit, Cocoa, Vision, QuickLook, `NSImage`, `NSView`, `NSWorkspace`, and `NSPasteboard`.

## 2. macOS Platform Layer

macOS-specific implementations currently live in `ScreenshotInbox/Platform/macOS`:

- `MacImageMetadataReader`: ImageIO metadata.
- `MacThumbnailService`: ImageIO thumbnail generation.
- `MacImageHashingService`: CoreGraphics/ImageIO hashing input.
- `MacOCRService`: Apple Vision OCR.
- `MacCodeDetectionService`: Apple Vision barcode detection.
- `MacPDFExportService`: CoreGraphics/ImageIO PDF rendering.
- `MacFileWatcherService`: Darwin file-system events.
- `MacFileActionService`, `MacFileOpener`, `MacTrashManager`: Finder/open-with/system-trash actions.
- `MacClipboardService`: `NSPasteboard` file/image pasteboard access.
- `MacShareService`: `NSSharingServicePicker`.
- `MacLibraryService`: macOS default library location under Pictures.

The SwiftUI/AppKit UI layer also remains macOS-only.

## 3. Future Windows Platform Layer

A future Windows implementation would add equivalents such as:

- `WindowsImageMetadataProvider`
- `WindowsThumbnailGenerator`
- `WindowsOCRService`
- `WindowsCodeDetectionService`
- `WindowsFileOpener`
- `WindowsTrashManager`
- `WindowsClipboardService`
- `WindowsShareService`
- `WindowsFolderWatcher`
- `WindowsLibraryService`

The Windows layer should satisfy the same Core protocols and preserve the managed library layout beneath its platform-specific root.

## 4. Services That Need Abstraction

Already protocol-backed or mostly protocol-backed:

- `ImportService`: uses `LibraryManaging`, `ImageMetadataReading`, `ThumbnailGenerating`.
- `OCRQueueService`: uses `OCRService`, which now refines `OCRRecognizing`.
- `CodeDetectionQueueService`: uses `CodeDetectionService`, which now refines `CodeDetecting`.
- `LibraryIntegrityService`: uses `LibraryManaging` and `ThumbnailGenerating`.
- `AutoImportService`: uses file watcher abstraction.

Still macOS-coupled and candidates for later extraction:

- `ExportShareService`: exports are reusable, but image/file clipboard and share-sheet methods use AppKit.
- `ScreenshotClipboardService`: internal screenshot clipboard semantics are business logic, but pasteboard and image decoding are AppKit.
- `ScreenshotActionRouter`: centralized action routing is useful, but it is currently a UI/AppState surface and uses AppKit clipboard/error types.
- `LibraryIntegrityService.isValidImage`: uses ImageIO directly and should eventually depend on an image validation protocol.

## 5. Known macOS-Only Dependencies

Frameworks and APIs intentionally kept out of Core:

- SwiftUI and AppKit for the app shell, sheets, previews, grid bridge, menus, drag/drop, context menus, and shortcuts.
- Apple Vision for OCR and QR/barcode detection.
- QuickLook for preview.
- ImageIO/CoreGraphics for metadata, thumbnail, PDF, and hash input.
- `NSWorkspace` for open/reveal/open-with.
- `NSPasteboard` for copy/paste and internal screenshot drag data.
- `NSSharingServicePicker` for share sheet.
- Darwin file-system event APIs for folder watching.

## 6. Migration Risks

- The executable target is macOS-only in `Package.swift`; a future shared package split will need explicit target boundaries.
- Some service files still live under `Services/` while importing AppKit. Moving them wholesale could churn UI call sites, so Phase 23 adds protocols and documents the remaining seams first.
- SQLite migrations use the current schema as source of truth. Windows support should not fork schema behavior.
- File paths are currently `String`/`URL` values. Future Windows work must audit path normalization and case sensitivity.
- Apple Vision result quality and language identifiers will not map exactly to a Windows OCR backend.
- Clipboard behavior is platform-specific; internal screenshot IDs should remain neutral, while pasteboard serialization should be per-platform.
