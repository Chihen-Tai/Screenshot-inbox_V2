import AppKit
import Foundation

enum InternalScreenshotDrag {
    static let pasteboardTypeString = "com.screenshotinbox.screenshot-ids"
    static let pasteboardType = NSPasteboard.PasteboardType(pasteboardTypeString)

    static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: "\n")
    }

    static func decode(_ raw: String?) -> [UUID] {
        guard let raw else { return [] }
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { UUID(uuidString: String($0)) }
    }
}
