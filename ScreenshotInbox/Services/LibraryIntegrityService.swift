import Foundation
import ImageIO

struct LibraryIntegrityReport: Hashable {
    var totalScreenshots: Int = 0
    var missingOriginals: Int = 0
    var missingThumbnails: Int = 0
    var missingLargeThumbnails: Int = 0
    var invalidImageFiles: Int = 0
    var orphanThumbnails: Int = 0
    var orphanOriginals: Int = 0
    var orphanDatabaseRows: Int = 0
    var missingOCRRecords: Int = 0
    var searchIndexOutOfDate: Bool = false
    var duplicateIndexOutOfDate: Bool = false
    var warnings: [String] = []

    var missingOriginalPaths: [String] = []
    var missingThumbnailPaths: [String] = []
    var missingLargeThumbnailPaths: [String] = []
    var orphanThumbnailPaths: [String] = []
    var orphanOriginalPaths: [String] = []

    var hasProblems: Bool {
        missingOriginals > 0 ||
        missingThumbnails > 0 ||
        missingLargeThumbnails > 0 ||
        invalidImageFiles > 0 ||
        orphanThumbnails > 0 ||
        orphanOriginals > 0 ||
        orphanDatabaseRows > 0 ||
        missingOCRRecords > 0 ||
        searchIndexOutOfDate ||
        duplicateIndexOutOfDate ||
        !warnings.isEmpty
    }
}

struct LibraryMaintenanceResult: Hashable {
    var processed: Int
    var skipped: Int = 0
    var message: String
}

final class LibraryIntegrityService {
    private let library: LibraryManaging
    private let screenshotRepository: ScreenshotRepository
    private let ocrRepository: OCRRepository
    private let imageHashRepository: ImageHashRepository
    private let thumbnailService: ThumbnailGenerating
    private let database: Database?
    private let fileManager: FileManager

    init(
        library: LibraryManaging,
        screenshotRepository: ScreenshotRepository,
        ocrRepository: OCRRepository,
        imageHashRepository: ImageHashRepository,
        thumbnailService: ThumbnailGenerating,
        database: Database?,
        fileManager: FileManager = .default
    ) {
        self.library = library
        self.screenshotRepository = screenshotRepository
        self.ocrRepository = ocrRepository
        self.imageHashRepository = imageHashRepository
        self.thumbnailService = thumbnailService
        self.database = database
        self.fileManager = fileManager
    }

    func checkIntegrity() throws -> LibraryIntegrityReport {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: true)
        let ocrResults = try ocrRepository.fetchAll()
        let existingOCRIDs = Set(ocrResults.map(\.screenshotUUID))
        let missingHashIDs = try imageHashRepository.fetchMissingScreenshotUUIDs(includeTrashed: false)
        let knownIDs = Set(screenshots.map(\.uuidString))
        let referencedOriginalPaths = Set(screenshots.compactMap { originalURL(for: $0)?.standardizedFileURL.path })

        var report = LibraryIntegrityReport(totalScreenshots: screenshots.count)
        report.duplicateIndexOutOfDate = !missingHashIDs.isEmpty
        if report.duplicateIndexOutOfDate {
            report.warnings.append("Duplicate index is missing \(missingHashIDs.count) hash\(missingHashIDs.count == 1 ? "" : "es").")
        }

        for screenshot in screenshots {
            let uuid = screenshot.uuidString
            guard let originalURL = originalURL(for: screenshot) else {
                report.missingOriginals += 1
                report.missingOriginalPaths.append(screenshot.libraryPath ?? "(missing library path)")
                continue
            }

            if !fileManager.fileExists(atPath: originalURL.path) {
                report.missingOriginals += 1
                report.missingOriginalPaths.append(originalURL.path)
            } else {
                if !isValidImage(at: originalURL) {
                    report.invalidImageFiles += 1
                    report.warnings.append("Invalid image file: \(screenshot.name)")
                }
                if let storedSize = storedFileSize(for: originalURL),
                   storedSize != screenshot.byteSize {
                    report.warnings.append("File size mismatch for \(screenshot.name).")
                }
            }

            let smallURL = library.smallThumbnailURL(for: screenshot.id)
            if !fileManager.fileExists(atPath: smallURL.path) {
                report.missingThumbnails += 1
                report.missingThumbnailPaths.append(smallURL.path)
            }

            let largeURL = library.largeThumbnailURL(for: screenshot.id)
            if !fileManager.fileExists(atPath: largeURL.path) {
                report.missingLargeThumbnails += 1
                report.missingLargeThumbnailPaths.append(largeURL.path)
            }

            if !existingOCRIDs.contains(uuid) {
                report.missingOCRRecords += 1
            }
        }

