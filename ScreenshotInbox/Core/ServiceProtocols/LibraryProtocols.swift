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

/// Result of a batch import. `failures` carries per-URL errors so the caller
/// can surface them in a toast; `duplicates` is a count rather than a list
/// because we don't reuse the existing record beyond skipping the copy.
struct ImportResult {
    var imported: [Screenshot] = []
    var duplicates: Int = 0
    var failures: [(URL, Error)] = []
}

/// Orchestrates the import pipeline (hash → dedupe → copy → metadata →
/// thumbnails → repository insert).
protocol ScreenshotImporting {
    func importURLs(_ urls: [URL]) async -> ImportResult
}
