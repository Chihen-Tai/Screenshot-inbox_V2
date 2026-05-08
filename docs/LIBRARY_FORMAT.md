# Managed Library Format

The managed library is the app-owned durable copy of imported screenshots. On macOS the default root is:

```text
~/Pictures/Screenshot Inbox Library/
```

Tests and previews can inject a different root through `MacLibraryService(rootURL:)`.

## Current Folder Layout

```text
Screenshot Inbox Library/
  screenshot-inbox.sqlite
  Originals/
    YYYY/
      MM/
        <uuid>.<original-extension>
  Thumbnails/
    small/
      <uuid>.jpg
    large/
      <uuid>.jpg
  Exports/
    PDFs/
```

## Database Location

The SQLite database lives at:

```text
<library-root>/screenshot-inbox.sqlite
```

SQLite sidecar files such as `screenshot-inbox.sqlite-wal` and `screenshot-inbox.sqlite-shm` can exist because WAL journaling is enabled.

## Managed Originals

Managed originals live under:

```text
Originals/<yyyy>/<mm>/
```

`LibraryManaging.originalsFolder(for:)` creates the year/month folder on demand. Imported files are copied into this managed area and named by screenshot UUID plus an extension derived from the source file.

## Thumbnails

Thumbnails are JPEG files:

```text
Thumbnails/small/<uuid>.jpg
Thumbnails/large/<uuid>.jpg
```

The current macOS generator uses longest-edge sizes of about 360 px for small thumbnails and 1200 px for large thumbnails.

## Exports, Temp, Cache, and Logs

PDF exports default under:

```text
Exports/PDFs/
```

Clipboard paste staging currently uses the system temporary directory under `ScreenshotInboxPastes`. Logs are currently runtime console output; no stable `Logs/` library directory is created.

## Path Semantics

`Screenshot.libraryPath` is the app-owned reliable path to the managed original. It is usually relative to the library root, for example:

```text
Originals/2026/04/<uuid>.png
```

If an older row stores an absolute `libraryPath`, services tolerate it.

`Screenshot.originalPath` is optional provenance for the external source file. Source files may be deleted, renamed, or moved after import. The app should not require `originalPath` to remain valid.

## UUID Usage

The screenshot UUID is the stable identity across:

- `screenshots.uuid`
- managed original filename
- thumbnail filenames
- OCR rows
- detected-code rows
- image-hash rows
- collection/tag logical joins

New code should treat UUID strings case-insensitively and prefer lowercase when storing paths.

## Missing Files

Missing managed originals are integrity problems because the managed copy is the reliable copy. Missing external source files are expected and should be surfaced as source-sync warnings rather than data loss.

If a managed original exists but thumbnails are missing, `LibraryIntegrityService.regenerateMissingThumbnails()` can rebuild thumbnails from the original.

## Orphan Cleanup

`LibraryIntegrityService` detects:

- orphan thumbnails not matching known screenshot UUIDs
- orphan originals not referenced by `screenshots.library_path`
- orphan repository rows in join/result tables

Cleanup methods remove orphan files only when they are inside the library root. Database orphan cleanup is reported but not automatically rewritten by the current maintenance service.

## Compatibility Contract

Future platforms should preserve the logical folder format and SQLite schema unless a migration explicitly changes them. Platform-specific path roots may differ, but the relative layout under the library root should remain stable.
