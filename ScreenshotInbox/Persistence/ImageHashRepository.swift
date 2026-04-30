import Foundation

final class ImageHashRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func upsert(_ record: ImageHashRecord) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO image_hashes(screenshot_uuid, algorithm, hash, created_at)
            VALUES(?, ?, ?, ?)
            ON CONFLICT(screenshot_uuid) DO UPDATE SET
                algorithm = excluded.algorithm,
                hash = excluded.hash,
                created_at = excluded.created_at;
            """)
            try stmt.bind(1, record.screenshotUUID.lowercased())
            try stmt.bind(2, record.algorithm)
            try stmt.bind(3, record.hash.lowercased())
            try stmt.bind(4, dateFormatter.string(from: record.createdAt))
            _ = try stmt.step()
        }
    }

    func fetchAll(algorithm: String = ImageHashRecord.dHashAlgorithm) throws -> [String: ImageHashRecord] {
        guard let database else { return [:] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT screenshot_uuid, algorithm, hash, created_at
            FROM image_hashes
            WHERE algorithm = ?;
            """)
            try stmt.bind(1, algorithm)
            var rows: [String: ImageHashRecord] = [:]
            while try stmt.step() {
                let record = row(from: stmt)
                rows[record.screenshotUUID] = record
            }
            return rows
        }
    }

    func fetchMissingScreenshotUUIDs(
        algorithm: String = ImageHashRecord.dHashAlgorithm,
        includeTrashed: Bool = false
    ) throws -> [String] {
        guard let database else { return [] }
        return try database.queue.sync {
            let trashClause = includeTrashed ? "" : "AND s.is_trashed = 0"
            let stmt = try database.prepare("""
            SELECT s.uuid
            FROM screenshots s
            LEFT JOIN image_hashes h
              ON h.screenshot_uuid = s.uuid AND h.algorithm = ?
            WHERE h.screenshot_uuid IS NULL \(trashClause)
            ORDER BY s.imported_at ASC;
            """)
            try stmt.bind(1, algorithm)
            var rows: [String] = []
            while try stmt.step() {
                if let uuid = stmt.columnString(0) {
                    rows.append(uuid.lowercased())
                }
            }
            return rows
        }
    }

    private func row(from stmt: Database.Statement) -> ImageHashRecord {
        ImageHashRecord(
            screenshotUUID: (stmt.columnString(0) ?? "").lowercased(),
            algorithm: stmt.columnString(1) ?? ImageHashRecord.dHashAlgorithm,
            hash: (stmt.columnString(2) ?? "").lowercased(),
            createdAt: dateFormatter.date(from: stmt.columnString(3) ?? "") ?? Date()
        )
    }
}
