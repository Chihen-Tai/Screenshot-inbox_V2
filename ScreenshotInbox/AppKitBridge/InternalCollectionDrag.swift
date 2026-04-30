import AppKit
import Foundation

enum InternalCollectionDrag {
    static let pasteboardTypeString = DragPasteboardTypes.collectionIDString
    static let pasteboardType = DragPasteboardTypes.collectionID

    static func encode(_ uuid: String) -> String {
        uuid
    }

    static func encodeTextFallback(_ uuid: String) -> String {
        "collection:\(uuid)"
    }

    static func decode(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.hasPrefix("collection:") {
            let uuid = String(value.dropFirst("collection:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return uuid.isEmpty ? nil : uuid
        }
        return value.isEmpty ? nil : value
    }

    static func decode(from pasteboard: NSPasteboard) -> String? {
        if let raw = pasteboard.string(forType: pasteboardType),
           let uuid = decode(raw) {
            return uuid
        }
        if let data = pasteboard.data(forType: pasteboardType),
           let raw = String(data: data, encoding: .utf8),
           let uuid = decode(raw) {
            return uuid
        }
        return decode(pasteboard.string(forType: .string))
    }
}
