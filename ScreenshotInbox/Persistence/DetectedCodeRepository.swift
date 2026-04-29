import Foundation

final class DetectedCodeRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func saveCodes(_ codes: [DetectedCode], for screenshotUUID: String) throws {
        guard let database else { return }
        let uuid = screenshotUUID.lowercased()
        let now = dateFormatter.string(from: Date())
        try database.queue.sync {
            try database.transaction {
                let delete = try database.prepare("DELETE FROM detected_codes WHERE screenshot_uuid = ?;")
                try delete.bind(1, uuid)
                _ = try delete.step()

                guard !codes.isEmpty else { return }
                let insert = try database.prepare("""
                INSERT INTO detected_codes(
                    screenshot_uuid, symbology, payload, is_url, created_at, updated_at
                ) VALUES(?, ?, ?, ?, ?, ?);
                """)
                for code in codes {
                    insert.reset()
                    try insert.bind(1, uuid)
                    try insert.bind(2, code.symbology)
                    try insert.bind(3, code.payload)
                    try insert.bind(4, code.isURL ? 1 : 0)
                    try insert.bind(5, now)
                    try insert.bind(6, now)
                    _ = try insert.step()
                }
            }
        }
    }

    func fetchCodes(for screenshotUUID: String) throws -> [DetectedCode] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE screenshot_uuid = ? ORDER BY id ASC;")
            try stmt.bind(1, screenshotUUID.lowercased())
            var rows: [DetectedCode] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchAll() throws -> [DetectedCode] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) ORDER BY created_at DESC;")
            var rows: [DetectedCode] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func deleteCodes(for screenshotUUID: String) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM detected_codes WHERE screenshot_uuid = ?;")
            try stmt.bind(1, screenshotUUID.lowercased())
            _ = try stmt.step()
        }
    }

    private static let selectColumns = """
    SELECT id, screenshot_uuid, symbology, payload, is_url, created_at, updated_at
    FROM detected_codes
    """

    private func row(from stmt: Database.Statement) -> DetectedCode {
        DetectedCode(
            id: Int(stmt.columnInt(0)),
            screenshotUUID: stmt.columnString(1) ?? "",
            symbology: stmt.columnString(2) ?? "",
            payload: stmt.columnString(3) ?? "",
            isURL: stmt.columnInt(4) != 0,
            createdAt: dateFormatter.date(from: stmt.columnString(5) ?? "") ?? Date(),
            updatedAt: stmt.columnString(6).flatMap { dateFormatter.date(from: $0) }
        )
    }
}
