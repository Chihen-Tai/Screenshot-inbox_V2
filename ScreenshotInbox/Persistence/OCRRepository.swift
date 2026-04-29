import Foundation

final class OCRRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func upsertPending(screenshotUUID: String) throws {
        guard let database else { return }
        let now = dateFormatter.string(from: Date())
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO ocr_results(screenshot_uuid, text, language, confidence, status, error_message, created_at, updated_at)
            VALUES(?, NULL, NULL, NULL, 'pending', NULL, ?, NULL)
            ON CONFLICT(screenshot_uuid) DO NOTHING;
            """)
            try stmt.bind(1, screenshotUUID.lowercased())
            try stmt.bind(2, now)
            _ = try stmt.step()
        }
    }

    func ensurePending(for screenshotUUIDs: [String]) throws {
        for uuid in screenshotUUIDs {
            try upsertPending(screenshotUUID: uuid)
        }
    }

    func markProcessing(screenshotUUID: String) throws {
        try updateStatus(uuid: screenshotUUID, status: .processing, error: nil)
    }

    func saveResult(screenshotUUID: String, text: String, language: String?, confidence: Double?) throws {
        guard let database else { return }
        let now = dateFormatter.string(from: Date())
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO ocr_results(screenshot_uuid, text, language, confidence, status, error_message, created_at, updated_at)
            VALUES(?, ?, ?, ?, 'complete', NULL, ?, ?)
            ON CONFLICT(screenshot_uuid) DO UPDATE SET
                text = excluded.text,
                language = excluded.language,
                confidence = excluded.confidence,
                status = 'complete',
                error_message = NULL,
                updated_at = excluded.updated_at;
            """)
            try stmt.bind(1, screenshotUUID.lowercased())
            try stmt.bind(2, text)
            try stmt.bind(3, language)
            try stmt.bind(4, confidence)
            try stmt.bind(5, now)
            try stmt.bind(6, now)
            _ = try stmt.step()
        }
    }

    func markFailed(screenshotUUID: String, error: String) throws {
        try updateStatus(uuid: screenshotUUID, status: .failed, error: error)
    }

    func fetch(for screenshotUUID: String) throws -> OCRResult? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE screenshot_uuid = ? LIMIT 1;")
            try stmt.bind(1, screenshotUUID.lowercased())
            return try stmt.step() ? row(from: stmt) : nil
        }
    }

    func fetchAll() throws -> [OCRResult] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) ORDER BY updated_at DESC;")
            var rows: [OCRResult] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchPending(limit: Int) throws -> [OCRResult] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE status = 'pending' ORDER BY created_at ASC LIMIT ?;")
            try stmt.bind(1, limit)
            var rows: [OCRResult] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchByStatus(_ status: OCRStatus) throws -> [OCRResult] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("\(Self.selectColumns) WHERE status = ? ORDER BY updated_at DESC;")
            try stmt.bind(1, status.rawValue)
            var rows: [OCRResult] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func resetProcessingToPending() throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("UPDATE ocr_results SET status = 'pending', updated_at = ? WHERE status = 'processing';")
            try stmt.bind(1, dateFormatter.string(from: Date()))
            _ = try stmt.step()
        }
    }

    func resetToPending(screenshotUUIDs: [String]) throws {
        guard let database, !screenshotUUIDs.isEmpty else { return }
        let now = dateFormatter.string(from: Date())
        try database.queue.sync {
            try database.transaction {
                let stmt = try database.prepare("""
                INSERT INTO ocr_results(screenshot_uuid, text, language, confidence, status, error_message, created_at, updated_at)
                VALUES(?, NULL, NULL, NULL, 'pending', NULL, ?, ?)
                ON CONFLICT(screenshot_uuid) DO UPDATE SET
                    text = NULL,
                    language = NULL,
                    confidence = NULL,
                    status = 'pending',
                    error_message = NULL,
                    updated_at = excluded.updated_at;
                """)
                for uuid in screenshotUUIDs {
                    stmt.reset()
                    try stmt.bind(1, uuid.lowercased())
                    try stmt.bind(2, now)
                    try stmt.bind(3, now)
                    _ = try stmt.step()
                }
            }
        }
    }

    func delete(for screenshotUUID: String) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM ocr_results WHERE screenshot_uuid = ?;")
            try stmt.bind(1, screenshotUUID.lowercased())
            _ = try stmt.step()
        }
    }

    private func updateStatus(uuid: String, status: OCRStatus, error: String?) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("""
            UPDATE ocr_results SET status = ?, error_message = ?, updated_at = ? WHERE screenshot_uuid = ?;
            """)
            try stmt.bind(1, status.rawValue)
            try stmt.bind(2, error)
            try stmt.bind(3, dateFormatter.string(from: Date()))
            try stmt.bind(4, uuid.lowercased())
            _ = try stmt.step()
        }
    }

    private static let selectColumns = """
    SELECT id, screenshot_uuid, text, language, confidence, status, error_message, created_at, updated_at
    FROM ocr_results
    """

    private func row(from stmt: Database.Statement) -> OCRResult {
        OCRResult(
            id: Int(stmt.columnInt(0)),
            screenshotUUID: stmt.columnString(1) ?? "",
            text: stmt.columnString(2),
            language: stmt.columnString(3),
            confidence: stmt.columnIsNull(4) ? nil : stmt.columnDouble(4),
            status: OCRStatus(rawValue: stmt.columnString(5) ?? "") ?? .pending,
            errorMessage: stmt.columnString(6),
            createdAt: dateFormatter.date(from: stmt.columnString(7) ?? "") ?? Date(),
            updatedAt: stmt.columnString(8).flatMap { dateFormatter.date(from: $0) }
        )
    }
}
