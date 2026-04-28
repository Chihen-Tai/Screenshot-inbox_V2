import Foundation

struct ImportSource: Identifiable, Hashable {
    var id: Int?
    var uuid: String
    var folderPath: String
    var displayName: String?
    var isEnabled: Bool
    var recursive: Bool
    var enabledSince: Date?
    var lastScannedAt: Date?
    var createdAt: Date
    var updatedAt: Date?

    var effectiveDisplayName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return URL(fileURLWithPath: folderPath).lastPathComponent
    }
}
