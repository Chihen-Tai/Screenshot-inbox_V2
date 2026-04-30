import Foundation
import Testing
@testable import ScreenshotInbox

struct ScreenshotRepositoryTrashTests {
    @Test
    func restoreAllFromTrashClearsTrashStateOnlyForTrashedRows() throws {
        let database = try makeDatabase()
        let repository = ScreenshotRepository(database: database)
        let trashed = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000401", trashed: true)
        let active = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000402", trashed: false)
        try repository.insert(trashed)
        try repository.insert(active)

        try repository.restoreAllFromTrash()

        #expect(try repository.fetchTrashed().isEmpty)
        let restored = try #require(try repository.fetchByUUID(trashed.id))
        let untouched = try #require(try repository.fetchByUUID(active.id))
        #expect(restored.isTrashed == false)
        #expect(restored.trashDate == nil)
        #expect(untouched.isTrashed == false)
    }

    @Test
    func permanentlyDeleteRemovesOnlyTrashedRowsAndRelatedMetadata() throws {
        let database = try makeDatabase()
        let repository = ScreenshotRepository(database: database)
        let trashed = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000501", trashed: true)
        let active = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000502", trashed: false)
        try repository.insert(trashed)
        try repository.insert(active)
        try insertRelatedRows(for: trashed.uuidString, database: database)

        try repository.permanentlyDelete(ids: [trashed.uuidString, active.uuidString])

        #expect(try repository.fetchByUUID(trashed.id) == nil)
        #expect(try repository.fetchByUUID(active.id) != nil)
        #expect(try countRows("collection_items", database: database) == 0)
        #expect(try countRows("screenshot_tags", database: database) == 0)
        #expect(try countRows("ocr_results", database: database) == 0)
        #expect(try countRows("detected_codes", database: database) == 0)
        #expect(try countRows("image_hashes", database: database) == 0)
    }

    private func makeDatabase() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxTrashTests-\(UUID().uuidString).sqlite")
        let database = try Database(path: url.path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.organizationSchema)
        migrations.register(.ocrSchema)
        migrations.register(.detectedCodesSchema)
        migrations.register(.imageHashesSchema)
        try migrations.runPending(on: database)
        return database
    }

    private func makeScreenshot(uuid: String, trashed: Bool) -> Screenshot {
        let date = Date(timeIntervalSince1970: 100)
        return Screenshot(
            id: UUID(uuidString: uuid)!,
            name: "\(uuid).png",
            createdAt: date,
            pixelWidth: 100,
            pixelHeight: 100,
            byteSize: 100,
            format: "PNG",
            tags: [],
            ocrSnippets: [],
            isFavorite: false,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: trashed,
            libraryPath: "Originals/2026/04/\(uuid).png",
            fileHash: uuid,
            importedAt: date,
            modifiedAt: date,
            sourceApp: nil,
            sortIndex: 0,
            trashDate: trashed ? date : nil
        )
    }

    private func insertRelatedRows(for screenshotUUID: String, database: Database) throws {
        try database.exec("""
        INSERT INTO collections(uuid, name, type, sort_index, created_at, updated_at)
        VALUES('10000000-0000-0000-0000-000000000001', 'Trash Test', 'manual', 0, '2026-04-01T00:00:00Z', NULL);
        INSERT INTO collection_items(collection_id, screenshot_uuid, sort_index, created_at)
        VALUES(1, '\(screenshotUUID)', 0, '2026-04-01T00:00:00Z');
        INSERT INTO tags(uuid, name, color, created_at, updated_at)
        VALUES('20000000-0000-0000-0000-000000000001', 'tag', NULL, '2026-04-01T00:00:00Z', NULL);
        INSERT INTO screenshot_tags(tag_id, screenshot_uuid, created_at)
        VALUES(1, '\(screenshotUUID)', '2026-04-01T00:00:00Z');
        INSERT INTO ocr_results(screenshot_uuid, text, language, confidence, status, error_message, created_at, updated_at)
        VALUES('\(screenshotUUID)', 'text', 'en', 1.0, 'complete', NULL, '2026-04-01T00:00:00Z', NULL);
        INSERT INTO detected_codes(screenshot_uuid, symbology, payload, is_url, created_at, updated_at)
        VALUES('\(screenshotUUID)', 'qr', 'payload', 0, '2026-04-01T00:00:00Z', NULL);
        INSERT INTO image_hashes(screenshot_uuid, algorithm, hash, created_at)
        VALUES('\(screenshotUUID)', 'dhash64', 'abc', '2026-04-01T00:00:00Z');
        """)
    }

    private func countRows(_ table: String, database: Database) throws -> Int {
        let stmt = try database.prepare("SELECT COUNT(*) FROM \(table);")
        return try stmt.step() ? Int(stmt.columnInt(0)) : 0
    }
}
