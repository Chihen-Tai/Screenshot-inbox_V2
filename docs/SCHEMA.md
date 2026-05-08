# SQLite Schema

The schema is managed by `ScreenshotInbox/Persistence/MigrationManager.swift`. Phase 23 documents the current schema and does not change it.

## Migration Bookkeeping

### `schema_migrations`

Purpose: records applied forward-only migration versions.

Key columns:

- `version INTEGER PRIMARY KEY`
- `applied_at REAL NOT NULL`

## Screenshots

### `screenshots`

Purpose: one row per managed screenshot.

Key columns:

- `uuid TEXT PRIMARY KEY`
- `filename TEXT NOT NULL`
- `library_path TEXT NOT NULL`
- `original_path TEXT`
- `file_hash TEXT NOT NULL`
- `width INTEGER NOT NULL`
- `height INTEGER NOT NULL`
- `file_size INTEGER NOT NULL`
- `format TEXT NOT NULL`
- `source_app TEXT`
- `created_at REAL NOT NULL`
- `imported_at REAL NOT NULL`
- `modified_at REAL NOT NULL`
- `is_favorite INTEGER NOT NULL DEFAULT 0`
- `is_trashed INTEGER NOT NULL DEFAULT 0`
- `trash_date REAL`
- `sort_index INTEGER NOT NULL DEFAULT 0`

Indexes:

- `idx_screenshots_imported_at(imported_at)`
- `idx_screenshots_is_trashed(is_trashed)`
- `idx_screenshots_file_hash(file_hash)`

Migration notes:

- `original_path` exists in the initial schema and is also guarded by migration v9 for older databases.
- `library_path` is the reliable managed copy. `original_path` is optional source provenance.

## Collections

### `collections`

Purpose: manual and smart collection metadata.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `uuid TEXT NOT NULL UNIQUE`
- `name TEXT NOT NULL`
- `type TEXT NOT NULL DEFAULT 'manual'`
- `sort_index REAL NOT NULL DEFAULT 0`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Indexes:

- `idx_collections_uuid(uuid)`
- `idx_collections_name(name)`

Migration notes:

- v7 adds `sort_index` for older databases and normalizes manual collection order when needed.

### `collection_items`

Purpose: many-to-many membership between collections and screenshots.

Key columns:

- `collection_id INTEGER NOT NULL`
- `screenshot_uuid TEXT NOT NULL`
- `sort_index REAL NOT NULL DEFAULT 0`
- `created_at TEXT NOT NULL`
- Primary key: `(collection_id, screenshot_uuid)`

Relationships:

- `collection_id` references `collections(id)` with `ON DELETE CASCADE`.
- `screenshot_uuid` is a logical reference to `screenshots(uuid)` but no foreign key is declared in the current schema.

Indexes:

- `idx_collection_items_screenshot_uuid(screenshot_uuid)`

Cascade behavior:

- Deleting a collection deletes its membership rows.
- Screenshot deletion cleanup is repository/service responsibility.

## Tags

### `tags`

Purpose: tag catalog.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `uuid TEXT NOT NULL UNIQUE`
- `name TEXT NOT NULL UNIQUE`
- `color TEXT`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Indexes:

- `idx_tags_uuid(uuid)`
- `idx_tags_name(name)`

### `screenshot_tags`

Purpose: many-to-many relationship between screenshots and tags.

Key columns:

- `tag_id INTEGER NOT NULL`
- `screenshot_uuid TEXT NOT NULL`
- `created_at TEXT NOT NULL`
- Primary key: `(tag_id, screenshot_uuid)`

Relationships:

- `tag_id` references `tags(id)` with `ON DELETE CASCADE`.
- `screenshot_uuid` is a logical reference to `screenshots(uuid)` but no foreign key is declared in the current schema.

Indexes:

- `idx_screenshot_tags_screenshot_uuid(screenshot_uuid)`

## Import Sources

### `import_sources`

