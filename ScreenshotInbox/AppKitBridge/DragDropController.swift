import AppKit

/// External drag/drop: drag-out to Finder/apps, drag-in from Finder.
enum DragDropController {
    static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "tif"
    ]

    struct FileDrop {
        let supported: [URL]
        let unsupportedCount: Int

        var hasSupportedFiles: Bool { !supported.isEmpty }
        var isEmpty: Bool { supported.isEmpty && unsupportedCount == 0 }
    }

    static func readFileDrop(from pasteboard: NSPasteboard) -> FileDrop {
        let urls = readFileURLs(from: pasteboard)
        let supported = urls.filter(isSupportedImageURL)
        return FileDrop(
            supported: supported,
            unsupportedCount: urls.count - supported.count
        )
    }

    static func isSupportedImageURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return supportedImageExtensions.contains(ext)
    }

    private static func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL] {
            return urls.map { $0 as URL }
        }

        guard let raw = pasteboard.propertyList(forType: .fileURL) as? String,
              let url = URL(string: raw),
              url.isFileURL else {
            return []
        }
        return [url]
    }
}
