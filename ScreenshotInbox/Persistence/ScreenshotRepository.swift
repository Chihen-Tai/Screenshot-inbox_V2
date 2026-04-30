import Foundation

/// CRUD over the `screenshots` table. All work runs on the database's serial
/// queue so callers can invoke from any thread.
final class ScreenshotRepository {
    private let database: Database?

    init(database: Database) {
        self.database = database
    }

    /// No-op default init kept for source compatibility. All methods become
    /// no-ops on an empty repository.
    init() { self.database = nil }

    // MARK: - Reads

    func fetchAll(includeTrashed: Bool) throws -> [Screenshot] {
        guard let database else { return [] }
        return try database.queue.sync {
            let where_ = includeTrashed ? "" : "WHERE is_trashed = 0"
            let stmt = try database.prepare("\(Self.selectColumns) \(where_) ORDER BY imported_at DESC;")
            var rows: [Screenshot] = []
            while try stmt.step() {
                rows.append(Self.row(from: stmt))
            }
            return rows
        }
    }

    func fetchInbox() throws -> [Screenshot] {
        try fetchWhere("WHERE is_trashed = 0 ORDER BY imported_at DESC;")
    }

    func fetchTrashed() throws -> [Screenshot] {
        try fetchWhere("WHERE is_trashed = 1 ORDER BY trash_date DESC, imported_at DESC;")
    }

    func fetchFavorites() throws -> [Screenshot] {
        try fetchWhere("WHERE is_favorite = 1 AND is_trashed = 0 ORDER BY imported_at DESC;")
    }

