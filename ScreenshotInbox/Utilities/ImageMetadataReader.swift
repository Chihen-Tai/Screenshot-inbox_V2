import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Plain image-metadata payload. Platform-neutral by intent — the macOS
/// ImageIO reader produces this struct, but a Windows port would produce the
/// same shape from WIC.
struct ImageMetadata {
    var width: Int
    var height: Int
    var byteSize: Int
    /// Display format: "PNG" / "JPEG" / "HEIC" / "TIFF" / etc.
    var format: String
    /// Best-effort capture timestamp. Priority: EXIF DateTimeOriginal →
    /// filesystem creation date → `Date()`.
    var createdAt: Date
}

enum ImageMetadataError: Error, CustomStringConvertible {
    case unreadable(URL)
    var description: String {
        switch self {
        case .unreadable(let u): return "Could not read image at \(u.path)"
        }
    }
}

/// Reads dimensions, byte size, format, and capture timestamp from an image
/// file using ImageIO. Used by `ImportService` to populate DB rows.
enum ImageMetadataReader {
    static func read(from url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageMetadataError.unreadable(url)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        let width  = (props[kCGImagePropertyPixelWidth]  as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0

        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let byteSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let fileCreationDate = attrs[.creationDate] as? Date

        let format = formatString(for: source, fallbackURL: url)
        let createdAt = exifDate(from: props) ?? fileCreationDate ?? Date()

        return ImageMetadata(
            width: width, height: height, byteSize: byteSize,
            format: format, createdAt: createdAt
        )
    }

    private static func formatString(for source: CGImageSource, fallbackURL: URL) -> String {
        if let utiRaw = CGImageSourceGetType(source) as String?,
           let utType = UTType(utiRaw) {
            switch utType {
            case .png:  return "PNG"
            case .jpeg: return "JPEG"
            case .heic, .heif: return "HEIC"
            case .tiff: return "TIFF"
            case .gif:  return "GIF"
            case .webP: return "WEBP"
            case .bmp:  return "BMP"
            default:    return utType.preferredFilenameExtension?.uppercased()
                            ?? fallbackURL.pathExtension.uppercased()
            }
        }
        return fallbackURL.pathExtension.uppercased()
    }

    /// EXIF stores capture time as `"yyyy:MM:dd HH:mm:ss"` (note the colon
    /// date separators). Falls back to `kCGImagePropertyTIFFDateTime` if EXIF
    /// is absent.
    private static func exifDate(from props: [CFString: Any]) -> Date? {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw else { return nil }
        return Self.exifFormatter.date(from: raw)
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
