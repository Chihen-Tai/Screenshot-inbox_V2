import Foundation
import ImageIO
import UniformTypeIdentifiers

/// macOS implementation of `ThumbnailGenerating`. Uses `CGImageSource` to
/// produce two JPEG thumbnails (small ~360 px, large ~1200 px) sized to the
/// longest edge, written to the paths the library service hands out.
final class MacThumbnailService: ThumbnailGenerating {
    private unowned let library: MacLibraryService

    /// Longest-edge pixel sizes for the two thumbnail tiers.
    static let smallMaxPixel: CGFloat = 360
    static let largeMaxPixel: CGFloat = 1200

    init(library: MacLibraryService) {
        self.library = library
    }

    enum ThumbnailError: Error {
        case sourceUnreadable
        case thumbnailGenerationFailed
        case writeFailed
    }

    func writeThumbnails(from sourceURL: URL, uuid: UUID) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw ThumbnailError.sourceUnreadable
        }

        let smallURL = library.smallThumbnailURL(for: uuid)
        let largeURL = library.largeThumbnailURL(for: uuid)

        try ensureParentDirectory(for: smallURL)
        try ensureParentDirectory(for: largeURL)

        try writeJPEG(from: source, maxPixel: Self.smallMaxPixel, to: smallURL)
        #if DEBUG
        print("[ThumbnailService] wrote small thumbnail: \(smallURL.path)")
        #endif
        try writeJPEG(from: source, maxPixel: Self.largeMaxPixel, to: largeURL)
        #if DEBUG
        print("[ThumbnailService] wrote large thumbnail: \(largeURL.path)")
        #endif
    }

    // MARK: - Helpers

    private func writeJPEG(from source: CGImageSource, maxPixel: CGFloat, to url: URL) throws {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ThumbnailError.thumbnailGenerationFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ThumbnailError.writeFailed
        }
        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImage(destination, cgImage, destinationOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailError.writeFailed
        }
    }

    private func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
