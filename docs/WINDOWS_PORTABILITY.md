# Windows Portability Notes

Phase 24 adds a read-only Windows prototype to validate whether a Screenshot Inbox library can be opened outside the macOS app.

## 1. Portable Paths

Portable:

- `screenshots.library_path` when it is relative to the library root, for example `Originals/2026/04/<uuid>.png`.
- Thumbnail paths derived from UUID:
  - `Thumbnails/small/<uuid>.jpg`
  - `Thumbnails/large/<uuid>.jpg`
- SQLite database path derived from the selected library root:
  - `<library-root>/screenshot-inbox.sqlite`

The current import pipeline writes `library_path` as a relative managed path via `ImportService.libraryRelativePath(for:)`. That is the right cross-platform shape.

## 2. macOS-only or Platform-specific Paths

Platform-specific:

- `screenshots.original_path`
- `screenshots.source_app` when it stores a source folder path
- historical absolute `library_path` values, if any exist in older libraries

`original_path` is external provenance. It can point to `/Users/...`, `/Volumes/...`, Desktop, Downloads, removable drives, or any other source location. Windows should display it as informational text only and must not require it to exist.

## 3. What Must Change Before Full Windows Sharing

Recommended future fields:

- `libraryRelativePath`: relative managed original path under the library root.
- `thumbnailRelativePath`: optional explicit relative thumbnail path if thumbnail layout ever changes.
- `originalPath`: optional platform-specific external source path.

The current schema already has a usable `library_path`. Before a production Windows app, add an integrity/migration check that flags absolute `library_path` values and offers a safe conversion only when the target file is inside the selected library root.

## 4. Original Path Policy

`original_path` should remain optional and platform-specific. It answers “where did this come from?” not “where is the app-owned file?”

Rules:

- UI may show it.
- Source sync may use it on the platform that created it.
- Windows should not use a macOS `original_path` to load the managed image.
- Missing `original_path` is not data loss.

## 5. Library Path Policy

`library_path` should be relative to the library root for all newly imported files. A relative path keeps the managed copy portable when the whole library folder is moved between macOS and Windows.

The Windows prototype resolves:

1. Relative `library_path` against the selected library root.
2. Absolute `library_path` as-is, with a portability warning.
3. Missing `library_path` as an unresolved managed image.

## 6. SQLite Compatibility

The Windows prototype opens SQLite in read-only mode and reads:

- `screenshots`
- `ocr_results` through a left join for optional text search

No migrations are run. WAL sidecars may exist beside the database, but the reader does not create or modify them intentionally.

## 7. Known Risks

- macOS and Windows differ in path separators and case sensitivity.
- Old libraries may contain absolute managed paths.
- Some metadata timestamps are stored as Unix seconds (`REAL`) while organization tables use text timestamps.
- OCR and QR backends will differ by platform; stored result tables are portable, but generation is not.
- Future write support must explicitly handle locking, WAL behavior, backups, and schema migrations.

## 8. Prototype Result

The Phase 24 prototype validates the read-only path:

1. User chooses a library folder.
2. Reader opens `screenshot-inbox.sqlite` read-only.
3. Reader loads screenshot rows.
4. Reader resolves thumbnails and managed image paths without modifying the library.
5. UI shows records, basic metadata, and portability warnings.
