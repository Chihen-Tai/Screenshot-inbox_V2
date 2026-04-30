import Foundation

/// macOS implementation of `LibraryManaging`. Library root is
/// `~/Pictures/Screenshot Inbox Library/` and is created on bootstrap.
final class MacLibraryService: LibraryManaging {
    let libraryRootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.libraryRootURL = rootURL
        } else {
            let pictures = FileManager.default.urls(
                for: .picturesDirectory, in: .userDomainMask
            ).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Pictures", isDirectory: true)
            self.libraryRootURL = pictures
                .appendingPathComponent("Screenshot Inbox Library", isDirectory: true)
        }
    }

    var databaseURL: URL {
        libraryRootURL.appendingPathComponent("screenshot-inbox.sqlite")
    }

    func originalsFolder(for date: Date) throws -> URL {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let yearStr = String(format: "%04d", comps.year ?? 1970)
        let monthStr = String(format: "%02d", comps.month ?? 1)
        let folder = libraryRootURL
            .appendingPathComponent("Originals", isDirectory: true)
            .appendingPathComponent(yearStr, isDirectory: true)
            .appendingPathComponent(monthStr, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        return folder
    }

    func smallThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL
            .appendingPathComponent("Thumbnails/small", isDirectory: true)
            .appendingPathComponent("\(uuid.uuidString.lowercased()).jpg")
    }

    func largeThumbnailURL(for uuid: UUID) -> URL {
        libraryRootURL
            .appendingPathComponent("Thumbnails/large", isDirectory: true)
            .appendingPathComponent("\(uuid.uuidString.lowercased()).jpg")
    }

    func bootstrap() throws {
        let fm = FileManager.default
        let folders = [
            libraryRootURL,
            libraryRootURL.appendingPathComponent("Originals", isDirectory: true),
            libraryRootURL.appendingPathComponent("Thumbnails/small", isDirectory: true),
            libraryRootURL.appendingPathComponent("Thumbnails/large", isDirectory: true),
            libraryRootURL.appendingPathComponent("Exports/PDFs", isDirectory: true),
        ]
        for folder in folders {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        #if DEBUG
        print("[Library] bootstrap ok: \(libraryRootURL.path)")
        #endif
    }
}
