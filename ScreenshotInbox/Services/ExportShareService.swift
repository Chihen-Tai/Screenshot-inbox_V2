import AppKit
import Foundation
import UniformTypeIdentifiers

struct OriginalExportResult: Hashable {
    var exportedCount: Int
    var skippedCount: Int
    var destinationFolder: String
}

struct TextExportResult: Hashable {
    var exportedCount: Int
    var skippedCount: Int
    var outputPath: String
}

enum OCRTextExportFormat: Hashable {
    case txt
    case markdown
}

enum ExportShareError: Error {
    case noScreenshots
    case noRenderableFiles
    case invalidDestination
    case writeFailed
}

final class ExportShareService {
    private let libraryRootURL: URL
    private let fileManager: FileManager

    init(libraryRootURL: URL, fileManager: FileManager = .default) {
        self.libraryRootURL = libraryRootURL
        self.fileManager = fileManager
    }

    func exportOriginals(_ screenshots: [Screenshot], to folder: URL) async throws -> OriginalExportResult {
        try await Task.detached(priority: .userInitiated) { [self] in
            guard !screenshots.isEmpty else { throw ExportShareError.noScreenshots }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            var exported = 0
            var skipped = 0
            for screenshot in screenshots {
                guard let source = originalURL(for: screenshot),
                      fileManager.fileExists(atPath: source.path) else {
                    skipped += 1
                    continue
                }
                let destination = uniqueURL(in: folder, filename: exportFilename(for: screenshot, sourceURL: source))
                try fileManager.copyItem(at: source, to: destination)
                exported += 1
            }
            guard exported > 0 else { throw ExportShareError.noRenderableFiles }
            return OriginalExportResult(exportedCount: exported, skippedCount: skipped, destinationFolder: folder.path)
        }.value
    }

    func exportOCRText(_ screenshots: [Screenshot], to outputURL: URL, format: OCRTextExportFormat) async throws -> TextExportResult {
        try await Task.detached(priority: .userInitiated) {
            guard !screenshots.isEmpty else { throw ExportShareError.noScreenshots }
            let renderable = screenshots.filter { $0.isOCRComplete && !$0.ocrSnippets.isEmpty }
            guard !renderable.isEmpty else { throw ExportShareError.noRenderableFiles }
            let content: String
            switch format {
            case .txt:
                content = Self.txtOCR(for: renderable, totalCount: screenshots.count)
            case .markdown:
                content = Self.markdownOCR(for: renderable)
            }
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: outputURL, atomically: true, encoding: .utf8)
            return TextExportResult(
                exportedCount: renderable.count,
                skippedCount: screenshots.count - renderable.count,
                outputPath: outputURL.path
            )
        }.value
    }

    func fileURLs(for screenshots: [Screenshot]) -> [URL] {
        screenshots.compactMap { screenshot in
            guard let url = originalURL(for: screenshot),
                  fileManager.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    func copyImages(_ screenshots: [Screenshot], to pasteboard: NSPasteboard = .general) -> Int {
        let images = fileURLs(for: screenshots).compactMap(NSImage.init(contentsOf:))
        guard !images.isEmpty else { return 0 }
        pasteboard.clearContents()
        pasteboard.writeObjects(images)
        return images.count
    }

    func copyFiles(_ screenshots: [Screenshot], to pasteboard: NSPasteboard = .general) -> Int {
        let urls = fileURLs(for: screenshots)
        guard !urls.isEmpty else { return 0 }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        return urls.count
    }

    func copyFilePaths(_ screenshots: [Screenshot], to pasteboard: NSPasteboard = .general) -> Int {
        let paths = fileURLs(for: screenshots).map(\.path)
        guard !paths.isEmpty else { return 0 }
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        return paths.count
    }

    func copyMarkdownReference(_ screenshots: [Screenshot], to pasteboard: NSPasteboard = .general) -> Int {
        let lines = screenshots.compactMap { screenshot -> String? in
            guard let url = originalURL(for: screenshot),
                  fileManager.fileExists(atPath: url.path) else { return nil }
            let escapedName = screenshot.name.replacingOccurrences(of: "]", with: "\\]")
            return "![\(escapedName)](\(url.absoluteString))"
        }
        guard !lines.isEmpty else { return 0 }
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        return lines.count
    }

    func share(_ screenshots: [Screenshot]) {
        let urls = fileURLs(for: screenshots)
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    private func originalURL(for screenshot: Screenshot) -> URL? {
        guard let libraryPath = screenshot.libraryPath, !libraryPath.isEmpty else { return nil }
        if libraryPath.hasPrefix("/") { return URL(fileURLWithPath: libraryPath) }
        return libraryRootURL.appendingPathComponent(libraryPath)
    }

    private func exportFilename(for screenshot: Screenshot, sourceURL: URL) -> String {
        let sourceExt = sourceURL.pathExtension
        let displayExt = URL(fileURLWithPath: screenshot.name).pathExtension
        if displayExt.isEmpty, !sourceExt.isEmpty {
            return "\(screenshot.name).\(sourceExt)"
        }
        return screenshot.name
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

    private static func txtOCR(for screenshots: [Screenshot], totalCount: Int) -> String {
        if screenshots.count == 1, totalCount == 1 {
            return screenshots[0].ocrSnippets.joined(separator: "\n")
        }
        return screenshots.map { screenshot in
            """
            \(screenshot.name)
            \(String(repeating: "=", count: screenshot.name.count))
            \(screenshot.ocrSnippets.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")
    }

    private static func markdownOCR(for screenshots: [Screenshot]) -> String {
        var parts = ["# Screenshot OCR Export"]
        for screenshot in screenshots {
            parts.append("""

            ## \(screenshot.name)
            \(screenshot.ocrSnippets.joined(separator: "\n"))
            """)
        }
        return parts.joined(separator: "\n")
    }
}
