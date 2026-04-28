import Foundation

final class ImportSourceRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func create(folderPath: String, displayName: String?, recursive: Bool) throws -> ImportSource {
        let now = Date()
        let source = ImportSource(
            id: nil,
            uuid: UUID().uuidString.lowercased(),
            folderPath: folderPath,
            displayName: displayName,
            isEnabled: true,
            recursive: recursive,
            enabledSince: now,
            lastScannedAt: nil,
            createdAt: now,
            updatedAt: nil
        )
        guard let database else { return source }
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO import_sources(
                uuid, folder_path, display_name, is_enabled, recursive,
                enabled_since, last_scanned_at, created_at, updated_at
            )
            VALUES(?,?,?,?,?,?,?,?,NULL);
            """)
            try bind(source, into: stmt)
            _ = try stmt.step()
        }
        return try fetch(uuid: source.uuid) ?? source
    }

    func fetchAll() throws -> [ImportSource] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT id, uuid, folder_path, display_name, is_enabled, recursive,
                   enabled_since, last_scanned_at, created_at, updated_at
            FROM import_sources
            ORDER BY created_at ASC;
            """)
            var rows: [ImportSource] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchEnabled() throws -> [ImportSource] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT id, uuid, folder_path, display_name, is_enabled, recursive,
                   enabled_since, last_scanned_at, created_at, updated_at
            FROM import_sources
            WHERE is_enabled = 1
            ORDER BY created_at ASC;
            """)
            var rows: [ImportSource] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func update(_ source: ImportSource) throws {
        guard let database else { return }
        var updated = source
        updated.updatedAt = Date()
        try database.queue.sync {
            let stmt = try database.prepare("""
            UPDATE import_sources
            SET folder_path = ?, display_name = ?, is_enabled = ?, recursive = ?,
                enabled_since = ?, last_scanned_at = ?, updated_at = ?
            WHERE uuid = ?;
            """)
            try stmt.bind(1, updated.folderPath)
            try stmt.bind(2, updated.displayName)
            try stmt.bindBool(3, updated.isEnabled)
            try stmt.bindBool(4, updated.recursive)
            try stmt.bind(5, updated.enabledSince.map(dateFormatter.string(from:)))
            try stmt.bind(6, updated.lastScannedAt.map(dateFormatter.string(from:)))
            try stmt.bind(7, updated.updatedAt.map(dateFormatter.string(from:)))
            try stmt.bind(8, updated.uuid)
            _ = try stmt.step()
        }
    }

    func setEnabled(uuid: String, enabled: Bool) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            UPDATE import_sources
            SET is_enabled = ?, enabled_since = ?, updated_at = ?
            WHERE uuid = ?;
            """)
            let now = Date()
            try stmt.bindBool(1, enabled)
            try stmt.bind(2, enabled ? dateFormatter.string(from: now) : nil)
            try stmt.bind(3, dateFormatter.string(from: now))
            try stmt.bind(4, uuid)
            _ = try stmt.step()
        }
    }

    func delete(uuid: String) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM import_sources WHERE uuid = ?;")
            try stmt.bind(1, uuid)
            _ = try stmt.step()
        }
    }

    func updateLastScanned(uuid: String, date: Date) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("UPDATE import_sources SET last_scanned_at = ?, updated_at = ? WHERE uuid = ?;")
            let value = dateFormatter.string(from: date)
            try stmt.bind(1, value)
            try stmt.bind(2, value)
            try stmt.bind(3, uuid)
            _ = try stmt.step()
        }
    }

    private func fetch(uuid: String) throws -> ImportSource? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT id, uuid, folder_path, display_name, is_enabled, recursive,
                   enabled_since, last_scanned_at, created_at, updated_at
            FROM import_sources
            WHERE uuid = ?
            LIMIT 1;
            """)
            try stmt.bind(1, uuid)
            return try stmt.step() ? row(from: stmt) : nil
        }
    }

    private func bind(_ source: ImportSource, into stmt: Database.Statement) throws {
        try stmt.bind(1, source.uuid)
        try stmt.bind(2, source.folderPath)
        try stmt.bind(3, source.displayName)
        try stmt.bindBool(4, source.isEnabled)
        try stmt.bindBool(5, source.recursive)
        try stmt.bind(6, source.enabledSince.map(dateFormatter.string(from:)))
        try stmt.bind(7, source.lastScannedAt.map(dateFormatter.string(from:)))
        try stmt.bind(8, dateFormatter.string(from: source.createdAt))
    }

    private func row(from stmt: Database.Statement) -> ImportSource {
        ImportSource(
            id: Int(stmt.columnInt(0)),
            uuid: stmt.columnString(1) ?? UUID().uuidString.lowercased(),
            folderPath: stmt.columnString(2) ?? "",
            displayName: stmt.columnString(3),
            isEnabled: stmt.columnInt(4) != 0,
            recursive: stmt.columnInt(5) != 0,
            enabledSince: stmt.columnString(6).flatMap { dateFormatter.date(from: $0) },
            lastScannedAt: stmt.columnString(7).flatMap { dateFormatter.date(from: $0) },
            createdAt: dateFormatter.date(from: stmt.columnString(8) ?? "") ?? Date(),
            updatedAt: stmt.columnString(9).flatMap { dateFormatter.date(from: $0) }
        )
    }
}
