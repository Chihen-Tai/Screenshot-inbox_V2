import Foundation

final class CollectionRepository {
    private let database: Database?
    private let dateFormatter = ISO8601DateFormatter()

    init(database: Database) {
        self.database = database
    }

    init() {
        self.database = nil
    }

    func createCollection(name: String) throws -> ScreenshotCollection {
        let normalized = try validateName(name)
        guard let database else {
            return ScreenshotCollection(id: nil, uuid: UUID().uuidString.lowercased(), name: normalized, type: "manual", sortIndex: 0, createdAt: Date(), updatedAt: nil)
        }
        if try collectionNameExists(normalized, excludingUUID: nil) {
            throw CollectionRepositoryError.duplicateName
        }
        let now = Date()
        let collection = ScreenshotCollection(
            id: nil,
            uuid: UUID().uuidString.lowercased(),
            name: normalized,
            type: "manual",
            sortIndex: now.timeIntervalSince1970,
            createdAt: now,
            updatedAt: nil
        )
        try database.queue.sync {
            let stmt = try database.prepare("""
            INSERT INTO collections(uuid, name, type, sort_index, created_at, updated_at)
            VALUES(?,?,?,?,?,NULL);
            """)
            try bind(collection, into: stmt)
            _ = try stmt.step()
        }
        return try fetchCollection(uuid: collection.uuid) ?? collection
    }

