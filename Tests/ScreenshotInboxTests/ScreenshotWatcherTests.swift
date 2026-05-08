import Foundation
import Testing
@testable import ScreenshotInbox

struct ScreenshotWatcherTests {
    @Test
    func acceptsCommonScreenshotImageExtensions() throws {
        let root = try makeRoot()
        let urls = [
            root.appendingPathComponent("Screenshot.png"),
            root.appendingPathComponent("Screenshot.JPG"),
            root.appendingPathComponent("Screenshot.jpeg"),
            root.appendingPathComponent("Screenshot.heic")
        ]

        for url in urls {
            try Data([1, 2, 3]).write(to: url)
            #expect(ScreenshotWatcher.isCandidateScreenshotFile(url))
        }
    }

    @Test
    func rejectsTemporaryHiddenDirectoriesAndUnsupportedFiles() throws {
        let root = try makeRoot()
        let directory = root.appendingPathComponent("folder.png", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = root.appendingPathComponent(".Screenshot.png")
        try Data([1]).write(to: temporary)
        let unsupported = root.appendingPathComponent("Screenshot.gif")
        try Data([1]).write(to: unsupported)

        #expect(!ScreenshotWatcher.isCandidateScreenshotFile(directory))
        #expect(!ScreenshotWatcher.isCandidateScreenshotFile(temporary))
        #expect(!ScreenshotWatcher.isCandidateScreenshotFile(unsupported))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

