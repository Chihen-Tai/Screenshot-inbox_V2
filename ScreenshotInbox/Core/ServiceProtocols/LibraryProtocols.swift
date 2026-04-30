import Foundation

/// Where the library lives, what the well-known subpaths are, and how to
/// turn UUIDs into thumbnail URLs. Platform-neutral.
protocol LibraryManaging: AnyObject {
    /// Root of the managed library on disk.
    var libraryRootURL: URL { get }
    /// Path to the SQLite database file inside the library.
    var databaseURL: URL { get }
    /// Folder for `Originals/<YYYY>/<MM>/`. Creates intermediate dirs as needed.
    func originalsFolder(for date: Date) throws -> URL
    /// `Thumbnails/small/<uuid>.jpg`
    func smallThumbnailURL(for uuid: UUID) -> URL
    /// `Thumbnails/large/<uuid>.jpg`
    func largeThumbnailURL(for uuid: UUID) -> URL
    /// Ensures the library folder structure exists. Idempotent.
    func bootstrap() throws
}

/// Reads dimensions / format / capture timestamp from an image file.
/// Implementations are platform-specific (ImageIO on macOS, WIC on Windows).
protocol ImageMetadataReading {
    func read(from url: URL) throws -> ImageMetadata
}

/// Writes small + large JPEG thumbnails for `uuid` derived from `sourceURL`.
protocol ThumbnailGenerating {
    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws
}

/// Generates compact perceptual hashes for image similarity. Implementations
/// can be platform-specific because decoding lives at the platform boundary.
protocol ImageHashingService {
    var algorithm: String { get }
    func hashImage(at url: URL) throws -> ImageHashRecord
}

enum ImportConflictReason: String, Hashable {
    case exactDuplicateHash
}

struct ImportConflict: Identifiable, Hashable {
    var id: String { "\(incomingFileHash):\(incomingPath):\(existingScreenshotUUID)" }
    let incomingPath: String
    let incomingFilename: String
    let incomingFileHash: String
    let existingScreenshotUUID: String
    let existingFilename: String
    let existingLibraryPath: String?
    let existingOriginalPath: String?
    let existingCreatedAt: Date?
    let reason: ImportConflictReason
}

enum ImportConflictResolution: String, Hashable {
    case keepBoth
    case replaceExisting
    case skip
}

struct ImportConflictDecision: Hashable {
    let conflict: ImportConflict
    let resolution: ImportConflictResolution
}

protocol ImportConflictResolving {
    func resolve(conflicts: [ImportConflict]) async -> [ImportConflictDecision]
}

struct SkipImportConflictResolver: ImportConflictResolving {
    func resolve(conflicts: [ImportConflict]) async -> [ImportConflictDecision] {
        conflicts.map { ImportConflictDecision(conflict: $0, resolution: .skip) }
    }
}

/// Result of a batch import. `failures` carries per-URL errors so the caller
/// can surface them in a toast. `duplicates` remains the skipped-duplicate
/// count for existing UI compatibility.
struct ImportResult {
    var imported: [Screenshot] = []
    var duplicates: Int = 0
    var conflicts: [ImportConflict] = []
    var keptDuplicateCopies: Int = 0
    var replaced: [Screenshot] = []
    var failures: [(URL, Error)] = []
}

/// Orchestrates the import pipeline (hash → dedupe → copy → metadata →
/// thumbnails → repository insert).
protocol ScreenshotImporting {
    func importURLs(_ urls: [URL]) async -> ImportResult
}