    func fetchCollections() throws -> [ScreenshotCollection] {
        guard let database else { return [] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT id, uuid, name, type, sort_index, created_at, updated_at
            FROM collections
            ORDER BY sort_index ASC, created_at ASC;
            """)
            var rows: [ScreenshotCollection] = []
            while try stmt.step() { rows.append(row(from: stmt)) }
            return rows
        }
    }

    func fetchCollection(uuid: String) throws -> ScreenshotCollection? {
        guard let database else { return nil }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT id, uuid, name, type, sort_index, created_at, updated_at
            FROM collections WHERE uuid = ? LIMIT 1;
            """)
            try stmt.bind(1, uuid)
            return try stmt.step() ? row(from: stmt) : nil
        }
    }

    func renameCollection(uuid: String, name: String) throws {
        let normalized = try validateName(name)
        guard let database else { return }
        if try collectionNameExists(normalized, excludingUUID: uuid) {
            throw CollectionRepositoryError.duplicateName
        }
        try database.queue.sync {
            let stmt = try database.prepare("UPDATE collections SET name = ?, updated_at = ? WHERE uuid = ?;")
            try stmt.bind(1, normalized)
            try stmt.bind(2, dateFormatter.string(from: Date()))
            try stmt.bind(3, uuid)
            _ = try stmt.step()
        }
    }

    func deleteCollection(uuid: String) throws {
        guard let database else { return }
        try database.queue.sync {
            let stmt = try database.prepare("DELETE FROM collections WHERE uuid = ?;")
            try stmt.bind(1, uuid)
            _ = try stmt.step()
        }
    }

    func updateSortOrder(collectionUUIDsInOrder: [String]) throws {
        guard let database, !collectionUUIDsInOrder.isEmpty else { return }
        try database.queue.sync {
            try database.transaction {
                let stmt = try database.prepare("UPDATE collections SET sort_index = ?, updated_at = ? WHERE uuid = ? AND type = 'manual';")
                let now = dateFormatter.string(from: Date())
                for (index, uuid) in collectionUUIDsInOrder.enumerated() {
                    stmt.reset()
                    try stmt.bind(1, Double(index))
                    try stmt.bind(2, now)
                    try stmt.bind(3, uuid)
                    _ = try stmt.step()
                }
            }
        }
    }

    func reorderCollections(uuidsInOrder: [String]) throws {
        try updateSortOrder(collectionUUIDsInOrder: uuidsInOrder)
    }

    func addScreenshots(_ screenshotUUIDs: [String], toCollection collectionUUID: String) throws {
        guard let database, !screenshotUUIDs.isEmpty else { return }
        try database.queue.sync {
            guard let collectionID = try collectionID(uuid: collectionUUID, database: database) else { return }
            try database.transaction {
                let stmt = try database.prepare("""
                INSERT OR IGNORE INTO collection_items(collection_id, screenshot_uuid, sort_index, created_at)
                VALUES(?,?,?,?);
                """)
                let now = Date()
                for (index, uuid) in screenshotUUIDs.enumerated() {
                    stmt.reset()
                    try stmt.bind(1, collectionID)
                    try stmt.bind(2, uuid.lowercased())
                    try stmt.bind(3, Double(index))
                    try stmt.bind(4, dateFormatter.string(from: now))
                    _ = try stmt.step()
                }
            }
        }
    }

    func removeScreenshots(_ screenshotUUIDs: [String], fromCollection collectionUUID: String) throws {
        guard let database, !screenshotUUIDs.isEmpty else { return }
        try database.queue.sync {
            guard let collectionID = try collectionID(uuid: collectionUUID, database: database) else { return }
            let stmt = try database.prepare("DELETE FROM collection_items WHERE collection_id = ? AND screenshot_uuid = ?;")
            for uuid in screenshotUUIDs {
                stmt.reset()
                try stmt.bind(1, collectionID)
                try stmt.bind(2, uuid.lowercased())
                _ = try stmt.step()
            }
        }
    }

    func fetchScreenshots(inCollection collectionUUID: String) throws -> [Screenshot] {
        guard let database else { return [] }
        return try database.queue.sync {
            guard let collectionID = try collectionID(uuid: collectionUUID, database: database) else { return [] }
            let stmt = try database.prepare("""
            \(ScreenshotRepository.selectColumns)
            JOIN collection_items ci ON ci.screenshot_uuid = screenshots.uuid
            WHERE ci.collection_id = ? AND screenshots.is_trashed = 0
            ORDER BY ci.sort_index ASC, screenshots.imported_at DESC;
            """)
            try stmt.bind(1, collectionID)
            var rows: [Screenshot] = []
            while try stmt.step() { rows.append(ScreenshotRepository.row(from: stmt)) }
            return rows
        }
    }

    func countItems(inCollection collectionUUID: String) throws -> Int {
        guard let database else { return 0 }
        return try database.queue.sync {
            guard let collectionID = try collectionID(uuid: collectionUUID, database: database) else { return 0 }
            let stmt = try database.prepare("""
            SELECT COUNT(*)
            FROM collection_items ci
            JOIN screenshots s ON s.uuid = ci.screenshot_uuid
            WHERE ci.collection_id = ? AND s.is_trashed = 0;
            """)
            try stmt.bind(1, collectionID)
            return try stmt.step() ? Int(stmt.columnInt(0)) : 0
        }
    }

    func countsByCollectionUUID() throws -> [String: Int] {
        guard let database else { return [:] }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT c.uuid, COUNT(s.uuid)
            FROM collections c
            LEFT JOIN collection_items ci ON ci.collection_id = c.id
            LEFT JOIN screenshots s ON s.uuid = ci.screenshot_uuid AND s.is_trashed = 0
            GROUP BY c.uuid;
            """)
            var counts: [String: Int] = [:]
            while try stmt.step() {
                if let uuid = stmt.columnString(0) {
                    counts[uuid] = Int(stmt.columnInt(1))
                }
            }
            return counts
        }
    }

    func ensureDefaultCollections() throws {
        guard try fetchCollections().isEmpty else { return }
        for name in ["Chemistry", "Papers", "UI Ideas", "Temporary"] {
            _ = try createCollection(name: name)
        }
    }

    private func bind(_ collection: ScreenshotCollection, into stmt: Database.Statement) throws {
        try stmt.bind(1, collection.uuid)
        try stmt.bind(2, collection.name)
        try stmt.bind(3, collection.type)
        try stmt.bind(4, collection.sortIndex)
        try stmt.bind(5, dateFormatter.string(from: collection.createdAt))
    }

    private func row(from stmt: Database.Statement) -> ScreenshotCollection {
        ScreenshotCollection(
            id: Int(stmt.columnInt(0)),
            uuid: stmt.columnString(1) ?? UUID().uuidString.lowercased(),
            name: stmt.columnString(2) ?? "",
            type: stmt.columnString(3) ?? "manual",
            sortIndex: stmt.columnDouble(4),
            createdAt: dateFormatter.date(from: stmt.columnString(5) ?? "") ?? Date(),
            updatedAt: stmt.columnString(6).flatMap { dateFormatter.date(from: $0) }
        )
    }

    private func collectionID(uuid: String, database: Database) throws -> Int? {
        let stmt = try database.prepare("SELECT id FROM collections WHERE uuid = ? LIMIT 1;")
        try stmt.bind(1, uuid)
        return try stmt.step() ? Int(stmt.columnInt(0)) : nil
    }

    private func validateName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw CollectionRepositoryError.emptyName }
        return normalized
    }

    private func collectionNameExists(_ name: String, excludingUUID: String?) throws -> Bool {
        guard let database else { return false }
        return try database.queue.sync {
            let stmt = try database.prepare("""
            SELECT uuid FROM collections
            WHERE name = ? COLLATE NOCASE
            LIMIT 1;
            """)
            try stmt.bind(1, name)
            guard try stmt.step(), let existingUUID = stmt.columnString(0) else {
                return false
            }
            return existingUUID != excludingUUID
        }
    }
}

enum CollectionRepositoryError: Error, Equatable {
    case emptyName
    case duplicateName
}