Purpose: watched source folders for auto-import.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `uuid TEXT NOT NULL UNIQUE`
- `folder_path TEXT NOT NULL`
- `display_name TEXT`
- `is_enabled INTEGER NOT NULL DEFAULT 1`
- `recursive INTEGER NOT NULL DEFAULT 0`
- `enabled_since TEXT`
- `last_scanned_at TEXT`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Indexes:

- `idx_import_sources_uuid(uuid)`
- `idx_import_sources_folder_path(folder_path)`
- `idx_import_sources_is_enabled(is_enabled)`

## OCR

### `ocr_results`

Purpose: OCR text and processing status per screenshot.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `screenshot_uuid TEXT NOT NULL UNIQUE`
- `text TEXT`
- `language TEXT`
- `confidence REAL`
- `status TEXT NOT NULL DEFAULT 'pending'`
- `error_message TEXT`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Relationships:

- `screenshot_uuid` references `screenshots(uuid)` with `ON DELETE CASCADE`.

Indexes:

- `idx_ocr_results_screenshot_uuid(screenshot_uuid)`
- `idx_ocr_results_status(status)`
- `idx_ocr_results_updated_at(updated_at)`

Search index:

- No FTS table exists yet. `SearchIndexRepository` is a placeholder and migration v4 explicitly leaves FTS for a later phase.

## Detected Codes

### `detected_codes`

Purpose: QR/barcode payloads detected in screenshots.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `screenshot_uuid TEXT NOT NULL`
- `symbology TEXT NOT NULL`
- `payload TEXT NOT NULL`
- `is_url INTEGER NOT NULL DEFAULT 0`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Relationships:

- `screenshot_uuid` references `screenshots(uuid)` with `ON DELETE CASCADE`.

Indexes:

- `idx_detected_codes_screenshot_uuid(screenshot_uuid)`
- `idx_detected_codes_symbology(symbology)`
- `idx_detected_codes_is_url(is_url)`

## Image Hashes

### `image_hashes`

Purpose: perceptual or content hashes used for duplicate detection.

Key columns:

- `screenshot_uuid TEXT PRIMARY KEY`
- `algorithm TEXT NOT NULL`
- `hash TEXT NOT NULL`
- `created_at TEXT NOT NULL`

Relationships:

- `screenshot_uuid` references `screenshots(uuid)` with `ON DELETE CASCADE`.

Indexes:

- `idx_image_hashes_hash(hash)`
- `idx_image_hashes_algorithm(algorithm)`

## Organization Rules

### `organization_rules`

Purpose: stored rule definitions for automatic tagging and collection actions.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `uuid TEXT NOT NULL UNIQUE`
- `name TEXT NOT NULL`
- `is_enabled INTEGER NOT NULL DEFAULT 1`
- `priority INTEGER NOT NULL DEFAULT 0`
- `match_mode TEXT NOT NULL DEFAULT 'all'`
- `conditions_json TEXT NOT NULL`
- `actions_json TEXT NOT NULL`
- `run_on_import INTEGER NOT NULL DEFAULT 1`
- `run_after_ocr INTEGER NOT NULL DEFAULT 1`
- `created_at TEXT NOT NULL`
- `updated_at TEXT`

Indexes:

- `idx_organization_rules_uuid(uuid)`
- `idx_organization_rules_is_enabled(is_enabled)`
- `idx_organization_rules_priority(priority)`

### `organization_rule_runs`

Purpose: audit records for rule application.

Key columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `rule_uuid TEXT NOT NULL`
- `screenshot_uuid TEXT NOT NULL`
- `actions_applied_json TEXT`
- `created_at TEXT NOT NULL`

Indexes:

- `idx_organization_rule_runs_screenshot_uuid(screenshot_uuid)`
- `idx_organization_rule_runs_rule_uuid(rule_uuid)`

Relationships:

- Current schema stores logical UUID references without foreign keys.

## Preferences

Preferences are not stored in SQLite in the current implementation. `SettingsService` stores `AppPreferences` outside the DB.

## Integrity Notes

`LibraryIntegrityService` checks missing originals, missing thumbnails, orphan originals, orphan thumbnails, orphan DB rows, missing OCR records, duplicate hash coverage, and SQLite `PRAGMA integrity_check`.
