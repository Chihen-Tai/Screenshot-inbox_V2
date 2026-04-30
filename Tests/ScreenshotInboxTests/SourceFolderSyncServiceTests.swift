import Foundation
import Testing
@testable import ScreenshotInbox

struct SourceFolderSyncServiceTests {
    @Test
    func missingOriginalCandidatesExcludeUnsafeAndUnrelatedPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxSourceFolderSyncTests-\(UUID().uuidString)", isDirectory: true)
        let libraryRoot = root.appendingPathComponent("Library", isDirectory: true)
        let watchedFolder = root.appendingPathComponent("Desktop", isDirectory: true)
        let otherFolder = root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existingSource = watchedFolder.appendingPathComponent("existing.png")
        let managedSource = libraryRoot.appendingPathComponent("Originals/managed.png")
        let unrelatedMissingSource = otherFolder.appendingPathComponent("missing.png")
        try FileManager.default.createDirectory(at: managedSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: existingSource.path, contents: Data([1]))

        let missing = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000701",
            originalPath: watchedFolder.appendingPathComponent("deleted.png").path
        )
        let existing = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000702",
            originalPath: existingSource.path
        )
        let managed = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000703",
            originalPath: managedSource.path
        )
        let unrelated = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000704",
            originalPath: unrelatedMissingSource.path
        )
        let noOriginalPath = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000705",
            originalPath: nil
        )
        let trashed = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000706",
            originalPath: watchedFolder.appendingPathComponent("trashed-deleted.png").path,
            trashed: true
        )

        let service = SourceFolderSyncService(libraryRootURL: libraryRoot)
        let result = service.missingOriginalScreenshots(
            in: [missing, existing, managed, unrelated, noOriginalPath, trashed],
            scopedToSourceFolders: [watchedFolder]
        )

        #expect(result.map(\.id) == [missing.id])
    }

    @Test
    func renamedOriginalCandidatesMatchSingleSameFolderFileByHash() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxSourceRenameTests-\(UUID().uuidString)", isDirectory: true)
        let libraryRoot = root.appendingPathComponent("Library", isDirectory: true)
        let watchedFolder = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let renamedSource = watchedFolder.appendingPathComponent("renamed.png")
        try Data([7, 8, 9]).write(to: renamedSource)
        let hash = try FileHash.sha256Hex(of: renamedSource)
        let screenshot = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000801",
            originalPath: watchedFolder.appendingPathComponent("old-name.png").path,
            fileHash: hash
        )

        let service = SourceFolderSyncService(libraryRootURL: libraryRoot)
        let changes = try service.reconcileOriginalSourceChanges(
            in: [screenshot],
            scopedToSourceFolders: [watchedFolder],
            detectRenamesByHash: true
        )

        #expect(changes.renamed.map(\.screenshot.id) == [screenshot.id])
        #expect(changes.renamed.first?.newOriginalURL == renamedSource.standardizedFileURL)
        #expect(changes.missing.isEmpty)
    }

    @Test
    func renamedOriginalCandidatesDoNotGuessWhenMultipleHashMatchesExist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxSourceRenameAmbiguousTests-\(UUID().uuidString)", isDirectory: true)
        let libraryRoot = root.appendingPathComponent("Library", isDirectory: true)
        let watchedFolder = root.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = watchedFolder.appendingPathComponent("copy-a.png")
        let second = watchedFolder.appendingPathComponent("copy-b.png")
        try Data([7, 8, 9]).write(to: first)
        try Data([7, 8, 9]).write(to: second)
        let screenshot = makeScreenshot(
            uuid: "00000000-0000-0000-0000-000000000802",
            originalPath: watchedFolder.appendingPathComponent("old-name.png").path,
            fileHash: try FileHash.sha256Hex(of: first)
        )

        let service = SourceFolderSyncService(libraryRootURL: libraryRoot)
        let changes = try service.reconcileOriginalSourceChanges(
            in: [screenshot],
            scopedToSourceFolders: [watchedFolder],
            detectRenamesByHash: true
        )

        #expect(changes.renamed.isEmpty)
        #expect(changes.missing.map(\.id) == [screenshot.id])
    }

    private func makeScreenshot(
        uuid: String,
        originalPath: String?,
        fileHash: String? = nil,
        trashed: Bool = false
    ) -> Screenshot {
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
            fileHash: fileHash ?? uuid,
            importedAt: date,
            modifiedAt: date,
            sourceApp: nil,
            originalPath: originalPath,
            sortIndex: 0,
            trashDate: trashed ? date : nil
        )
    }
}
