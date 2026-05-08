import AppKit
import Foundation

final class MacClipboardService: ClipboardProviding {
    private let pasteboard: NSPasteboard
    private let fileManager: FileManager

    init(pasteboard: NSPasteboard = .general, fileManager: FileManager = .default) {
        self.pasteboard = pasteboard
        self.fileManager = fileManager
    }

    func copyFiles(paths: [String]) throws {
        let urls = paths.map(URL.init(fileURLWithPath:)).filter {
            fileManager.fileExists(atPath: $0.path)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    func pasteImageOrFiles() async throws -> [ImportInput] {
        var inputs = fileURLsFromPasteboard().map {
            ImportInput(path: $0.path, suggestedFilename: $0.lastPathComponent)
        }
        if inputs.isEmpty, let imageURL = try imageDataFileFromPasteboard() {
            inputs = [ImportInput(path: imageURL.path, suggestedFilename: imageURL.lastPathComponent)]
        }
        return inputs
    }

    private func fileURLsFromPasteboard() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL])?
            .map { $0 as URL } ?? []
    }

    private func imageDataFileFromPasteboard() throws -> URL? {
        if let pngData = pasteboard.data(forType: .png) {
            return try writePastedImageData(pngData, extension: "png")
        }
        if let tiffData = pasteboard.data(forType: .tiff) {
            return try writePastedImageData(tiffData, extension: "tiff")
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let data = image.platformPNGData else {
            return nil
        }
        return try writePastedImageData(data, extension: "png")
    }

    private func writePastedImageData(_ data: Data, extension ext: String) throws -> URL {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("ScreenshotInboxPastes", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = "Pasted Image \(UUID().uuidString).\(ext)"
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension NSImage {
    var platformPNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
