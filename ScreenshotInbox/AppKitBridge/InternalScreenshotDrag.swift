import AppKit
import Foundation

enum InternalScreenshotDrag {
    static let pasteboardTypeString = DragPasteboardTypes.screenshotIDsString
    static let pasteboardType = DragPasteboardTypes.screenshotIDs

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
