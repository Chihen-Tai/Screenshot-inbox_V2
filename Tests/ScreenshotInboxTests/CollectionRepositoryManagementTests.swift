import Foundation
import Testing
@testable import ScreenshotInbox

struct CollectionRepositoryManagementTests {
    @Test
    func renameCollectionTrimsNameAndRejectsDuplicateNames() throws {
        let repository = try makeRepository()
        let first = try repository.createCollection(name: "Chemistry")
        _ = try repository.createCollection(name: "Papers")

        try repository.renameCollection(uuid: first.uuid, name: "  Chem Notes  ")
        let renamed = try #require(try repository.fetchCollection(uuid: first.uuid))

        #expect(renamed.name == "Chem Notes")
        #expect(throws: CollectionRepositoryError.duplicateName) {
            try repository.renameCollection(uuid: first.uuid, name: "Papers")
        }
    }

    @Test
    func deleteCollectionRemovesMembershipButLeavesScreenshots() throws {
        let database = try makeDatabase()
        let collections = CollectionRepository(database: database)
        let screenshots = ScreenshotRepository(database: database)
        let collection = try collections.createCollection(name: "Temporary")
        let screenshot = makeScreenshot()

        try screenshots.insert(screenshot)
        try collections.addScreenshots([screenshot.uuidString], toCollection: collection.uuid)

        try collections.deleteCollection(uuid: collection.uuid)

        #expect(try collections.fetchCollection(uuid: collection.uuid) == nil)
        #expect(try collections.fetchScreenshots(inCollection: collection.uuid).isEmpty)
        #expect(try screenshots.fetchByUUID(screenshot.id) != nil)
    }

    @Test
    func reorderCollectionsPersistsSortIndexOrder() throws {
        let repository = try makeRepository()
        let chemistry = try repository.createCollection(name: "Chemistry")
        let papers = try repository.createCollection(name: "Papers")
        let ideas = try repository.createCollection(name: "UI Ideas")

        try repository.updateSortOrder(collectionUUIDsInOrder: [ideas.uuid, chemistry.uuid, papers.uuid])

        let names = try repository.fetchCollections().map(\.name)
        let sortIndexes = try repository.fetchCollections().map(\.sortIndex)

        #expect(names == ["UI Ideas", "Chemistry", "Papers"])
        #expect(sortIndexes == [0, 1, 2])
    }

    @Test
    func collectionSortIndexMigrationAddsAndNormalizesLegacyRows() throws {
        let database = try makeLegacyCollectionsDatabase()
        let migrations = MigrationManager()
        migrations.register(.collectionSortIndexSchema)

        try migrations.runPending(on: database)

        let collections = try CollectionRepository(database: database).fetchCollections()

        #expect(collections.map(\.name) == ["Chemistry", "Papers", "UI Ideas"])
        #expect(collections.map(\.sortIndex) == [0, 1, 2])
    }

    private func makeRepository() throws -> CollectionRepository {
        try CollectionRepository(database: makeDatabase())
    }

    private func makeDatabase() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxCollectionTests-\(UUID().uuidString).sqlite")
        let database = try Database(path: url.path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.organizationSchema)
        migrations.register(.collectionSortIndexSchema)
        try migrations.runPending(on: database)
        return database
    }

    private func makeLegacyCollectionsDatabase() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxLegacyCollectionTests-\(UUID().uuidString).sqlite")
        let database = try Database(path: url.path)
        try database.exec("""
        CREATE TABLE collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'manual',
            created_at TEXT NOT NULL,
            updated_at TEXT
        );
        """)
        try database.exec("""
        INSERT INTO collections(uuid, name, type, created_at, updated_at) VALUES
            ('00000000-0000-4000-8000-000000000001', 'Papers', 'manual', '2026-04-02T00:00:00Z', NULL),
            ('00000000-0000-4000-8000-000000000002', 'Chemistry', 'manual', '2026-04-01T00:00:00Z', NULL),
            ('00000000-0000-4000-8000-000000000003', 'UI Ideas', 'manual', '2026-04-03T00:00:00Z', NULL);
        """)
        return database
    }

    private func makeScreenshot() -> Screenshot {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 100)
        return Screenshot(
            id: id,
            name: "shot.png",
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
            isTrashed: false,
            libraryPath: "Originals/2026/04/\(id.uuidString.lowercased()).png",
            fileHash: UUID().uuidString,
            importedAt: date,
            modifiedAt: date,
            sourceApp: nil,
            sortIndex: 0,
            trashDate: nil
        )
    }
}
