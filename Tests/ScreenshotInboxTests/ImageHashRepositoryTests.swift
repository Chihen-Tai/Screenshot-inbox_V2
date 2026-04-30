import Foundation
import Testing
@testable import ScreenshotInbox

struct ImageHashRepositoryTests {
    @Test
    func upsertAndFetchImageHashesRoundTrip() throws {
        let database = try makeDatabase()
        let screenshots = ScreenshotRepository(database: database)
        let repository = ImageHashRepository(database: database)
        let owner = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000101", fileHash: "a", trashed: false)
        let first = ImageHashRecord(
            screenshotUUID: owner.uuidString,
            algorithm: "dhash64",
            hash: "0000000000000001",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let replacement = ImageHashRecord(
            screenshotUUID: first.screenshotUUID,
            algorithm: "dhash64",
            hash: "0000000000000002",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try screenshots.insert(owner)
        try repository.upsert(first)
        try repository.upsert(replacement)

        let fetched = try repository.fetchAll()

        #expect(fetched.count == 1)
        #expect(fetched[first.screenshotUUID]?.hash == replacement.hash)
        #expect(fetched[first.screenshotUUID]?.algorithm == "dhash64")
    }

    @Test
    func fetchMissingScreenshotUUIDsReturnsNonTrashedRowsWithoutHashes() throws {
        let database = try makeDatabase()
        let screenshots = ScreenshotRepository(database: database)
        let hashes = ImageHashRepository(database: database)
        let missing = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000201", fileHash: "a", trashed: false)
        let hashed = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000202", fileHash: "b", trashed: false)
        let trashed = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000203", fileHash: "c", trashed: true)

        try screenshots.insert(missing)
        try screenshots.insert(hashed)
        try screenshots.insert(trashed)
        try hashes.upsert(ImageHashRecord(
            screenshotUUID: hashed.uuidString,
            algorithm: "dhash64",
            hash: "0000000000000002",
            createdAt: Date()
        ))

        let missingUUIDs = try hashes.fetchMissingScreenshotUUIDs(algorithm: "dhash64", includeTrashed: false)

        #expect(missingUUIDs == [missing.uuidString])
    }

    @Test
    func deleteScreenshotRemovesPersistedHashRecord() throws {
        let database = try makeDatabase()
        let screenshots = ScreenshotRepository(database: database)
        let hashes = ImageHashRepository(database: database)
        let screenshot = makeScreenshot(uuid: "00000000-0000-0000-0000-000000000301", fileHash: "delete-me", trashed: true)

        try screenshots.insert(screenshot)
        try hashes.upsert(ImageHashRecord(
            screenshotUUID: screenshot.uuidString,
            algorithm: "dhash64",
            hash: "0000000000000003",
            createdAt: Date()
        ))

        try screenshots.delete(uuids: [screenshot.id])

        #expect(try screenshots.fetchByUUID(screenshot.id) == nil)
        #expect(try hashes.fetchAll().isEmpty)
    }

    private func makeDatabase() throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxTests-\(UUID().uuidString).sqlite")
        let database = try Database(path: url.path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.imageHashesSchema)
        try migrations.runPending(on: database)
        return database
    }

    private func makeScreenshot(uuid: String, fileHash: String, trashed: Bool) -> Screenshot {
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
            fileHash: fileHash,
            importedAt: date,
            modifiedAt: date,
            sourceApp: nil,
            sortIndex: 0,
            trashDate: trashed ? date : nil
        )
    }
}
