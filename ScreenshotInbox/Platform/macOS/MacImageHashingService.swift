import CoreGraphics
import Foundation
import ImageIO

final class MacImageHashingService: ImageHashingService {
    let algorithm = ImageHashRecord.dHashAlgorithm

    enum HashingError: Error {
        case imageUnreadable
        case bitmapUnavailable
    }

    func hashImage(at url: URL) throws -> ImageHashRecord {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw HashingError.imageUnreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw HashingError.imageUnreadable
        }
        let value = try Self.dHash64(image: image)
        return ImageHashRecord(
            screenshotUUID: "",
            algorithm: algorithm,
            hash: String(format: "%016llx", value),
            createdAt: Date()
        )
    }

    private static func dHash64(image: CGImage) throws -> UInt64 {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            throw HashingError.bitmapUnavailable
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                hash <<= 1
                let left = pixels[y * width + x]
                let right = pixels[y * width + x + 1]
                if left > right {
                    hash |= 1
                }
            }
        }
        return hash
    }
}
