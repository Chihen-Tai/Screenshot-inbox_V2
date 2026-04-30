import Foundation

/// One forward-only schema migration.
struct Migration {
    let version: Int
    let up: (Database) throws -> Void
}

/// Applies an ordered list of schema migrations at startup. The applied set
/// is tracked in a `schema_migrations` bookkeeping table created on first
/// run; only versions not in that set are run, in ascending order.
final class MigrationManager {
    private var migrations: [Migration] = []

    init() {}

    func register(_ migration: Migration) {
        migrations.append(migration)
    }

    /// Idempotent. Safe to call on every launch.
    func runPending(on database: Database) throws {
        try database.exec("""
        CREATE TABLE IF NOT EXISTS schema_migrations(
            version    INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );
        """)

        let applied = try fetchAppliedVersions(database)
        let pending = migrations
            .filter { !applied.contains($0.version) }
            .sorted { $0.version < $1.version }

        guard !pending.isEmpty else {
            print("[Migrations] up to date (applied=\(applied.sorted()))")
            return
        }

        for migration in pending {
            print("[Migrations] applying v\(migration.version)")
            try database.transaction {
                try migration.up(database)
                let stmt = try database.prepare(
                    "INSERT INTO schema_migrations(version, applied_at) VALUES(?,?);")
                try stmt.bind(1, migration.version)
                try stmt.bind(2, Date().timeIntervalSince1970)
                _ = try stmt.step()
            }
            print("[Migrations] v\(migration.version) applied")
        }
    }

    private func fetchAppliedVersions(_ database: Database) throws -> Set<Int> {
        let stmt = try database.prepare("SELECT version FROM schema_migrations;")
        var versions: Set<Int> = []
        while try stmt.step() {
            versions.insert(Int(stmt.columnInt(0)))
        }
        return versions
    }
}

// MARK: - Initial schema

extension Migration {
    /// v1 — initial schema. One `screenshots` row per imported file plus
    /// indexes on the columns we filter on the most.
    static let initialSchema = Migration(version: 1) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS screenshots(
            uuid         TEXT PRIMARY KEY,
            filename     TEXT NOT NULL,
            library_path TEXT NOT NULL,
            file_hash    TEXT NOT NULL,
            original_path TEXT,
            width        INTEGER NOT NULL,
            height       INTEGER NOT NULL,
            file_size    INTEGER NOT NULL,
            format       TEXT NOT NULL,
            source_app   TEXT,
            created_at   REAL NOT NULL,
            imported_at  REAL NOT NULL,
            modified_at  REAL NOT NULL,
            is_favorite  INTEGER NOT NULL DEFAULT 0,
            is_trashed   INTEGER NOT NULL DEFAULT 0,
            trash_date   REAL,
            sort_index   INTEGER NOT NULL DEFAULT 0
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_screenshots_imported_at ON screenshots(imported_at);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_screenshots_is_trashed  ON screenshots(is_trashed);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_screenshots_file_hash   ON screenshots(file_hash);")
    }

