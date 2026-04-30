import Foundation
import Testing
@testable import ScreenshotInbox

struct LibraryIntegrityServiceTests {
    @Test
    func integrityReportDetectsMissingAndOrphanedLibraryAssets() throws {
        let harness = try MaintenanceHarness()
        let screenshot = try harness.insertScreenshotWithOriginal()
        try Data("large".utf8).write(to: harness.library.largeThumbnailURL(for: screenshot.id))
        try Data("orphan-thumb".utf8).write(
            to: harness.library.libraryRootURL
                .appendingPathComponent("Thumbnails/small", isDirectory: true)
                .appendingPathComponent("orphan.jpg")
        )
        try Data("orphan-original".utf8).write(
            to: harness.library.libraryRootURL
                .appendingPathComponent("Originals/2026/04", isDirectory: true)
                .appendingPathComponent("orphan.png")
        )

        let report = try harness.service.checkIntegrity()

        #expect(report.totalScreenshots == 1)
        #expect(report.missingOriginals == 0)
        #expect(report.missingThumbnails == 1)
        #expect(report.missingLargeThumbnails == 0)
        #expect(report.orphanThumbnails == 1)
        #expect(report.orphanOriginals == 1)
        #expect(report.missingOCRRecords == 1)
        #expect(report.duplicateIndexOutOfDate)
    }

    @Test
    func regenerateMissingThumbnailsUsesManagedOriginals() throws {
        let harness = try MaintenanceHarness()
        let screenshot = try harness.insertScreenshotWithOriginal()

        let result = try harness.service.regenerateMissingThumbnails()

        #expect(result.processed == 1)
        #expect(FileManager.default.fileExists(atPath: harness.library.smallThumbnailURL(for: screenshot.id).path))
        #expect(FileManager.default.fileExists(atPath: harness.library.largeThumbnailURL(for: screenshot.id).path))
    }

    @Test
    func cleanOrphanThumbnailsOnlyRemovesUnreferencedThumbnailFiles() throws {
        let harness = try MaintenanceHarness()
        let screenshot = try harness.insertScreenshotWithOriginal()
        try Data("referenced".utf8).write(to: harness.library.smallThumbnailURL(for: screenshot.id))
        let orphanURL = harness.library.libraryRootURL
            .appendingPathComponent("Thumbnails/large", isDirectory: true)
            .appendingPathComponent("orphan.jpg")
        try Data("orphan".utf8).write(to: orphanURL)

        let result = try harness.service.cleanOrphanThumbnails()

        #expect(result.processed == 1)
        #expect(FileManager.default.fileExists(atPath: harness.library.smallThumbnailURL(for: screenshot.id).path))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @Test
    func databaseIntegrityCheckReturnsOKForFreshLibraryDatabase() throws {
        let harness = try MaintenanceHarness()

        let result = try harness.service.databaseIntegrityCheck()

        #expect(result == "ok")
    }
}

private final class MaintenanceHarness {
    let root: URL
    let library: TestMaintenanceLibrary
    let database: Database
    let screenshotRepository: ScreenshotRepository
    let ocrRepository: OCRRepository
    let imageHashRepository: ImageHashRepository
    let service: LibraryIntegrityService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
        library = TestMaintenanceLibrary(root: root.appendingPathComponent("Managed", isDirectory: true))
        try library.bootstrap()

        database = try Database(path: library.databaseURL.path)
        let migrations = MigrationManager()
        migrations.register(.initialSchema)
        migrations.register(.organizationSchema)
        migrations.register(.ocrSchema)
        migrations.register(.detectedCodesSchema)
        migrations.register(.imageHashesSchema)
        try migrations.runPending(on: database)

        screenshotRepository = ScreenshotRepository(database: database)
        ocrRepository = OCRRepository(database: database)
        imageHashRepository = ImageHashRepository(database: database)
        service = LibraryIntegrityService(
            library: library,
            screenshotRepository: screenshotRepository,
            ocrRepository: ocrRepository,
            imageHashRepository: imageHashRepository,
            thumbnailService: TestMaintenanceThumbnailService(library: library),
            database: database
        )
    }

    func insertScreenshotWithOriginal() throws -> Screenshot {
        let uuid = UUID(uuidString: "00000000-0000-0000-0000-000000009001")!
        let relativePath = "Originals/2026/04/\(uuid.uuidString.lowercased()).png"
        let originalURL = library.libraryRootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data("not a real image".utf8)
        try data.write(to: originalURL)
        let screenshot = Screenshot(
            id: uuid,
            name: "maintenance.png",
            createdAt: Date(timeIntervalSince1970: 100),
            pixelWidth: 100,
            pixelHeight: 50,
            byteSize: data.count,
            format: "PNG",
            tags: [],
            ocrSnippets: [],
            isFavorite: false,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: false,
            libraryPath: relativePath,
            fileHash: "abc",
            importedAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            sortIndex: 0,
            trashDate: nil
        )
        try screenshotRepository.insert(screenshot)
        return screenshot
    }
}

private final class TestMaintenanceLibrary: LibraryManaging {
    let libraryRootURL: URL
    var databaseURL: URL { libraryRootURL.appendingPathComponent("library.sqlite") }

    init(root: URL) {
        libraryRootURL = root
    }

    func originalsFolder(for date: Date) throws -> URL {
        let url = libraryRootURL.appendingPathComponent("Originals/2026/04", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func smallThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL
            .appendingPathComponent("Thumbnails/small", isDirectory: true)
            .appendingPathComponent("\(uuid.uuidString.lowercased()).jpg")
    }

    func largeThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL
            .appendingPathComponent("Thumbnails/large", isDirectory: true)
            .appendingPathComponent("\(uuid.uuidString.lowercased()).jpg")
    }

    func bootstrap() throws {
        for folder in [
            libraryRootURL,
            libraryRootURL.appendingPathComponent("Originals/2026/04", isDirectory: true),
            libraryRootURL.appendingPathComponent("Thumbnails/small", isDirectory: true),
            libraryRootURL.appendingPathComponent("Thumbnails/large", isDirectory: true)
        ] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }
}

private struct TestMaintenanceThumbnailService: ThumbnailGenerating {
    let library: TestMaintenanceLibrary

    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws {
        try Data("small".utf8).write(to: library.smallThumbnailURL(for: uuid))
        try Data("large".utf8).write(to: library.largeThumbnailURL(for: uuid))
    }
}
