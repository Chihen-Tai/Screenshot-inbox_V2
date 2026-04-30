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
        await importURLs(urls, conflictResolver: SkipImportConflictResolver())
    }

    func importURLs(
        _ urls: [URL],
        conflictResolver: ImportConflictResolving
    ) async -> ImportResult {
        await Task.detached(priority: .userInitiated) { [self] in
            var result = ImportResult()
            var pendingConflicts: [(url: URL, hash: String, existing: Screenshot, conflict: ImportConflict)] = []
            for url in urls {
                do {
                    let hash = try FileHash.sha256Hex(of: url)
                    if let existing = try repository.findByHash(hash) {
                        let conflict = self.makeConflict(url: url, hash: hash, existing: existing)
                        pendingConflicts.append((url, hash, existing, conflict))
                        result.conflicts.append(conflict)
                    } else {
                        result.imported.append(try self.importOne(url: url, hash: hash, forcedName: nil))
                    }
                } catch {
                    print("[Import] failure: \(url.lastPathComponent) — \(error)")
                    result.failures.append((url, error))
                }
            }
            if !pendingConflicts.isEmpty {
                let decisions = await conflictResolver.resolve(conflicts: pendingConflicts.map(\.conflict))
                let resolutionByID = Dictionary(uniqueKeysWithValues: decisions.map { ($0.conflict.id, $0.resolution) })
                for pending in pendingConflicts {
                    do {
                        switch resolutionByID[pending.conflict.id] ?? .skip {
                        case .skip:
                            result.duplicates += 1
                        case .keepBoth:
                            let name = try self.uniqueDisplayName(for: pending.url.lastPathComponent)
                            let imported = try self.importOne(url: pending.url, hash: pending.hash, forcedName: name)
                            result.imported.append(imported)
                            result.keptDuplicateCopies += 1
                        case .replaceExisting:
                            let replaced = try self.replace(existing: pending.existing, with: pending.url, hash: pending.hash)
                            result.replaced.append(replaced)
                        }
                    } catch {
                        print("[Import] conflict resolution failure: \(pending.url.lastPathComponent) — \(error)")
                        result.failures.append((pending.url, error))
                    }
                }
            }
            print("[Import] done: imported=\(result.imported.count) " +
                  "duplicates=\(result.duplicates) keptDuplicates=\(result.keptDuplicateCopies) replaced=\(result.replaced.count) failures=\(result.failures.count)")
            return result
        }.value
    }

    // MARK: - Pipeline

    /// Imports a file as a new screenshot row. Duplicate policy is handled by
    /// `importURLs(_:conflictResolver:)` before this method is called.
    private func importOne(url: URL, hash: String, forcedName: String?) throws -> Screenshot {
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
            #if DEBUG
            let fm = FileManager.default
            print("[Import] small thumbnail: \(smallThumbnailURL.path) exists=\(fm.fileExists(atPath: smallThumbnailURL.path))")
            print("[Import] large thumbnail: \(largeThumbnailURL.path) exists=\(fm.fileExists(atPath: largeThumbnailURL.path))")
            #endif
        } catch {
            print("[Import] thumbnail generation failed for \(destURL.lastPathComponent): \(error)")
        }

        let now = Date()
        let relativePath = libraryRelativePath(for: destURL)
        #if DEBUG
        print("[SourceSync] imported managedPath=\(relativePath)")
        print("[SourceSync] originalPath=\(url.path)")
        #endif

        let shot = Screenshot(
            id: uuid,
            name: forcedName ?? url.lastPathComponent,
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
            sourceApp: url.deletingLastPathComponent().path,
            originalPath: url.path,
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

    private func replace(existing: Screenshot, with url: URL, hash: String) throws -> Screenshot {
        let metadata = try metadataReader.read(from: url)
        let ext = url.pathExtension.isEmpty
            ? defaultExtension(for: metadata.format)
            : url.pathExtension
        let originalURL = managedOriginalURL(for: existing)
            ?? libraryRelativeURL(for: existing, extension: ext)
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try copyOriginal(from: url, to: originalURL)
        do {
            try thumbnailService.writeThumbnails(from: originalURL, uuid: existing.id)
        } catch {
            print("[Import] thumbnail regeneration failed for \(existing.uuidString): \(error)")
        }
        var updated = existing
        updated.name = url.lastPathComponent
        updated.createdAt = metadata.createdAt
        updated.pixelWidth = metadata.width
        updated.pixelHeight = metadata.height
        updated.byteSize = metadata.byteSize
        updated.format = metadata.format
        updated.fileHash = hash
        updated.libraryPath = libraryRelativePath(for: originalURL)
        updated.modifiedAt = Date()
        updated.sourceApp = url.deletingLastPathComponent().path
        updated.originalPath = url.path
        #if DEBUG
        print("[SourceSync] imported managedPath=\(updated.libraryPath ?? "")")
        print("[SourceSync] originalPath=\(url.path)")
        #endif
        try repository.update(updated)
        return updated
    }

    private func makeConflict(url: URL, hash: String, existing: Screenshot) -> ImportConflict {
        ImportConflict(
            incomingPath: url.path,
            incomingFilename: url.lastPathComponent,
            incomingFileHash: hash,
            existingScreenshotUUID: existing.uuidString,
            existingFilename: existing.name,
            existingLibraryPath: existing.libraryPath,
            existingOriginalPath: managedOriginalURL(for: existing)?.path,
            existingCreatedAt: existing.createdAt,
            reason: .exactDuplicateHash
        )
    }

    private func uniqueDisplayName(for filename: String) throws -> String {
        let existingNames = Set(try repository.fetchAll(includeTrashed: true).map { $0.name.lowercased() })
        guard existingNames.contains(filename.lowercased()) else { return filename }
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    private func managedOriginalURL(for screenshot: Screenshot) -> URL? {
        guard let libraryPath = screenshot.libraryPath, !libraryPath.isEmpty else { return nil }
        if libraryPath.hasPrefix("/") {
            return URL(fileURLWithPath: libraryPath)
        }
        return library.libraryRootURL.appendingPathComponent(libraryPath)
    }

    private func libraryRelativeURL(for screenshot: Screenshot, extension ext: String) -> URL {
        let date = screenshot.importedAt ?? screenshot.createdAt
        let folder = try? library.originalsFolder(for: date)
        return (folder ?? library.libraryRootURL)
            .appendingPathComponent("\(screenshot.uuidString).\(ext)")
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
