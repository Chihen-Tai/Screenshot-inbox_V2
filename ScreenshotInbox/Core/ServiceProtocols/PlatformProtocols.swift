import Foundation

/// Neutral image metadata used by import, duplicate, and library integrity
/// flows. Platform readers fill this from ImageIO on macOS or another decoder
/// stack on future platforms.
struct ImageMetadata: Hashable {
    var width: Int
    var height: Int
    var byteSize: Int
    var format: String
    var createdAt: Date
}

struct ThumbnailResult: Hashable {
    var smallPath: String
    var largePath: String
}

struct ImportInput: Hashable {
    var path: String
    var suggestedFilename: String?
}

/// Reads dimensions, byte size, format, and capture timestamp from an image.
protocol ImageMetadataProvider {
    func read(from url: URL) throws -> ImageMetadata
    func readImageMetadata(path: String) throws -> ImageMetadata
}

extension ImageMetadataProvider {
    func readImageMetadata(path: String) throws -> ImageMetadata {
        try read(from: URL(fileURLWithPath: path))
    }
}

/// Writes small and large thumbnails for a managed screenshot.
protocol ThumbnailGenerating {
    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws
    func generateThumbnails(for imagePath: String, uuid: String) throws -> ThumbnailResult
}

/// Generates compact perceptual hashes for image similarity. Implementations
/// can be platform-specific because decoding lives at the platform boundary.
protocol ImageHashingService {
    var algorithm: String { get }
    func hashImage(at url: URL) throws -> ImageHashRecord
}

protocol OCRRecognizing {
    func recognizeText(imagePath: String, languages: [String]) async throws -> OCRRecognitionResult
}

protocol CodeDetecting {
    func detectCodes(imagePath: String) async throws -> [CodeDetectionResult]
}

protocol FileOpening {
    func openFile(path: String) throws
    func revealInFinder(path: String) throws
    @MainActor func openWith(path: String) throws
}

protocol FileTrashManaging {
    func moveToSystemTrash(path: String) throws
}

protocol ClipboardProviding {
    func copyFiles(paths: [String]) throws
    func pasteImageOrFiles() async throws -> [ImportInput]
}

protocol SharingProviding {
    @discardableResult
    func shareFiles(paths: [String]) -> Int
}

typealias ImageMetadataReading = ImageMetadataProvider
