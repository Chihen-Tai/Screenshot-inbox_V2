import Foundation

final class TagRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) { self.database = database }
    init() { self.database = nil }

    func createTag(name: String, color: String?) throws -> Tag {
        let normalized = normalize(name)
        guard !normalized.isEmpty else { throw TagRepositoryError.emptyName }
        if let existing = try fetchTag(named: normalized) { return existing }
        guard let database else {
            return Tag(id: nil, uuid: UUID().uuidString.lowercased(), name: normalized, color: color, createdAt: Date(), updatedAt: nil)
        }
        let tag = Tag(id: nil, uuid: UUID().uuidString.lowercased(), name: normalized, color: color, createdAt: Date(), updatedAt: nil)
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT OR IGNORE INTO tags(uuid, name, color, created_at, updated_at)
            VALUES(?,?,?,?,NULL);
            """)
            try stmt.bind(1, tag.uuid)
            try stmt.bind(2, tag.name)
            try stmt.bind(3, tag.color)
            try stmt.bind(4, dateFormatter.string(from: tag.createdAt))
            _ = try stmt.step()
        }
        return try fetchTag(named: normalized) ?? tag
    }

    func fetchTags() throws -> [Tag] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("SELECT id, uuid, name, color, created_at, updated_at FROM tags ORDER BY name COLLATE NOCASE ASC;")
            var rows: [Tag] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchTags(forScreenshot screenshotUUID: String) throws -> [Tag] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT t.id, t.uuid, t.name, t.color, t.created_at, t.updated_at
            FROM tags t
            JOIN screenshot_tags st ON st.tag_id = t.id
            WHERE st.screenshot_uuid = ?
            ORDER BY t.name COLLATE NOCASE ASC;
            """)
            try stmt.bind(1, screenshotUUID.lowercased())
            var rows: [Tag] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func addTag(name: String, toScreenshots screenshotUUIDs: [String]) throws {
        let tag = try createTag(name: name, color: nil)
        try addTag(tagUUID: tag.uuid, toScreenshots: screenshotUUIDs)
    }

    func addTag(tagUUID: String, toScreenshots screenshotUUIDs: [String]) throws {
        guard let database, !screenshotUUIDs.isEmpty else { return }
        try database.queue.sync {
            guard let tagID = try tagID(uuid: tagUUID, database: database) else { return }
            try database.transaction {
                let stmt = try database.prepare("""
                INSERT OR IGNORE INTO screenshot_tags(tag_id, screenshot_uuid, created_at)
                VALUES(?,?,?);
                """)
                let now = dateFormatter.string(from: Date())
                for uuid in screenshotUUIDs {
                    stmt.reset()
                    try stmt.bind(1, tagID)
                    try stmt.bind(2, uuid.lowercased())
                    try stmt.bind(3, now)
                    _ = try stmt.step()
                }
            }
        }
    }

    func removeTag(tagUUID: String, fromScreenshots screenshotUUIDs: [String]) throws {
        guard let database, !screenshotUUIDs.isEmpty else { return }
        try database.queue.sync {
            guard let tagID = try tagID(uuid: tagUUID, database: database) else { return }
            let stmt = try database.prepare("DELETE FROM screenshot_tags WHERE tag_id = ? AND screenshot_uuid = ?;")
            for uuid in screenshotUUIDs {
                stmt.reset()
                try stmt.bind(1, tagID)
                try stmt.bind(2, uuid.lowercased())
                _ = try stmt.step()
            }
        }
    }

    func fetchScreenshots(withTag tagUUID: String) throws -> [Screenshot] {
        guard let database else { return [] }
        return try database.queue.sync {
            guard let tagID = try tagID(uuid: tagUUID, database: database) else { return [] }
            let stmt = try database.prepare("""
            \(ScreenshotRepository.selectColumns)
            JOIN screenshot_tags st ON st.screenshot_uuid = screenshots.uuid
            WHERE st.tag_id = ? AND screenshots.is_trashed = 0
            ORDER BY screenshots.imported_at DESC;
            """)
            try stmt.bind(1, tagID)
            var rows: [Screenshot] = []
            while try stmt.step() { rows.append(ScreenshotRepository.row(from: stmt)) }
            return rows
        }
    }

    func countScreenshots(withTag tagUUID: String) throws -> Int {
        guard let database else { return 0 }
        return try database.queue.sync {
            guard let tagID = try tagID(uuid: tagUUID, database: database) else { return 0 }
            let stmt = try database.prepare("""
            SELECT COUNT(*)
            FROM screenshot_tags st
            JOIN screenshots s ON s.uuid = st.screenshot_uuid
            WHERE st.tag_id = ? AND s.is_trashed = 0;
            """)
            try stmt.bind(1, tagID)
            return try stmt.step() ? Int(stmt.columnInt(0)) : 0
        }
    }

    func tagsByScreenshotUUID() throws -> [String: [Tag]] {
        guard let database else { return [:] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT st.screenshot_uuid, t.id, t.uuid, t.name, t.color, t.created_at, t.updated_at
            FROM screenshot_tags st
            JOIN tags t ON t.id = st.tag_id
            ORDER BY t.name COLLATE NOCASE ASC;
            """)
            var grouped: [String: [Tag]] = [:]
            while try stmt.step() {
                let screenshotUUID = stmt.columnString(0) ?? ""
                let tag = Tag(
                    id: Int(stmt.columnInt(1)),
                    uuid: stmt.columnString(2) ?? UUID().uuidString.lowercased(),
                    name: stmt.columnString(3) ?? "",
                    color: stmt.columnString(4),
                    createdAt: dateFormatter.date(from: stmt.columnString(5) ?? "") ?? Date(),
                    updatedAt: stmt.columnString(6).flatMap { dateFormatter.date(from: $0) }
                )
                grouped[screenshotUUID, default: []].append(tag)
            }
            return grouped
        }
    }

    private func fetchTag(named name: String) throws -> Tag? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("SELECT id, uuid, name, color, created_at, updated_at FROM tags WHERE name = ? LIMIT 1;")
            try stmt.bind(1, name)
            return try stmt.step() ? row(from: stmt) : nil
        }
    }

    private func row(from stmt: Database.Statement) -> Tag {
        Tag(
            id: Int(stmt.columnInt(0)),
            uuid: stmt.columnString(1) ?? UUID().uuidString.lowercased(),
            name: stmt.columnString(2) ?? "",
            color: stmt.columnString(3),
            createdAt: dateFormatter.date(from: stmt.columnString(4) ?? "") ?? Date(),
            updatedAt: stmt.columnString(5).flatMap { dateFormatter.date(from: $0) }
        )
    }

    private func tagID(uuid: String, database: Database) throws -> Int? {
        let stmt = try database.prepare("SELECT id FROM tags WHERE uuid = ? LIMIT 1;")
        try stmt.bind(1, uuid)
        return try stmt.step() ? Int(stmt.columnInt(0)) : nil
    }

    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TagRepositoryError: Error {
    case emptyName
}
