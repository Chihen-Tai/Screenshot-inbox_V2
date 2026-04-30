import Foundation
import Testing
@testable import ScreenshotInbox

struct ImportConflictTests {
    @Test
    func skipResolutionLeavesExistingDuplicateOnly() async throws {
        let harness = try ImportHarness()
        let source = try harness.makeImage(named: "duplicate.png", bytes: [1, 2, 3, 4])
        _ = await harness.importService.importURLs([source])

        let second = await harness.importService.importURLs(
            [source],
            conflictResolver: FixedImportConflictResolver(.skip)
        )

        #expect(second.duplicates == 1)
        #expect(second.imported.isEmpty)
        #expect(try harness.screenshotRepository.fetchAll(includeTrashed: true).count == 1)
    }

    @Test
    func keepBothResolutionImportsDuplicateWithUniqueDisplayName() async throws {
        let harness = try ImportHarness()
        let source = try harness.makeImage(named: "duplicate.png", bytes: [1, 2, 3, 4])
        _ = await harness.importService.importURLs([source])

        let second = await harness.importService.importURLs(
            [source],
            conflictResolver: FixedImportConflictResolver(.keepBoth)
        )

        let screenshots = try harness.screenshotRepository.fetchAll(includeTrashed: true)
        #expect(second.keptDuplicateCopies == 1)
        #expect(second.imported.count == 1)
        #expect(screenshots.count == 2)
        #expect(Set(screenshots.map(\.fileHash)).count == 1)
        #expect(Set(screenshots.map(\.name)) == ["duplicate.png", "duplicate 2.png"])
    }

    @Test
    func replaceResolutionKeepsUUIDAndOrganizationMetadata() async throws {
        let harness = try ImportHarness()
        let source = try harness.makeImage(named: "duplicate.png", bytes: [1, 2, 3, 4])
        let first = await harness.importService.importURLs([source])
        let existing = try #require(first.imported.first)
        let collection = try harness.collectionRepository.createCollection(name: "Papers")
        try harness.tagRepository.addTag(name: "important", toScreenshots: [existing.uuidString])
        try harness.collectionRepository.addScreenshots([existing.uuidString], toCollection: collection.uuid)
        try harness.screenshotRepository.updateFavorite(ids: [existing.id], isFavorite: true)

        let replacement = await harness.importService.importURLs(
            [source],
            conflictResolver: FixedImportConflictResolver(.replaceExisting)
        )

        let screenshots = try harness.screenshotRepository.fetchAll(includeTrashed: true)
        let updated = try #require(try harness.screenshotRepository.fetchByUUID(existing.id))
        #expect(replacement.replaced.map(\.id) == [existing.id])
        #expect(screenshots.count == 1)
        #expect(updated.isFavorite)
        #expect(try harness.tagRepository.fetchTags(forScreenshot: existing.uuidString).map(\.name) == ["important"])
        #expect(try harness.collectionRepository.fetchScreenshots(inCollection: collection.uuid).map(\.id) == [existing.id])
    }

    @Test
    func importStoresOriginalSourcePath() async throws {
        let harness = try ImportHarness()
        let source = try harness.makeImage(named: "source.png", bytes: [1, 2, 3, 4])

        let result = await harness.importService.importURLs([source])
        let imported = try #require(result.imported.first)
        let stored = try #require(try harness.screenshotRepository.fetchByUUID(imported.id))

        #expect(imported.originalPath == source.path)
        #expect(stored.originalPath == source.path)
    }
}

private struct FixedImportConflictResolver: ImportConflictResolving {
    let resolution: ImportConflictResolution

    init(_ resolution: ImportConflictResolution) {
        self.resolution = resolution
    }

    func resolve(conflicts: [ImportConflict]) async -> [ImportConflictDecision] {
        conflicts.map { ImportConflictDecision(conflict: $0, resolution: resolution) }
    }
}

private final class ImportHarness {
    let root: URL
    let database: Database
    let screenshotRepository: ScreenshotRepository
    let tagRepository: TagRepository
    let collectionRepository: CollectionRepository
    let importService: ImportService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxImportConflictTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        database = try Database(path: root.appendingPathComponent("library.sqlite").path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.organizationSchema)
        try migrations.runPending(on: database)
        screenshotRepository = ScreenshotRepository(database: database)
        tagRepository = TagRepository(database: database)
        collectionRepository = CollectionRepository(database: database)
        importService = ImportService(
            library: TestLibrary(root: root),
            repository: screenshotRepository,
            metadataReader: TestMetadataReader(),
            thumbnailService: TestThumbnailService()
        )
    }

    func makeImage(named name: String, bytes: [UInt8]) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }
}

private final class TestLibrary: LibraryManaging {
    let libraryRootURL: URL
    var databaseURL: URL { libraryRootURL.appendingPathComponent("library.sqlite") }

    init(root: URL) {
        libraryRootURL = root.appendingPathComponent("Managed", isDirectory: true)
    }

    func originalsFolder(for date: Date) throws -> URL {
        let url = libraryRootURL.appendingPathComponent("Originals/2026/04", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func smallThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL.appendingPathComponent("Thumbnails/small/\(uuid.uuidString.lowercased()).jpg")
    }

    func largeThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL.appendingPathComponent("Thumbnails/large/\(uuid.uuidString.lowercased()).jpg")
    }

    func bootstrap() throws {}
}

private struct TestMetadataReader: ImageMetadataReading {
    func read(from url: URL) throws -> ImageMetadata {
        let size = (try? Data(contentsOf: url).count) ?? 0
        return ImageMetadata(width: 10, height: 10, byteSize: size, format: "PNG", createdAt: Date(timeIntervalSince1970: 100))
    }
}

private struct TestThumbnailService: ThumbnailGenerating {
    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws {}
}
