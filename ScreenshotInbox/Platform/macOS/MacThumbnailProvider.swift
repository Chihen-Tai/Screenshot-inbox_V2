import AppKit
import Foundation

/// Resolves and loads persisted screenshot thumbnails for macOS UI surfaces.
///
/// The core `Screenshot` model stays platform-neutral: it carries only the
/// UUID and relative original path. This provider derives image file locations
/// from the managed library service at the UI/platform boundary.
final class MacThumbnailProvider {
    enum Tier {
        case small
        case large
    }

    private let library: MacLibraryService
    private let fileManager: FileManager

    init(library: MacLibraryService, fileManager: FileManager = .default) {
        self.library = library
        self.fileManager = fileManager
    }

    func thumbnailURL(for screenshot: Screenshot, tier: Tier) -> URL? {
        guard screenshot.libraryPath != nil else { return nil }
        switch tier {
        case .small:
            return library.smallThumbnailURL(for: screenshot.id)
        case .large:
            return library.largeThumbnailURL(for: screenshot.id)
        }
    }

    func originalURL(for screenshot: Screenshot) -> URL? {
        guard let path = screenshot.libraryPath, !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return library.libraryRootURL.appendingPathComponent(path)
    }

    func originalExists(for screenshot: Screenshot) -> Bool {
        guard let url = originalURL(for: screenshot) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func loadThumbnail(for screenshot: Screenshot, tier: Tier) -> NSImage? {
        guard let url = thumbnailURL(for: screenshot, tier: tier) else {
            return nil
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard let image = NSImage(contentsOf: url), image.isValid else {
            #if DEBUG
            print("[ThumbnailProvider] failed to load thumbnail image: \(url.path)")
            #endif
            return nil
        }
        return image
    }

    func loadPreviewImage(for screenshot: Screenshot) -> NSImage? {
        if let large = loadThumbnail(for: screenshot, tier: .large) {
            return large
        }
        guard let url = originalURL(for: screenshot) else { return nil }
        guard fileManager.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url),
              image.isValid else {
            print("[ThumbnailProvider] failed to load original image for preview")
            return nil
        }
        return image
    }
}
