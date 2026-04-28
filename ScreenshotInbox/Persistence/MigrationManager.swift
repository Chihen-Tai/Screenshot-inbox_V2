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
}
