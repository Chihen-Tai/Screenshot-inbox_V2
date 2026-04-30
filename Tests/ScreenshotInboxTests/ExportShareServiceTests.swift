import Foundation
import Testing
@testable import ScreenshotInbox

struct ExportShareServiceTests {
    @Test
    func exportOriginalsUsesUniqueFilenamesWithoutOverwriting() async throws {
        let root = try makeRoot()
        let originals = root.appendingPathComponent("Originals", isDirectory: true)
        let destination = root.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = originals.appendingPathComponent("managed.png")
        try Data([1, 2, 3]).write(to: source)
        try Data([9]).write(to: destination.appendingPathComponent("shot.png"))
        let screenshot = makeScreenshot(name: "shot.png", libraryPath: "Originals/managed.png")
        let service = ExportShareService(libraryRootURL: root)

        let result = try await service.exportOriginals([screenshot], to: destination)

        #expect(result.exportedCount == 1)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("shot 2.png").path))
        #expect((try Data(contentsOf: destination.appendingPathComponent("shot.png"))) == Data([9]))
    }

    @Test
    func exportOCRMarkdownUsesFilenameHeadersAndSkipsMissingOCR() async throws {
        let root = try makeRoot()
        let output = root.appendingPathComponent("ocr.md")
        let withOCR = makeScreenshot(name: "with.png", libraryPath: "with.png", ocr: ["Hello", "World"])
        let withoutOCR = makeScreenshot(name: "without.png", libraryPath: "without.png", ocr: [])
        let service = ExportShareService(libraryRootURL: root)

        let result = try await service.exportOCRText([withOCR, withoutOCR], to: output, format: .markdown)
        let content = try String(contentsOf: output)

        #expect(result.exportedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(content.contains("# Screenshot OCR Export"))
        #expect(content.contains("## with.png"))
        #expect(content.contains("Hello\nWorld"))
        #expect(!content.contains("without.png"))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeScreenshot(name: String, libraryPath: String, ocr: [String] = []) -> Screenshot {
        Screenshot(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 100),
            pixelWidth: 10,
            pixelHeight: 10,
            byteSize: 3,
            format: "PNG",
            tags: [],
            ocrSnippets: ocr,
            isFavorite: false,
            isOCRComplete: !ocr.isEmpty,
            thumbnailKind: .document,
            isTrashed: false,
            libraryPath: libraryPath,
            fileHash: UUID().uuidString,
            importedAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 100),
            sourceApp: nil,
            sortIndex: 0,
            trashDate: nil
        )
    }
}
