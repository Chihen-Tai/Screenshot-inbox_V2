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

    func delete(uuid: UUID) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM screenshots WHERE uuid = ?;")
            try stmt.bind(1, uuid.uuidString.lowercased())
            _ = try stmt.step()
        }
    }

    // MARK: - Row mapping

    /// Column order MUST match the `columnXxx(_:)` indices in `row(from:)`.
    private static let selectColumns = """
    SELECT
        uuid, filename, library_path, file_hash,
        width, height, file_size, format, source_app,
        created_at, imported_at, modified_at,
        is_favorite, is_trashed, trash_date, sort_index
    FROM screenshots
    """

    private static func row(from s: Database.Statement) -> Screenshot {
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
