import AppKit
import Foundation

enum ScreenshotClipboardError: LocalizedError {
    case noScreenshots
    case noRenderableFiles
    case noImageContent
    case importServiceUnavailable
    case cutUnavailable

    var errorDescription: String? {
        switch self {
        case .noScreenshots:
            return "No screenshots are selected."
        case .noRenderableFiles:
            return "Selected screenshots do not have managed files."
        case .noImageContent:
            return "No image found on clipboard."
        case .importServiceUnavailable:
            return "Import service is unavailable."
        case .cutUnavailable:
            return "Cut is not available for screenshots."
        }
    }
}

final class ScreenshotClipboardService {
    typealias ScreenshotsProvider = ([String]) -> [Screenshot]

    private let screenshotsProvider: ScreenshotsProvider
    private let libraryRootURL: URL
    private let importService: ImportService?
    private let fileManager: FileManager

    init(
        screenshotsProvider: @escaping ScreenshotsProvider,
        libraryRootURL: URL,
        importService: ImportService? = nil,
        fileManager: FileManager = .default
    ) {
        self.screenshotsProvider = screenshotsProvider
        self.libraryRootURL = libraryRootURL
        self.importService = importService
        self.fileManager = fileManager
    }

    @discardableResult
    func copyScreenshots(ids: [String]) throws -> Int {
        try copyScreenshots(ids: ids, to: .general)
    }

    @discardableResult
    func copyScreenshots(ids: [String], to pasteboard: NSPasteboard) throws -> Int {
        let screenshots = screenshotsProvider(ids)
        guard !screenshots.isEmpty else { throw ScreenshotClipboardError.noScreenshots }
        let urls = screenshots.compactMap(managedFileURL)
        guard !urls.isEmpty else { throw ScreenshotClipboardError.noRenderableFiles }

        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        pasteboard.setString(
            screenshots.map(\.uuidString).joined(separator: "\n"),
            forType: DragPasteboardTypes.screenshotIDs
        )
        if let firstImage = urls.compactMap(NSImage.init(contentsOf:)).first {
            if let pngData = firstImage.pngData {
                pasteboard.setData(pngData, forType: .png)
            }
            if let tiffData = firstImage.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
        return urls.count
    }

    func cutScreenshots(ids: [String]) throws {
        throw ScreenshotClipboardError.cutUnavailable
    }

    func canPasteImageContent() -> Bool {
        canPasteImageContent(from: .general)
    }

    func canPasteImageContent(from pasteboard: NSPasteboard) -> Bool {
        !imageFileURLs(from: pasteboard).isEmpty ||
            pasteboard.data(forType: .png) != nil ||
            pasteboard.data(forType: .tiff) != nil ||
            NSImage(pasteboard: pasteboard) != nil
    }

    func pasteIntoInbox() async throws -> ImportResult {
        try await pasteIntoInbox(from: .general, conflictResolver: MacImportConflictResolver())
    }

    func pasteIntoInbox(
        from pasteboard: NSPasteboard,
        conflictResolver: ImportConflictResolving
    ) async throws -> ImportResult {
        guard let importService else { throw ScreenshotClipboardError.importServiceUnavailable }
        var urls = imageFileURLs(from: pasteboard)
        if urls.isEmpty, let imageURL = try imageDataFile(from: pasteboard) {
            urls = [imageURL]
        }
        guard !urls.isEmpty else { throw ScreenshotClipboardError.noImageContent }
        return await importService.importURLs(urls, conflictResolver: conflictResolver)
    }

    private func managedFileURL(for screenshot: Screenshot) -> URL? {
        guard let libraryPath = screenshot.libraryPath, !libraryPath.isEmpty else { return nil }
        let url = libraryPath.hasPrefix("/")
            ? URL(fileURLWithPath: libraryPath)
            : libraryRootURL.appendingPathComponent(libraryPath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL] {
            return urls.map { $0 as URL }.filter(DragDropController.isSupportedImageURL)
        }
        if let filenames = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            return filenames.map(URL.init(fileURLWithPath:)).filter(DragDropController.isSupportedImageURL)
        }
        if let raw = pasteboard.propertyList(forType: .fileURL) as? String,
           let url = URL(string: raw),
           DragDropController.isSupportedImageURL(url) {
            return [url]
        }
        return []
    }

    private func imageDataFile(from pasteboard: NSPasteboard) throws -> URL? {
        if let pngData = pasteboard.data(forType: .png) {
            return try writePastedImageData(pngData, extension: "png")
        }
        if let tiffData = pasteboard.data(forType: .tiff) {
            return try writePastedImageData(tiffData, extension: "tiff")
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let data = image.pngData else {
            return nil
        }
        return try writePastedImageData(data, extension: "png")
    }

    private func writePastedImageData(_ data: Data, extension ext: String) throws -> URL {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxPastes", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let filename = "Pasted Image \(formatter.string(from: Date())).\(ext)"
        let url = uniqueURL(in: folder, filename: filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func uniqueURL(in folder: URL, filename: String) -> URL {
        let baseURL = folder.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }
        let ext = baseURL.pathExtension
        let stem = ext.isEmpty ? baseURL.lastPathComponent : String(baseURL.lastPathComponent.dropLast(ext.count + 1))
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