    func fetchByUUID(_ uuid: UUID) throws -> Screenshot? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE uuid = ? LIMIT 1;")
            try stmt.bind(1, uuid.uuidString.lowercased())
            return try stmt.step() ? Self.row(from: stmt) : nil
        }
    }

    func findByHash(_ hash: String) throws -> Screenshot? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE file_hash = ? LIMIT 1;")
            try stmt.bind(1, hash)
            return try stmt.step() ? Self.row(from: stmt) : nil
        }
    }

    func fetchExactDuplicateGroups(includeTrashed: Bool = false) throws -> [DuplicateGroup] {
        let screenshots = try fetchAll(includeTrashed: includeTrashed)
        return DuplicateDetectionService.findDuplicateGroups(
            screenshots: screenshots,
            imageHashes: [:],
            includeTrashed: includeTrashed
        ).filter { $0.kind == .exact }
    }

    func fetchDuplicateCount(includeTrashed: Bool = false) throws -> Int {
        try fetchExactDuplicateGroups(includeTrashed: includeTrashed)
            .reduce(into: Set<String>()) { ids, group in
                ids.formUnion(group.screenshotUUIDs)
            }
            .count
    }

    private func fetchWhere(_ clause: String) throws -> [Screenshot] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) \(clause)")
            var rows: [Screenshot] = []
            while try stmt.step() {
                rows.append(Self.row(from: stmt))
            }
            return rows
        }
    }

    // MARK: - Writes

    func insert(_ shot: Screenshot) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO screenshots(
                uuid, filename, library_path, file_hash,
                width, height, file_size, format, source_app,
                created_at, imported_at, modified_at,
                is_favorite, is_trashed, trash_date, sort_index
            ) VALUES (?,?,?,?, ?,?,?,?,?, ?,?,?, ?,?,?,?);
            """)
            try Self.bindRow(shot, into: stmt)
            _ = try stmt.step()
        }
    }

    /// Updates every mutable column for the row identified by `uuid`.
    func update(_ shot: Screenshot) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            UPDATE screenshots SET
                filename = ?, library_path = ?, file_hash = ?,
                width = ?, height = ?, file_size = ?, format = ?, source_app = ?,
                created_at = ?, imported_at = ?, modified_at = ?,
                is_favorite = ?, is_trashed = ?, trash_date = ?, sort_index = ?
            WHERE uuid = ?;
            """)
            try stmt.bind(1,  shot.name)
            try stmt.bind(2,  shot.libraryPath ?? "")
            try stmt.bind(3,  shot.fileHash ?? "")
            try stmt.bind(4,  shot.pixelWidth)
            try stmt.bind(5,  shot.pixelHeight)
            try stmt.bind(6,  shot.byteSize)
            try stmt.bind(7,  shot.format)
            try stmt.bind(8,  shot.sourceApp)
            try stmt.bind(9,  shot.createdAt.timeIntervalSince1970)
            try stmt.bind(10, (shot.importedAt ?? shot.createdAt).timeIntervalSince1970)
            try stmt.bind(11, Date().timeIntervalSince1970)
            try stmt.bindBool(12, shot.isFavorite)
            try stmt.bindBool(13, shot.isTrashed)
            try stmt.bind(14, shot.trashDate?.timeIntervalSince1970)
            try stmt.bind(15, shot.sortIndex ?? 0)
            try stmt.bind(16, shot.uuidString)
            _ = try stmt.step()
        }
    }

    func markTrashed(ids: [UUID], trashed: Bool) throws {
        guard let database, !ids.isEmpty else { return }
        try database.queue.sync {
            try database.transaction {
                let stmt = try database.prepare("""
                UPDATE screenshots SET is_trashed = ?, trash_date = ?, modified_at = ? WHERE uuid = ?;
                """)
                let now = Date().timeIntervalSince1970
                for id in ids {
                    stmt.reset()
                    try stmt.bindBool(1, trashed)
                    try stmt.bind(2, trashed ? now : nil)
                    try stmt.bind(3, now)
                    try stmt.bind(4, id.uuidString.lowercased())
                    _ = try stmt.step()
                }
            }
        }
    }

    func updateFavorite(ids: [UUID], isFavorite: Bool) throws {
        guard let database, !ids.isEmpty else { return }
        try database.queue.sync {
            try database.transaction {
                let stmt = try database.prepare("""
                UPDATE screenshots SET is_favorite = ?, modified_at = ? WHERE uuid = ?;
                """)
                let now = Date().timeIntervalSince1970
                for id in ids {
                    stmt.reset()
                    try stmt.bindBool(1, isFavorite)
                    try stmt.bind(2, now)
                    try stmt.bind(3, id.uuidString.lowercased())
                    _ = try stmt.step()
                }
            }
        }
    }

    func restoreFromTrash(ids: [UUID]) throws {
        try markTrashed(ids: ids, trashed: false)
    }

    func restoreFromTrash(ids: [String]) throws {
        try restoreFromTrash(ids: ids.compactMap(UUID.init(uuidString:)))
    }

    func restoreAllFromTrash() throws {
        let ids = try fetchTrashed().map(\.id)
        try restoreFromTrash(ids: ids)
    }

    func emptyTrash() throws {
        let ids = try fetchTrashed().map(\.uuidString)
        try permanentlyDelete(ids: ids)
    }

    func permanentlyDelete(ids: [String]) throws {
        guard let database else { return }
        let requestedIDs = ids.map { $0.lowercased() }
        guard !requestedIDs.isEmpty else { return }
        let trashedIDs = try database.queue.sync {
            try fetchTrashedUUIDs(matching: requestedIDs, database: database)
        }
        try delete(uuids: trashedIDs.compactMap(UUID.init(uuidString:)))
    }

    func delete(uuid: UUID) throws {
        try delete(uuids: [uuid])
    }

    func delete(uuids: [UUID]) throws {
        guard let database else { return }
        let ids = uuids.map { $0.uuidString.lowercased() }
        guard !ids.isEmpty else { return }
        try database.queue.sync {
            try database.transaction {
                for table in ["collection_items", "screenshot_tags", "ocr_results", "detected_codes", "image_hashes"] {
                    try deleteRows(from: table, screenshotUUIDs: ids, database: database)
                }
                let stmt = try database.prepare("DELETE FROM screenshots WHERE uuid = ?;")
                for uuid in ids {
                    stmt.reset()
                    try stmt.bind(1, uuid)
                    _ = try stmt.step()
                }
            }
        }
    }

    private func deleteRows(from table: String, screenshotUUIDs: [String], database: Database) throws {
        guard try tableExists(table, database: database) else { return }
        let stmt = try database.prepare("DELETE FROM \(table) WHERE screenshot_uuid = ?;")
        for uuid in screenshotUUIDs {
            stmt.reset()
            try stmt.bind(1, uuid)
            _ = try stmt.step()
        }
    }

    private func fetchTrashedUUIDs(matching ids: [String], database: Database) throws -> [String] {
        let stmt = try database.prepare("SELECT uuid FROM screenshots WHERE uuid = ? AND is_trashed = 1;")
        var trashedIDs: [String] = []
        for uuid in ids {
            stmt.reset()
            try stmt.bind(1, uuid)
            while try stmt.step() {
                if let matched = stmt.columnString(0) {
                    trashedIDs.append(matched)
                }
            }
        }
        return trashedIDs
    }

    private func tableExists(_ name: String, database: Database) throws -> Bool {
        let stmt = try database.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;")
        try stmt.bind(1, name)
        return try stmt.step()
    }

    // MARK: - Row mapping

    /// Column order MUST match the `columnXxx(_:)` indices in `row(from:)`.
    static let selectColumns = """
    SELECT
        screenshots.uuid, screenshots.filename, screenshots.library_path, screenshots.file_hash,
        screenshots.width, screenshots.height, screenshots.file_size, screenshots.format, screenshots.source_app,
        screenshots.created_at, screenshots.imported_at, screenshots.modified_at,
        screenshots.is_favorite, screenshots.is_trashed, screenshots.trash_date, screenshots.sort_index
    FROM screenshots
    """

    static func row(from s: Database.Statement) -> Screenshot {
        let uuidString = s.columnString(0) ?? UUID().uuidString
        let id = UUID(uuidString: uuidString) ?? UUID()
        let filename     = s.columnString(1) ?? ""
        let libraryPath  = s.columnString(2)
        let fileHash     = s.columnString(3)
        let width        = Int(s.columnInt(4))
        let height       = Int(s.columnInt(5))
        let fileSize     = Int(s.columnInt(6))
        let format       = s.columnString(7) ?? ""
        let sourceApp    = s.columnString(8)
        let createdAt    = Date(timeIntervalSince1970: s.columnDouble(9))
        let importedAt   = Date(timeIntervalSince1970: s.columnDouble(10))
        let modifiedAt   = Date(timeIntervalSince1970: s.columnDouble(11))
        let isFavorite   = s.columnInt(12) != 0
        let isTrashed    = s.columnInt(13) != 0
        let trashDate    = s.columnIsNull(14) ? nil : Date(timeIntervalSince1970: s.columnDouble(14))
        let sortIndex    = Int(s.columnInt(15))

        return Screenshot(
            id: id,
            name: filename,
            createdAt: createdAt,
            pixelWidth: width,
            pixelHeight: height,
            byteSize: fileSize,
            format: format,
            tags: [],
            ocrSnippets: [],
            isFavorite: isFavorite,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: isTrashed,
            libraryPath: libraryPath,
            fileHash: fileHash,
            importedAt: importedAt,
            modifiedAt: modifiedAt,
            sourceApp: sourceApp,
            sortIndex: sortIndex,
            trashDate: trashDate
        )
    }

    private static func bindRow(_ shot: Screenshot, into stmt: Database.Statement) throws {
        try stmt.bind(1,  shot.uuidString)
        try stmt.bind(2,  shot.name)
        try stmt.bind(3,  shot.libraryPath ?? "")
        try stmt.bind(4,  shot.fileHash ?? "")
        try stmt.bind(5,  shot.pixelWidth)
        try stmt.bind(6,  shot.pixelHeight)
        try stmt.bind(7,  shot.byteSize)
        try stmt.bind(8,  shot.format)
        try stmt.bind(9,  shot.sourceApp)
        try stmt.bind(10, shot.createdAt.timeIntervalSince1970)
        try stmt.bind(11, (shot.importedAt ?? shot.createdAt).timeIntervalSince1970)
        try stmt.bind(12, (shot.modifiedAt ?? shot.importedAt ?? shot.createdAt).timeIntervalSince1970)
        try stmt.bindBool(13, shot.isFavorite)
        try stmt.bindBool(14, shot.isTrashed)
        try stmt.bind(15, shot.trashDate?.timeIntervalSince1970)
        try stmt.bind(16, shot.sortIndex ?? 0)
    }
}
