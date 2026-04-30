import AppKit
import Foundation
import Testing
@testable import ScreenshotInbox

struct ScreenshotClipboardServiceTests {
    @Test
    func copyScreenshotsWritesManagedFileURLsAndInternalIDs() throws {
        let root = try makeRoot()
        let managed = root.appendingPathComponent("Originals/managed.png")
        try FileManager.default.createDirectory(
            at: managed.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: managed)
        let screenshot = makeScreenshot(libraryPath: "Originals/managed.png")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotInboxClipboardTests-\(UUID().uuidString)"))
        let service = ScreenshotClipboardService(
            screenshotsProvider: { ids in
                ids.contains(screenshot.uuidString) ? [screenshot] : []
            },
            libraryRootURL: root
        )

        let count = try service.copyScreenshots(ids: [screenshot.uuidString], to: pasteboard)

        #expect(count == 1)
        #expect(
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] == [managed]
        )
        #expect(pasteboard.string(forType: DragPasteboardTypes.screenshotIDs) == screenshot.uuidString)
    }

    @Test
    func canPasteImageContentRecognizesFileURLsAndImageData() throws {
        let root = try makeRoot()
        let image = root.appendingPathComponent("incoming.png")
        try Data([1, 2, 3]).write(to: image)
        let filePasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotInboxFilePaste-\(UUID().uuidString)"))
        filePasteboard.clearContents()
        filePasteboard.writeObjects([image as NSURL])
        let service = ScreenshotClipboardService(screenshotsProvider: { _ in [] }, libraryRootURL: root)

        #expect(service.canPasteImageContent(from: filePasteboard))

        let pngPasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotInboxPNGPaste-\(UUID().uuidString)"))
        pngPasteboard.clearContents()
        pngPasteboard.setData(Data([137, 80, 78, 71]), forType: .png)

        #expect(service.canPasteImageContent(from: pngPasteboard))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxClipboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeScreenshot(libraryPath: String) -> Screenshot {
        Screenshot(
            id: UUID(),
            name: "managed.png",
            createdAt: Date(timeIntervalSince1970: 100),
            pixelWidth: 10,
            pixelHeight: 10,
            byteSize: 3,
            format: "PNG",
            tags: [],
            ocrSnippets: [],
            isFavorite: false,
            isOCRComplete: false,
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