    static let organizationSchema = Migration(version: 2) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'manual',
            sort_index REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try db.exec("""
        CREATE TABLE IF NOT EXISTS collection_items (
            collection_id INTEGER NOT NULL,
            screenshot_uuid TEXT NOT NULL,
            sort_index REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            PRIMARY KEY (collection_id, screenshot_uuid),
            FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
        );
        """)
        try db.exec("""
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try db.exec("""
        CREATE TABLE IF NOT EXISTS screenshot_tags (
            tag_id INTEGER NOT NULL,
            screenshot_uuid TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (tag_id, screenshot_uuid),
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_collections_uuid ON collections(uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_collections_name ON collections(name);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_collection_items_screenshot_uuid ON collection_items(screenshot_uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_tags_uuid ON tags(uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_screenshot_tags_screenshot_uuid ON screenshot_tags(screenshot_uuid);")
    }

    static let autoImportSchema = Migration(version: 3) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS import_sources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            folder_path TEXT NOT NULL,
            display_name TEXT,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            recursive INTEGER NOT NULL DEFAULT 0,
            enabled_since TEXT,
            last_scanned_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_import_sources_uuid ON import_sources(uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_import_sources_folder_path ON import_sources(folder_path);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_import_sources_is_enabled ON import_sources(is_enabled);")
    }

    static let ocrSchema = Migration(version: 4) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS ocr_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            screenshot_uuid TEXT NOT NULL UNIQUE,
            text TEXT,
            language TEXT,
            confidence REAL,
            status TEXT NOT NULL DEFAULT 'pending',
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT,
            FOREIGN KEY (screenshot_uuid) REFERENCES screenshots(uuid) ON DELETE CASCADE
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_ocr_results_screenshot_uuid ON ocr_results(screenshot_uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_ocr_results_status ON ocr_results(status);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_ocr_results_updated_at ON ocr_results(updated_at);")
        // TODO: Add optional FTS5 screenshot_search table once index maintenance is ready.
    }

    static let detectedCodesSchema = Migration(version: 5) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS detected_codes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            screenshot_uuid TEXT NOT NULL,
            symbology TEXT NOT NULL,
            payload TEXT NOT NULL,
            is_url INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT,
            FOREIGN KEY (screenshot_uuid) REFERENCES screenshots(uuid) ON DELETE CASCADE
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_detected_codes_screenshot_uuid ON detected_codes(screenshot_uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_detected_codes_symbology ON detected_codes(symbology);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_detected_codes_is_url ON detected_codes(is_url);")
    }

    static let imageHashesSchema = Migration(version: 6) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS image_hashes (
            screenshot_uuid TEXT PRIMARY KEY,
            algorithm TEXT NOT NULL,
            hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (screenshot_uuid) REFERENCES screenshots(uuid) ON DELETE CASCADE
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_image_hashes_hash ON image_hashes(hash);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_image_hashes_algorithm ON image_hashes(algorithm);")
    }

    static let collectionSortIndexSchema = Migration(version: 7) { db in
        if try !collectionTableHasColumn("sort_index", database: db) {
            try db.exec("ALTER TABLE collections ADD COLUMN sort_index REAL NOT NULL DEFAULT 0;")
        }

        if try collectionSortIndexesNeedNormalization(database: db) {
            let rows = try collectionIDsByCreatedAt(database: db)
            let stmt = try db.prepare("UPDATE collections SET sort_index = ? WHERE id = ?;")
            for (index, id) in rows.enumerated() {
                stmt.reset()
                try stmt.bind(1, Double(index))
                try stmt.bind(2, id)
                _ = try stmt.step()
            }
        }
    }

    static let organizationRulesSchema = Migration(version: 8) { db in
        try db.exec("""
        CREATE TABLE IF NOT EXISTS organization_rules (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            priority INTEGER NOT NULL DEFAULT 0,
            match_mode TEXT NOT NULL DEFAULT 'all',
            conditions_json TEXT NOT NULL,
            actions_json TEXT NOT NULL,
            run_on_import INTEGER NOT NULL DEFAULT 1,
            run_after_ocr INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_organization_rules_uuid ON organization_rules(uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_organization_rules_is_enabled ON organization_rules(is_enabled);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_organization_rules_priority ON organization_rules(priority);")
        try db.exec("""
        CREATE TABLE IF NOT EXISTS organization_rule_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rule_uuid TEXT NOT NULL,
            screenshot_uuid TEXT NOT NULL,
            actions_applied_json TEXT,
            created_at TEXT NOT NULL
        );
        """)
        try db.exec("CREATE INDEX IF NOT EXISTS idx_organization_rule_runs_screenshot_uuid ON organization_rule_runs(screenshot_uuid);")
        try db.exec("CREATE INDEX IF NOT EXISTS idx_organization_rule_runs_rule_uuid ON organization_rule_runs(rule_uuid);")
    }

    static let originalPathSchema = Migration(version: 9) { db in
        if try !screenshotTableHasColumn("original_path", database: db) {
            try db.exec("ALTER TABLE screenshots ADD COLUMN original_path TEXT;")
        }
    }

    private static func collectionTableHasColumn(_ column: String, database: Database) throws -> Bool {
        let stmt = try database.prepare("PRAGMA table_info(collections);")
        while try stmt.step() {
            if stmt.columnString(1) == column {
                return true
            }
        }
        return false
    }

    private static func screenshotTableHasColumn(_ column: String, database: Database) throws -> Bool {
        let stmt = try database.prepare("PRAGMA table_info(screenshots);")
        while try stmt.step() {
            if stmt.columnString(1) == column {
                return true
            }
        }
        return false
    }

    private static func collectionSortIndexesNeedNormalization(database: Database) throws -> Bool {
        let stmt = try database.prepare("""
        SELECT COUNT(*), COUNT(DISTINCT sort_index)
        FROM collections
        WHERE type = 'manual';
        """)
        guard try stmt.step() else { return false }
        let total = Int(stmt.columnInt(0))
        let distinct = Int(stmt.columnInt(1))
        return total > 0 && total != distinct
    }

    private static func collectionIDsByCreatedAt(database: Database) throws -> [Int] {
        let stmt = try database.prepare("""
        SELECT id
        FROM collections
        WHERE type = 'manual'
        ORDER BY created_at ASC, id ASC;
        """)
        var ids: [Int] = []
        while try stmt.step() {
            ids.append(Int(stmt.columnInt(0)))
        }
        return ids
    }
}