        report.orphanThumbnailPaths = orphanThumbnailURLs(expectedScreenshotIDs: knownIDs).map(\.path)
        report.orphanThumbnails = report.orphanThumbnailPaths.count
        report.orphanOriginalPaths = orphanOriginalURLs(referencedPaths: referencedOriginalPaths).map(\.path)
        report.orphanOriginals = report.orphanOriginalPaths.count
        report.orphanDatabaseRows = try orphanDatabaseRowCount(knownScreenshotIDs: knownIDs)
        report.searchIndexOutOfDate = false

        return report
    }

    func regenerateMissingThumbnails(progress: ((Int, Int) -> Void)? = nil) throws -> LibraryMaintenanceResult {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: true)
        let targets = screenshots.filter { screenshot in
            guard originalURL(for: screenshot).map({ fileManager.fileExists(atPath: $0.path) }) == true else {
                return false
            }
            return !fileManager.fileExists(atPath: library.smallThumbnailURL(for: screenshot.id).path) ||
                !fileManager.fileExists(atPath: library.largeThumbnailURL(for: screenshot.id).path)
        }
        return try regenerateThumbnails(for: targets, progress: progress, message: "Regenerated missing thumbnails")
    }

    func rebuildAllThumbnails(progress: ((Int, Int) -> Void)? = nil) throws -> LibraryMaintenanceResult {
        let targets = try screenshotRepository.fetchAll(includeTrashed: true).filter {
            originalURL(for: $0).map { fileManager.fileExists(atPath: $0.path) } == true
        }
        return try regenerateThumbnails(for: targets, progress: progress, message: "Rebuilt thumbnails")
    }

    func createMissingOCRRecords() throws -> LibraryMaintenanceResult {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: true)
        let existingIDs = Set(try ocrRepository.fetchAll().map(\.screenshotUUID))
        let missingIDs = screenshots
            .map(\.uuidString)
            .filter { !existingIDs.contains($0) }
        try ocrRepository.ensurePending(for: missingIDs)
        return LibraryMaintenanceResult(processed: missingIDs.count, message: "Queued missing OCR records")
    }

    func resetFailedOCRRecords() throws -> LibraryMaintenanceResult {
        let failedIDs = try ocrRepository.fetchByStatus(.failed).map(\.screenshotUUID)
        try ocrRepository.resetToPending(screenshotUUIDs: failedIDs)
        return LibraryMaintenanceResult(processed: failedIDs.count, message: "Re-queued failed OCR")
    }

    func resetProcessingOCRRecords() throws -> LibraryMaintenanceResult {
        let processing = try ocrRepository.fetchByStatus(.processing)
        try ocrRepository.resetProcessingToPending()
        return LibraryMaintenanceResult(processed: processing.count, message: "Reset processing OCR records")
    }

    func cleanOrphanThumbnails() throws -> LibraryMaintenanceResult {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: true)
        let knownIDs = Set(screenshots.map(\.uuidString))
        let urls = orphanThumbnailURLs(expectedScreenshotIDs: knownIDs)
        try removeLibraryFiles(urls)
        return LibraryMaintenanceResult(processed: urls.count, message: "Cleaned orphan thumbnails")
    }

    func cleanOrphanOriginals() throws -> LibraryMaintenanceResult {
        let screenshots = try screenshotRepository.fetchAll(includeTrashed: true)
        let referencedPaths = Set(screenshots.compactMap { originalURL(for: $0)?.standardizedFileURL.path })
        let urls = orphanOriginalURLs(referencedPaths: referencedPaths)
        try removeLibraryFiles(urls)
        return LibraryMaintenanceResult(processed: urls.count, message: "Cleaned orphan originals")
    }

    func databaseIntegrityCheck() throws -> String {
        guard let database else { return "Database unavailable" }
        return try database.queue.sync {
            let stmt = try database.prepare("PRAGMA integrity_check;")
            var rows: [String] = []
            while try stmt.step() {
                if let row = stmt.columnString(0) {
                    rows.append(row)
                }
            }
            return rows.isEmpty ? "ok" : rows.joined(separator: "\n")
        }
    }

    func vacuumDatabase() throws -> LibraryMaintenanceResult {
        guard let database else {
            return LibraryMaintenanceResult(processed: 0, message: "Database unavailable")
        }
        try database.queue.sync {
            try database.exec("VACUUM;")
            try database.exec("ANALYZE;")
        }
        return LibraryMaintenanceResult(processed: 1, message: "Vacuumed database")
    }

    private func regenerateThumbnails(
        for screenshots: [Screenshot],
        progress: ((Int, Int) -> Void)?,
        message: String
    ) throws -> LibraryMaintenanceResult {
        var processed = 0
        var skipped = 0
        for (index, screenshot) in screenshots.enumerated() {
            progress?(index + 1, screenshots.count)
            guard let sourceURL = originalURL(for: screenshot),
                  fileManager.fileExists(atPath: sourceURL.path) else {
                skipped += 1
                continue
            }
            try thumbnailService.writeThumbnails(from: sourceURL, uuid: screenshot.id)
            processed += 1
        }
        return LibraryMaintenanceResult(processed: processed, skipped: skipped, message: message)
    }

    private func originalURL(for screenshot: Screenshot) -> URL? {
        guard let path = screenshot.libraryPath, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return library.libraryRootURL.appendingPathComponent(path)
    }

    private func storedFileSize(for url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize
    }

    private func isValidImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 &&
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private func orphanThumbnailURLs(expectedScreenshotIDs: Set<String>) -> [URL] {
        let folders = [
            library.libraryRootURL.appendingPathComponent("Thumbnails/small", isDirectory: true),
            library.libraryRootURL.appendingPathComponent("Thumbnails/large", isDirectory: true)
        ]
        return folders.flatMap { folder in
            regularFiles(under: folder).filter { url in
                url.pathExtension.lowercased() == "jpg" &&
                    !expectedScreenshotIDs.contains(url.deletingPathExtension().lastPathComponent.lowercased())
            }
        }
    }

    private func orphanOriginalURLs(referencedPaths: Set<String>) -> [URL] {
        let originalsRoot = library.libraryRootURL.appendingPathComponent("Originals", isDirectory: true)
        return regularFiles(under: originalsRoot).filter { url in
            !referencedPaths.contains(url.standardizedFileURL.path)
        }
    }

    private func regularFiles(under folder: URL) -> [URL] {
        guard fileManager.fileExists(atPath: folder.path),
              let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            urls.append(url)
        }
        return urls
    }

    private func removeLibraryFiles(_ urls: [URL]) throws {
        for url in urls {
            guard isInsideLibrary(url) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
            }
            try fileManager.removeItem(at: url)
        }
    }

    private func isInsideLibrary(_ url: URL) -> Bool {
        let root = library.libraryRootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func orphanDatabaseRowCount(knownScreenshotIDs: Set<String>) throws -> Int {
        guard let database else { return 0 }
        return try database.queue.sync {
            var total = 0
            for table in ["collection_items", "screenshot_tags", "ocr_results", "detected_codes", "image_hashes"] where try tableExists(table, database: database) {
                let stmt = try database.prepare("SELECT screenshot_uuid FROM \(table);")
                while try stmt.step() {
                    let uuid = (stmt.columnString(0) ?? "").lowercased()
                    if !knownScreenshotIDs.contains(uuid) {
                        total += 1
                    }
                }
            }
            if try tableExists("collection_items", database: database) {
                let stmt = try database.prepare("""
                SELECT COUNT(*)
                FROM collection_items ci
                LEFT JOIN collections c ON c.id = ci.collection_id
                WHERE c.id IS NULL;
                """)
                if try stmt.step() {
                    total += Int(stmt.columnInt(0))
                }
            }
            return total
        }
    }

    private func tableExists(_ name: String, database: Database) throws -> Bool {
        let stmt = try database.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;")
        try stmt.bind(1, name)
        return try stmt.step()
    }
}
