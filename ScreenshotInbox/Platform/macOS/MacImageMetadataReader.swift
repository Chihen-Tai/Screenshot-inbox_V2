import Foundation

/// macOS conformer for `ImageMetadataReading`. Delegates to the free-standing
/// `ImageMetadataReader` helper so the call site can be mocked.
final class MacImageMetadataReader: ImageMetadataReading {
    func read(from url: URL) throws -> ImageMetadata {
        try ImageMetadataReader.read(from: url)
    }
}
