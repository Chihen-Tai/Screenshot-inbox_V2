import Foundation

/// Orchestrates the import pipeline: hash → dedupe → read metadata → copy
/// original → write thumbnails → insert DB row. Returns an `ImportResult`
/// the caller can surface as toasts.
final class ImportService: ScreenshotImporting {
    private let library: LibraryManaging
    private let repository: ScreenshotRepository
    private let metadataReader: ImageMetadataReading
    private let thumbnailService: ThumbnailGenerating

    init(
        library: LibraryManaging,
        repository: ScreenshotRepository,
        metadataReader: ImageMetadataReading,
        thumbnailService: ThumbnailGenerating
    ) {
        self.library = library
        self.repository = repository
        self.metadataReader = metadataReader
        self.thumbnailService = thumbnailService
    }

    /// Source-compat shim. Without dependencies the service is a no-op.
    init() {
        self.library = NullLibrary()
        self.repository = ScreenshotRepository()
        self.metadataReader = NullMetadataReader()
        self.thumbnailService = NullThumbnailService()
    }

    // MARK: - ScreenshotImporting

    func importURLs(_ urls: [URL]) async -> ImportResult {
        await Task.detached(priority: .userInitiated) { [self] in
            var result = ImportResult()
            for url in urls {
                do {
                    if let imported = try self.importOne(url: url) {
                        result.imported.append(imported)
                    } else {
                        result.duplicates += 1
                    }
                } catch {
                    print("[Import] failure: \(url.lastPathComponent) — \(error)")
                    result.failures.append((url, error))
                }
            }
            print("[Import] done: imported=\(result.imported.count) " +
                  "duplicates=\(result.duplicates) failures=\(result.failures.count)")
            return result
        }.value
    }

    // MARK: - Pipeline

    /// Returns `nil` when the file's hash already exists in the repository.
    private func importOne(url: URL) throws -> Screenshot? {
        let hash = try FileHash.sha256Hex(of: url)
        if let existing = try repository.findByHash(hash) {
            print("[Import] dedupe hit \(url.lastPathComponent) → \(existing.uuidString)")
            return nil
        }

        let metadata = try metadataReader.read(from: url)
        let uuid = UUID()
        let ext = url.pathExtension.isEmpty
            ? defaultExtension(for: metadata.format)
            : url.pathExtension

        let folder = try library.originalsFolder(for: metadata.createdAt)
        let destURL = folder.appendingPathComponent("\(uuid.uuidString.lowercased()).\(ext)")
        try copyOriginal(from: url, to: destURL)

        let smallThumbnailURL = library.smallThumbnailURL(for: uuid)
        let largeThumbnailURL = library.largeThumbnailURL(for: uuid)
        do {
            try thumbnailService.writeThumbnails(from: destURL, uuid: uuid)
            let fm = FileManager.default
            print("[Import] small thumbnail: \(smallThumbnailURL.path) exists=\(fm.fileExists(atPath: smallThumbnailURL.path))")
            print("[Import] large thumbnail: \(largeThumbnailURL.path) exists=\(fm.fileExists(atPath: largeThumbnailURL.path))")
        } catch {
            print("[Import] thumbnail generation failed for \(destURL.lastPathComponent): \(error)")
        }

        let now = Date()
        let relativePath = libraryRelativePath(for: destURL)

        let shot = Screenshot(
            id: uuid,
            name: url.lastPathComponent,
            createdAt: metadata.createdAt,
            pixelWidth: metadata.width,
            pixelHeight: metadata.height,
            byteSize: metadata.byteSize,
            format: metadata.format,
            tags: [],
            ocrSnippets: [],
            isFavorite: false,
            isOCRComplete: false,
            thumbnailKind: .document,
            isTrashed: false,
            libraryPath: relativePath,
            fileHash: hash,
            importedAt: now,
            modifiedAt: now,
            sourceApp: nil,
            sortIndex: 0,
            trashDate: nil
        )

        do {
            try repository.insert(shot)
        } catch {
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.removeItem(at: smallThumbnailURL)
            try? FileManager.default.removeItem(at: largeThumbnailURL)
            throw error
        }
        return shot
    }

    private func copyOriginal(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    /// Stores `Originals/2026/04/<uuid>.png` rather than the absolute path so
    /// the library can be relocated without rewriting every row.
    private func libraryRelativePath(for url: URL) -> String {
        let rootPath = library.libraryRootURL.path
        let absolute = url.path
        if absolute.hasPrefix(rootPath) {
            var trimmed = String(absolute.dropFirst(rootPath.count))
            if trimmed.hasPrefix("/") { trimmed.removeFirst() }
            return trimmed
        }
        return absolute
    }

    private func defaultExtension(for format: String) -> String {
        switch format.uppercased() {
        case "PNG": return "png"
        case "JPEG": return "jpg"
        case "HEIC": return "heic"
        case "TIFF": return "tiff"
        case "GIF": return "gif"
        case "WEBP": return "webp"
        case "BMP": return "bmp"
        default: return "img"
        }
    }
}

// MARK: - No-op fallbacks for the legacy parameterless init

private final class NullLibrary: LibraryManaging {
    var libraryRootURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
    var databaseURL: URL { libraryRootURL.appendingPathComponent("null.sqlite") }
    func originalsFolder(for date: Date) throws -> URL { libraryRootURL }
    func smallThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL.appendingPathComponent("\(uuid.uuidString).jpg")
    }
    func largeThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL.appendingPathComponent("\(uuid.uuidString).jpg")
    }
    func bootstrap() throws {}
}

private struct NullMetadataReader: ImageMetadataReading {
    func read(from url: URL) throws -> ImageMetadata {
        ImageMetadata(width: 0, height: 0, byteSize: 0, format: "", createdAt: Date())
    }
}

private struct NullThumbnailService: ThumbnailGenerating {
    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws {}
}
